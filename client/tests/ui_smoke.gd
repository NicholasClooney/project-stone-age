extends SceneTree
var game
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, description: String) -> void:
	if value: print("PASS: "+description)
	else:
		push_error("FAIL: "+description)
		failures+=1
func ticks(count: int) -> void:
	for i in range(count): await physics_frame
func pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position=point
	root.push_input(event,true)
func click(point: Vector2) -> void:
	pointer(point)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		event.position=point
		root.push_input(event,true)
func key(code: int, ctrl: bool=false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.ctrl_pressed=ctrl
		event.pressed=down
		root.push_input(event,true)
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/"+name+".png"))
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await ticks(4)
	var hud=game.classic_hud
	check(hud.art.size()==38,"38 original UI images load")
	pointer(Vector2(650,400))
	await ticks(15)
	check(not hud.taskbar.visible,"bottom menus retract outside hover area")
	pointer(Vector2(650,790))
	await ticks(20)
	check(hud.taskbar.visible and hud.reveal>0.99,"bottom hover reveals all seven menu items")
	var safe=game.cell
	for i in range(1,7):
		click(hud.task_buttons[i].get_global_rect().get_center())
	await ticks(4)
	check(game.path.is_empty() and game.cell==safe,"visual-only menu items do not trigger movement or gameplay")
	click(hud.task_buttons[0].get_global_rect().get_center())
	await ticks(3)
	check(hud.map_panel.visible,"original Map button opens window")
	check(hud.map_coordinates.text.contains("80") and hud.map_coordinates.text.contains("90"),"map coordinates match player")
	await capture("classic-ui-map")
	click(hud.map_panel.get_global_rect().get_center())
	await ticks(3)
	check(game.path.is_empty(),"clicking map surface does not move character")
	click(hud.map_panel.get_node("CloseMap").get_global_rect().get_center())
	check(not hud.map_panel.visible,"original close button closes map")
	key(KEY_M,true)
	check(hud.map_panel.visible and not game.muted,"Ctrl+M opens map without muting music")
	key(KEY_ESCAPE)
	check(not hud.map_panel.visible,"Escape closes map")
	click(game.find_child("MaxOut",true,false).get_global_rect().get_center())
	await ticks(30)
	check(game.overview and game.camera.zoom.x<0.1,"Max out fits whole village")
	check(game.get_child(0).radius>=160,"overview rendering covers all terrain cells")
	var expected=game.project(Vector2(79.5,79.5))
	check(game.camera.global_position.distance_to(expected)<1,"overview centers on map rather than player")
	await capture("classic-ui-overview")
	game.set_zoom(1)
	await ticks(3)
	check(not game.overview and game.camera.position==Vector2(0,-25),"normal zoom restores player camera")
	key(KEY_M,true)
	game.request_step(game.cell+Vector2i(1,0))
	await ticks(25)
	check(game.cell==Vector2i(81,90) and hud.map_coordinates.text.contains("81"),"map remains live while walking")
	key(KEY_ESCAPE)
	await capture("classic-ui")
	game.music.stop()
	game.effect.stop()
	await create_timer(0.2).timeout
	game.queue_free()
	await ticks(2)
	print("CLASSIC UI RESULT: %d failures" % failures)
	quit(1 if failures else 0)
