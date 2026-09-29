extends SceneTree
## Minimizing 自动练级 and 自动抓极品 while they run: the window collapses to a
## progress bar, other panels (pets, warehouse) open and act normally and stay
## current, and restoring shows the backend's live progress.
var failures:=0
const PREFS:="user://automation-minimize-test-viewer.cfg"
class FixedTroop extends RefCounted:
	var troop: Dictionary
	func roll(_map, _cell, _rng) -> Dictionary:return troop.duplicate(true)
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
func frames(count: int) -> void:
	for i in range(count):await physics_frame
func choose_seed(game, count: int) -> int:
	var rng:=RandomNumberGenerator.new()
	for seed_value in range(10000):
		rng.seed=seed_value
		var valid:=true
		for i in range(count):
			var troop: Dictionary=game.encounter_catalog.roll(int(game.data.map_id),game.cell,rng)
			if troop.is_empty() or not game.battle_view.can_render_troop(troop.enemies):valid=false;break
		if valid:return seed_value
	return -1
func pet_id_not_active(game) -> String:
	var profile: Dictionary=game.session.snapshot()
	for i in range(profile.pets.size()):
		if i!=int(profile.active_pet) and i!=int(profile.get("ride_pet",-1)):return str(profile.pets[i].pet_id)
	return ""

func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	game.viewer_prefs_path=PREFS
	root.add_child(game)
	await process_frame
	game.session.grant_starter_pets()
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,10)
	game.session.gm_set_base_stat(-1,"strength",100)
	game.session.gm_set_base_stat(-1,"toughness",100)
	game.session.gm_heal()
	await training(game)
	await hunting(game)
	await find_pet(game)
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("AUTOMATION MINIMIZE: %d failures"%failures)
	quit(1 if failures else 0)

func training(game) -> void:
	var helper=game.training_helper
	helper.set_process(false)
	helper.open_menu();helper.compact.button_pressed=true;helper.battle_limit.value=200;helper.hp_floor.value=1;helper.multiplier.select(3);helper.speed.select(3)
	var seed_value:=choose_seed(game,4)
	check(seed_value>=0,"find deterministic valid source troops")
	game.encounter_rng.seed=seed_value
	helper.start_training();helper.advance()
	check(helper.running and helper.visible and helper.progress.visible and not helper.minimize_button.disabled,"running window offers 最小化")
	helper.minimize()
	var chip: Panel=helper.chip
	check(helper.minimized and not helper.visible and is_instance_valid(chip) and chip.visible,"minimize collapses the window into a progress bar")
	check(helper.running and game.paused_input,"run continues and the character stays in place")
	check(not game._panel_open(),"a minimized window does not count as an open panel")
	check(game.viewer_pref("training_minimized")==true,"this device remembers the minimized view")
	check(game.gamepad.panel()==null,"controller no longer treats the helper as the top panel")
	# Esc no longer reaches the helper: with nothing open it only toggles help off.
	await key(KEY_ESCAPE)
	check(helper.running and helper.minimized,"Esc does not stop minimized automation")
	var shown: String=chip.detail.text
	for i in range(60):
		if helper.battles>=2:break
		helper.advance()
	check(helper.battles>=2 and chip.detail.text!=shown and chip.detail.text.begins_with("%d 场"%helper.battles),"progress bar follows battles live")
	# The pet menu opens through the same hotkey path the player uses.
	game.show_adventure_menu("pets")
	var menu=game.adventure_menu
	check(menu.visible and helper.running,"pet menu opens while automation runs")
	var pet_id:=pet_id_not_active(game)
	check(not pet_id.is_empty(),"fixture has a spare carried pet")
	menu.pet_storage_open=true;menu.pet_storage_target_id=pet_id;menu.rebuild()
	await process_frame
	var stored_before: int=game.session.snapshot().get("pet_storage",[]).size()
	menu.panel.get_node("PetStoragePanel/StoreSelectedPet").pressed.emit()
	await process_frame
	var profile: Dictionary=game.session.snapshot()
	check(profile.pet_storage.size()==stored_before+1 and str(profile.pet_storage.back().pet_id)==pet_id,"storing a pet works beside running automation")
	var retrieve: Button=null
	var stored_row: Node=menu.panel.find_child("StorageRow_"+pet_id,true,false)
	for node in menu.panel.find_children("RetrievePet_*","Button",true,false):
		if stored_row!=null and stored_row.is_ancestor_of(node):retrieve=node
	check(retrieve!=null,"stored pet row offers 取出")
	if retrieve!=null:
		retrieve.pressed.emit();await process_frame
	check(game.session.snapshot().pet_storage.size()==stored_before,"retrieving it back works too")
	var drawn: Control=menu.panel
	var battles: int=helper.battles
	for i in range(60):
		if helper.battles>battles:break
		helper.advance()
	await create_timer(0.5).timeout
	await frames(3)
	check(helper.battles>battles and menu.visible and menu.panel!=drawn,"open warehouse redraws as automation changes the profile")
	check(chip.visible and chip.get_index()>menu.get_index(),"progress bar stays above the open menu")
	await key(KEY_ESCAPE)
	check(not menu.visible and helper.running and game.paused_input,"Esc closes the menu, not the automation; the map stays held")
	# Arriving on a map (another device's move, a reload) keeps the bar: the UI
	# is built once. Arrival where automation stands is not travel.
	game._followed=[int(game.data.map_id),game.cell]
	game.load_area_id(int(game.data.map_id),game.cell)
	check(chip.visible and helper.minimized and helper.running and game.paused_input,"a map load keeps the bar and holds the character")
	game.gamepad.hud_mode=true
	check(chip.restore_button in game.gamepad.candidates(game.gamepad.panel()),"controller HUD mode reaches 展开")
	game.gamepad.hud_mode=false
	game.show_adventure_menu("pets")
	chip.restore_button.pressed.emit()
	check(not helper.minimized and not chip.visible and helper.visible and helper.progress.visible and not helper.panel.visible,"展开 restores the progress window")
	check(not menu.visible and game.paused_input,"restoring closes the pet menu and keeps the modal lock")
	check(game.viewer_pref("training_minimized")==false,"restoring is remembered too")
	check(helper.status.text.contains("%d 场"%helper.battles),"restored window shows current progress")
	helper.close_menu()
	check(not helper.running and not helper.visible and not chip.visible,"closing still stops as before")
	for i in range(20):
		if not game.battle_session.snapshot().active and game.session._pending.is_empty():break
		game.acknowledge_presentation();game.return_from_battle();game.battle_view._process(0.2)
		await process_frame
	if game.battle_view.visible:
		game.battle_session.developer_escape();game.battle_view._process(1.0);game.return_from_battle()
	# A run that ends while minimized drops its bar and releases the map.
	helper.open_menu();helper.battle_limit.value=1;helper.start_training();helper.advance()
	helper.minimize()
	for i in range(60):
		if not helper.running:break
		helper.advance()
	check(not helper.running and not helper.minimized and not helper.chip.visible and not game.paused_input,"finished run removes the bar and unlocks walking")
	check(game.message.text.contains("自动练级"),"finish reason reaches the message line")

func hunting(game) -> void:
	check(game.switch_area(true,Vector2i(45,45)),"enter original wilderness for hunting")
	var hunt=game.pet_hunt_menu
	hunt.set_process(false)
	hunt.open_menu();hunt.auto_capture.button_pressed=false;hunt.train_after_capture.button_pressed=false
	check(hunt.minimize_button.disabled,"最小化 needs a running scan")
	hunt.rate.value=20
	game.encounter_rng.seed=1234
	hunt.start_hunt()
	check(hunt.running and not hunt.minimize_button.disabled,"running scan offers 最小化")
	hunt.minimize()
	var chip: Panel=hunt.chip
	check(hunt.minimized and not hunt.visible and chip.visible and game.gamepad.panel()==null,"hunt window collapses to its bar")
	hunt.set_process(true)
	game.show_adventure_menu("pets")
	await frames(20)
	check(hunt.running and hunt.rolls>0,"scan keeps running behind the pet menu")
	check(chip.detail.text.begins_with("遇敌 %d 组"%hunt.rolls),"bar shows live encounter count")
	# Warehouse work beside the scan: store a pet, then release it for good.
	var menu=game.adventure_menu
	var pet_id:=pet_id_not_active(game)
	menu.pet_storage_open=true;menu.pet_storage_target_id=pet_id;menu.rebuild()
	menu.panel.get_node("PetStoragePanel/StoreSelectedPet").pressed.emit()
	await frames(2)
	check(game.session.snapshot().pet_storage.any(func(pet):return str(pet.pet_id)==pet_id),"storing works beside the minimized scan")
	var released: Dictionary=game.release_pets([pet_id])
	await create_timer(0.5).timeout
	await frames(3)
	check(int(released.released)==1 and not game.session.snapshot().pet_storage.any(func(pet):return str(pet.pet_id)==pet_id),"releasing a stored pet works beside the scan")
	check(menu.visible and menu.panel.find_children("StorageRow_"+pet_id,"",true,false).is_empty(),"open warehouse drops the released pet")
	check(hunt.running and hunt.minimized,"warehouse work leaves the scan running")
	game.close_adventure_menu()
	await frames(5)
	check(hunt.running and game.paused_input,"closing the menu neither stops the scan nor frees the map")
	hunt.set_process(false)
	var rolls: int=hunt.rolls
	hunt.open_menu()
	check(hunt.visible and not hunt.minimized and not chip.visible and not hunt.stop_button.disabled and hunt.start_button.disabled,"自动抓极品 button restores the running window")
	check(hunt.status.text.contains("已遇敌 %d 组"%rolls),"restored window shows current scan count")
	hunt.close_menu()
	check(not hunt.running and not hunt.visible and not game.paused_input,"closing still stops the scan")

func find_pet(game) -> void:
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,120);game.session.gm_set_base_stat(-1,"toughness",500);game.session.gm_heal()
	var flow=game.pet_workflow;flow.set_process(false)
	var hunt=game.pet_hunt_menu;hunt.set_process(false)
	var helper=game.training_helper;helper.set_process(false)
	hunt.open_menu();hunt.apply_preset(0)
	check(flow.start_cycle(),"find-pet cycle starts")
	hunt.minimize()
	check(hunt.minimized and hunt.chip.visible and hunt.chip.title.text.contains("找宠流程"),"cycle minimizes with its own progress heading")
	game.show_adventure_menu("pets")
	var fixture=FixedTroop.new()
	var rng=RandomNumberGenerator.new();rng.seed=1234
	for i in range(100):
		var rolled: Dictionary=game.encounter_catalog.roll(100,game.cell,rng)
		for actor in rolled.get("enemies",[]):
			if int(actor.level)==1 and actor.can_capture and game.battle_view.can_render_troop([actor]):
				actor.hp=1
				fixture.troop={"enemies":[actor]};break
		if not fixture.troop.is_empty():break
	hunt.hunt_catalog=fixture;hunt.scan_once()
	check(flow.phase=="capture" and hunt.minimized and not helper.visible and game.adventure_menu.visible,"capture phase stays minimized behind the open menu")
	for i in range(100):
		game.battle_view._process(0.2);helper.advance();flow.advance()
		if flow.phase!="capture":break
	check(flow.phase=="compare" and not hunt.minimized and not hunt.chip.visible,"finished cycle drops the bar")
	check(game.adventure_menu.visible and game.adventure_menu.pet_compare_open,"cycle result opens the comparison as before")
