extends RefCounted
## Shared safe landing lookup; no independent navigation UI.
var world: Node
func configure(owner: Node) -> void:world=owner

func safe_destination(map_id: int, target: Vector2i) -> Vector2i:
 var filename: String=world.world_catalog.file(map_id)
 if not world.world_catalog.maps.has(str(map_id)) or not FileAccess.file_exists(filename):return Vector2i(-1,-1)
 var data: Variant=world.data if map_id==int(world.data.map_id) else JSON.parse_string(FileAccess.get_file_as_string(filename))
 if not data is Dictionary:return Vector2i(-1,-1)
 var occupied: Dictionary={}
 for resident in world.world_catalog.residents:
  if int(resident.map_id)==map_id:occupied[Vector2i(resident.cell[0],resident.cell[1])]=true
 if map_id==1000 and FileAccess.file_exists("res://assets/legacy/samgir-npc.json"):
  var resident: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/samgir-npc.json"))
  occupied[Vector2i(resident.cell[0],resident.cell[1])]=true
 if map_id==1002 and not world.mvp_manifest.get("merchant",{}).is_empty():
  var cell: Array=world.mvp_manifest.merchant.cell
  occupied[Vector2i(cell[0],cell[1])]=true
 if map_id==int(world.data.map_id):occupied[world.npc_cell]=true
 var links: Dictionary=world.world_catalog.links(map_id)
 var bounds:=Rect2i(0,0,int(data.width),int(data.height))
 for radius in range(33):
  for y in range(-radius,radius+1):
   for x in range(-radius,radius+1):
    if maxi(absi(x),absi(y))!=radius:continue
    var point:=target+Vector2i(x,y)
    if bounds.has_point(point) and int(data.blocked[point.y*int(data.width)+point.x])==0 and not occupied.has(point) and not links.has(point):return point
 return Vector2i(-1,-1)

