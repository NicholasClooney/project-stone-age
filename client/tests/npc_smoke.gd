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
func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func click_at(point: Vector2) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event,true)
func arrive() -> void:
	var frames := 0
	while not game.dialogue.visible and frames<600:
		await physics_frame
		frames += 1
	print("Arrival state: ",game.cell," pending=",game.pending_talk," path=",game.path.size()," moving=",game.moving)
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await ticks(3)
	check(game.npc_cell==Vector2i(93,72),"NPC uses original outdoor location")
	check(game.npc_data.graphic==16039 and game.npc_data.bitmap==5885,"NPC logical graphic resolves to original archive bitmap")
	check(not game.is_walkable(game.npc_cell) and game.navigation.is_point_solid(game.npc_cell),"NPC blocks both keyboard and path movement")
	game.approach_npc()
	await ticks(4)
	check(game.pending_talk and not game.dialogue.visible,"conversation waits for arrival")
	key(KEY_S,true)
	await ticks(2)
	key(KEY_S,false)
	check(not game.pending_talk,"manual movement cancels pending talk")
	game.reset_player()
	game.approach_npc()
	game.walk_to(Vector2i(85,95))
	check(not game.pending_talk,"ground click cancels pending talk")
	game.reset_player()
	# Exercise the same sprite hit test used by mouse input, while walking.
	game.request_step(game.cell+Vector2i(1,0))
	game.handle_world_click(game.npc_sprite.global_position+Vector2(20,40))
	await arrive()
	check(game.dialogue.visible and game.in_talk_range(game.cell),"sprite click walks around obstacles and opens dialogue next to NPC")
	check(not game.moving and game.player.action==3,"player is idle before talking")
	check(game.last_ui_sound==202 and game.effect.stream.resource_path.ends_with("sas_02.wav"),"dialogue opens with original window sound")
	check(game.dialogue_name.text=="村民" and game.dialogue_text.text==game.npc_data.text,"dialogue displays imported name and original line")
	var safe=game.cell
	key(KEY_W,true)
	game.handle_world_click(game.project(Vector2(80,90)))
	await ticks(20)
	check(game.cell==safe and game.held.is_empty() and game.path.is_empty(),"dialogue consumes movement and map clicks")
	key(KEY_ESCAPE,true)
	key(KEY_ESCAPE,false)
	await ticks(3)
	check(not game.dialogue.visible and not game.paused_input,"Escape closes dialogue")
	check(game.last_ui_sound==203 and game.effect.stream.resource_path.ends_with("sas_03.wav"),"dialogue closes with original window sound")
	key(KEY_W,false)
	click_at(game.npc_sprite.get_global_transform_with_canvas()*Vector2(20,40))
	await ticks(3)
	check(game.dialogue.visible,"actual mouse click reopens adjacent conversation")
	click_at(game.find_child("DevHelp",true,false).get_global_rect().get_center())
	await ticks(2)
	check(game.dialogue.visible and not game.help.visible,"modal overlay prevents underlying Help button clicks")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/samgir-npc.png"))
	key(KEY_ENTER,true)
	key(KEY_ENTER,false)
	await ticks(3)
	check(not game.dialogue.visible,"Enter closes dialogue without reopening")
	game.walk_to(game.SPAWN)
	check(not game.path.is_empty(),"exploration resumes after dialogue")
	game.clear_input()
	game.approach_npc()
	game.clear_input()
	check(not game.pending_talk,"explicit route cancellation clears pending interaction")
	game.approach_npc()
	await ticks(3)
	var close_button = game.dialogue.find_child("ConfirmDialogue",true,false)
	click_at(close_button.get_global_rect().get_center())
	await ticks(3)
	check(not game.dialogue.visible and not game.paused_input,"clicking 确定 closes dialogue")
	game.reset_player()
	for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		game.navigation.set_point_solid(game.npc_cell+offset,true)
	game.approach_npc()
	await ticks(3)
	check(not game.pending_talk and not game.dialogue.visible and game.path.is_empty(),"unreachable NPC cannot open remote dialogue")
	for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var point: Vector2i = game.npc_cell+offset
		game.navigation.set_point_solid(point,not game.is_walkable(point))
	game.music.stop()
	game.effect.stop()
	await create_timer(0.2).timeout
	game.queue_free()
	await ticks(2)
	print("NPC SMOKE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
