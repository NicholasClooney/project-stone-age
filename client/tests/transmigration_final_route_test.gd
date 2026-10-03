extends "res://tests/quest_arrival_transmigration_test.gd"
const FinalHelper=preload("res://server/transmigration_final_helper.gd")
# The inherited two-battle/savefail/LAN/restart route runs against the private
# product world and imported NPCs. No portal or source catalog is installed.
func final_backend():
 var b=fresh()
 var ids:Array=[]
 for npc in b.quest_catalog.npcs:
  if npc.get("kind","")=="original_transmigration" or FinalHelper.owns(npc):ids.append(str(npc.id))
 check(ids.has(FinalHelper.KING),"private importer contains actual king identity")
 var closed_npc:Dictionary=b.quest_catalog.npcs.filter(func(n):return str(n.id)==FinalHelper.KING)[0]
 for mode in ["near","arrival"]:
  check(b.quest_helper.destination(b,closed_npc,mode).is_empty(),"production closed king helper "+mode)
 for event in [48,49,50,51,52]:
  if event not in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(event)
 b.quest_helper.places.set_quest_catalog(b.quest_catalog)
 for e in [39,40,42,46]:Rules.set_flag(b.session._profile,"ended",e,true)
 var outer:Dictionary=FinalRoute.npc(b,"genout/wpm_300_103_228")
 for mode in ["near","arrival"]:
  check(b.quest_helper.destination(b,outer,mode)=={"map_id":300,"cell":[102,228],"npc_id":""},"public outside-only helper "+mode)
  check(not b.handle({"type":"quest_visit","npc_id":FinalHelper.KING,"mode":mode}).get("ok",false),"distant king raw helper refused "+mode)
 check(not b.handle({"type":"quest_visit","quest_id":48,"step_id":"777/ten.arg","mode":"arrival"}).get("ok",false),"unregistered historical event is not a forged guide step")
 return b
func near_helpers(b,npc:Dictionary)->void:
 var before:Vector2i=b.automation.position_cell
 var map_id:int=b.automation.position_map
 for mode in ["near","arrival"]:
  check(b.quest_helper.destination(b,npc,mode)=={"map_id":map_id,"cell":[before.x,before.y],"npc_id":str(npc.id)},"legitimate helper stays at current cell "+mode+" "+str(npc.id))
  check(b.handle({"type":"quest_visit","npc_id":npc.id,"mode":mode}).get("ok",false) and b.automation.position_cell==before,"raw visit is authoritative stationary "+mode)
 var fake:Dictionary=npc.duplicate(true);fake.source_create_index=999
 check(b.quest_helper.destination(b,fake,"near").is_empty(),"unreviewed create identity fails closed")
func actual_guard(b,source:String,stage:String)->void:
 near_helpers(b,FinalRoute.npc(b,source))
 super.actual_guard(b,source,stage)
func lan_last_gate(b)->void:
 near_helpers(b,FinalRoute.npc(b,"genout/wpm_32021_31_51"))
 await super.lan_last_gate(b)
 check(FinalRoute.near(b,"777/ten.arg",[32021]),"product world reaches original king near cell")
 var king:Dictionary=FinalRoute.npc(b,"777/ten.arg")
 var proof:Dictionary=b.quest_arrival.action_context(b,king,{},"SERVICE")
 near_helpers(b,king)
 check(not proof.is_empty() and b.quest_arrival.check_action_context(b,proof).is_empty(),"helper projections and raw visits preserve previously issued service receipt")
