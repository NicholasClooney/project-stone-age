extends SceneTree
## Actual viewport input regression: directional blocked clicks and interior exits.
var game
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, description: String) -> void:
	if not ok:failures.append(description)
func frames(count: int = 3) -> void:
	for i in range(count):await process_frame
func click_cell(cell: Vector2i, button: int = MOUSE_BUTTON_LEFT, press: bool = true) -> void:
	var screen: Vector2 = game.get_global_transform_with_canvas() * game.project(Vector2(cell))
	var move := InputEventMouseMotion.new()
	move.position = screen
	root.push_input(move,true)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = screen
	event.pressed = press
	root.push_input(event,true)
	if press:
		event = event.duplicate()
		event.pressed = false
		root.push_input(event,true)
func settle(expected_map: int = -1) -> void:
	for i in range(160):
		game._physics_process(0.25)
		await frames(1)
		if not game.moving and game.path.is_empty() and (expected_map < 0 or int(game.data.map_id) == expected_map):
			# Deferred transitions must complete before considering the movement settled.
			await frames(4)
			if not game.paused_input:break
func enter_shop(cell: Vector2i) -> void:
	check(game.load_area_id(1002,cell),"shop fixture loads")
	await frames()
	game.camera.reset_smoothing()
	await frames()
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await frames()
	game.music.stop()
	game.muted = true
	check(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color") == Color.BLACK,"outside-map background is black")
	await enter_shop(Vector2i(11,15))
	check(not game.is_walkable(Vector2i(8,15)),"outside click targets non-floor")
	click_cell(Vector2i(8,15))
	check(not game.path.is_empty() or game.moving,"actual outside-floor mouse click queues directional movement")
	await settle(1000)
	check(int(game.data.map_id) == 1000,"outside-floor click crosses shop doorway into Samgir")
	check(not game.paused_input and not game.moving,"portal releases input after transition")
	await enter_shop(Vector2i(11,18))
	click_cell(Vector2i(11,11))
	await settle()
	check(int(game.data.map_id) == 1002 and game.cell == Vector2i(11,13),"blocked target walks toward wall without crossing it")
	check(not game.can_step(Vector2i(11,13),Vector2i(12,12)),"diagonal move cannot clip blocked corner")
	await enter_shop(Vector2i(11,15))
	click_cell(Vector2i(8,15),MOUSE_BUTTON_LEFT,false)
	await settle()
	check(game.cell == Vector2i(11,15) and game.path.is_empty(),"release-only cancelled click does not move")
	click_cell(Vector2i(8,15),MOUSE_BUTTON_RIGHT)
	await settle()
	check(game.cell == Vector2i(11,15) and game.path.is_empty(),"secondary click does not move")
	game.show_adventure_menu("inventory")
	check(game.adventure_menu.visible,"modal fixture opens")
	click_cell(Vector2i(8,15))
	for i in range(5):game._physics_process(0.25)
	check(game.cell == Vector2i(11,15) and game.path.is_empty(),"modal click cannot route player behind interface")
	game.close_adventure_menu()
	game.music.stop()
	game.effect.stop()
	await create_timer(0.3).timeout
	game.queue_free()
	await frames()
	await create_timer(0.3).timeout
	for failure in failures:push_error("FAIL: " + failure)
	print("WORLD FIDELITY: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
