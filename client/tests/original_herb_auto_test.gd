extends "res://tests/original_quest_auto_test.gd"
const SAVE="user://herb-auto-resume.json"
func start(b) -> Dictionary:
 return b.handle({"type":"quest_auto_start","quest_id":30,"client":"test"})
func fresh(load_saved:bool=false):
 var b=Backend.new()
 b.quest_catalog.enabled_events=[1,15,16]
 b.session._profile.no_random_encounters=true
 if load_saved:check(b.load_profile(SAVE),"Real herb profile reloads")
 b.save_path=SAVE
 b.keep_resume_current=true
 return b
func reach(b,id:String,wanted:String) -> void:
 for index in range(3000):
  if str(b.quest_auto.step.get("id",""))==id and b.quest_auto.phase==wanted:return
  advance(b,false)
  if b.quest_auto.phase=="landing" and not (wanted=="landing" and str(b.quest_auto.step.get("id",""))==id):
   b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"client":"test"})
 check(false,"Reach herb checkpoint "+id+"/"+wanted)
func finish(b) -> void:
 for index in range(3000):
  if not b.quest_auto.running:return
  advance(b)
 check(false,"Herb runner completes the finite original five-floor path")
func clear_save() -> void:
 for path in [SAVE,SAVE+".bak",SAVE+".tmp",SAVE.get_basename()+".resume.json",SAVE.get_basename()+".resume.json.tmp"]:
  if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
func route_checks()->void:
 var b=Backend.new();b.quest_catalog.enabled_events=[1]
 b.session._profile.no_random_encounters=true
 check(b.handle({"type":"quest_auto_start","quest_id":30,"client":"test"}).ok,"existing herb auto starts without adult prerequisite")
 var visited:Dictionary={};var interrupted:=false;var failed_save:=false
 for index in range(3000):
  if not b.quest_auto.running:break
  var map_id:int=b.automation.position_map
  if map_id in range(20101,20106):
   visited[map_id]=true
   check(b.quest_arrival.has_arrival(b,map_id,b.automation.position_cell),"automatic cave step retains actual original route")
  if map_id==20103 and not interrupted:
   var cell:Vector2i=b.automation.position_cell
   b.handle({"type":"quest_auto_stop"})
   check(b.handle({"type":"quest_auto_start","quest_id":30,"client":"test"}).ok and b.automation.position_cell==cell,"stop/restart resumes original current cave position")
   interrupted=true
  if str(b.quest_auto.step.get("id",""))=="herb:medicine" and b.quest_auto.phase=="ok" and not failed_save:
   var before:Dictionary=b.session.snapshot()
   b.save_path="user://missing-herb-route-auto/save.json"
   advance(b)
   check(not b.quest_auto.running and b.quest_auto.message=="save_failed" and b.session.snapshot()==before,"medicine save failure preserves material and flags")
   b.save_path="";failed_save=true
   check(b.handle({"type":"quest_auto_start","quest_id":30,"client":"test"}).ok,"explicit restart retries source transaction after save repair")
  advance(b)
 check(not b.quest_auto.running and Rules.flag(b.session.snapshot(),"ended",1) and b.session.snapshot().original_items==[2427],"full original five-floor herb auto ends with one amulet")
 check(visited.size()==5 and interrupted and failed_save,"all five original floors, interruption and save failure exercised")
 b.free()

func run() -> void:
 var started_at:=Time.get_ticks_msec()
 route_checks()
 for id in ["herb:request","herb:medicine","herb:return"]:
  for phase in ["landing","talk","yes","ok"]:
   for graceful in [false,true]:
    clear_save()
    var b=fresh()
    check(start(b).ok,"Herb runner starts")
    reach(b,id,phase)
    var before:Dictionary=b.session.snapshot()
    var token:String=str(b.original_quests.pending.get("token",""))
    b.keep_resume_file()
    if graceful:b.shut_down()
    b.free()
    b=fresh(true);b.load_resume()
    check(b.quest_auto.running and b.quest_auto.restored and b.original_quests.pending.is_empty(),"Real file restores intent and discards dialogue")
    if not token.is_empty():check(not b.original_quests.choose(b,token,"ok").ok,"Old token rejected")
    for index in range(3000):
     if not b.quest_auto.running:break
     advance(b,false)
    check(Rules.flag(b.session._profile,"ended",1) and b.session._profile.original_items==[2427],"Three original transactions yield one amulet")
    var done:Dictionary=b.session.snapshot()
    check(not start(b).ok and b.session.snapshot()==done,"Completed herb has no invented repeat")
    b.free()
   # Explicit stop invalidates pending tokens and preserves committed stages.
   clear_save();var stopped=fresh();start(stopped);reach(stopped,id,phase)
   var before_stop:Dictionary=stopped.session.snapshot()
   stopped.handle({"type":"quest_auto_stop"})
   for index in range(15):advance(stopped)
   check(stopped.session.snapshot()==before_stop and stopped.original_quests.pending.is_empty(),"Stop preserves original stage "+id+"/"+phase)
   check(start(stopped).ok,"Explicit restart derives current stage")
   finish(stopped)
   check(stopped.session._profile.original_items==[2427],"Restart finishes once")
   stopped.free()
  clear_save()
  var b=fresh();start(b);reach(b,id,"yes" if id=="herb:request" else "ok")
  var before:Dictionary=b.session.snapshot()
  remove_tree("user://herb-auto-missing")
  b.save_path="user://herb-auto-missing/save.json"
  finish(b)
  check(b.session.snapshot()==before and b.quest_auto.message=="save_failed","Atomic failed save at "+id)
  b.free()
 print("HERB MATRIX MS: ",Time.get_ticks_msec()-started_at)
 for action in ["eat","discard"]:
  clear_save()
  var b=fresh();start(b);reach(b,"herb:return","landing")
  b.handle({"type":"quest_auto_stop"})
  var reply:Dictionary=b.handle({"type":"use_item","item":"original_2401"} if action=="eat" else {"type":"quest_discard","item_id":2401})
  check(reply.ok and Rules.flag(b.session._profile,"now",1) and not Rules.flag(b.session._profile,"ended",1),"Lost medicine preserves original NOW/END: "+action)
  check(start(b).ok and b.quest_auto.step.id=="herb:medicine","Re-derive doctor after "+action)
  finish(b);check(b.session._profile.original_items==[2427],"Replenish and finish after "+action)
  b.free()
 for conflict in ["manual","party","flag"]:
  clear_save()
  var b=fresh();start(b);reach(b,"herb:medicine","landing")
  var before:Dictionary=b.session.snapshot()
  if conflict=="manual":b.handle({"type":"report_position","map_id":-1,"cell":[1,1],"client":"test"})
  elif conflict=="party":
   b.quest_visit_guard=func():return "party"
   advance(b,false)
  else:
   Rules.set_flag(b.session._profile,"ended",1,true)
   b.publish()
   before=b.session.snapshot()
   finish(b)
  check(not b.quest_auto.running and b.session.snapshot()==before,"Current authoritative conflict prevents stale transaction: "+conflict)
  b.free()
 var b=fresh()
 for id in [6,7]:check(not b.handle({"type":"quest_auto_start","quest_id":id,"client":"test"}).ok,"Reviewed doctor job refuses auto")
 b.free()
 clear_save()
 var remote_at:=Time.get_ticks_msec()
 print("HERB FIXTURES MS: ",remote_at-started_at)
 await remote_auto()
 print("HERB REMOTE MS: ",Time.get_ticks_msec()-remote_at)
 print("ORIGINAL HERB AUTO: %d failures" % failures)
 quit(1 if failures else 0)
func remote_auto() -> void:
 var backend=Backend.new()
 backend.quest_catalog.enabled_events=[1]
 backend.session._profile.no_random_encounters=true
 root.add_child(backend)
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
 root.add_child(server)
 if not check(server.start()==OK,"Auto ephemeral WebSocket starts"):return
 var script=load("res://scripts/game.gd")
 script.server_url_override="ws://127.0.0.1:%d" % server.port
 world=load("res://scenes/main.tscn").instantiate()
 script.server_url_override=""
 world.profile_persistence=false
 world.viewer_prefs_path="user://herb-auto-ui.cfg"
 var catalog=preload("res://scripts/quest_catalog.gd").new()
 catalog.enabled_events=[1]
 world.world_catalog.set_quest_catalog(catalog)
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Auto remote connects"):return
 if not check(await Wait.settle(self,world),"Auto startup settles"):return
 check(world.backend==null,"Remote automatic UI has no backend")
 world.quest_helper_menu.open_menu()
 var original_packs=world.asset_packs
 var gate:=PackGate.new()
 root.add_child(gate)
 world.asset_packs=gate
 var before:Dictionary=backend.session.snapshot()
 if not await click(world.quest_helper_menu.find_child("QuestHelper_30",true,false)):return
 if not await click(world.quest_helper_menu.find_child("QuestAutoStart_30",true,false)):return
 check(gate.waiting.is_valid() and not backend.quest_auto.running,"Automatic button waits for download before server start")
 world.quest_helper_menu.close_menu()
 gate.finish(true)
 check(await Wait.settle(self,world),"Cancelled download settles")
 check(not backend.quest_auto.running and backend.session.snapshot()==before,"Close cancels late automatic download")
 world.asset_packs=original_packs
 world.quest_helper_menu.open_menu()
 if not await click(world.quest_helper_menu.find_child("QuestHelper_30",true,false)):return
 if not await click(world.quest_helper_menu.find_child("QuestAutoStart_30",true,false)):return
 if not await ready(func():return backend.quest_auto.running and world.state.derived.get("quest_auto",{}).get("running",false),"Real button starts authoritative runner"):return
 if not await click(world.quest_helper_menu.find_child("QuestAutoStop",true,false)):return
 if not check(await Wait.settle(self,world),"Stop button settles"):return
 check(not backend.quest_auto.running,"Real stop button stops server immediately")
 before=backend.session.snapshot()
 for i in range(20):backend.quest_auto.tick(backend,0.21)
 check(backend.session.snapshot()==before,"Stopped server cannot execute more transactions")
 world.quest_helper_menu.open_menu()
 if not await click(world.quest_helper_menu.find_child("QuestHelper_30",true,false)):return
 if not await click(world.quest_helper_menu.find_child("QuestAutoStart_30",true,false)):return
 if not check(await Wait.until(self,func():return Rules.flag(backend.session._profile,"ended",1) and not backend.quest_auto.running,150.0),"Remote walks original five-floor route and confirms three herb transactions"):return
 if not check(await Wait.settle(self,world),"Completion settles"):return
 check(world.session.snapshot().original_items==[2427],"Remote reads original server reward")
 world.link.close()
 world.music.stop();world.effect.stop();world.queue_free()
 server.stop();server.queue_free();backend.queue_free();gate.queue_free()
 if not await ready(func():return not is_instance_valid(world),"Auto remote disposed"):return
 DirAccess.remove_absolute(ProjectSettings.globalize_path("user://herb-auto-ui.cfg"))
