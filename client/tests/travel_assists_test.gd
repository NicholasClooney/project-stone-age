extends SceneTree
var failures:=0
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game)
	await process_frame
	game.random_encounters=false
	var selector=game.dev_map_overview.selector
	check(selector.item_count==game.world_catalog.navigation_maps().size(),"map dropdown includes all nonbuilding regions")
	check(selector.get_item_index(2002)<0 and selector.get_item_index(1002)<0,"map dropdown hides all village buildings")
	game.dev_blink_mode=true
	game.handle_world_click(game.project(Vector2(85,95)))
	check(game.cell==Vector2i(85,95) and game.path.is_empty() and not game.moving,"world click blinks immediately without walk path")
	var saved: Vector2i=game.cell
	check(not game.blink_to(Vector2i(-100,-100)) and game.cell==saved,"out-of-map click cannot move into void")
	game.paused_input=true
	check(not game.blink_to(Vector2i(80,90)) and game.cell==saved,"modal state blocks blink")
	game.paused_input=false
	game.dev_blink_mode=false
	game.handle_world_click(game.project(Vector2(80,90)))
	check(game.cell==saved and not game.path.is_empty(),"disabling blink restores click-to-walk")
	game.clear_input()
	game.dev_map_overview.open_map()
	check(game.dev_map_overview.visible and game.paused_input,"all destination browser opens from game integration")
	game.dev_map_overview.close_map()
	game.leveling_destinations.open_menu()
	game.leveling_destinations.level.value=100
	check(not game.leveling_destinations.ranked.is_empty(),"high-level training recommendations available")
	var row: Dictionary=game.leveling_destinations.ranked[0].duplicate(true)
	check(game.leveling_destinations.visit(0),"training teleport lands at verified regional encounter point")
	check(int(game.data.map_id)==int(row.map_id) and game.cell==Vector2i(row.cell[0],row.cell[1]),"training landing uses exact source region")
	check(game.world_catalog.field(int(game.data.map_id)),"new training areas support ordinary encounters")
	game.encounter_rng.seed=0
	check(game.begin_wild_battle(),"new training region enters original enemy battle")
	if game.battle_session.snapshot().active:
		game.battle_action("developer_escape")
		for i in range(200):game.battle_view._process(0.1)
		game.return_from_battle()
	check(game.session._pending.is_empty(),"training battle settles and returns normally")
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null;game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("TRAVEL ASSISTS: %d failures"%failures);quit(1 if failures else 0)
