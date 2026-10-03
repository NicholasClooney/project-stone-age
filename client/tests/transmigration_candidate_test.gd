extends SceneTree
const Session=preload("res://server/game_session.gd")
const Candidate=preload("res://server/transmigration_candidate.gd")
const Rules=preload("res://server/transmigration_rules.gd")
const Q=preload("res://server/original_quests.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func pet(template:int,uid:int)->Dictionary:
 var species:="original_%d"%template
 var d:Dictionary=Session.Progression.species_definition(species)
 var p:Dictionary=Session.Progression.species_actor(species,1,100+uid)
 p.merge({"species":species,"sprite":d.sprite,"name":d.name,"pet_id":"pet-%d"%uid,"level":1,"xp":0,"skill_unlocked":false,"modai":d.modai,"variable_ai":-123,"elements":d.elements.duplicate(),"skill_slots":4})
 return p
func definition(enemy:int,template:int)->Dictionary:
 # Isolated candidate input from the real encounter table; this test does not
 # install a service NPC, invent arrival, or exercise the final content importer.
 var d:Dictionary=Session.Progression.species_definition("original_%d"%template).duplicate(true)
 d.merge({"enemy_id":enemy,"template_id":template,"species":"original_%d"%template,"level":1,"skill_slots":4})
 return d
func _initialize()->void:
 var s=Session.new()
 for village in range(4):
  var p:Dictionary=s.snapshot();p.original_savepoint_bits=1<<village
  p.pets=[pet(693,1),pet(694,2),pet(695,3),pet(696,4),pet(6,5)];p.next_pet_id=6;p.active_pet=4;p.ride_pet=4
  p.automation_settings={"capture":{"pet":4,"pet_id":"pet-5"}}
  for count in range(1,6):
   p.player.level=100;p.player.stat_points=297+int(p.rebirth.round_points)
   for event in [39,40,42,46,69,127]:Q.set_flag(p,"ended",event,true)
   Q.set_flag(p,"now",69,true);Q.set_flag(p,"now",34,true)
   if count==5:
    # Refill consumed source sacrifices as independent test setup; normal
    # gameplay must earn these again and this fixture grants no route proof.
    p.pets=[pet(693,20),pet(694,21),pet(695,22),pet(696,23),pet(6,24)];p.next_pet_id=25;p.active_pet=4
   var frozen:=p.duplicate(true)
   var r:=Rules.reward_for(p.original_savepoint_bits,count)
   var d:=definition(r.enemy_id,r.template_id)
   var result:=Candidate.build(p,[],d,27,"candidate-%d-%d"%[village,count],Session.PET_CAPACITY)
   check(result.ok,"candidate village %d round %d builds"%[village,count])
   if not result.ok:print(result);continue
   check(p==frozen,"input remains immutable")
   check(result.profile==Candidate.build(p,[],d,27,"candidate-%d-%d"%[village,count],Session.PET_CAPACITY).profile,"same frozen seed creates identical retry")
   p=result.profile
   check(s._valid_profile(p),"complete v7 candidate passes ordinary Session validation")
   check(p.player.level==1 and p.player.stat_points==10*count and p.location==r.location and p.ride_pet==-1,"round points and persistent village are atomic candidate fields")
   check(Q.flag(p,"ended",47+count) and Q.flag(p,"ended",69) and Q.flag(p,"ended",127) and not Q.flag(p,"ended",39) and not Q.flag(p,"now",34) and Q.flag(p,"now",69),"original flags cleared and preserved precisely")
   check(p.pets[-1].source_enemy_id==r.enemy_id and p.pets[-1].variable_ai==0,"reward uses real village enemy and fresh loyalty debt")
   if count==1:
    check(p.active_pet==3 and p.automation_settings.capture.pet==3 and p.pets[3].pet_id=="pet-5" and p.pets[3].variable_ai==-123,"ordinary UID and variable AI survive remap")
    var before:Dictionary=s.snapshot();s._profile=frozen
    check(not s.commit_transmigration_candidate(p,"user://absent-rebirth-candidate/save.json") and s._profile==frozen,"save failure rolls back full candidate")
    var path:="user://candidate-atomic-%d.json"%village
    check(s.commit_transmigration_candidate(p,path),"candidate single save succeeds")
    var readback=Session.new()
    check(readback.load_game(path) and readback.snapshot().rebirth==p.rebirth and readback.snapshot().location==p.location,"reward/history/return survive actual readback")
    check(not s.commit_transmigration_candidate(p,path),"same round cannot replay")
    s._profile=before
    for suffix in ["",".tmp",".bak"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 var full:Dictionary=s.snapshot()
 full.player.level=80;full.player.stat_points=237
 for event in [39,40,42,46]:Q.set_flag(full,"ended",event,true)
 for index in range(30):full.pets.append(pet(693 if index==29 else 6,index+1))
 full.next_pet_id=31;full.active_pet=0
 full.gm_bonus_points=20;full.player.stat_points+=20
 var original:=full.duplicate(true)
 var reward_def:=definition(1377,6)
 var thirty:=Candidate.build(full,[],reward_def,27,"thirty-slot-round",Session.PET_CAPACITY)
 check(thirty.ok and thirty.profile.pets.size()==30 and thirty.selected.pet_ids==["pet-30"],"real 30 carried slots selects last sacrifice with net capacity")
 if thirty.ok:
  check(s._valid_profile(thirty.profile) and thirty.profile.gm_bonus_points==0 and thirty.profile.rebirth.consumed_gm_points==20 and thirty.profile.player.stat_points==10,"GM points consumed once, new round isolated")
 check(not Candidate.build(full,["pet-1"],reward_def,27,"wrong-template",30).ok and full==original,"wrong UID template rejected without mutation")
 check(not Candidate.build(full,["pet-30","pet-30"],reward_def,27,"duplicate-uid",30).ok,"duplicate selection rejected")
 check(not Candidate.build(full,[],reward_def,27,"capacity",29).ok,"candidate honors supplied Session capacity")
 var invalid:=full.duplicate(true);invalid.original_savepoint_bits=0
 check(not Candidate.build(invalid,[],reward_def,27,"no-home",30).ok,"missing village fails closed")
 invalid=full.duplicate(true);invalid.player.level=79
 check(not Candidate.build(invalid,[],reward_def,27,"low-level",30).ok,"below original level rejected")
 invalid=full.duplicate(true);invalid.rebirth={"schema":1,"rules":Candidate.State.RULES,"history":"legacy_unknown"};invalid.player.transmigration=1
 check(not Candidate.build(invalid,[],reward_def,27,"unknown-history",30).ok,"unknown old history is never invented")
 print("TRANSMIGRATION CANDIDATE: %d failures"%failures)
 quit(1 if failures else 0)
