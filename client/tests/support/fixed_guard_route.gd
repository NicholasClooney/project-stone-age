extends RefCounted
## Public departure is fixture setup; protected travel is always real commands.
## No arrival scope, epoch, mark or receipt is assigned by this driver.
const Walk=preload("res://tests/support/water_route_driver.gd")
static func approach(b,npc:Dictionary)->Dictionary:
 if int(npc.map_id) in range(20601,20609):
  return {"ok":preload("res://tests/support/jan_route_driver.gd").approach(b,npc),"reason":"Jan original route"}
 if int(npc.map_id) in range(11101,11108):
  var gate:Dictionary=b.original_quests.npc_by_id("genout/wpm_100_443_127@100:443:127")
  if gate.is_empty():return {"ok":false,"reason":"missing actual public Munde keyword gate"}
  b.original_quests.pending={}
  var placed:Dictionary=b.handle({"type":"quest_visit","npc_id":gate.id,"mode":"near"})
  if not placed.ok:return placed
  var talked:Dictionary=b.handle({"type":"quest_talk","npc_id":gate.id})
  if not talked.ok:return talked
  var entered:Dictionary=b.handle({"type":"quest_choose","token":talked.get("dialogue",{}).get("token",""),"choice":"submit","text":str(gate.branches[0].keyword)})
  if not entered.ok:return entered
  return {"ok":Walk.walk_near(b,npc,range(11101,11108)),"reason":"Munde original seven-map route"}
 return {"ok":false,"reason":"unreviewed fixed guard test route"}
