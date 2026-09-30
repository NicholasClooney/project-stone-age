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
	check(hud.art.size()==50,"50 original UI and dialogue images load (with the V.S. battle mark)")
	pointer(Vector2(650,400))
	await ticks(15)
	check(not hud.taskbar.visible,"bottom menus retract outside hover area")
	pointer(Vector2(650,790))
	await ticks(20)
	check(hud.taskbar.visible and hud.reveal>0.99,"bottom hover reveals all seven menu items")
	var safe=game.cell
	for i in range(1,7):
		pointer(Vector2(650,790))
		await ticks(20)
		click(hud.task_buttons[i].get_global_rect().get_center())
		await ticks(2)
		if i==6:
			check(game.settings_menu.visible and game.paused_input,"系统 opens 设置 and pauses walking")
			click(hud.task_buttons[i].get_global_rect().get_center())
			await ticks(2)
			check(not game.settings_menu.visible and not game.paused_input,"系统 again closes 设置 and resumes exploration")
			click(hud.task_buttons[i].get_global_rect().get_center())
			await ticks(2)
			key(KEY_ESCAPE)
			await ticks(2)
			check(not game.settings_menu.visible and not game.paused_input,"Escape closes 设置")
		elif i in [1,2,3]:
			check(game.adventure_menu.visible and game.paused_input,"implemented original menu tab opens a modal")
			if i==1:check(game.adventure_menu.panel.position==Vector2(4,4),"status uses original upper-left anchor")
			if i==3:
				check(game.adventure_menu.panel.position==Vector2(game.adventure_menu.size.x-275,4),"inventory follows original right edge anchor")
				check(game.adventure_menu.panel.size==Vector2(272,440),"inventory has original vertical footprint")
				await capture("classic-inventory-layout")
			click(hud.task_buttons[i].get_global_rect().get_center())
			await ticks(2)
			check(not game.adventure_menu.visible and not game.paused_input,"same menu tab closes its window and resumes exploration")
			click(hud.task_buttons[i].get_global_rect().get_center())
			await ticks(2)
			key(KEY_ESCAPE)
			await ticks(2)
		else:
			check(not game.adventure_menu.visible,"deferred social tab stays visual-only")
	check(game.path.is_empty() and game.cell==safe,"menu tabs never trigger world movement")
	pointer(Vector2(650,790))
	await ticks(20)
	click(hud.task_buttons[0].get_global_rect().get_center())
	await ticks(3)
	check(hud.map_panel.visible,"original Map button opens window")
	check(game.last_ui_sound==202,"map opens with original open sound")
	check(hud.map_coordinates.text=="80" and hud.map_south_coordinates.text=="90","map coordinates match player")
	await capture("classic-ui-map")
	click(hud.map_panel.get_global_rect().get_center())
	await ticks(3)
	check(game.path.is_empty(),"clicking map surface does not move character")
	click(hud.map_panel.get_node("CloseMap").get_global_rect().get_center())
	check(not hud.map_panel.visible,"original close button closes map")
	check(game.last_ui_sound==203,"map closes with original close sound")
	key(KEY_M,true)
	check(hud.map_panel.visible and not game.muted,"Ctrl+M opens map without muting music")
	key(KEY_ESCAPE)
	check(not hud.map_panel.visible and not game.settings_menu.visible,"Escape closes map first, without opening 设置")
	key(KEY_M)
	check(hud.map_panel.visible and not game.muted,"M opens the map window")
	var strip=hud.map_panel.get_node("MapTravelMenu")
	check(strip.get_node("MapOverviewButton").is_visible_in_tree() and strip.get_node("MapTravelButton").is_visible_in_tree(),"the map window shows 地图导航 and 刷怪传送 below it")
	click(strip.get_node("MapTravelButton").get_global_rect().get_center())
	await ticks(2)
	check(game.leveling_destinations.visible and not hud.map_panel.visible,"刷怪传送 below the map opens its window")
	game.leveling_destinations.close_menu()
	key(KEY_M)
	click(hud.map_panel.get_node("MapTravelMenu/MapOverviewButton").get_global_rect().get_center())
	await ticks(2)
	check(game.dev_map_overview.visible,"地图导航 below the map opens its window")
	game.dev_map_overview.close_map()
	key(KEY_ESCAPE)
	check(game.settings_menu.visible,"Escape with no window open opens 设置")
	await ticks(2)
	var zoom: HSlider=game.settings_menu.find_child("SettingsZoom",true,false)
	check(zoom.min_value==10 and zoom.max_value==200 and is_equal_approx(zoom.value,100) and is_equal_approx(game.camera.zoom.x,1.0),"the zoom slider spans 10% to 200% and a new device starts at 100%")
	check(game.settings_menu.find_child("MaxOut",true,false)==null and game.settings_menu.find_child("ZoomMinus",true,false)==null,"拉到最远 and the zoom buttons are gone")
	zoom.value=10
	await ticks(30)
	check(is_equal_approx(game.camera.zoom.x,0.1) and game.settings_menu.find_child("SettingsZoomValue",true,false).text=="10%","dragging to the left zooms out to 10%")
	check(game.camera.position==Vector2(0,-25),"zooming keeps the player camera")
	game.zoom_by(-game.ZOOM_STEP)
	check(is_equal_approx(game.camera.zoom.x,game.MIN_ZOOM),"the wheel stops at the same 10% minimum")
	zoom.value=200
	check(is_equal_approx(game.camera.zoom.x,2.0),"dragging to the right zooms in to 200%")
	game.set_zoom(0.1)
	game.settings_menu.close_menu()
	await capture("classic-ui-zoom-out")
	game.set_zoom(1)
	var top_button=hud.get_child(0).get_child(1)
	pointer(top_button.get_global_rect().get_center())
	await ticks(2)
	check(top_button.texture_hover==top_button.texture_normal and top_button.texture_pressed!=top_button.texture_normal,"hover keeps top icon green; pressed artwork remains distinct")
	var sound_count=game.ui_sound_count
	game.set_effects_on(false)
	hud.toggle_map()
	hud.toggle_map()
	check(game.ui_sound_count==sound_count,"with sound effects off the UI plays no sounds")
	game.set_effects_on(true)
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
