extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Progression=preload("res://server/progression.gd")
const CaveRoute=preload("res://tests/support/legacy_cave_route.gd")
const Hub=preload("res://server/profile_hub.gd")
const DOCTOR="sainasu/event/event15_1"
const ASSISTANT="sainasu/event/event15_2"
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func row(b,event:int) -> Dictionary:
 for q in b.quest_helper.snapshot(b).quests:
  if int(q.event)==event:return q
 return {}
func current(b,event:int,id:String) -> bool:
 return row(b,event).steps.any(func(s):return s.id=="doctor%d:"%event+id and s.current and s.actionable)
func talk(b,id:String=DOCTOR) -> Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 check(CaveRoute.approach(b,b.original_quests.npc_by_id(id)).ok,"actual cave route reaches original NPC")
 return b.handle({"type":"quest_talk","npc_id":id})
func choose(b,r:Dictionary,c:String) -> Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":c})
func trade(b) -> Dictionary:
 var r:=choose(b,talk(b),"yes")
 return choose(b,r,"ok") if r.has("dialogue") else r
func add(b,species:int,level:int,event:int=0) -> String:
 check(b.session.gm_grant_pet(species),"real imported birth %d"%species)
 var pet:Dictionary=b.session._profile.pets[-1]
 pet.original_end_event=event
 check(b.session.level_pet_to(str(pet.pet_id),level),"real progression to %d"%level)
 return str(pet.pet_id)
func run() -> void:
 var b=Backend.new()
 check(preload("res://tests/support/registered_quest_events.gd").matches(b.quest_catalog.enabled_events),"both doctor stages enabled")
 check(not row(b,15).repeatable and not row(b,16).repeatable,"no invented CLEAN")
 for id in [DOCTOR,ASSISTANT]:
  var npc:Dictionary=b.original_quests.npc_by_id(id)
  check(npc.map_id==11006 and FileAccess.file_exists("res://assets/legacy/"+str(npc.path)),"real doctor map and static art")
  for mode in ["arrival","near"]:
   var target:Dictionary=b.quest_helper.destination(b,npc,mode)
   check(int(target.get("map_id",-1))==100,"doctor helper reaches public entrance without END4 "+mode)
 var definition:Dictionary=b.quest_catalog.reward_pets["95"]
 check(definition.template_id==173 and definition.level==1 and definition.weights.map(func(v):return int(v))==[26,26,26,17] and definition.initial==25 and definition.sprite==100321 and definition.skill_slots==5 and definition.modai==270,"GetPet95 maps source enemy to exact species and birth parameters")
 b.session.gm_raise_level(-1,9)
 check(not current(b,15,"request"),"LV9 blocked")
 b.session.gm_raise_level(-1,10)
 check(current(b,15,"request") and not Rules.flag(b.session.snapshot(),"ended",4),"LV10 enabled without adult ceremony")
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-doctor/save.json"
 check(not trade(b).ok and b.session.snapshot()==before,"request save failure rolls back")
 b.save_path=""
 check(trade(b).ok and Rules.flag(b.session.snapshot(),"now",15),"doctor first request")
 var reply:=talk(b,ASSISTANT)
 check(reply.dialogue.text.contains("１５级") and reply.dialogue.text.contains("北方"),"original assistant source explanation")
 var event_id:=add(b,74,15,1)
 var young_id:=add(b,74,14)
 check(not current(b,15,"return") and current(b,15,"capture"),"event pet and Lv14 rejected; helper cache updates")
 var first:=add(b,74,15)
 var second:=add(b,74,16)
 check(current(b,15,"return"),"pet level and provenance refresh helper cache")
 b.session._profile.pets[0].name="鲁尼帖斯"
 check(Rules.pet_index(b.session.snapshot(),"PET>14-74")==2,"nickname never bypasses event provenance, first eligible slot")
 reply=choose(b,talk(b),"yes")
 b.session._profile.pets[2].original_end_event=1
 before=b.session.snapshot()
 check(not choose(b,reply,"ok").ok and b.session.snapshot()==before,"UID-bound confirmation cannot silently consume next pet")
 b.session._profile.pets[2].original_end_event=0
 b.session._profile.active_pet=2;b.session._profile.ride_pet=3
 b.session._profile.automation_settings={"capture":{"pet":2,"pet_id":first}}
 b.automation.settings.capture_pet_id=first;b.automation.settings.capture_pet=2;b.automation.training_pet_id=first
 b.session._profile.original_items.resize(14);b.session._profile.original_items.fill(2414)
 before=b.session.snapshot()
 check(not trade(b).ok and b.session.snapshot()==before and row(b,15).blocked_reason.contains("道具栏"),"full bag blocks random reward without deleting pet")
 b.session._profile.original_items=[]
 reply=choose(b,talk(b),"yes")
 before=b.session.snapshot();b.save_path="user://missing-doctor/save.json"
 check(not choose(b,reply,"ok").ok and b.session.snapshot()==before,"failed disk commit restores pet UID, references, flags and bag")
 check(not choose(b,reply,"ok").ok and b.session.snapshot()==before,"failed consumed token cannot reroll")
 b.save_path=""
 reply=choose(b,talk(b),"yes")
 check(b.session.snapshot().original_items.is_empty(),"YES thanks does not sample or consume")
 var token:String=reply.dialogue.token
 check(choose(b,reply,"ok").ok,"final OK commits first doctor exchange")
 var profile:Dictionary=b.session.snapshot()
 check(profile.pets.map(func(p):return str(p.pet_id))==[event_id,young_id,second],"exact first eligible UID removed once")
 check(profile.active_pet==-1 and profile.ride_pet==2 and profile.automation_settings.capture.pet_id=="" and profile.automation_settings.capture.pet==-2,"active, mount slot and selected capture reference repaired")
 check(b.automation.settings.capture_pet_id=="" and b.automation.settings.capture_pet==-2 and b.automation.training_pet_id=="","removed pet clears cached automation selection after successful save")
 check(profile.original_items.size()==1 and profile.original_items[0] in [1350,1351,1352,1354,700,1455,1102,1122] and Rules.flag(profile,"ended",15) and not Rules.flag(profile,"now",15),"one reviewed random item and END15 atomically")
 check(not choose(b,{"dialogue":{"token":token}},"ok").ok,"success token replay refused")
 check(not current(b,16,"request"),"second request LV10 blocked despite END15")
 b.session.gm_raise_level(-1,15)
 check(not current(b,16,"request"),"LV15 second boundary blocked")
 b.session.gm_raise_level(-1,16)
 # Original earlier ENDEV15 PET74 message takes precedence if a spare 74
 # remains; the REQUEST16 precedes it and therefore still wins at LV16.
 check(current(b,16,"request") and trade(b).ok,"LV16 END15 starts second stage with original ordering")
 var bel:=add(b,191,29)
 check(not current(b,16,"return"),"Lv29 Beluka blocked")
 check(b.session.level_pet_to(bel,30) and current(b,16,"return"),"Lv30 enables second return")
 for i in range(Session.PET_CAPACITY-b.session._profile.pets.size()):add(b,173,1)
 b.session._profile.ride_pet=3
 b.session._profile.active_pet=-1
 before=b.session.snapshot();b.save_path="user://missing-doctor/save.json"
 check(not trade(b).ok and b.session.snapshot()==before,"second save failure restores full roster")
 b.save_path=""
 check(trade(b).ok and b.session.snapshot().pets.size()==Session.PET_CAPACITY,"full pet roster supports net one-for-one exchange")
 profile=b.session.snapshot()
 var reward:Dictionary=profile.pets[-1]
 check(reward.species=="original_173" and reward.level==1 and reward.source_enemy_id==95 and reward.original_end_event==0 and reward.variable_ai==0 and reward.modai==270 and reward.elements.map(func(v):return int(v))==[0,50,50,0] and reward.skill_slots==5 and reward.size==0 and profile.ride_pet==-1,"source-correct Lv1 reward, original variable AI and cleared removed mount")
 var born:=Progression.species_actor("original_173",1,int(reward.growth_seed),[],definition)
 check(born.base_stats==reward.base_stats and born.growth_weights==reward.growth_weights,"reward birth uses exact reviewed enemybase and ordinary random grades")
 var grown:=Progression.project_pet(reward,2)
 check(b.session.level_pet_to(str(reward.pet_id),2) and b.session.snapshot().pets[-1].base_stats==grown.base_stats,"reward follows persisted authentic progression")
 check(Rules.flag(profile,"ended",16) and not Rules.flag(profile,"now",16) and not row(b,16).can_restart,"END16 once and no repeat")
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 check(not b.handle({"type":"quest_auto_start","quest_id":6,"client":"test"}).ok,"doctor auto remains unavailable")
 for event in [15,16]:
  for step in row(b,event).steps:
   if not step.has("map_id"):continue
   for mode in ["arrival","near"]:
    var visit:Dictionary=b.handle({"type":"quest_visit","quest_id":row(b,event).id,"step_id":step.id,"mode":mode})
    if not str(step.get("npc_id","")).is_empty() and visit.ok:check(b.automation.position_map==100 or b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"helper never manufactures cave route")
 migration(b)
 b.free()
 lan()
 print("ORIGINAL DOCTOR QUEST: %d failures"%failures)
 quit(1 if failures else 0)
func migration(b) -> void:
 var path:="user://doctor-source-migration.json"
 var copy:Dictionary=b.session.snapshot()
 copy.pets=copy.pets.slice(0,3);copy.active_pet=-1;copy.ride_pet=-1
 for pet in copy.pets:pet.erase("original_end_event");pet.erase("source_enemy_id")
 copy.pets[0].source_enemy_id=157
 copy.pets[1].name="鲁尼帖斯"
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(copy));file.close()
 var loaded=Session.new()
 check(loaded.load_game(path) and loaded.snapshot().pets[0].original_end_event==0 and loaded.snapshot().pets[1].original_end_event==1,"old captured source migrates; ambiguous nickname remains conservatively ineligible")
 check(loaded.save_game(path) and Session.new().load_game(path),"new field roundtrip retains compatible version")
 copy.pets[0].original_end_event=2
 file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(copy));file.close()
 DirAccess.remove_absolute(path+".bak")
 check(not Session.new().load_game(path),"invalid provenance flag rejected")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
func lan() -> void:
 var dir:="user://doctor-hub-%d"%OS.get_process_id()
 DirAccess.make_dir_recursive_absolute(dir)
 var hub=Hub.new(dir.path_join("accounts.json"));hub.tick=false;hub.backups=false;hub.share_dir=""
 check(hub.start(),"real doctor ProfileHub starts")
 check(hub.handle(1,{"type":"create_profile","name":"Alice","pin":"1111"}).ok and hub.handle(2,{"type":"create_profile","name":"Bob","pin":"2222"}).ok and hub.handle(3,{"type":"login","name":"Alice","pin":"1111"}).ok,"isolated LAN profiles and shared Alice device")
 var a=hub.backend_of(1);var b=hub.backend_of(2)
 for backend in [a,b]:
  backend.session.gm_raise_level(-1,10)
  check(CaveRoute.approach(backend,backend.original_quests.npc_by_id(DOCTOR)).ok,"LAN each character walks original cave")
 var one:Dictionary=hub.handle(1,{"type":"quest_talk","npc_id":DOCTOR})
 var bob:Dictionary=hub.handle(2,{"type":"quest_talk","npc_id":DOCTOR})
 var two:Dictionary=hub.handle(3,{"type":"quest_talk","npc_id":DOCTOR})
 check(not hub.handle(1,{"type":"quest_choose","token":one.dialogue.token,"choice":"yes"}).ok,"second device invalidates old doctor token")
 check(hub.handle(3,{"type":"quest_choose","token":two.dialogue.token,"choice":"yes"}).ok and not Rules.flag(b.session.snapshot(),"now",15),"doctor flags isolated across LAN profiles")
 check(not hub.handle(2,{"type":"quest_choose","token":two.dialogue.token,"choice":"yes"}).ok and hub.handle(2,{"type":"quest_choose","token":bob.dialogue.token,"choice":"yes"}).ok,"foreign token leaves Bob doctor token intact")
 hub.shut_down();hub.free()
 for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(f))
 DirAccess.remove_absolute(dir)
