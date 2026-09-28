extends SceneTree
## A map change rebuilds only the world: panels stay open with their state,
## map-specific UI follows the new map, and nothing from the old map lingers.
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func overlays(game) -> int:
	var count := 0
	for node in game.ui_root.get_children():
		if node is Control and node.mouse_filter==Control.MOUSE_FILTER_STOP and node.get_anchor(SIDE_RIGHT)==1.0 and node.get_anchor(SIDE_BOTTOM)==1.0 and node.get_script()==null:count += 1
	return count

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	await process_frame
	game.random_encounters = false
	var hud = game.classic_hud
	var menu = game.adventure_menu
	var baseline := overlays(game)
	check(game.dev_bar.has_node("ExploreOutside") and game.dev_bar.get_node("ExploreOutside").text=="村外探险","Samgir shows its own DEV shortcuts")

	game.show_adventure_menu("pets")
	check(game.paused_input,"an open panel pauses walking")
	game.load_area_id(100,Vector2i(637,493))
	await process_frame
	check(is_instance_valid(menu) and game.adventure_menu==menu and menu.visible,"an open panel stays open across a map change")
	check(game.paused_input,"walking stays paused while that panel is open")
	check(game.classic_hud==hud,"the HUD is kept")
	check(hud.map_name.text==game.area_name() and is_same(hud.map_view.built_for,game.data),"the map window shows the new map")
	check(game.dev_bar.get_node("ExploreOutside").text=="返回村庄" and is_instance_valid(game.boss_button),"DEV shortcuts follow the new map")
	check(overlays(game)==baseline,"the old map's travel dialogue is removed")
	game.close_adventure_menu()
	check(not game.paused_input,"closing the panel lets the player walk")

	game.load_area_id(1000,Vector2i(85,95))
	await process_frame
	check(not game.paused_input,"a map change with nothing open leaves walking enabled")
	check(game.boss_button==null and game.dev_bar.get_node("ExploreOutside").text=="村外探险","returning restores the village shortcuts")
	var names: Array = []
	for node in game.dev_bar.get_children():names.append(str(node.name))
	check(names.count("ExploreOutside")==1,"map shortcuts are replaced, not duplicated")
	check(overlays(game)==baseline,"repeated map changes leave one travel dialogue")

	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream = null;game.effect.stream = null;game.queue_free()
	# The audio thread releases stopped playbacks a moment later; quitting sooner leaks them.
	await create_timer(0.3).timeout
	print("MAP CHANGE UI: %d failures" % failures)
	quit(1 if failures else 0)
