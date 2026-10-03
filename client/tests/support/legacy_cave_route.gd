extends RefCounted
const Geometry=preload("res://server/legacy_cave_helper.gd")
const Driver=preload("res://tests/support/original_route_driver.gd")
static func approach(b,npc:Dictionary)->Dictionary:
 var entry:Array=Geometry.cave(int(npc.map_id))
 if entry.is_empty():return {"ok":false,"reason":"unreviewed test route"}
 var map_id:int=b.automation.position_map
 if Geometry.cave(map_id)!=entry or not b.quest_arrival.has_arrival(b,map_id,b.automation.position_cell):
  var portal:Dictionary=Geometry.entrance(b.quest_helper,npc)
  if portal.is_empty():return {"ok":false,"reason":"missing original entrance"}
  var visit:Dictionary=b.handle({"type":"quest_visit","npc_id":str(npc.id),"mode":"near"})
  if not visit.ok:return visit
  var point:=Vector2i(int(portal.cell[0]),int(portal.cell[1]))
  var walked:Dictionary=Driver.walk(b,int(portal.from_map),point,[int(portal.from_map)])
  if not walked.ok:return walked
  var crossed:Dictionary=b.handle({"type":"report_position","map_id":portal.to_map,"cell":portal.target})
  if not crossed.ok:return crossed
 var maps:Array=range(int(entry[0]),int(entry[1])+1)
 for delta in preload("res://scripts/npc_interaction.gd").offsets():
  var goal:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))+delta
  if b.automation.position_map==int(npc.map_id) and b.automation.position_cell==goal:return {"ok":true}
  if not Driver.path(b,int(npc.map_id),goal,maps).is_empty():return Driver.walk(b,int(npc.map_id),goal,maps)
 return {"ok":false,"reason":"no real original path"}
