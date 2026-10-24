extends "res://tests/rare_teleport_test.gd"
const Clock=preload("res://scripts/clock.gd")
class ObservedBackend extends "res://server/backend.gd":
 var denied_capture_reports:=0
 func _cmd_report_position(command:Dictionary)->Dictionary:
  var result:Dictionary=super._cmd_report_position(command)
  var at:Array=command.get("cell",[])
  if not result.ok and at.size()==2 and int(at[0])==34 and int(at[1])==35:denied_capture_reports+=1
  return result
var proof_dir:=""
func shot(game,name:String)->void:
 if proof_dir.is_empty():return
 await RenderingServer.frame_post_draw
 var result:int=game.get_viewport().get_texture().get_image().save_png(proof_dir.path_join(name+".png"))
 check(result==OK,"real rendered capture screenshot "+name)
func reveal(button:Button)->bool:
 var deadline:int=Clock.ticks_msec()+60000
 while Clock.ticks_msec()<deadline and is_instance_valid(button):
  var ancestor:Node=button.get_parent()
  while ancestor!=null:
   if ancestor is ScrollContainer:ancestor.ensure_control_visible(button)
   ancestor=ancestor.get_parent()
  await process_frame
  var rect:Rect2=button.get_global_rect()
  var point:Vector2=rect.get_center()
  if not Rect2(Vector2.ZERO,Vector2(root.size)).has_point(point):continue
  var visible:=true;ancestor=button.get_parent()
  while ancestor!=null:
   if ancestor is ScrollContainer and not ancestor.get_global_rect().has_point(point):visible=false
   ancestor=ancestor.get_parent()
  if not visible:continue
  await process_frame
  if rect!=button.get_global_rect():continue
  var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
  if root.gui_get_hovered_control()==button:return true
 return false
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 for map_id in [41,42]:await boundary(map_id)
 print("DREAM CATCH BOUNDARY: %d failures"%failures)
 quit(1 if failures else 0)
func boundary(map_id:int)->void:
 var backend=ObservedBackend.new();root.add_child(backend)
 backend.session._profile.no_random_encounters=true
 backend.automation.position_changed(map_id,Vector2i(47,54))
 var before:Dictionary=backend.session.snapshot().duplicate(true)
 var server=WsServer.new(backend,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"dream capture remote server")
 var game_script=load("res://scripts/game.gd");game_script.server_url_override="ws://127.0.0.1:%d"%server.port
 var game=load("res://scenes/main.tscn").instantiate();game_script.server_url_override=""
 game.profile_persistence=false;game.viewer_prefs_path="user://dream-catch-boundary.cfg";root.add_child(game)
 check(await until(func():return not game.data.is_empty() and game.link.online and int(game.data.map_id)==map_id) and await Wait.settle(self,game),"remote hunt-room scene is ready")
 check(game.blink_to(Vector2i(34,35)),"production quick-move sends speculative destination")
 check(await Wait.settle(self,game) and backend.denied_capture_reports==1,"same-map quick movement reaches the same authority rejection")
 check(await until(func():return game.cell==Vector2i(47,54) and not game.moving) and backend.automation.position_cell==Vector2i(47,54),"quick-move client and authority return to original room")
 var menu=game.pet_encyclopedia
 menu.open_menu(72)
 var area:=416 if map_id==41 else 427
 var name:="GoPlace%d_%d"%[map_id,area]
 check(await until(func():return menu.body.find_child(name,true,false)!=null),"real encyclopedia lists reward-room capture target")
 var button:Button=menu.body.find_child(name,true,false)
 if button!=null:
  var parent:Node=button.get_parent()
  while parent!=null:
   if parent is ScrollContainer:parent.ensure_control_visible(button)
   parent=parent.get_parent()
  check(await reveal(button),"reviewed capture button is actually visible, stable and hoverable")
  await shot(game,"capture-%d-reviewed-place"%map_id)
  check(button.get_global_rect().intersects(Rect2(Vector2.ZERO,Vector2(root.size))),"reviewed capture button remains visible at click")
  await click(button)
  check(await Wait.settle(self,game),"real capture command acknowledged")
  check(await until(func():return game.cell==Vector2i(34,35) and not game.moving and not game.area_transition_busy),"authorized capture lands in exact reward-room pet point %d"%map_id)
  check(backend.automation.position_map==map_id and backend.automation.position_cell==Vector2i(34,35),"capture target is server authoritative")
  check(not backend.quest_arrival.has_arrival(backend,map_id,Vector2i(34,35)),"capture point has no legitimate quest route")
  check(await until(func():return game.pet_hunt_menu.visible),"actual capture arrival opens original automatic hunt UI")
  await shot(game,"capture-%d-authoritative-hunt"%map_id)
  await click(game.pet_hunt_menu.start_button)
  check(await Wait.settle(self,game) and await until(func():return backend.automation.hunt_running or backend.automation.flow_active()),"real rendered start button begins authoritative hunt at reviewed point")
  check(backend.session.automation_settings().get("hunt",{}).get("templates",[])==[72],"started hunt retains clicked encyclopedia target")
  await click(game.pet_hunt_menu.stop_button)
  check(await Wait.settle(self,game) and await until(func():return not backend.automation.hunt_running and not backend.automation.flow_active()),"actual stop button stops reviewed hunt")
  var after:Dictionary=backend.session.snapshot()
  check(after.original_items==before.original_items and after.original_events==before.original_events,"capture click cannot change rewards or quest flags")
  check(backend.denied_capture_reports==1,"dedicated capture command needs no generic report bypass")
  game.pet_hunt_menu.close_menu();menu.close_menu()
 game.process_mode=Node.PROCESS_MODE_DISABLED;game.link.close();game.music.stop();game.effect.stop();game.queue_free()
 server.stop();server.queue_free();backend.queue_free();await process_frame
