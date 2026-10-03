extends RefCounted
## Trusted repository descriptors, separate from player saves and commands.
static func entries() -> Array:
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://data/quest-modules.json"))
 if not data is Dictionary or int(data.get("version",0))!=1:return []
 var result:Array=[]
 var seen:Dictionary={}
 for raw in data.get("modules",[]):
  if not raw is Dictionary:return []
  var entry:Dictionary=raw
  var id:=str(raw.get("id",""))
  if id.is_empty() or seen.has(id):return []
  if raw.has("configuration"):
   var expected:="client/data/quests/"+id+".json"
   if raw.size()!=2 or str(raw.configuration)!=expected or not id in ["transmigration-earth","transmigration-fire","transmigration-wind","transmigration-water"]:return []
   var path:="res://data/quests/"+id+".json"
   if not FileAccess.file_exists(path):return []
   var configuration=JSON.parse_string(FileAccess.get_file_as_string(path))
   if not configuration is Dictionary or str(configuration.get("id",""))!=id:return []
   entry=configuration
  seen[id]=true
  result.append(entry)
 return result
