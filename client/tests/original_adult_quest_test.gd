extends "res://tests/original_herb_quest_test.gd"
const JUDGE="jaruga/event/event04_1"
const MESSENGER="jaruga/event/event04_2"
func adult_row(b) -> Dictionary:
 for q in b.quest_helper.snapshot(b).quests:
  if int(q.event)==4:return q
 return {}
func clear_bag(b) -> void:
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
func tick(b) -> void:
 b.automation.tick(1.0)
 b.quest_auto.tick(b,0.21)
 if b.quest_auto.phase=="landing":b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"client":"test"})
func run() -> void:
 var b=Backend.new()
 clear_bag(b)
 check(adult_row(b).steps.size()==3 and not adult_row(b).repeatable,"three original adult stages, no CLEAN")
 check(b.quest_helper.places.field(10204),"original channel supports walking encounters")
 b.automation.position_changed(10202,Vector2i(31,13),true)
 check(b.quest_helper.places.links(10202)[Vector2i(31,13)].requires_level==30,"source-backed original entrance level metadata")
 check(not b.handle({"type":"check_passage","from_map":10202,"to_map":10204}).ok,"original entrance rejects low level")
 check(not b.handle({"type":"report_position","map_id":10204,"cell":[2,6],"client":"test"}).ok,"forged low-level walk arrival rejected")
 check(b.handle({"type":"quest_visit","npc_id":JUDGE,"mode":"near"}).ok,"explicit helper bypasses entrance")
 check(trade(b,JUDGE).ok and Rules.flag(b.session._profile,"now",4),"level1 follows original LV>0 REQUEST")
 b.session._profile.inventory.potion=1
 check(not trade(b,MESSENGER).ok and b.session._profile.original_items.is_empty(),"fifteen jade require fifteen independent empty slots")
 clear_bag(b)
 check(trade(b,MESSENGER).ok and b.session._profile.original_items.count(2417)==15,"messenger grants actual fifteen jade")
 check(trade(b,JUDGE).ok and b.session._profile.original_items==[2418] and Rules.flag(b.session._profile,"ended",4),"judge consumes fifteen and grants exactly one helmet END4")
 var before:Dictionary=b.session.snapshot()
 trade(b,JUDGE)
 check(b.session.snapshot()==before,"ended original ritual cannot repeat reward")
 b.free()
 b=Backend.new();clear_bag(b)
 for id in [JUDGE,MESSENGER]:
  var npc:Dictionary=b.original_quests.npc_by_id(id)
  check(npc.map_id==10204 and FileAccess.file_exists("res://assets/legacy/"+str(npc.path)),"original NPC art and location "+id)
  var near:Dictionary=b.quest_helper.destination(b,npc,"near")
  var arrival:Dictionary=b.quest_helper.destination(b,npc,"arrival")
  b.automation.position_changed(10204,Vector2i(arrival.cell[0],arrival.cell[1]),true)
  var path:Array=b.quest_auto.walk_path(b,Vector2i(near.cell[0],near.cell[1]))
  check(arrival.cell==near.cell or not path.is_empty(),"actual walkable component reaches "+id)
 b.free()
 for encounters in [false,true]:
  b=Backend.new();clear_bag(b)
  # Strong ordinary character fixture; combat, policy, enemies and settlement stay real.
  b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
  preload("res://server/progression.gd").refresh(b.session._profile.player)
  b.session._profile.player.hp=b.session._profile.player.max_hp
  b.handle({"type":"no_random_encounters","enabled":not encounters})
  b.encounter_rng.seed=7
  check(b.handle({"type":"quest_auto_start","quest_id":1,"client":"test"}).ok,"adult auto starts")
  var walked:=0
  var battles:=0
  for i in range(6000):
   if not b.quest_auto.running:break
   var old:Vector2i=b.automation.position_cell
   var old_phase:String=b.quest_auto.phase
   tick(b)
   if old_phase=="walking" and old!=b.automation.position_cell:
    walked+=1
    check(absi(old.x-b.automation.position_cell.x)+absi(old.y-b.automation.position_cell.y)==1,"one real source-channel step")
   if b.quest_auto.phase=="battle" and old_phase!="battle":battles+=1
  check(not b.quest_auto.running and Rules.flag(b.session._profile,"ended",4) and b.session._profile.original_items==[2418],"auto completes original three exchanges "+str(encounters)+" "+b.quest_auto.message)
  check(walked>300,"auto actually walks both directions")
  check((battles>0 and not b.session._profile.completed_battles.is_empty()) if encounters else battles==0,"real walking encounters obey general toggle")
  b.free()
 print("ORIGINAL ADULT QUEST: %d failures" % failures)
 quit(1 if failures else 0)
