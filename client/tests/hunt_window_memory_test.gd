extends SceneTree
## 自动抓极品 opens as it was last used. The character's settings (saved in
## the profile, so other devices and a restarted server show them too): the
## selected target set, kept even where it does not live (the window only
## hunts the local intersection and never substitutes other species), and the
## independent species the 属性条件 page shows. This device's
## own choice (viewer.cfg): the page the window shows.
const Rules = preload("res://scripts/pet_hunt_rules.gd")
const PREFS := "user://hunt-window-memory-test.cfg"
const MAP := 100
const CELL := Vector2i(637,493)
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func new_game():
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	game.viewer_prefs_path = PREFS
	root.add_child(game)
	await process_frame
	game.random_encounters = false
	return game

func free_game(game) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

func hunt_settings(game) -> Dictionary:
	return game.automation_settings().hunt

func ids(game, map_id: int, cell: Vector2i) -> Array:
	return Rules.candidates(game.encounter_catalog,map_id,cell,true).map(func(item):return int(item.id))

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game = await new_game()
	game.session.grant_starter_pets()
	var menu = game.pet_hunt_menu
	# A species found at the hunting ground and not in the wilderness outside the village.
	var here := ids(game,MAP,CELL)
	var other_map := MAP
	var other_cell := Vector2i(-1,-1)
	var elsewhere: Array = []
	for area in game.encounter_catalog.data.get("areas",[]):
		if int(area.map_id)!=MAP:continue
		var r: Array = area.rect
		var middle := Vector2i((int(r[0])+int(r[2]))/2,(int(r[1])+int(r[3]))/2)
		var landing: Vector2i = game.travel_landing.safe_destination(MAP,middle)
		if landing.x<0:continue
		var found := ids(game,MAP,landing)
		if found.is_empty() or here.all(func(id):return id in found):continue
		other_cell = landing;elsewhere = found;break
	game.load_area_id(MAP,CELL)
	var target := -1
	for id in ids(game,MAP,CELL):
		if not id in elsewhere:target = id;break
	check(target>=0 and not elsewhere.is_empty(),"a species of this place does not live at the other place (%d; here %s, there %s at %d %s)" % [target,str(ids(game,MAP,CELL)),str(elsewhere),other_map,str(other_cell)])

	# Choosing the target saves it, and 属性条件 follows it.
	menu.open_menu()
	var last: int=int(here.back())
	check(menu.choose_target(last) and int(hunt_settings(game).stat_species)==last,"navigation to a non-first target saves the followed 属性条件 preference")
	check(menu.choose_target(target),"navigation picks one available species in the real checklist")
	check(hunt_settings(game).templates==[target],"the selected singleton is saved with the character")
	check(menu.stat_species.get_selected_id()==target and int(hunt_settings(game).stat_species)==target,"属性条件 shows the target, remembered too")
	# 属性条件 can show another species; that is remembered as well.
	var other_index: int = 0 if menu.stat_species.get_item_id(0)!=target else 1
	var other: int = menu.stat_species.get_item_id(other_index)
	menu.stat_species.select(other_index);menu.stat_species.item_selected.emit(other_index)
	check(int(hunt_settings(game).stat_species)==other,"a species picked on 属性条件 is remembered")
	# A second target is chosen through the visible checklist's real signal.
	menu.target_button.get_popup().id_pressed.emit(other)
	var chosen: Array=[target,other];chosen.sort()
	check(hunt_settings(game).templates==chosen and menu.target_ids==chosen,"two checklist targets are saved without replacing the 属性条件 species")
	menu.show_capture_settings(true)
	check(str(game.viewer_pref("hunt_page","")) == "capture","the page shown is remembered on this device")
	menu.close_menu();menu.open_menu()
	check(menu.target_ids==chosen and menu.stat_species.get_selected_id()==other and menu.capture_page.visible,"reopened, the window shows the same target, 属性条件 species and page")
	menu.close_menu()

	# Elsewhere, choices are retained and only the local intersection may run.
	game.load_area_id(other_map,other_cell)
	menu.open_menu()
	var intersection: Array=chosen.filter(func(id):return id in elsewhere)
	check(menu.target_ids==chosen and (menu.target_button.text=="未选" if intersection.is_empty() else menu.target_button.text.contains("%d 种" % intersection.size())),"another place retains choices and shows only the local selected count")
	menu.level_one.button_pressed = false;menu.level_one.button_pressed = true
	game.flush_automation_settings()
	check(hunt_settings(game).templates==chosen and int(hunt_settings(game).stat_species)==other,"other controls preserve explicit multi-target preferences")
	menu.auto_capture.button_pressed = false
	menu.train_after_capture.button_pressed = false
	menu.start_hunt()
	check((not menu.running if intersection.is_empty() else menu.running and Rules.targets(game.backend.automation.hunt_filter)==intersection),"start refuses an empty local intersection or hunts exactly its selected species")
	check(hunt_settings(game).templates==chosen,"starting elsewhere never replaces saved choices")
	menu.close_menu()
	game.load_area_id(MAP,CELL)
	menu.open_menu()
	check(menu.target_ids==chosen and menu.target_button.text.contains("2 种"),"returning restores both checked local species")
	# Explicit none must also survive reopening and unrelated changes.
	menu.target_button.get_popup().id_pressed.emit(-3)
	menu.close_menu();menu.open_menu()
	menu.fast.button_pressed = not menu.fast.button_pressed
	check(menu.target_ids.is_empty() and hunt_settings(game).templates==[],"explicit none stays none after reopening and editing another control")
	for id in chosen:menu.target_button.get_popup().id_pressed.emit(id)
	menu.close_menu()

	# Another device (or the game after a restart) shows the same: the profile
	# carries the character's choices, viewer.cfg the page.
	var overrides: Dictionary = game.backend.session.automation_settings()
	await free_game(game)
	var again = await new_game()
	again.backend.session.set_automation_settings(overrides)
	again.backend.publish()
	again.load_area_id(MAP,CELL)
	var reopened = again.pet_hunt_menu
	reopened.open_menu()
	check(reopened.target_ids==chosen and reopened.stat_species.get_selected_id()==other,"a new game with the character's settings shows the same target and 属性条件 species")
	check(reopened.capture_page.visible,"and this device's last page")
	reopened.show_stat_settings()
	reopened.close_menu();reopened.open_menu()
	check(reopened.stat_page.visible,"属性条件 is remembered as the page too")
	reopened.close_menu()
	await free_game(again)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("HUNT WINDOW MEMORY: %d failures" % failures)
	quit(1 if failures else 0)
