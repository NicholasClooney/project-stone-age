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
 return id in [100,200]
