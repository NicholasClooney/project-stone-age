extends SceneTree
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Candidate=preload("res://server/transmigration_candidate.gd")
const Rules=preload("res://server/transmigration_rules.gd")
const Fixture=preload("res://tests/transmigration_candidate_test.gd")
const Q=preload("res://server/original_quests.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func options(mode:String="120",quests:int=20,stats:Array=["strength"])->Dictionary:
 return {"level_mode":mode,"bonus_quests":quests,"allocation_stats":stats}
func packet(mode:String="120",quests:int=20,stats:Array=["strength"])->Dictionary:
 var c:=options(mode,quests,stats);c.merge({"type":"quick_transmigration","action":"preview"});return c
func fresh():
 var b=Backend.new();b.set_process(false);b.admin=false
 b.save_path="user://quick-rebirth.json"
 return b
func build(p:Dictionary,o:Dictionary)->Dictionary:
 var r:=Rules.reward_for(p.original_savepoint_bits,int(p.player.transmigration)+1)
 return Candidate.build_quick(p,o,Fixture.definition(r.enemy_id,r.template_id) if r.ok else {},71,"quick-test-%d"%int(p.player.transmigration),30)
func run()->void:
 var s=Session.new();s.gm_raise_level(-1,80);s.allocate_stat("strength",200)
 var before:Dictionary=s.snapshot()
 check(before.player.stat_points==37,"fixture leaves 37 real free points and 200 assigned strength")
 # Expected values independently computed by the audited binary32 C oracle.
 var expected:Array=[[120,1948,50,81],[137,2423,50,88],[145,3912,50,92],[157,4394,50,97],[149,4406,50,94],[160,4890,50,99]]
 var index:=0
 for mode in ["current","120","130"]:
  for q in [0,20]:
   var result:=build(before,options(mode,q))
   check(result.ok,"mode %s Q%d builds"%[mode,q])
   if not result.ok:print(result);continue
   var target:int=80 if mode=="current" else int(mode)
   check(result.pre_base_stats.strength==20700+100*(37+3*(target-80)) and result.pre_base_stats.vitality==900 and result.allocation==[{"stat":"strength","points":37+3*(target-80)}],"all existing and simulated points enter original P without respec")
   check(result.inherited.equation==(q<<16)+target and result.profile.player.level==1 and result.profile.player.stat_points==10,"only selected round Q/L recorded and saved level is one")
   check(s._valid_profile(result.profile) and s.snapshot()==before,"valid candidate, real state immutable")
   var values:Array=[]
   for stat in Rules.STATS:values.append(result.inherited.base_stats[stat])
   check(values==expected[index],"exact audited binary32 inheritance vector")
   index+=1
 var low:Dictionary=Session.new().snapshot()
 check(not build(low,options("current")).ok and build(low,options("current")).reason.contains("120"),"below80 current offers explicit simulation")
 var remainder:=build(low,options("120",0,["dexterity","toughness","strength","vitality"]))
 check(remainder.ok and remainder.allocation==[{"stat":"vitality","points":90},{"stat":"strength","points":89},{"stat":"toughness","points":89},{"stat":"dexterity","points":89}],"four-stat remainder uses standard order independent of client order")
 for bad in [[],["strength","strength"],["hp"],[7]]:check(not build(low,options("120",0,bad)).ok,"invalid allocation refused")
 for mode in ["max","", "119"]:check(not build(low,options(mode)).ok,"unknown mode refused")
 check(not build(low,options("120",1)).ok,"only Q0/20 allowed")
 var high:=before.duplicate(true);high.player.level=131
 check(not build(high,options("120")).ok and not build(high,options("130")).ok,"simulation never lowers actual level")
 for village in range(4):
  var p:Dictionary=low.duplicate(true);p.original_savepoint_bits=1<<village
  p.pets=[Fixture.pet(693,1),Fixture.pet(6,2)];p.pet_storage=[Fixture.pet(6,3)];p.next_pet_id=4;p.active_pet=1;p.ride_pet=1
  p.automation_settings={"capture":{"pet":1,"pet_id":"pet-2"}}
  for count in range(1,6):
   for e in [4,39,40,42,46,69,127]:Q.set_flag(p,"ended",e,true)
   Q.set_flag(p,"now",69,true);Q.set_flag(p,"now",34,true)
   var frozen:=p.duplicate(true)
   var r:=build(p,options("130",20 if count==1 else 0))
   check(r.ok,"all village/round rewards build %d/%d"%[village,count])
   if not r.ok:continue
   p=r.profile
   check(s._valid_profile(p) and frozen!=p and p.pets.size()==2+count and p.pets[0].pet_id=="pet-1" and p.pets[1].pet_id=="pet-2","original pets never consumed, including guardian")
   check((int(p.rebirth.equation)>>16)==20 and (int(p.rebirth.equation)&65535)==130*count,"Q0 retains prior Q; prior L not rewritten")
   check(p.pets[-1].source_enemy_id==Rules.PRESENTS[village][count-1] and p.location=={"map_id":Rules.HOMES[village][0],"x":Rules.HOMES[village][1],"y":Rules.HOMES[village][2]},"exact per-village reward and return")
   check(p.active_pet==1 and p.ride_pet==-1 and p.automation_settings.capture.pet_id=="pet-2" and p.pets[0].variable_ai==-123 and p.pet_storage[0].variable_ai==-123,"references and loyalty debt retained while dismounted")
   check(Q.flag(p,"ended",69) and Q.flag(p,"ended",127) and Q.flag(p,"now",69) and not Q.flag(p,"ended",4) and not Q.flag(p,"ended",39) and not Q.flag(p,"now",34),"normal flag clearing and keep-list, no fabricated completion")
  check(not build(p,options()).ok and p.pets[-1].species=="original_304","fifth directly gives mech pet, sixth refused")
 var full:=low.duplicate(true)
 for i in range(30):full.pets.append(Fixture.pet(6,i+1))
 full.next_pet_id=31
 check(not build(full,options()).ok,"30 carried pets refuse entire reward transaction")
 full.pets.pop_back();check(build(full,options()).ok,"29 pets allow net one reward")
 var unknown:=before.duplicate(true);unknown.player.transmigration=1;unknown.rebirth={"schema":1,"rules":Candidate.State.RULES,"history":"legacy_unknown"}
 check(not build(unknown,options()).ok,"unknown history never reconstructed")
 check(not Candidate.build(before,[],Fixture.definition(1377,6),71,"natural-test",30).ok,"natural candidate still requires trials and sacrifices")
 service_checks()
 print("QUICK TRANSMIGRATION: %d failures"%failures);quit(1 if failures else 0)
func service_checks()->void:
 var b=fresh()
 var original:Dictionary=b.session.snapshot()
 b.session._profile.player.base_stats.strength=-1
 check(not b.handle(packet()).ok and b.quick_transmigration.pending.is_empty(),"invalid real profile rejected before preview")
 b.session._profile=original
 var reward_definition:Dictionary=b.quest_catalog.reward_pets["1377"]
 b.quest_catalog.reward_pets.erase("1377")
 check(not b.handle(packet()).ok and b.session.snapshot()==original,"missing actual reward source refuses without mutation")
 b.quest_catalog.reward_pets["1377"]=reward_definition
 var before:Dictionary=b.session.snapshot()
 var first:Dictionary=b.handle(packet())
 check(first.ok and first.has("quick_transmigration"),"ordinary player can preview without trials, pets or location proof")
 if not first.has("quick_transmigration"):print(first);b.free();return
 var token:String=first.quick_transmigration.token
 var seed_value:int=b.quick_transmigration.pending.seed
 var forged:=packet();forged.seed=1
 check(not b.handle(forged).ok and b.quick_transmigration.pending.token==token and b.session.snapshot()==before,"forged seed cannot supersede valid preview or mutate")
 for field in ["base_stats","reward","new_count","pet_ids"]:
  forged=packet();forged[field]={};check(not b.handle(forged).ok,"reject forbidden field "+field)
 for values in [{"level_mode":120},{"bonus_quests":true},{"bonus_quests":0.5},{"allocation_stats":"strength"}]:
  forged=packet();forged.merge(values,true);check(not b.handle(forged).ok,"malformed options reject atomically")
 var second:Dictionary=b.handle(packet("130",0,["strength","dexterity"]))
 check(second.ok and b.quick_transmigration.pending.seed==seed_value,"changing options retains frozen reward seed")
 token=second.quick_transmigration.token
 check(not b.handle({"type":"quick_transmigration","action":"cancel","token":first.quick_transmigration.token}).ok and b.quick_transmigration.pending.token==token,"old cancel cannot erase latest preview")
 var injected:Dictionary={"type":"quick_transmigration","action":"confirm","token":token,"level_mode":"120"}
 check(not b.handle(injected).ok and b.session.snapshot()==before,"confirm rejects even valid option edits alongside token")
 var frozen:Dictionary=b.quick_transmigration.pending.candidate.duplicate(true)
 b.save_path="user://quick-rebirth-absent-dir/save.json"
 b.quest_helper.cached_key="old-round";b.quest_helper.cached_snapshot={"old":true}
 var npc_id:=""
 for npc in b.quest_catalog.npcs:
  if npc.get("events",[]).any(func(e):return int(e)==39):npc_id=str(npc.id);break
 check(not npc_id.is_empty(),"real round NPC selected for cache test")
 b.original_quests.npc_state.records[npc_id]={"counter":2,"dead_until":99999999,"map_id":1000,"cell":[1,1]}
 var cache:String=b.last_saved_payload
 for i in range(2):
  var failed:Dictionary=b.handle({"type":"quick_transmigration","action":"confirm","token":token})
  check(not failed.ok and failed.reason=="save_failed" and b.session.snapshot()==before and b.quick_transmigration.pending.candidate==frozen and b.last_saved_payload==cache and b.quest_helper.cached_key=="old-round","failed save keeps frozen candidate, assets and caches for retry")
 b.save_path="user://quick-rebirth.json"
 var success:Dictionary=b.handle({"type":"quick_transmigration","action":"confirm","token":token})
 check(success.ok and success.transaction_id==token and success.new_count==1 and b.session.snapshot()==frozen,"one atomic commit installs exactly the preview")
 check(b.quick_transmigration.pending.is_empty() and b.transmigration.pending.is_empty() and b.quest_helper.cached_key!="old-round" and not b.original_quests.npc_state.records.has(npc_id) and b.automation.position_map==1006,"shared commit sync clears previews and round caches and returns village")
 check(not b.handle({"type":"quick_transmigration","action":"confirm","token":token}).ok and b.session.snapshot()==frozen,"replay cannot duplicate reward")
 var restored=fresh();check(restored.load_profile(b.save_path) and restored.session.snapshot()==restored.session._normalize_numbers(frozen),"saved candidate survives server reload exactly")
 check(not restored.handle({"type":"quick_transmigration","action":"confirm","token":token}).ok,"restart cannot reuse token")
 restored.free()
 var preview:Dictionary=b.handle(packet())
 b.rev+=1
 check(not b.handle({"type":"quick_transmigration","action":"confirm","token":preview.quick_transmigration.token}).ok,"revision change invalidates token")
 preview=b.handle(packet());b.session._profile.player.gold+=1
 check(not b.handle({"type":"quick_transmigration","action":"confirm","token":preview.quick_transmigration.token}).ok,"state change without revision still invalidates token")
 b.stationary.running=true
 check(not b.handle(packet()).ok and b.stationary.running,"active stationary activity rejected without stopping it")
 b.stationary.running=false
 b.battle_open=true
 check(not b.handle(packet()).ok and b.battle_open,"battle cannot be bypassed")
 b.battle_open=false;b.automation.hunt_running=true
 check(not b.handle(packet()).ok and b.automation.hunt_running,"hunt cannot be bypassed")
 b.automation.hunt_running=false;b.quest_auto.running=true
 check(not b.handle(packet()).ok and b.quest_auto.running,"automatic quest cannot be bypassed")
 b.quest_auto.running=false;b.quest_visit_guard=func():return "队伍限制"
 check(not b.handle(packet()).ok,"party admission retained")
 b.free()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quick-rebirth.json"+suffix))
