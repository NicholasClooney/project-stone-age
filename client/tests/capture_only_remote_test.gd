extends SceneTree
## Real WebSocket RPC + actual portrait viewport clicks; no local backend UI writes.
const Backend=preload("res://server/backend.gd")
const WsServer=preload("res://server/ws_server.gd")
const Wait=preload("res://tests/support/wait.gd")
const Settings=preload("res://scripts/automation_settings.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,note:String):
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func click(control:Control):
	check(await Wait.until(self,func():return control.is_visible_in_tree() and control.size.x>0),"remote click target ready")
	var point:Vector2=control.get_global_transform_with_canvas()*(control.size/2)
	var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;root.push_input(move,true)
	await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point;root.push_input(event,true)
		await process_frame
func run():
	root.size=Vector2i(720,1280)
	var backend=Backend.new();backend.set_process(false);root.add_child(backend)
	var server=WsServer.new(backend,0,"127.0.0.1");root.add_child(server)
	check(server.start()==OK,"isolated port-zero server starts")
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
	var game=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	game.profile_persistence=false;game.viewer_prefs_path="user://capture-only-remote.cfg";root.add_child(game)
	check(await Wait.until(self,func():return game.link.online and not game.data.is_empty()) and await Wait.settle(self,game),"real remote client connects")
	check(game.backend==null,"remote UI has no local backend to mutate")
	game.random_encounters=false
	check(await Wait.until(self,func():return not game.paused_input and not game.area_transition_busy),"remote UI ready")
	var menu=game.pet_hunt_menu;menu.open_menu()
	await click(menu.panel.get_node("HuntRuntimeTab"))
	check(menu.runtime_page.visible and menu.capture_only.visible,"real capture tab exposes capture-only switch")
	check(menu.runtime_page.is_ancestor_of(menu.capture_only) and not menu.capture_only.get_global_rect().intersects(menu.train_after_capture.get_global_rect()),"portrait switch fits with no training control overlap")
	check(menu.capture_only.tooltip_text.contains("非原版") or menu.capture_only.text.contains("非原版"),"non-original convenience is explicitly labelled")
	menu.runtime_scroll.ensure_control_visible(menu.capture_only);await process_frame
	await click(menu.capture_only)
	check(await Wait.until(self,func():return bool(backend.session.automation_settings().get("hunt",{}).get("capture_only",false))) and await Wait.settle(self,game),"actual remote checkbox click writes strict character preference")
	check(menu.level_one.button_pressed and menu.level_one.disabled and menu.showcase.button_pressed and not menu.showcase.disabled and not menu.train_after_capture.button_pressed and not menu.train_after_capture.disabled,"remote UI keeps Lv1/showcase fixed; 直接升至120级 is off but clickable")
	check(not menu.stop_after.editable and menu.start_button.text=="开始只抓不练" and menu.ready_description().contains("忽略"),"remote UI explains carried capture limits")
	for bad in ["true",1]:
		var reply:Dictionary={}
		game.link.request({"type":"set_automation_settings","settings":{"hunt":{"capture_only":bad}}},func(result):reply.merge(result,true))
		check(await Wait.until(self,func():return reply.has("ok")) and not reply.ok,"WebSocket rejects non-boolean capture_only")
	menu.close_menu();menu.open_menu();menu.show_page("runtime")
	check(menu.capture_only.button_pressed and not menu.train_after_capture.button_pressed,"saved mode survives panel reopen")
	menu.runtime_scroll.ensure_control_visible(menu.capture_only);await process_frame
	await click(menu.capture_only)
	check(await Wait.until(self,func():return not Settings.effective(backend.session.automation_settings()).hunt.capture_only) and await Wait.settle(self,game),"real second click disables capture-only")
	check(menu.train_after_capture.button_pressed and not menu.train_after_capture.disabled and not menu.level_one.disabled,"prior training preference returns without ambiguous mode")
	menu.close_menu();game.process_mode=Node.PROCESS_MODE_DISABLED;game.link.close();game.music.stop();game.effect.stop();game.queue_free()
	server.queue_free();backend.queue_free();await process_frame
	print("CAPTURE ONLY REMOTE: %d failures"%failures);quit(1 if failures else 0)
