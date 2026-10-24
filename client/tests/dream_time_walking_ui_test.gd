extends "res://tests/yam_axe_ui_test.gd"
const WorldClock=preload("res://server/original_world_clock.gd")
class ObservedBackend extends "res://server/backend.gd":
 var checked:=[false,Vector2i.ZERO]
 var cross_phase:Callable
 var denied_arrival:=false
 func _cmd_check_passage(command:Dictionary)->Dictionary:
  checked=[true,automation.position_cell]
  var result:Dictionary=super._cmd_check_passage(command)
  if result.ok and cross_phase.is_valid():cross_phase.call()
  return result
 func _cmd_report_position(command:Dictionary)->Dictionary:
  var result:Dictionary=super._cmd_report_position(command)
  if int(command.get("map_id",0))==41 and not result.ok:denied_arrival=true
  return result
var seconds:=WorldClock.ERA
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var original:=WorldClock.clock;WorldClock.clock=func():return seconds
 await crossing(false)
 await crossing(true)
 WorldClock.clock=original
 print("DREAM TIME WALKING UI: %d failures"%failures);quit(1 if failures else 0)
func crossing(change_phase:bool)->void:
 seconds=WorldClock.ERA+int(ceil(930.0*5400.0/1024.0))
 var backend=ObservedBackend.new();root.add_child(backend)
 backend.session._profile.default_companions_claimed=true;backend.session._profile.no_random_encounters=true
 backend.automation.position_changed(400,Vector2i(99,119))
 if change_phase:backend.cross_phase=func():seconds=WorldClock.ERA+int(ceil(931.0*5400.0/1024.0))
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"timed walk port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://dream-time-walk.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online and int(world.data.map_id)==400,"production remote starts next to original M gate"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"remote scene has no backend"):return
 if not check(world.world_catalog.links(400)[Vector2i(98,119)].get("requires_time","")=="M","actual imported gate retains M suffix"):return
 world.walk_to(Vector2i(98,119))
 if not await ready(func():return backend.checked[0],"real walking triggers production check_passage"):return
 if not check(backend.checked[1]==Vector2i(98,119),"source position report precedes check on same socket"):return
 if change_phase:
  if not await ready(func():return backend.denied_arrival and int(world.data.map_id)==400 and world.cell==Vector2i(98,119) and not world.area_transition_busy,"phase changed before arrival rejects and repairs speculative scene"):return
  if not check(backend.automation.position_map==400,"server remains outside after boundary"):return
  await proof("dream-time-02-rejected-return")
 else:
  if not await ready(func():return int(world.data.map_id)==41 and world.cell==Vector2i(11,8) and backend.automation.position_map==41 and not world.area_transition_busy,"real production walk enters at exact original destination"):return
  await proof("dream-time-01-original-arrival")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
