extends SceneTree
var failures:=0
func check(value: bool,note:String)->void:
	if value:print("PASS: "+note)
	else:failures+=1;push_error("FAIL: "+note)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world=load("res://scenes/main.tscn").instantiate()
	world.profile_persistence=false
	root.add_child(world)
	await process_frame
	world.muted=true
	world.random_encounters=false
	var router=world.travel_router
	check(router.map_route(1000,3000,false).is_empty(),"crossisland requires originalpermit")
	check(not router.map_route(1000,3000,true).is_empty(),"permit exposes realunderseaportals")
	var menu=world.dev_map_overview
	menu.open_map()
	check(menu.walk_mode,"map defaults toWalk notTeleport")
	menu.browse_map(3000)
	check(int(world.data.map_id)==1000 and menu.current_map==3000,"browsing othermap nevermovesplayer")
	var pointer:Vector2=menu.cell_to_point(Vector2i(84,100))
	var before:Vector2i=menu.point_to_cell(pointer)
	menu.zoom_at(pointer,2)
	check(menu.point_to_cell(pointer)==before,"pointerzoom keepssame mapcoordinate")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/navigation-overview.png")
	var before_pan: Vector2=menu.map_rect.position
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_MIDDLE
	press.pressed=true
	press.position=pointer
	menu._gui_input(press)
	var drag:=InputEventMouseMotion.new()
	drag.position=pointer+Vector2(45,20)
	menu._gui_input(drag)
	press.pressed=false
	press.position=drag.position
	menu._gui_input(press)
	check(menu.map_rect.position==before_pan+Vector2(45,20),"drag pans withoutselectingdestination")
	menu.recenter_map()
	check(menu.zoom_level==1.0,"recenter restoresentiremap")
	menu.close_map()
	world.load_area_id(1002,Vector2i(11,15))
	check(router.request(1000,Vector2i(65,108)),"walkingroute starts frominside shop")
	check(int(world.data.map_id)==1002,"walkrequest doesnotteleport")
	world.release_keyboard_input()
	check(router.active,"losingfocus preservesautopath")
	for i in range(300):
		world._physics_process(0.25)
		await process_frame
		if world.area_transition_busy:await create_timer(0.03).timeout
		if not router.active:break
	check(int(world.data.map_id)==1000 and world.cell==Vector2i(65,108),"walkcrosses realshopdoor and reachesdestination")
	check(not router.active,"route completeswithout remainingcommands")
	router.request(1000,Vector2i(62,108))
	world.walk_to(Vector2i(64,108))
	check(not router.active,"manualnewtarget cancelscrossmaproute")
	world.load_area_id(10202,Vector2i(21,27))
	world.session._profile.travel_pass=true
	check(router.request(10202,Vector2i(21,33)),"routeapproaches originalpermitguard")
	for i in range(50):
		world._physics_process(0.25)
		await process_frame
		if world.world_travel.overlay.visible:break
	check(world.world_travel.overlay.visible and world.cell.y<30,"Walk waitsforguardconfirmation withoutjump")
	world.world_travel.choice.pressed.emit()
	for i in range(30):
		world._physics_process(0.25)
		await process_frame
		if not router.active:break
	check(world.cell==Vector2i(21,33) and world.session.has_travel_pass(),"confirmedoriginalgate resumesroute andpreservespermit")
	world.music.stop();world.effect.stop();world.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("TRAVEL ROUTER: %d failures" % failures)
	quit(1 if failures else 0)
