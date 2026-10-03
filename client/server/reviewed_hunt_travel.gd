extends RefCounted
## Exact, source-reviewed capture destinations. No generic movement exemption.
const Encyclopedia=preload("res://scripts/pet_encyclopedia.gd")
const MapFile=preload("res://scripts/map_file.gd")
const POLICY="项目便利，绕过原版门；抓宠直达不授予任务领奖资格。"
const PATH="res://data/reviewed-hunt-travel.json"
static var reviewed:Array=[]
var book
static func targets()->Array:
 if reviewed.is_empty():
  var data=JSON.parse_string(FileAccess.get_file_as_string(PATH))
  if data is Dictionary:reviewed=data.get("targets",[])
 return reviewed
static func reviewed_target(map_id:int,area_id:int,template_id:int)->Dictionary:
 for row in targets():
  if int(row.map_id)==map_id and int(row.area_id)==area_id and int(row.template_id)==template_id:return row
 return {}
func resolve(backend,command:Dictionary)->Dictionary:
 for key in ["map_id","area_id","template_id"]:
  if not backend.session._integer(command.get(key),1,2147483647):return {}
 var row:=reviewed_target(int(command.map_id),int(command.area_id),int(command.template_id))
 if row.is_empty():return {}
 if book==null:
  var spots:Dictionary=Encyclopedia.read_json(Encyclopedia.SPOTS_PATH)
  book=Encyclopedia.new(backend.encounter_catalog.data,Encyclopedia.read_json(Encyclopedia.FAMILIES_PATH),Encyclopedia.read_json(Encyclopedia.POTENTIAL_PATH),spots.get("spots",[]),backend.session.world_catalog.maps,Encyclopedia.read_json(Encyclopedia.PETS_PATH))
 var entry:Dictionary=book.entry_for(int(row.template_id))
 for place in entry.get("locations",[]):
  if int(place.map_id)!=int(row.map_id) or int(place.area_id)!=int(row.area_id) or int(place.template_id)!=int(row.template_id):continue
  var plan:=Encyclopedia.catch_plan(place)
  if plan.has("error") or not bool(place.capturable):continue
  var cell:=Vector2i(int(row.cell[0]),int(row.cell[1]))
  if plan.cell!=cell:continue
  var info:Dictionary=backend.session.world_catalog.info(int(row.map_id))
  if info.is_empty():return {}
  var map:Dictionary=MapFile.load_map(backend.session.world_catalog.file(int(row.map_id)))
  if map.is_empty() or cell.x<0 or cell.y<0 or cell.x>=int(map.width) or cell.y>=int(map.height):return {}
  if int(map.blocked[cell.y*int(map.width)+cell.x])!=0 or backend.session.world_catalog.links(int(row.map_id)).has(cell):return {}
  for npc in backend.session.world_catalog.residents:
   if int(npc.map_id)==int(row.map_id) and Vector2i(int(npc.cell[0]),int(npc.cell[1]))==cell:return {}
  if int(backend.encounter_catalog.area_at(int(row.map_id),cell).get("id",-1))!=int(row.area_id):return {}
  return plan
 return {}
