extends SceneTree
## 自动抓极品 opens as it was last used. The character's settings (saved in
## the profile, so other devices and a restarted server show them too): the
## target species, kept even where it does not live (the window then shows
## 任何 and hunts any species there without forgetting the choice), and the
## species the 属性条件 page shows, which follows the target. This device's
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
	var index: int = menu.species.get_item_index(target)
	menu.species.select(index);menu.species.item_selected.emit(index)
	check(int(hunt_settings(game).template)==target,"the target species is saved with the character")
	check(menu.stat_species.get_selected_id()==target and int(hunt_settings(game).stat_species)==target,"属性条件 shows the target, remembered too")
	# 属性条件 can show another species; that is remembered as well.
	var other_index: int = menu.stat_species.get_item_index(92)
	menu.stat_species.select(other_index);menu.stat_species.item_selected.emit(other_index)
	check(int(hunt_settings(game).stat_species)==92,"a species picked on 属性条件 is remembered")
	menu.show_capture_settings(true)
	check(str(game.viewer_pref("hunt_page","")) == "capture","the page shown is remembered on this device")
	menu.close_menu();menu.open_menu()
	check(menu.species.get_selected_id()==target and menu.stat_species.get_selected_id()==92 and menu.capture_page.visible,"reopened, the window shows the same target, 属性条件 species and page")
	menu.close_menu()

	# Elsewhere the target does not live: 任何 is shown, the choice kept.
	game.load_area_id(other_map,other_cell)
	menu.open_menu()
	check(menu.species.get_selected_id()==-1 and menu._template_fallback,"where the target does not live the window shows 任何")
	menu.level_one.button_pressed = false;menu.level_one.button_pressed = true
	game.flush_automation_settings()
	check(int(hunt_settings(game).template)==target and int(hunt_settings(game).stat_species)==92,"other changes there keep the saved target")
	menu.auto_capture.button_pressed = false
	menu.train_after_capture.button_pressed = false
	menu.start_hunt()
	check(menu.running and int(game.backend.automation.hunt_filter.template)==-1,"started there, it hunts any species")
	check(int(hunt_settings(game).template)==target,"and the saved target is still the one chosen")
	menu.close_menu()
	game.load_area_id(MAP,CELL)
	menu.open_menu()
	check(menu.species.get_selected_id()==target and not menu._template_fallback,"back where it lives, the target is shown again")
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
	check(reopened.species.get_selected_id()==target and reopened.stat_species.get_selected_id()==92,"a new game with the character's settings shows the same target and 属性条件 species")
	check(reopened.capture_page.visible,"and this device's last page")
	reopened.show_stat_settings()
	reopened.close_menu();reopened.open_menu()
	check(reopened.stat_page.visible,"属性条件 is remembered as the page too")
	reopened.close_menu()
	await free_game(again)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("HUNT WINDOW MEMORY: %d failures" % failures)
	quit(1 if failures else 0)
