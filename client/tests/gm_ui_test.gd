extends SceneTree
var failures:=0
func check(value:bool,note:String)->void:
	if value:print("PASS: "+note)
	else:failures+=1;push_error("FAIL: "+note)
func _initialize()->void:call_deferred("run")
func click(control:Control)->void:
	var point:Vector2=control.get_global_transform_with_canvas()*(control.size/2)
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	root.push_input(motion,true)
	var event:=InputEventMouseButton.new()
	event.position=point
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	root.push_input(event,true)
	event.pressed=false
	root.push_input(event,true)
func run()->void:
	var world=load("res://scenes/main.tscn").instantiate()
	world.profile_persistence=false
	root.add_child(world)
	await process_frame
	world.muted=true
	var before:Dictionary=world.session.snapshot()
	var menu=world.dev_gm_menu
	menu.open_menu()
	check(menu.visible and world.session.snapshot()==before,"openingGM nevermodifiesprofile")
	check(menu.actor_picker.get_selected_id()==-1,"playerisdefaulttarget")
	menu.level_input.value=2
	await process_frame
	click(menu.mutation_buttons[0])
	check(world.session.snapshot().player.level==2,"actualGMclick raisesplayerlevel")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/gm-controls.png")
	menu.close_menu()
	check(not world.paused_input,"closingGM restoresfieldinput")
	world.load_area_id(100,Vector2i(637,493))
	check(world.begin_battle(),"battlefixture begins")
	menu=world.dev_gm_menu
	menu.open_menu()
	check(menu.visible and menu.mutation_buttons.all(func(button):return button.disabled),"allstatbuttons lockduringbattle")
	check(not menu.escape_button.disabled,"GMescape remainsavailable")
	await process_frame
	var gold:int=world.session.snapshot().player.gold
	click(menu.escape_button)
	check(not menu.visible and world.battle_session.snapshot().outcome=="escaped","actualescape click settlesbattle")
	check(world.battle_view.is_animating(),"GMescape preservesoriginalanimation")
	for i in range(100):world.battle_view._process(0.1)
	world.return_from_battle()
	check(not world.battle_view.visible and not world.paused_input and world.session.snapshot().player.gold==gold,"normalreturn afteranimation givesnorewards")
	world.music.stop();world.effect.stop();world.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("GM UI: %d failures" % failures)
	quit(1 if failures else 0)
