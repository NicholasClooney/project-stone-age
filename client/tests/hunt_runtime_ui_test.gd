extends SceneTree
const Backend=preload("res://server/backend.gd")
const WsServer=preload("res://server/ws_server.gd")
const Settings=preload("res://scripts/automation_settings.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
var visual:=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func click(control:Control)->void:
	if visual:await RenderingServer.frame_post_draw
	var at:=control.get_global_transform_with_canvas()*(control.size/2)
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	await process_frame
func reach(menu,control:Control,scroll:ScrollContainer)->void:
	await process_frame
	scroll.ensure_control_visible(control)
	await process_frame
	check(await Wait.until(self,func():return scroll.get_global_rect().encloses(control.get_global_rect())),"fully reachable without horizontal scroll: "+str(control.name))
	check(control.size.y>=44,"minimum 44px touch target: "+str(control.name))
	check(not control.get_global_rect().intersects(menu.status.get_global_rect()),"control does not overlap status: "+str(control.name))
func shot(menu,name:String)->void:
	if not visual:return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/hunt-runtime-shots/"+name+".png")
func connect_game(port:int,tag:String):
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%port
	var game=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	game.profile_persistence=false;game.viewer_prefs_path="user://hunt-runtime-"+tag+".cfg";root.add_child(game)
	check(await Wait.until(self,func():return game.link.online and not game.data.is_empty()) and await Wait.settle(self,game),"real remote client startup: "+tag)
	game.random_encounters=false
	check(await Wait.until(self,func():return not game.paused_input and not game.area_transition_busy),"remote arrival ready")
	return game
func run()->void:
	visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	root.content_scale_size=Vector2i.ZERO;root.gui_embed_subwindows=true;root.size=Vector2i(1280,720)
	var backend=Backend.new();root.add_child(backend);backend.set_process(false)
	var server=WsServer.new(backend,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"real server listens on port zero")
	var game=await connect_game(server.port,"a");var other=await connect_game(server.port,"b");other.hide();other.ui_layer.hide()
	check(game.backend==null and other.backend==null,"both UI clients have no backend")
	var menu=game.pet_hunt_menu;menu.open_menu();menu.show_page("runtime")
	check(menu.runtime_page.visible and not menu.capture_page.visible and not menu.stat_page.visible,"runtime is a separate page")
	for key in ["background_search","show_battles","battle_training"]:
		var control=menu.showcase if key=="background_search" else (menu.show_battles if key=="show_battles" else menu.battle_training)
		await reach(menu,control,menu.runtime_scroll)
		await click(control)
		check(await Wait.until(self,func():return not bool(Settings.effective(backend.session.automation_settings()).hunt[key])) and await Wait.settle(self,game),"actual remote click changes independent preference: "+key)
	check(not menu.showcase.button_pressed and not menu.show_battles.button_pressed and not menu.battle_training.button_pressed,"all three choices update independently")
	check(await Wait.until(self,func():return not other.pet_hunt_menu.showcase.button_pressed and not other.pet_hunt_menu.show_battles.button_pressed and not other.pet_hunt_menu.battle_training.button_pressed),"second device receives independent choices")
	check(menu.train_after_capture.text=="捕获后培养至120级","training wording does not promise instant upgrade")
	menu.show_page("keep");await reach(menu,menu.preview_keep,menu.keep_scroll);await click(menu.preview_keep)
	check(await Wait.until(self,func():return not Settings.effective(backend.session.automation_settings()).hunt.preview_keep) and await Wait.settle(self,game),"real remote click disables pre-capture retention preview")
	check(await Wait.until(self,func():return not other.pet_hunt_menu.preview_keep.button_pressed),"second device receives preview preference")
	for size in [Vector2i(1280,720),Vector2i(390,844),Vector2i(844,390)]:
		root.size=size;menu.relayout();await process_frame
		for page in ["runtime","keep"]:
			menu.show_page(page);await process_frame
			var scroll=menu.runtime_scroll if page=="runtime" else menu.keep_scroll
			var controls:Array=[menu.fast,menu.showcase,menu.thread_count,menu.show_battles,menu.showcase_speed,menu.train_after_capture,menu.capture_only,menu.battle_training,menu.showcase_xp,menu.stop_after,menu.auto_capture,menu.clean_only,menu.mixed_if_stats,menu.rule_auto,menu.resume_after_restart] if page=="runtime" else [menu.queue_size,menu.rule_tiers,menu.rule_per_tier,menu.rule_champions]+menu.stat_rank+menu.rule_stats.values()
			for control in controls:await reach(menu,control,scroll)
			check(scroll.scroll_horizontal==0,"page does not need horizontal scrolling: "+page)
			scroll.scroll_vertical=0;await shot(menu,"%dx%d-%s-top"%[size.x,size.y,page])
			scroll.scroll_vertical=10000;await shot(menu,"%dx%d-%s-bottom"%[size.x,size.y,page])
			if page=="runtime":
				await reach(menu,menu.capture_only,scroll);await shot(menu,"%dx%d-runtime-capture-only"%[size.x,size.y])
				await reach(menu,menu.battle_training,scroll);await shot(menu,"%dx%d-runtime-training"%[size.x,size.y])
			for i in range(menu._page_tabs.size()):
				for j in range(i):check(not menu._page_tabs[i].get_global_rect().intersects(menu._page_tabs[j].get_global_rect()),"page tabs do not overlap")
	root.size=Vector2i(390,844);menu.show_page("runtime");await process_frame
	await reach(menu,menu.capture_only,menu.runtime_scroll);await click(menu.capture_only)
	check(await Wait.until(self,func():return Settings.effective(backend.session.automation_settings()).hunt.capture_only),"remote only-capture click remains available")
	check(not menu.showcase.disabled and not menu.show_battles.disabled and menu.battle_training.disabled,"capture-only does not force background searching or display")
	menu.close_menu();menu.open_menu();check(menu.page=="runtime" and menu.runtime_page.visible,"new page remembered per device")
	menu.set_controls(true)
	check(menu.rule_tiers.editable and not menu.rule_auto.disabled and not menu.preview_keep.disabled,"shared keep and preview remain editable during a run")
	menu.set_controls(false)
	for page in ["filters","capture","stats"]:
		root.size=Vector2i(1280,720);menu.show_page(page);await shot(menu,"1280x720-"+page)
	for client in [game,other]:client.link.close();client.process_mode=Node.PROCESS_MODE_DISABLED;client.music.stop();client.effect.stop();client.queue_free()
	server.queue_free();backend.queue_free();await process_frame
	print("HUNT RUNTIME UI: %d failures"%failures);quit(1 if failures else 0)
