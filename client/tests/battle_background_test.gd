extends SceneTree
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool, message: String) -> void:
	print(("PASS: " if value else "FAIL: ")+message)
	if not value:failures+=1
func run() -> void:
	var selector = preload("res://scripts/battle_background.gd").new()
	check(selector.catalog.get("backgrounds",{}).size()==217,"217 original battle terrain assets are available")
	var visited := {}
	var bitmaps: PackedInt32Array = selector.catalog.bitmaps
	for i in range(bitmaps.size()):
		var tile := str(int(selector.catalog.grounds[i]))
		var choices: Array = selector.choices(int(tile))
		if choices==[0,0,0]:continue
		if choices.any(func(x):return not selector.catalog.backgrounds.has(str(int(x)))):continue
		check(selector.ground_of(bitmaps[i])==int(tile),"bitmap %d finds its ground %s" % [bitmaps[i],tile])
		selector.choose(str(bitmaps[i]))
		check(choices.any(func(x):return int(x)==selector.last_field),"ground %s selects one of original three fields" % tile)
		visited[selector.last_field]=true
		if visited.size()>=4:break
	check(visited.size()>=4,"different ground types produce distinct battlefields")
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game)
	await process_frame
	await process_frame
	game.open_battle_config(game.session.start_battle_config("wooli",false,1))
	await process_frame
	var view = game.battle_view
	check(view.background_selector.last_ground>=0,"battle reads the encounter cell's original ground graphic")
	check(view.battlefield.texture.resource_path.contains("backgrounds/"),"battle renders selected original terrain instead of fixed background")
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	quit(1 if failures else 0)
