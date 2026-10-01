extends SceneTree
var failures := 0
var visual := false
var menu
func _initialize()->void:call_deferred("run")
func check(ok:bool, message:String)->void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures+=1
func settle()->void:
	await process_frame
	await process_frame
func shot(name:String)->void:
	await settle()
	if visual:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/hunt-layout-shots/"+name+".png")
func click(control:Control)->void:
	var position:=control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=position;motion.global_position=position;root.push_input(motion,true);await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=position;event.global_position=position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true)
		await process_frame
func choose_next(control:OptionButton)->void:
	var previous:=control.selected
	var press:=InputEventMouseButton.new();press.position=control.get_global_rect().get_center();press.global_position=press.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true);await process_frame
	var popup:=control.get_popup()
	check(popup.visible,"real click opens popup: "+control.name)
	var next:=0 if previous!=0 else mini(1,control.item_count-1)
	popup.set_focused_item(next)
	for code in [KEY_ENTER]:
		for pressed in [true,false]:
			var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;root.push_input(event,true);await process_frame
	check(control.selected==next,"real popup selection: "+control.name)
	popup.hide()
	press.pressed=false;root.push_input(press,true);await process_frame
func geometry()->void:
	var visible_controls:Array=[menu.thread_count]
	for control in menu.controls:
		if control.is_visible_in_tree() and control not in visible_controls:visible_controls.append(control)
	for i in range(visible_controls.size()):
		var control:Control=visible_controls[i]
		check(not control.get_global_rect().intersects(menu.status.get_global_rect()),"separate status: "+control.name)
		for j in range(i):
			check(not control.get_global_rect().intersects(visible_controls[j].get_global_rect()),"separate controls: %s / %s"%[control.name,visible_controls[j].name])
func reach_controls()->void:
	for control in menu.controls:
		if control.is_visible_in_tree():
			menu.window_scroll.ensure_control_visible(control);await settle()
			check(menu.window_scroll.get_global_rect().encloses(control.get_global_rect()),"phone can fully reach: "+control.name)
func run()->void:
	root.gui_embed_subwindows=true
	visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game)
	await settle()
	game.switch_area(true,Vector2i(45,45))
	menu=game.pet_hunt_menu;menu.open_menu();menu.show_capture_settings(true)
	await settle()
	check(not menu.status.get_global_rect().intersects(menu.capture_only.get_global_rect()),"capture-only has a separate status region")
	check(not menu.train_after_capture.get_global_rect().intersects(menu.capture_only.get_global_rect()),"capture modes have separate rows")
	geometry()
	await shot("pc-capture-normal")
	await click(menu.capture_only)
	check(menu.capture_only.button_pressed,"real click toggles capture-only")
	await shot("pc-capture-only")
	# The two modes stay clickable and turn each other off.
	check(not menu.train_after_capture.disabled,"直接升至120级 stays clickable while 只抓不练 is on")
	await click(menu.train_after_capture)
	check(menu.train_after_capture.button_pressed and not menu.capture_only.button_pressed,"clicking 直接升至120级 turns 只抓不练 off")
	await click(menu.capture_only)
	check(menu.capture_only.button_pressed and not menu.train_after_capture.button_pressed,"clicking 只抓不练 turns 直接升至120级 off")
	await click(menu.capture_only)
	await click(menu.showcase)
	await shot("pc-capture-background")
	menu.show_stat_settings();await settle()
	var scroll:ScrollContainer=menu.stat_page.get_node("StatSettingsScroll")
	var content:Control=scroll.get_node("StatSettingsContent")
	for child in content.get_children():
		if child is Control and child.visible:
			check(child.position.x>=0 and child.position.y>=0,"nonnegative stat content: "+child.name)
			check(not child.get_global_rect().intersects(menu.status.get_global_rect()),"stat stays above status: "+child.name)
	check(scroll.get_global_rect().encloses(menu.stat_species.get_global_rect()),"species fully visible at scroll top")
	check(game.link.request({"type":"gm_grant_pet","template":menu.stat_species.get_selected_id(),"full_grade":true}).ok,"real progression fixture grants the selected species")
	menu.refresh_stat_thresholds(true);await settle();geometry()
	await choose_next(menu.stat_threshold_mode);await settle();geometry()
	await shot("pc-stat-fixed-owned")
	await choose_next(menu.stat_threshold_mode);await settle();geometry()
	await choose_next(menu.stat_species)
	await choose_next(menu.stat_mode)
	geometry()
	await choose_next(menu.stat_threshold_mode);await settle();geometry()
	await shot("pc-stat-fixed")
	await choose_next(menu.stat_threshold_mode);await settle();geometry()
	await shot("pc-stat-top")
	scroll.scroll_vertical=10000;await shot("pc-stat-bottom")
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844);menu.relayout();await settle()
	menu.window_scroll.scroll_horizontal=0;menu.window_scroll.scroll_vertical=0
	menu.show_capture_settings(true);await shot("phone-capture-normal")
	await click(menu.capture_only)
	check(menu.capture_only.button_pressed,"phone click reaches bottom capture-only")
	await shot("phone-capture-only")
	await reach_controls()
	menu.window_scroll.scroll_horizontal=10000;await shot("phone-capture-right")
	menu.window_scroll.scroll_horizontal=0;menu.show_stat_settings();scroll.scroll_vertical=0
	await shot("phone-stat-top")
	scroll.scroll_vertical=10000;await shot("phone-stat-bottom")
	var wheel:=InputEventMouseButton.new();wheel.position=Vector2(200,600);wheel.button_index=MOUSE_BUTTON_WHEEL_RIGHT;wheel.pressed=true;wheel.factor=20;root.push_input(wheel,true);wheel.pressed=false;root.push_input(wheel,true);await settle()
	check(menu.window_scroll.scroll_horizontal>0,"actual phone wheel scroll moves the window")
	menu.window_scroll.scroll_horizontal=10000;await shot("phone-stat-right")
	check(menu.window_scroll.get_global_rect().encloses(menu.stat_rank[2].get_global_rect()),"phone horizontal scrolling reaches complete third ranking control")
	await choose_next(menu.stat_rank[2])
	await reach_controls()
	menu.window_scroll.ensure_control_visible(menu.stat_mode);await shot("phone-stat-middle")
	menu.show_capture_settings(false);await settle();await reach_controls()

	game.queue_free();await process_frame
	print("HUNT SETTINGS LAYOUT: %d failures"%failures)
	quit(1 if failures else 0)
