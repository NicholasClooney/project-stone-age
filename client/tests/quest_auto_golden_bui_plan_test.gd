extends SceneTree
const Plan=preload("res://server/quest_auto_golden_bui_plan.gd")
const Sources=preload("res://server/quest_auto_golden_bui_sources.gd")
const Fixture=preload("res://tests/support/quest_auto_golden_bui_fixture.gd")
const Rules=preload("res://server/original_quests.gd")
var failures:=0
var assertions:=0
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 check(Plan.supports(2) and not Plan.supports(44),"job2 is event44, not job44")
 var table:=Sources.table()
 check(table.get("npcs",[]).size()==39 and table.get("portals",[]).size()==30,"Exact reviewed source cardinalities")
 for expected in table.npcs:
  var b=Fixture.new()
  var map_id:=int(expected.map_id)
  b.at(map_id,Vector2i(int(expected.cell[0]),int(expected.cell[1])+2))
  if map_id in [811,831,851]:
   var level:=75 if map_id==851 else (55 if int(expected.cell[0])==28 else 35)
   b.session._profile.player.level=level
   b.session._profile.original_items=[2757 if level==75 else (2756 if level==55 else 2755)]
  if str(expected.source_script)=="quiz/equiz_02":
   Rules.set_flag(b.session._profile,"now",44,true)
   b.session._profile.original_items=[2753]
  var before:Dictionary=b.session._profile.duplicate(true)
  var reply:=Plan.select(b,2)
  check(reply.status=="step","Every reviewed service/claim/exchange has a proposal: "+str(expected.id))
  if reply.status=="step":
   check(reply.step.npc_id==expected.id,"Proposal names the exact source NPC")
   check(not reply.step.has("token") and not reply.step.has("run_id") and not reply.step.has("Warp"),"No execution capability in proposal")
   if reply.step.action=="source_exchange":check(reply.step.source.branch_index==expected.branches[0].source_branch_index,"Source branch number survives runtime array index zero")
  check(b.session._profile==before,"Selection does not change profile")
  b.quest_arrival.valid=false
  check(Plan.select(b,2).status=="manual","Missing arrival/action proof refuses")
  b.quest_arrival.valid=true
  b.quest_catalog.npcs.append(expected.duplicate(true))
  check(Plan.select(b,2).status=="manual","Duplicate resident identity refuses")
  b.quest_catalog.npcs.pop_back()
  for actor in b.quest_catalog.npcs:
   if actor.id==expected.id:actor.cell[0]=float(actor.cell[0])+0.25
  check(Plan.select(b,2).status=="manual","Fractional/moved source NPC refuses")
 for level in [29,35,55,75]:
  var b=Fixture.new();b.session._profile.player.level=level;b.session._profile.original_items=[]
  b.at(851 if level==75 else 811,Vector2i(29,22))
  check(Plan.select(b,2).status=="manual","No admission purchase/fallback")
 var b=Fixture.new()
 b.session._profile.original_items=[]
 check(Plan.select(b,2).status=="manual","Quiz requires 2752")
 b.at(802,Vector2i(29,21))
 check(Plan.select(b,2).status=="step","Original janken allows no 2751")
 b.at(810,Vector2i(28,18));Rules.set_flag(b.session._profile,"now",44,true)
 check(Plan.select(b,2).status=="manual","Lost membership never automatically cleans/reclaims")
 b.session._profile.original_items=[2753]
 b.quest_catalog.reward_pets["14"].template_id=13
 check(Plan.select(b,2).status=="manual","Changed pet14 reward refuses")
 b.quest_catalog.reward_pets["14"]=table.reward_pet.duplicate(true)
 for actor in b.quest_catalog.npcs:
  if actor.id=="quiz/equiz_02@810:28:16":actor.branches[0].actions.GetPet="15"
 check(Plan.select(b,2).status=="manual","Extra/changed original actions refuse")
 var full=Fixture.new();full.at(810,Vector2i(29,18))
 full.session._profile.original_items=Array(range(15))
 check(Plan.select(full,2).status=="manual","Full bag keeps membership claim manual")
 full.session._profile.original_items=[2753];Rules.set_flag(full.session._profile,"now",44,true)
 full.session._profile.pets=Array(range(Rules.Session.PET_CAPACITY))
 check(Plan.select(full,2).status=="manual","Full pet capacity keeps exchange manual")
 var index_zero=Fixture.new();index_zero.at(810,Vector2i(29,18))
 for actor in index_zero.quest_catalog.npcs:
  if actor.id=="quiz/equiz_01@810:29:16":actor.branches[0].source_branch_index=0
 check(Plan.select(index_zero,2).status=="manual","Runtime array0 cannot replace original branch3")
 Rules.set_flag(b.session._profile,"ended",44,true)
 check(Plan.select(b,2).status=="done","END44 ends without another reward")
 print("golden bui pure plan: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
