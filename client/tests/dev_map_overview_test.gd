extends SceneTree
var failures:=0
func check(value:bool,note:String)->void:
	if value:print("PASS: "+note)
	else:failures+=1;push_error("FAIL: "+note)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world=load("res://scenes/main.tscn").instantiate()
	world.profile_persistence=false
	root.add_child(world)
	await process_frame
	world.muted=true
	var menu=world.dev_map_overview
	menu.open_map()
	menu.walk_mode=false
	check(menu.visible and world.paused_input,"overview opens and blocks movement")
	check(menu.thumbnail!=null and menu.pois.size()>0,"terrain and original POIs populated")
	var point:=Vector2i(89,73)
	check(menu.point_to_cell(menu.cell_to_point(point))==point,"maptransform roundtrip")
	var safe:Vector2i=menu.nearest_safe(world.npc_cell)
	check(world.is_walkable(safe) and safe!=world.npc_cell,"NPC click chooses nearby valid floor")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/dev-map-overview.png")
	var click:=InputEventMouseButton.new()
	click.position=menu.get_global_transform_with_canvas()*menu.cell_to_point(world.npc_cell)
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	root.push_input(click,true)
	click.pressed=false
	root.push_input(click,true)
	check(world.cell==safe and not menu.visible and not world.paused_input,"actual map click teleports and closesmodal")
	world.load_area_id(200,Vector2i(570,377))
	menu=world.dev_map_overview
	menu.open_map()
	check(menu.map_dimensions==Vector2i(800,1200),"entirelargeisland represented")
	check(menu.thumbnail.get_width()<=1600 and menu.thumbnail.get_height()<=1600,"largeisland boundedthumbnail")
	point=Vector2i(700,1100)
	check(menu.point_to_cell(menu.cell_to_point(point))==point,"largeisland transform roundtrip")
	menu.close_map()
	world.music.stop();world.effect.stop();world.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("DEV MAP OVERVIEW: %d failures" % failures)
	quit(1 if failures else 0)
