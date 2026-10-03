extends RefCounted
## Reviewed legacy cave geometry; this module never grants arrival evidence.
const RANGES=[[20101,20105,200],[11001,11006,100]]
static func cave(map_id:int)->Array:
 for entry in RANGES:
  if map_id>=int(entry[0]) and map_id<=int(entry[1]):return entry
 return []
static func owns(npc:Dictionary)->bool:return not cave(int(npc.get("map_id",-1))).is_empty()
static func entrance(helper,npc:Dictionary)->Dictionary:
 var entry:Array=cave(int(npc.get("map_id",-1)))
 if entry.is_empty():return {}
 for portal in helper.places.links(int(entry[2])).values():
  if int(portal.to_map)==int(entry[0]) and not bool(portal.get("disabled",false)) and not portal.has("gate_source"):
   var result:Dictionary=portal.duplicate(true);result.from_map=int(entry[2]);return result
 return {}
static func walk_destination(helper,backend,npc:Dictionary)->Dictionary:
 if not owns(npc):return {}
 # Internal geometry for actual server/test walking, never a travel receipt.
 return helper.geometric_destination(backend,npc,"near")
static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if mode not in ["near","arrival"]:return {}
 var current_map:int=backend.automation.position_map
 var current:Vector2i=backend.automation.position_cell
 var same_scope:bool=not cave(current_map).is_empty() and cave(current_map)==cave(int(npc.map_id))
 if same_scope and backend.quest_arrival.has_arrival(backend,current_map,current):
  if current_map!=int(npc.map_id):return {}
  var delta:=current-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
  if maxi(absi(delta.x),absi(delta.y))>2:return {}
  var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session._profile)
  if not backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty():return {}
  var geometric:Dictionary=walk_destination(helper,backend,npc)
  if geometric.is_empty() or not backend.quest_arrival.has_arrival(backend,current_map,Vector2i(int(geometric.cell[0]),int(geometric.cell[1]))):return {}
  return {"map_id":current_map,"cell":[current.x,current.y],"npc_id":str(npc.id)}
 var portal:Dictionary=entrance(helper,npc)
 if portal.is_empty():return {}
 var outside:Dictionary=helper.geometric_destination(backend,{"id":"","map_id":int(portal.from_map),"cell":portal.cell,"events":[]},"near")
 if not outside.is_empty():outside.npc_id="" # Arrival mode ends at the public entrance, without an unrelated NPC approach.
 return outside

