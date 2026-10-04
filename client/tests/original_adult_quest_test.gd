extends "res://tests/original_herb_quest_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const JUDGE="jaruga/event/event04_1"
const MESSENGER="jaruga/event/event04_2"
func adult_row(b) -> Dictionary:
 for q in b.quest_helper.snapshot(b).quests:
  if int(q.event)==4:return q
 return {}
func clear_bag(b) -> void:
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
func initialize_walk(b)->void:
 if b.automation.position_map<0:
  var spawn:Array=b.quest_helper.places.info(1000).spawn
  b.automation.position_changed(1000,Vector2i(spawn[0],spawn[1]))
func tick(b) -> void:
 b.automation.tick(1.0)
 b.quest_auto.tick(b,0.21)
 if b.quest_auto.phase=="landing":b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"client":"test"})
func trade(b,id:String)->Dictionary:
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 var goal:Dictionary=b.quest_helper.adult_walk_destination(b,npc)
 if goal.is_empty():return {"ok":false,"reason":"missing original adult target"}
 var walked:Dictionary=Route.walk(b,10204,Vector2i(int(goal.cell[0]),int(goal.cell[1])),[10204])
 if not walked.ok:return walked
 return super.trade(b,id)
func enter(b)->void:
 b.session.gm_raise_level(-1,30)
 b.automation.position_changed(10202,Vector2i(31,13))
 check(b.handle({"type":"check_passage","from_map":10202,"to_map":10204}).ok and b.handle({"type":"report_position","map_id":10204,"cell":[2,6],"client":"test"}).ok,"level30 uses exact original entry and receives continuous route")
func run() -> void:
 check(preload("res://scripts/quest_auto_policy.gd").JOB_MAPS[1]==[10202,10204],"adult preloads only original gate map and ritual channel")
 var b=Backend.new()
 b.quest_catalog.enabled_events=[4,15]
 clear_bag(b)
 check(adult_row(b).steps.size()==3 and not adult_row(b).repeatable,"three original adult stages, no CLEAN")
 check(b.quest_helper.places.field(10204),"original channel supports walking encounters")
 b.automation.position_changed(10202,Vector2i(31,13),true)
 check(b.quest_helper.places.links(10202)[Vector2i(31,13)].requires_level==30,"source-backed original entrance level metadata")
 check(not b.handle({"type":"check_passage","from_map":10202,"to_map":10204}).ok,"original entrance rejects low level")
 check(not b.handle({"type":"report_position","map_id":10204,"cell":[2,6],"client":"test"}).ok,"forged low-level walk arrival rejected")
 check(b.handle({"type":"quest_visit","npc_id":JUDGE,"mode":"near"}).ok and b.automation.position_map==10202,"helper stops outside original gate even at low level")
 check(not b.handle({"type":"quest_talk","npc_id":JUDGE}).ok and not Rules.flag(b.session._profile,"now",4),"outside helper cannot talk through level gate")
 check(not b.handle({"type":"quest_auto_start","quest_id":1,"client":"test"}).ok,"automatic ritual does not bypass original level requirement")
 enter(b)
 check(not b.handle({"type":"quest_visit","npc_id":MESSENGER,"mode":"near"}).ok and b.quest_arrival.has_arrival(b,10204,b.automation.position_cell),"distant helper refusal leaves legitimate route intact")
 check(trade(b,JUDGE).ok and Rules.flag(b.session._profile,"now",4),"original request commits only after actual entry and walking")
 b.session._profile.inventory.potion=1
 check(not trade(b,MESSENGER).ok and b.session._profile.original_items.is_empty(),"fifteen jade require fifteen independent empty slots")
 clear_bag(b)
 check(trade(b,MESSENGER).ok and b.session._profile.original_items.count(2417)==15,"messenger grants actual fifteen jade")
 check(trade(b,JUDGE).ok and b.session._profile.original_items==[2418] and Rules.flag(b.session._profile,"ended",4),"judge consumes fifteen and grants exactly one helmet END4")
 var before:Dictionary=b.session.snapshot()
 trade(b,JUDGE)
 check(b.session.snapshot()==before,"ended original ritual cannot repeat reward")
 b.free()
 b=Backend.new();b.quest_catalog.enabled_events=[4,15];clear_bag(b)
 for id in [JUDGE,MESSENGER]:
  var npc:Dictionary=b.original_quests.npc_by_id(id)
  check(npc.map_id==10204 and FileAccess.file_exists("res://assets/legacy/"+str(npc.path)),"original NPC art and location "+id)
  enter(b)
  var near:Dictionary=b.quest_helper.adult_walk_destination(b,npc)
  var arrival:Dictionary={"cell":[2,6]}
  var path:Array=b.quest_auto.walk_path(b,Vector2i(near.cell[0],near.cell[1]))
  check(arrival.cell==near.cell or not path.is_empty(),"actual walkable component reaches "+id)
 b.free()
 for encounters in [false,true]:
  b=Backend.new();b.quest_catalog.enabled_events=[4,15];clear_bag(b);b.session.gm_raise_level(-1,30)
  # Strong ordinary character fixture; combat, policy, enemies and settlement stay real.
  b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
  preload("res://server/progression.gd").refresh(b.session._profile.player)
  b.session._profile.player.hp=b.session._profile.player.max_hp
  b.handle({"type":"no_random_encounters","enabled":not encounters})
  Rules.set_flag(b.session._profile,"now",15,true)
  b.encounter_rng.seed=7
  initialize_walk(b)
  check(b.handle({"type":"quest_auto_start","quest_id":1,"client":"test"}).ok,"adult auto starts")
  var walked:=0
  var battles:=0
  for i in range(6000):
   if not b.quest_auto.running:break
   var old:Vector2i=b.automation.position_cell
   var old_phase:String=b.quest_auto.phase
   var old_map:int=b.automation.position_map
   tick(b)
   if old_map==b.automation.position_map and old!=b.automation.position_cell:
    walked+=1
    check(absi(old.x-b.automation.position_cell.x)+absi(old.y-b.automation.position_cell.y)==1,"one real source-channel step")
   if b.quest_auto.phase=="battle" and old_phase!="battle":battles+=1
  check(not b.quest_auto.running and Rules.flag(b.session._profile,"ended",4) and b.session._profile.original_items==[2418],"auto completes original three exchanges "+str(encounters)+" "+b.quest_auto.message)
  check(Rules.flag(b.session._profile,"now",15) and not Rules.flag(b.session._profile,"ended",15),"adult exchange preserves concurrent doctor flags")
  check(b.session._valid_profile(b.session.snapshot()) and b.session._profile.original_instances.size()==b.session._profile.original_items.size(),"original NPC add/remove retains validated v6 instance alignment")
  check(walked>300,"auto actually walks both directions")
  check((battles>0 and not b.session._profile.completed_battles.is_empty()) if encounters else battles==0,"real walking encounters obey general toggle")
  b.free()
 print("ORIGINAL ADULT QUEST: %d failures" % failures)
 quit(1 if failures else 0)
