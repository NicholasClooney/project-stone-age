extends SceneTree
const Backend=preload("res://server/backend.gd")
const Hub=preload("res://server/profile_hub.gd")
const Rules=preload("res://server/original_quests.gd")
const Checkpoint=preload("res://server/adult_battle_checkpoint.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func clean(path:String)->void:
 if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
  for file in DirAccess.get_files_at(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file)))
  for directory in DirAccess.get_directories_at(path):clean(path.path_join(directory))
  DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
func make_hub(path:String):
 var hub=Hub.new(path.path_join("accounts.json"))
 hub.tick=false;hub.share_dir="";hub.backups=false
 root.add_child(hub)
 check(hub.start(),"Real profile hub starts")
 return hub
func run()->void:
 var directory="user://quest-saved-position-hub"
 clean(directory)
 var hub=make_hub(directory)
 check(hub.handle(101,{"type":"create_profile","name":"Alice","pin":"1111"}).ok,"Create Alice")
 check(hub.handle(102,{"type":"create_profile","name":"Bob","pin":"2222"}).ok,"Create Bob")
 var origins:Dictionary={}
 for id in ["alice","bob"]:
  var b=hub.backends[id]
  b.quest_catalog.enabled_events=[2]
  b.session._profile.original_savepoint_bits=1 if id=="alice" else 2
  b.session._profile.no_random_encounters=true
  var home:int=1000 if id=="alice" else 2000
  var spawn:Array=b.quest_helper.places.info(home).spawn
  b.automation.position_changed(home,Vector2i(spawn[0],spawn[1]))
  origins[id]={"map_id":home,"cell":spawn}
  check(hub.handle(101 if id=="alice" else 102,{"type":"quest_auto_start","quest_id":11,"client":id}).ok,"Authenticated task starts")
  b.keep_resume_file()
 hub.shut_down();hub.free()
 hub=make_hub(directory)
 check(hub.backends.size()==2 and hub.connections_of("alice").is_empty() and hub.connections_of("bob").is_empty(),"Both real saved profiles reopen without any client")
 for id in ["alice","bob"]:
  var b=hub.backends[id]
  b.quest_catalog.enabled_events=[2]
  check(b.automation.position_map==origins[id].map_id and b.automation.position_cell==Vector2i(origins[id].cell[0],origins[id].cell[1]),"Restored authority is saved location: "+id)
  for index in range(8000):
   if not b.quest_auto.running:break
   b.quest_auto.tick(b,0.21)
  check(Rules.flag(b.session._profile,"ended",2) and b.session._profile.original_items==([2414] if id=="alice" else [2415]),"No-device strict A completes independent saved direction: "+id+" "+b.quest_auto.message)
 hub.shut_down();hub.free();clean(directory)
 invalid_and_protected()
 checkpoint_priority()
 print("QUEST AUTO SAVED POSITION: %d failures"%failures)
 quit(1 if failures else 0)
func invalid_and_protected()->void:
 var b=Backend.new()
 for location in [null,{}, {"map_id":-1,"x":0,"y":0},{"map_id":1000,"x":1.5,"y":2},{"map_id":true,"x":2,"y":2},{"map_id":1000,"x":9999,"y":2}]:
  b.last_saved_payload=JSON.stringify({"location":location})
  check(not b._restore_quest_saved_position() and b.automation.position_map==-1,"Missing or malformed saved location cannot synthesize authority")
 b.session.set_location(20101,29,69)
 b.save_path="user://quest-position-protected.json"
 check(b.save(),"Actual protected location saved")
 b._write_resume_file(b._resume_file(),{"quest_auto":{"version":2,"quest_id":30},"map_id":1000,"cell":[56,58]})
 b.free()
 b=Backend.new();b.save_path="user://quest-position-protected.json"
 check(b.load_profile(b.save_path),"Reload real protected profile")
 b.load_resume()
 check(b.automation.position_map==20101 and b.automation.position_cell==Vector2i(29,69),"Resume envelope coordinate forgery ignored")
 check(not b.quest_arrival.has_arrival(b,20101,b.automation.position_cell) and b.quest_auto.issued.is_empty(),"Profile location restores neither proof nor receipt")
 b.quest_auto.tick(b,0.21)
 check(not b.quest_auto.running and b.quest_auto.phase=="manual","Protected saved location requires original entrance again")
 remove_files(b.save_path);b.free()
func remove_files(path:String)->void:
 for file in [path,path+".bak",path+".tmp",path.get_basename()+".resume.json"]:
  if FileAccess.file_exists(file):DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
func checkpoint_priority()->void:
 var path="user://quest-position-adult.json"
 remove_files(path)
 var b=Backend.new();b.save_path=path
 b.quest_catalog.enabled_events=[4]
 b.session.gm_raise_level(-1,30)
 check(b.session.set_location(1000,56,58) and b.save(),"Pre-battle saved location deliberately differs")
 b.automation.position_changed(10204,Vector2i(3,6))
 b.encounter_rng.seed=7
 check(b.wild_encounter(10204,Vector2i(3,6)).ok,"Real original adult troop opens")
 b.quest_auto.running=true;b.quest_auto.quest_id=1;b.quest_auto.strict_walk=true
 b.quest_auto.identity.begin();b.quest_auto.identity.select_step("adult:request")
 var saved:Dictionary=Checkpoint.snapshot(b)
 check(not saved.is_empty(),"Real adult checkpoint produced")
 var pending:Dictionary=b.session._pending.duplicate(true)
 b._write_resume_file(b._resume_file(),{"adult_battle":saved,"quest_auto":b.quest_auto.resume_state(),"map_id":100,"cell":[1,1]})
 b.free()
 b=Backend.new();b.save_path=path
 check(b.load_profile(path),"Reload adult pre-battle profile")
 b.load_resume()
 check(b.battle_open and b.automation.position_map==10204 and b.automation.position_cell==Vector2i(3,6) and b.session._pending==pending,"Real checkpoint battle and location take priority over saved profile and resume envelope")
 check(b.quest_auto.phase=="battle" and not b.quest_arrival.has_arrival(b,10204,b.automation.position_cell),"Restored battle may settle but checkpoint grants no route proof")
 b.quest_auto.stop(b);b.free();remove_files(path)
