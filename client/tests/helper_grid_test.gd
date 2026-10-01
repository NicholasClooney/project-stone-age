extends SceneTree
## Real scene and device prefs, including a backend-free remote viewer.
const Wait = preload("res://tests/support/wait.gd")
const PREFS := "user://helper-grid-a.cfg"
const OTHER := "user://helper-grid-b.cfg"
var failures := 0

func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func make_game(path: String):
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	game.viewer_prefs_path = path
	root.add_child(game)
	check(await Wait.until(self,func():return not game.data.is_empty()),"Scene starts")
	return game

func dispose(game) -> void:
	if is_instance_valid(game.link) and game.link.has_method("close"):game.link.close()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

func click(button: Button) -> void:
	check(await Wait.until(self,func():return button.is_visible_in_tree() and button.size.x>0),"Click target laid out")
	var scroll = button.find_parent("HelperScroll")
	if scroll:scroll.ensure_control_visible(button)
	check(await Wait.until(self,func():
		var motion := InputEventMouseMotion.new()
		motion.position = button.get_global_transform_with_canvas()*(button.size/2)
		root.push_input(motion,true)
		return root.gui_get_hovered_control()==button),"Viewport mouse reaches button")
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = button.get_global_transform_with_canvas()*(button.size/2)
		root.push_input(event,true)
	await process_frame

func run() -> void:
	for path in [PREFS,OTHER]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var game = await make_game(PREFS)
	var menu = game.helper_menu
	menu.open_menu()
	await click(menu.find_child("HelperNoRandomEncounters",true,false))
	check(game.state.derived.get("no_random_encounters",false),"Real helper click enables server random-encounter setting")
	await click(menu.find_child("HelperNoRandomEncounters",true,false))
	check(not game.state.derived.get("no_random_encounters",true),"Real helper click disables setting")
	await click(menu.find_child("HelperViewGrid",true,false))
	check(menu.view=="grid" and game.viewer_pref("helper_view")=="grid","Real click switches and saves device grid")
	menu.rebuild()
	check(menu.view=="grid","Rebuild keeps preference")
	var opened := {
		"HelperQuest":func():return game.quest_helper_menu.visible,
		"HelperTraining":func():return game.training_helper.visible,
		"HelperPetHunt":func():return game.pet_hunt_menu.visible,
		"HelperPets":func():return game.adventure_menu.visible,
		"HelperEncyclopedia":func():return game.pet_encyclopedia.visible,
		"HelperPetRecords":func():return game.adventure_menu.visible and game.adventure_menu.pet_records_open,
		"HelperRadio":func():return game.radio_panel.visible,
		"HelperMapOverview":func():return game.dev_map_overview.visible,
		"HelperTravel":func():return game.leveling_destinations.visible,
		"HelperGM":func():return game.dev_gm_menu.visible,
	}
	var fingerprints := {}
	for id in opened:
		menu.open_menu()
		var button: Button = menu.find_child(id,true,false)
		check(button!=null and not button.tooltip_text.is_empty(),id+" keeps button name and explanation")
		var icon: TextureRect = button.get_child(0).get_child(0)
		var fingerprint = hash(icon.texture.get_image().get_data())
		check(not fingerprints.has(fingerprint),id+" has a distinct icon")
		fingerprints[fingerprint] = true
		if id=="HelperQuest":await click(button)
		else:button.pressed.emit()
		check(not menu.visible and opened[id].call(),id+" opens original destination")
		for panel in [game.quest_helper_menu,game.training_helper,game.pet_hunt_menu,game.pet_encyclopedia,game.dev_gm_menu,game.leveling_destinations]:
			if panel.visible:panel.close_menu()
		if game.dev_map_overview.visible:game.dev_map_overview.close_map()
		if game.adventure_menu.visible:game.close_adventure_menu()
		if game.radio_panel.visible:game.radio_panel.close_panel()
		await process_frame
	# A battle shell needs no running combat, only the existing view visibility.
	game.battle_view.show()
	for mode in ["grid","list"]:
		game.set_viewer_pref("helper_view",mode)
		menu.open_menu()
		for id in opened:
			var allowed: bool = id in ["HelperPets","HelperEncyclopedia","HelperPetRecords","HelperRadio","HelperGM"]
			check(menu.find_child(id,true,false).disabled!=allowed,mode+" battle rule "+id)
		game.training_helper.minimized = true
		game.pet_hunt_menu.minimized = true
		menu.rebuild()
		check(not menu.find_child("HelperTraining",true,false).disabled and not menu.find_child("HelperPetHunt",true,false).disabled,"Minimized automation remains available")
		game.training_helper.minimized = false
		game.pet_hunt_menu.minimized = false
	game.battle_view.hide()
	game.set_viewer_pref("helper_view","grid")
	menu.rebuild()
	check(game.gamepad.candidates(menu).any(func(control):return control.name=="HelperQuest"),"Gamepad reaches task tile")
	var quest: Button = menu.find_child("HelperQuest",true,false)
	quest.grab_focus()
	check(quest.has_focus(),"Keyboard can focus tile")
	for down in [true,false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = down
		root.push_input(key,true)
	check(await Wait.until(self,func():return game.quest_helper_menu.visible),"Keyboard Enter opens focused task tile")
	game.quest_helper_menu.close_menu()
	menu.open_menu()
	# Force a small actual viewport; layouts must stay within it.
	var original_scale: Vector2i = root.content_scale_size
	root.content_scale_size = Vector2i(360,420)
	menu.relayout()
	check(await Wait.until(self,func():return menu.size.x<=game.get_viewport_rect().size.x and menu.size.y<=game.get_viewport_rect().size.y),"Small viewport bounds menu with scroll")
	root.content_scale_size = original_scale
	await dispose(game)
	game = await make_game(PREFS)
	game.helper_menu.open_menu()
	check(game.helper_menu.view=="grid","New scene restores device grid")
	await dispose(game)
	game = await make_game(OTHER)
	game.helper_menu.open_menu()
	check(game.helper_menu.view=="list","Different device defaults to list")
	await dispose(game)
	var backend = preload("res://server/backend.gd").new()
	root.add_child(backend)
	var server = preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"Ephemeral test server starts")
	var script = load("res://scripts/game.gd")
	script.server_url_override = "ws://127.0.0.1:%d" % server.port
	game = await make_game(PREFS)
	script.server_url_override = ""
	check(await Wait.until(self,func():return game.link.online),"Remote viewer connects")
	check(game.backend==null,"Remote grid viewer has no backend")
	game.helper_menu.open_menu()
	check(game.helper_menu.view=="grid","Remote viewer uses own device preference")
	await click(game.helper_menu.find_child("HelperNoRandomEncounters",true,false))
	check(await Wait.until(self,func():return game.state.derived.get("no_random_encounters",false)),"Remote true click enables authoritative helper setting")
	check(backend.session.snapshot().no_random_encounters,"Remote setting reaches server profile")
	await click(game.helper_menu.find_child("HelperViewList",true,false))
	await click(game.helper_menu.find_child("HelperViewGrid",true,false))
	await click(game.helper_menu.find_child("HelperQuest",true,false))
	check(game.quest_helper_menu.visible,"Remote viewport grid click opens task helper")
	game.quest_helper_menu.close_menu()
	game.helper_menu.open_menu()
	check(game.gamepad.candidates(game.helper_menu).any(func(control):return control.name=="HelperQuest"),"Remote gamepad reaches grid task tile")
	await dispose(game)
	server.stop();server.queue_free();backend.queue_free()
	for path in [PREFS,OTHER]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("HELPER GRID: %d failures" % failures)
	quit(1 if failures else 0)
