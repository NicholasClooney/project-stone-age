extends "res://tests/rare_teleport_test.gd"
class ObservedBackend extends "res://server/backend.gd":
 var denied_capture_reports:=0
 func _cmd_report_position(command:Dictionary)->Dictionary:
  var result:Dictionary=super._cmd_report_position(command)
  var at:Array=command.get("cell",[])
  if not result.ok and at.size()==2 and int(at[0])==34 and int(at[1])==35:denied_capture_reports+=1
  return result
func run()->void:
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
  await process_frame
  await click(button)
  check(await Wait.settle(self,game) and backend.denied_capture_reports==1,"real catch click sends one forbidden destination and server rejects it")
  check(await until(func():return game.cell==Vector2i(47,54) and not game.moving and not game.area_transition_busy),"server rejection restores speculative capture teleport %d"%map_id)
  check(backend.automation.position_map==map_id and backend.automation.position_cell==Vector2i(47,54),"capture UI cannot place server behind final guard")
  var after:Dictionary=backend.session.snapshot()
  check(after.original_items==before.original_items and after.original_events==before.original_events,"capture click cannot change rewards or quest flags")
  check(not backend.battle_open and not backend.automation.hunt_running,"rejected capture travel grants no battle or hunt")
  game.pet_hunt_menu.close_menu();menu.close_menu()
  check(await until(func():return not game.paused_input),"close hunt preview before quick movement")
  check(game.blink_to(Vector2i(34,35)),"production quick-move sends speculative destination")
  check(await Wait.settle(self,game) and backend.denied_capture_reports==2,"same-map quick movement reaches the same authority rejection")
  check(await until(func():return game.cell==Vector2i(47,54) and not game.moving) and backend.automation.position_cell==Vector2i(47,54),"quick-move client and authority return to original room")
 game.process_mode=Node.PROCESS_MODE_DISABLED;game.link.close();game.music.stop();game.effect.stop();game.queue_free()
 server.stop();server.queue_free();backend.queue_free();await process_frame
