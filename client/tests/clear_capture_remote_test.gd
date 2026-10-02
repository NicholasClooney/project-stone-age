extends SceneTree
## Portrait-size headless viewport + real input + port-zero WebSocket backend.
## This validates click routing and layout geometry, not rendered pixels.
const Backend=preload("res://server/backend.gd")
const WsServer=preload("res://server/ws_server.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok: bool,note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func click(control: Control,offset: Vector2=Vector2(-1,-1)):
 check(await Wait.until(self,func():return control.is_visible_in_tree() and control.size.x>0),"real click control ready")
 var local: Vector2=control.size/2 if offset.x<0 else offset
 var point: Vector2=control.get_global_transform_with_canvas()*local
 var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;root.push_input(move,true)
 await process_frame
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
  root.push_input(event,true)
  await process_frame
func run():
 root.size=Vector2i(720,1280)
 var backend=Backend.new();backend.set_process(false);root.add_child(backend)
 var server=WsServer.new(backend,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"isolated port-zero server starts")
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 var game=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 game.profile_persistence=false;game.viewer_prefs_path="user://clear-capture-remote.cfg";root.add_child(game)
 check(await Wait.until(self,func():return game.link.online and not game.data.is_empty()) and await Wait.settle(self,game),"remote client connects without a local backend")
 game.random_encounters=false
 check(await Wait.until(self,func():return not game.paused_input and not game.area_transition_busy),"remote client is ready")
 var menu=game.pet_hunt_menu;menu.open_menu()
 await click(menu.panel.get_node("HuntCaptureTab"))
 check(menu.capture_page.visible,"real click opens capture settings")
 var helper=game.training_helper
 var fields: Array=[helper.capture_fallback_attempts,helper.capture_fallback_rate,helper.capture_fallback_hp]
 for field in fields:
  check(menu.panel.get_global_rect().encloses(field.get_global_rect()) and not field.get_global_rect().intersects(menu.train_after_capture.get_global_rect()),"portrait capture field fits and does not overlap the training toggle")
  check(int(field.value) in [5,20,50],"old/new character gets safe fallback defaults")
 await click(fields[0],Vector2(fields[0].size.x-8,fields[0].size.y*0.25))
 check(await Wait.until(self,func():return int(backend.session.automation_settings().get("capture",{}).get("fallback_attempts",0))==6),"a real spinner click writes the character setting over WebSocket")
 menu.show_page("runtime");await process_frame
 menu.runtime_scroll.ensure_control_visible(menu.mixed_if_stats);await process_frame
 check(await Wait.until(self,func():return menu.runtime_scroll.get_global_rect().encloses(menu.mixed_if_stats.get_global_rect())),"mixed exception is fully reachable in runtime scroll")
 await click(menu.mixed_if_stats)
 check(await Wait.until(self,func():return bool(backend.session.automation_settings().get("hunt",{}).get("mixed_if_stats",false))),"real click enables mixed encounter capture remotely")
 menu.close_menu();menu.open_menu();menu.show_capture_settings(true)
 check(int(helper.capture_fallback_attempts.value)==6,"reopening preserves the saved fallback setting")
 menu.close_menu();game.process_mode=Node.PROCESS_MODE_DISABLED;game.link.close();game.music.stop();game.effect.stop();game.queue_free()
 server.queue_free();backend.queue_free();await process_frame
 print("CLEAR CAPTURE REMOTE: %d failures"%failures);quit(1 if failures else 0)
