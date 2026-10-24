extends "res://tests/yam_axe_ui_test.gd"
const WorldClock=preload("res://server/original_world_clock.gd")
var seconds:=WorldClock.ERA
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var old:=WorldClock.clock;WorldClock.clock=func():return seconds
 var backend=Backend.new();root.add_child(backend);backend.session._profile.default_companions_claimed=true;backend.session._profile.no_random_encounters=true
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"TimeMan rendered remote server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://dream-timeman-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"TimeMan remote scene ready"):return
 var previous_collision:Dictionary={}
 for hour in [127,300]:
  seconds=WorldClock.ERA+int(ceil(float(hour)*5400.0/1024.0));backend.original_quests.refresh_npc_state();backend.publish()
  if not check(await Wait.settle(self,world),"same source clock projection reaches client"):return
  for point in ["95_120","98_120","85_102","88_102"]:
   if not await stage("dream34:time:"+point,34):return
   var id:String="genout/tman_400_"+point+"@400:"+point.replace("_",":")
   var entries:Array=world.world_travel.entries.filter(func(n):return str(n.get("id",""))==id)
   if not check(entries.size()==1,"actual original TimeMan resident exists"):return
   var npc:Dictionary=entries[0]
   var index:int=world.world_travel.entries.find(npc);var sprite=world.world_travel.sprites[index]
   if not check(sprite.texture!=null and sprite.visible,"current original TimeMan texture is visible"):return
   var collision:Dictionary={"cell":npc.cell,"walkable":world.is_walkable(Vector2i(int(npc.cell[0]),int(npc.cell[1])))}
   if hour==127:previous_collision[id]=collision
   elif not check(previous_collision[id]==collision,"mode change leaves original location and collision unchanged"):return
   await proof("dream-timeman-%d-%s"%[hour,point])
   if not await choose("ok"):return
   if not await ready(func():return not world.world_travel.quest_dialogue.active,"original dialogue closes before sprite proof"):return
   await proof("dream-timeman-%d-%s-visible"%[hour,point])
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 WorldClock.clock=old
 print("DREAM TIMEMAN UI: %d failures"%failures);quit(1 if failures else 0)
