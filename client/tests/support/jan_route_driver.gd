extends RefCounted
## Only the public approach may be positioned as a fixture. Protected cave
## movement uses original report_position, keywords, portals and real combat.
const Travel=preload("res://tests/support/water_route_driver.gd")
const GATES=["genout/wpm_20604_11_53","genout/wpm_20605_51_4","genout/wpm_20606_9_23"]
static func enter(b)->bool:
 b.original_quests.pending={}
 for portal in b.quest_helper.places.links(200).values():
  if int(portal.to_map)!=20601 or portal.get("disabled",false) or portal.has("gate_source"):continue
  b.automation.position_changed(200,Vector2i(int(portal.cell[0]),int(portal.cell[1])))
  return b.handle({"type":"report_position","map_id":20601,"cell":portal.target}).get("ok",false)
 return false
static func approach(b,target:Dictionary)->bool:
 if target.is_empty():return false
 var goal:int=target.map_id
 if goal not in range(20601,20609):return b.handle({"type":"quest_visit","npc_id":target.id,"mode":"near"}).get("ok",false)
 var current:int=b.automation.position_map
 var valid:bool=current in range(20601,20609) and b.quest_arrival.has_arrival(b,current,b.automation.position_cell)
 if valid and Travel.walk_near(b,target,range(20601,20609)):return true
 # A different side of the guard requires another real entry/battle, never a
 # project placement at a keyword or the victory landing.
 if not valid or current>goal or current==20608 or (current==20607 and goal==20607):
  if not enter(b):return false
 for script in GATES:
  var gate:Dictionary=Travel.npc(b,script)
  if int(gate.map_id)<b.automation.position_map:continue
  if not Travel.walk_near(b,gate,range(20601,20608)):return false
  if str(target.id)==str(gate.id):return true
  if goal<=int(gate.map_id):return Travel.walk_near(b,target,range(20601,20608))
  var r:Dictionary=b.handle({"type":"quest_talk","npc_id":gate.id})
  if not b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":"submit","text":str(gate.branches[0].keyword)}).get("ok",false):return false
 if Travel.walk_near(b,target,[20607,20608]):return true
 if not Travel.guard(b,"200/sb_jan1.arg",[20607]):return false
 return Travel.walk_near(b,target,[20607,20608])
