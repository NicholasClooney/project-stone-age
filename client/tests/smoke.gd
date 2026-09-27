extends SceneTree
var game
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, description: String) -> void:
	if value:
		print("PASS: "+description)
	else:
		push_error("FAIL: "+description)
		failures += 1
func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
func press(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
func settle() -> void:
	while game.moving:
		await physics_frame
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await ticks(3)
	check(game.load_error.is_empty(),"original assets load")
	check(game.textures.size()>=1000,"original map and character textures loaded")
	check(game.is_walkable(game.SPAWN),"spawn lies on walkable original map cell")
	check(game.music.playing,"original village music playing")
	for pair in [[KEY_W,Vector2i(1,-1),4],[KEY_S,Vector2i(-1,1),0],[KEY_A,Vector2i(-1,-1),2],[KEY_D,Vector2i(1,1),6]]:
		game.reset_player()
		press(pair[0],true)
		await ticks(8)
		check(game.moving and game.player.action==4,"keyboard starts original walk animation")
		check(game.player.facing==pair[2],"legacy facing matches movement")
		press(pair[0],false)
		await settle()
		await ticks(2)
		check(game.cell==game.SPAWN+pair[1],"cardinal move finishes one valid grid step")
		check(game.player.action==3,"movement returns to original idle animation")
	var idle_image=game.player.current_image
	await create_timer(0.3).timeout
	check(game.player.current_image!=idle_image,"idle advances original animation frames")
	var obstacle_found := false
	for y in range(60,105):
		for x in range(60,105):
			var cell := Vector2i(x,y)
			if game.is_walkable(cell) and not game.is_walkable(cell+Vector2i.RIGHT):
				check(not game.can_step(cell,cell+Vector2i.RIGHT),"original object collision blocks movement")
				obstacle_found=true
				break
		if obstacle_found: break
	check(obstacle_found,"map contains verifiable collision boundary")
	check(not game.is_walkable(Vector2i(-1,80)) and not game.is_walkable(Vector2i(160,80)),"map bounds reject invalid cells")
	game.reset_player()
	game.walk_to(Vector2i(85,95))
	check(not game.path.is_empty(),"click-to-walk finds a route")
	var frames := 0
	while (not game.path.is_empty() or game.moving) and frames<1500:
		await physics_frame
		frames+=1
	check(game.cell==Vector2i(85,95),"click route reaches destination without crashing")
	var safe=game.cell
	game.walk_to(Vector2i(-1,-1))
	await ticks(2)
	check(game.cell==safe and game.path.is_empty(),"invalid destination does not mutate player state")
	# Exercise all directions and repeated route replacements through actual game logic.
	var stress_valid := true
	for i in range(200):
		var d: Vector2i = game.SCREEN_DIRECTIONS[i%8]
		if game.request_step(game.cell+d):
			await settle()
		stress_valid = stress_valid and game.is_walkable(game.cell)
	check(stress_valid,"200 repeated movement steps stay on valid terrain")
	game.change_character()
	await ticks(2)
	check(game.player.character_id=="100005","original character switching works")
	game.player.set_action(5)
	await ticks(2)
	check(game.player.action==5,"original sit animation supported")
	game.music.seek(game.music.stream.get_length()-0.1)
	await create_timer(0.35).timeout
	check(game.music.playing,"original BGM survives loop boundary")
	game.toggle_mute()
	check(game.music.volume_db<=-79,"mute works")
	game.toggle_mute()
	check(game.music.volume_db>-79,"unmute restores volume")
	game.clear_input()
	check(game.held.is_empty() and game.path.is_empty(),"focus reset clears input and route")
	game.music.stop()
	game.effect.stop()
	await create_timer(0.2).timeout
	game.queue_free()
	await ticks(2)
	print("ORIGINAL-ASSET SMOKE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
