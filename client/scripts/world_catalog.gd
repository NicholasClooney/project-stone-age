extends RefCounted
## Map dimensions and portals generated from pinned original server resources.
const ROOT := "res://assets/legacy/"
var maps: Dictionary = {}
var portals: Dictionary = {}
var residents: Array = []
func _init() -> void:
 if not FileAccess.file_exists(ROOT+"world/manifest.json"): return
 var manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"world/manifest.json"))
 if not manifest is Dictionary: return
 maps = manifest.get("maps",{})
 residents = manifest.get("residents",[])
 for link in manifest.get("portals",[]):
  if bool(link.get("disabled",false)):continue
  var key := str(int(link.from_map))
  if not portals.has(key):portals[key] = {}
  portals[key][Vector2i(int(link.cell[0]),int(link.cell[1]))] = link
func info(id: int) -> Dictionary:
 return maps.get(str(id),{})
func file(id: int) -> String:
 if maps.has(str(id)):return ROOT+str(maps[str(id)].path)
 return ROOT+str({100:"wilderness.json",1000:"samgir.json",1002:"shop.json"}.get(id,""))
func links(id: int) -> Dictionary:
 return portals.get(str(id),{})
func field(id: int) -> bool:
 return id in [100,200] or str(info(id).get("kind","")) == "training"

# Village-local buildings belong to their nearest village through interior doors.
# Wilderness and dungeons remain global destinations.
func village_for(id: int) -> int:
 var declared:=int(info(id).get("village_id",-1))
 if declared>=0 and str(info(declared).get("kind",""))=="village":return declared
 if str(info(id).get("kind",""))=="village":return id
 if str(info(id).get("kind",""))!="interior" or id>=5000:return -1
 var pending: Array=[id]
 var seen: Dictionary={id:true}
 while not pending.is_empty():
  var current:=int(pending.pop_front())
  for link in links(current).values():
   var next:=int(link.to_map)
   var kind:=str(info(next).get("kind",""))
   if kind=="village":return next
   if kind=="interior" and next<5000 and not seen.has(next):
    seen[next]=true;pending.append(next)
 return -1

func destination_maps(current: int) -> Array:
 var village:=village_for(current)
 var result: Array=[]
 for key in maps:
  var id:=int(key)
  var owner:=village_for(id)
  if str(info(id).get("kind",""))=="interior" and owner>=0 and owner!=village:continue
  result.append(key)
 result.sort_custom(func(a,b):
  var local_a:=village>=0 and village_for(int(a))==village
  var local_b:=village>=0 and village_for(int(b))==village
  if local_a!=local_b:return local_a
  return int(a)<int(b))
 return result

# Settlement interiors are buildings; the three undersea maps and training
# caves remain regions. 2020 is the standalone original village dojo counter.
func is_building(id: int) -> bool:
 return str(info(id).get("kind",""))=="interior" and (village_for(id)>=0 or id==2020)

func navigation_maps() -> Array:
 var result: Array=[]
 for key in maps:
  if not is_building(int(key)):result.append(key)
 result.sort_custom(func(a,b):return int(a)<int(b))
 return result
