extends RefCounted
## Integration fixture uses real passage, every original maze step, actual
## guard commands and saved original Warp. It never writes an arrival proof.
const Clock=preload("res://server/original_world_clock.gd")
const Route=preload("res://tests/support/original_route_driver.gd")
static func guard(b,map_id:int=41)->Dictionary:
 var old:Callable=Clock.clock
 Clock.clock=func():return Clock.ERA+int(ceil(float(400 if map_id==42 else 200)*5400.0/1024.0))
 b.automation.position_changed(400,Vector2i(87,101) if map_id==42 else Vector2i(97,119))
 var reply:Dictionary=b.handle({"type":"check_passage","from_map":400,"to_map":map_id})
 if reply.ok:reply=b.handle({"type":"report_position","map_id":map_id,"cell":[11,8]})
 if reply.ok:reply=Route.walk(b,map_id,Vector2i(34,42),[map_id])
 Clock.clock=old
 return reply
static func sage(b)->Dictionary:
 return Route.walk(b,41,Vector2i(34,27),[41])
static func win(b,map_id:int=41)->Dictionary:
 var reply:=guard(b,map_id)
 if not reply.ok:
  push_error("Dream route stage refused: "+str(reply));return reply
 reply=b.handle({"type":"quest_talk","npc_id":"400/sb_muge1.arg@%d:34:41"%map_id})
 if not reply.ok:
  push_error("Dream route stage refused: "+str(reply));return reply
 reply=b.handle({"type":"quest_choose","token":reply.get("dialogue",{}).get("token",""),"choice":"yes"})
 if not reply.ok:
  push_error("Dream route stage refused: "+str(reply));return reply
 for turn in range(100):
  var state:Dictionary=b.battle.snapshot()
  if not state.active:break
  var target:=0
  for i in range(state.enemies.size()):
   if int(state.enemies[i].hp)>0:target=i;break
  reply=b.handle({"type":"battle_command","action":"attack","target":target})
  if not reply.ok:
   push_error("Dream route stage refused: "+str(reply));return reply
 reply=b.handle({"type":"battle_close"})
 if not reply.ok:return reply
 if str(reply.get("outcome",""))!="win":return {"ok":false,"reason":"guard did not win: "+str(reply)}
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 return sage(b)
