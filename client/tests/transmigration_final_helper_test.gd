extends "res://tests/quest_arrival_backend_test.gd"
const FinalHelper=preload("res://server/transmigration_final_helper.gd")
func run()->void:
 var b=fresh()
 var closed:Array=b.quest_catalog.enabled_events.duplicate()
 for event in [48,49,50,51,52]:
  if event not in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(event)
 b.quest_helper.places.set_quest_catalog(b.quest_catalog)
 for e in [39,40,42,46]:Rules.set_flag(b.session._profile,"ended",e,true)
 var actors:Array=b.quest_catalog.active_npcs().filter(func(n):return FinalHelper.owns(n))
 check(actors.size()==12,"exact original cave helper ownership excludes five prison services")
 for npc in actors:
  if str(npc.id)==FinalHelper.OUTER:continue
  var pos:=Vector2i(int(npc.cell[0])-1,int(npc.cell[1]))
  b.automation.position_changed(int(npc.map_id),pos)
  var before:Dictionary=b.session.snapshot()
  for mode in ["near","arrival"]:
   check(b.quest_helper.destination(b,npc,mode).is_empty(),"project close placement cannot authorize "+str(npc.id)+" "+mode)
   check(not b.handle({"type":"quest_visit","npc_id":npc.id,"mode":mode}).get("ok",false),"raw NPC project placement refused "+mode)
  check(b.session.snapshot()==before and b.automation.position_cell==pos,"rejected helper never changes profile or location")
  var old_step:Dictionary={"current":true,"actionable":true,"npc_id":npc.id,"source":{"branch_data":npc.get("branches",[])[0] if not npc.get("branches",[]).is_empty() else {}}}
  check(not FinalHelper.can_visit(b.quest_helper,b,old_step),"stale source step cannot authorize project placement")
  check(b.quest_helper.destination(b,npc,"fake").is_empty(),"unknown mode fails closed")
 b.quest_catalog.enabled_events=closed
 for npc in actors:
  for mode in ["near","arrival"]:check(b.quest_helper.destination(b,npc,mode).is_empty(),"closed source helper "+mode)
 b.free()
 print("TRANSMIGRATION FINAL HELPER: %d failures"%failures)
 quit(1 if failures else 0)
