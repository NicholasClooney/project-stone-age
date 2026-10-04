extends "res://tests/original_quest_auto_test.gd"
## Real saves and original transactions. No pending dialogue/token survives restart.
const SAVE="user://quest-auto-resume.json"
func fresh(load_saved:bool=false):
 var b=Backend.new() if load_saved else fixture()
 b.quest_catalog.enabled_events=[2]
 b.set_process(false)
 root.add_child(b)
 if load_saved:check(b.load_profile(SAVE),"Real profile reloads")
 b.save_path=SAVE
 b.keep_resume_current=true
 return b
func reach(b,branch:String,phase:String) -> void:
 for index in range(20000):
  if str(b.quest_auto.step.get("source",{}).get("type",""))==branch and checkpoint(b,phase):return
  advance(b,false)
  if b.quest_auto.phase=="landing" and not (phase=="landing" and str(b.quest_auto.step.get("source",{}).get("type",""))==branch):
   b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"client":"test"})
 check(false,"Reach checkpoint "+branch+"/"+phase)
func finish_restored(b) -> void:
 for index in range(20000):
  if not b.quest_auto.running:return
  advance(b,false)
 check(false,"Restored server completes without any device/mapreport")
func clear_save() -> void:
 for path in [SAVE,SAVE+".bak",SAVE+".tmp",SAVE.get_basename()+".resume.json",SAVE.get_basename()+".resume.json.tmp"]:
  if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
func run() -> void:
 for graceful in [false,true]:
  for branch in ["REQUEST","ACCEPT","CLEAN"]:
   for phase in ["travel","landing","talk","yes","ok"]:
    if phase=="travel" and branch!="REQUEST":continue
    clear_save()
    var b=fresh()
    if branch=="CLEAN":Rules.set_flag(b.session._profile,"ended",2,true)
    check(start(b).ok,"Checkpoint fixture starts")
    reach(b,branch,phase)
    b.keep_resume_file()
    var token:String=str(b.original_quests.pending.get("token",""))
    if graceful:
     # Exercise transport-first shutdown as well as direct backend shutdown.
     var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1")
     server.stop()
     b.shut_down()
     server.free()
    b.free()
    var restored=fresh(true)
    restored.load_resume()
    check(restored.quest_auto.running and restored.quest_auto.restored and restored.quest_auto.connection==-1,"Intent resumes with no forged connection")
    check(restored.original_quests.pending.is_empty(),"Old dialogue discarded")
    if not token.is_empty():check(not restored.original_quests.choose(restored,token,"ok").ok,"Old token cannot replay")
    finish_restored(restored)
    check(restored.session._profile.original_items==[2414] and Rules.flag(restored.session._profile,"ended",2),"One authentic reward after %s/%s (%s)" % [branch,phase,graceful])
    restored.free()
 # Stale periodic intent against newer committed reward must never CLEAN/reward again.
 clear_save()
 var b=fresh()
 start(b);b.keep_resume_file()
 finish(b)
 # Recreate stale periodic file, but keep real completed profile.
 b._write_resume_file(b._resume_file(),{"quest_auto":{"version":1,"quest_id":11,"clean_authorized":true}})
 var done:Dictionary=b.session.snapshot()
 b.free()
 b=fresh(true);b.load_resume();finish_restored(b)
 check(not b.quest_auto.running and b.session.snapshot()==done,"Completed reward prevents stale intent replay/CLEAN")
 b.free()
 for conflict in ["stop","manual","battle","party"]:
  clear_save();b=fresh();start(b);b.keep_resume_file();b.free()
  b=fresh(true);b.load_resume()
  if conflict=="stop":b.handle({"type":"quest_auto_stop"})
  elif conflict=="manual":b.handle({"type":"report_position","map_id":-1,"cell":[1,1],"client":"other"})
  elif conflict=="battle":b.battle_open=true;advance(b,false);b.battle_open=false
  else:
   b.quest_visit_guard=func():return "party"
   advance(b,false)
  check(not b.quest_auto.running and not FileAccess.file_exists(b._resume_file()),"Restored conflict removes intent: "+conflict)
  b.shut_down();b.free();b=fresh(true);b.load_resume()
  check(not b.quest_auto.running,"Explicit stop/conflict cannot revive on another restart")
  b.free()
 clear_save();b=fresh()
 b.handle({"type":"set_automation_settings","settings":{"hunt":{"resume":false}}})
 start(b);b.keep_resume_file()
 check(not FileAccess.file_exists(b._resume_file()),"Opt out does not checkpoint quests")
 b.shut_down();b.free();b=fresh(true);b.load_resume()
 check(not b.quest_auto.running,"Opt out stays stopped after clean restart")
 b.free()
 await hub_restart()
 clear_save()
 print("QUEST AUTO RESUME: %d failures" % failures)
 quit(1 if failures else 0)
func hub_restart() -> void:
 var directory="user://quest-auto-resume-hub"
 remove_tree(directory)
 var Hub=preload("res://server/profile_hub.gd")
 var hub=Hub.new(directory.path_join("accounts.json"))
 hub.tick=false;hub.share_dir="";hub.backups=false
 root.add_child(hub)
 check(hub.start(),"Real hub starts")
 check(hub.handle(101,{"type":"create_profile","name":"Alice","pin":"1111"}).ok,"Alice created")
 check(hub.handle(102,{"type":"create_profile","name":"Bob","pin":"2222"}).ok,"Bob created")
 for id in ["alice","bob"]:
  var b=hub.backends[id]
  b.quest_catalog.enabled_events=[2]
  prepare(b)
  if id=="bob":b.session._profile.original_savepoint_bits=2
  check(b.save(),"Fixture saves its original direction and encounter setting before restart")
  check(hub.handle(101 if id=="alice" else 102,{"type":"quest_auto_start","quest_id":11,"client":id}).ok,"Authenticated profile starts")
  b.keep_resume_file()
 hub.shut_down();hub.free()
 # Event availability is server configuration; use its existing on-disk config.
 hub=Hub.new(directory.path_join("accounts.json"))
 hub.tick=false;hub.share_dir="";hub.backups=false
 root.add_child(hub)
 check(hub.start(),"Hub opens profiles with checkpoints without login")
 check(hub.backends.size()==2 and hub.connections_of("alice").is_empty(),"Profiles open with no old device")
 for id in ["alice","bob"]:
  var b=hub.backends[id]
  check(b.quest_auto.running,"Profile restored from independent checkpoint: "+id)
  finish_restored(b)
  check(b.session._profile.original_items==([2414] if id=="alice" else [2415]),"Independent direction/reward: "+id)
 hub.shut_down();hub.free();remove_tree(directory)
