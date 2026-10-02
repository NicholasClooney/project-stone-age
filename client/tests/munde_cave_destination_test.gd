extends "res://tests/munde_cave_navigation_test.gd"
func run()->void:
 var b=setup()
 for position in [Vector2i(18,41),Vector2i(23,35)]:
  b.automation.position_changed(11107,position)
  var own:int=Munde.region_at(b.quest_helper,b,position)
  print("PLAYER ",position," REGION ",own)
  var targets:Array=guards.duplicate();targets.append(b.original_quests.npc_by_id(CHIEF))
  for npc in targets:
   var neighbours:Array=[]
   for offset in preload("res://scripts/npc_interaction.gd").offsets():
    var point:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))+offset
    neighbours.append([point,Munde.region_data(b.quest_helper,b).get("labels",{}).get(point,-1)])
   print("NPC ",npc.id," NEIGHBOURS ",neighbours)
   for mode in ["near","arrival"]:
    var destination:Dictionary=b.quest_helper.destination(b,npc,mode)
    var region:=-1
    if not destination.is_empty():region=Munde.region_at(b.quest_helper,b,Vector2i(int(destination.cell[0]),int(destination.cell[1])))
    print("MODE ",mode," TARGET ",destination," REGION ",region)
    check(destination.is_empty() or region==own,"actual permitted destination remains in player's original component")
    var reply:Dictionary=b.handle({"type":"quest_visit","npc_id":npc.id,"mode":mode})
    check(bool(reply.ok)==not destination.is_empty(),"backend raw NPC command follows component-filtered destination")
    if reply.ok:check(Munde.region_at(b.quest_helper,b,b.automation.position_cell)==own,"backend actually lands in unchanged player component")
 Munde.region_cache.clear();b.quest_helper.maps[11107]={}
 b.quest_helper.cached_key=""
 for mode in ["near","arrival"]:
  check(b.quest_helper.destination(b,b.original_quests.npc_by_id(CHIEF),mode).is_empty(),"missing map rejects actual destination")
 for kind in ["now"]:
  for event in [9,10,11]:Rules.set_flag(b.session._profile,kind,event,true)
 b.quest_helper.cached_key=""
 for quest in b.quest_helper.snapshot(b).quests:
  if int(quest.event)!=9:continue
  for step in quest.steps:
   if str(step.id)=="munde9:battle":check(not step.done,"missing victory component never treats -1==-1 as guard passed")
   if str(step.id)=="munde12:stones":check(not step.current and not step.get("navigation_allowed",false),"missing map keeps chief stage locked")
 Munde.region_cache.clear()
 b.free();print("MUNDE CAVE DESTINATION: %d failures"%failures);quit(1 if failures else 0)
