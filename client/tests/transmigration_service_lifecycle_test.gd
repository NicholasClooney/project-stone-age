extends "res://tests/transmigration_service_test.gd"
var touched:Array=[]
var visual_id:=""
func _init()->void:discard_confirmation_ack=true
func prepare_round_state(b)->void:
 # Previous-round personal state is the fixture. Reset occurs only via the
 # actual current king transaction, not by calling its reset method ourselves.
 for n in b.quest_catalog.npcs:
  if n.get("events",[]).any(func(e):return int(e) in [39,40,42,46,27]) and not str(n.id) in touched:
   b.original_quests.npc_state.records[str(n.id)]={"dead_until":9999999999,"counter":2,"map_id":int(n.map_id),"cell":n.cell.duplicate()}
   touched.append(str(n.id))
  if str(n.get("kind",""))=="timeman" and visual_id.is_empty():
   visual_id=str(n.id);b.original_quests.npc_state.records[visual_id]={"time_mode":"changed"}
 b.quest_helper.cached_key="previous-round-cache"
 b.quest_helper.cached_snapshot={"round_marker":"stale"}
func verify_round_state(b)->void:
 check(not touched.is_empty(),"actual four-chain/bonus NPC records prepared")
 for id in touched:
  var entry:Dictionary=b.original_quests.npc_state.records.get(id,{})
  check(not entry.has("dead_until") and not entry.has("counter"),"saved rebirth resets personal cooldown and move sequence: "+id)
 if not visual_id.is_empty():check(b.original_quests.npc_state.records.get(visual_id,{}).has("time_mode"),"timeman visual state remains independently managed")
 var snapshot:Dictionary=b.quest_helper.snapshot(b)
 check(not snapshot.has("round_marker") and b.quest_helper.cached_key!="previous-round-cache","helper cache rebuilt after commit")
 for event in [39,40,42,46,27]:
  var jobs:Array=snapshot.quests.filter(func(q):return int(q.event)==event)
  check(not jobs.is_empty() and jobs[0].status=="未开始" and not Rules.flag(b.session._profile,"ended",event),"next round entry projects uncompleted chain: "+str(event))
 # New level1 must still pass each original level/adult gate again. These
 # checks prove reset/entry eligibility, not another complete four-chain run.
 for script in ["genout/wpm_200_359_671","genout/wpm_100_278_325","genout/wpm_200_73_696"]:
  var n:Dictionary=FinalRoute.npc(b,script)
  check(not n.is_empty() and b.original_quests.branch_for(n,b.session.snapshot()).is_empty(),"next round retains original level/adult entry requirements: "+script)
