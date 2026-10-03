extends RefCounted
## Independent test oracle: historical activation plus explicitly registered
## module events. Never invokes the production catalog's activation function.
const BASELINE := [1,2,4,15,16,18,19,28,29,30,31,54]
static func matches(actual: Array) -> bool:
 for event in BASELINE:
  if event not in actual:return false
 var expected:Array=BASELINE.duplicate()
 var registry=JSON.parse_string(FileAccess.get_file_as_string("res://data/quest-modules.json"))
 if not registry is Dictionary or int(registry.get("version",0))!=1:return false
 for raw in registry.get("modules",[]):
  var module:Dictionary=raw
  if raw.has("configuration"):
   var path:="res://data/quests/"+str(raw.id)+".json"
   if str(raw.configuration)!="client/data/quests/"+str(raw.id)+".json" or not FileAccess.file_exists(path):return false
   var descriptor=JSON.parse_string(FileAccess.get_file_as_string(path))
   if not descriptor is Dictionary or descriptor.get("id","")!=raw.id:return false
   module=descriptor
  for value in module.get("enabled_events",[]):
   if not (value is int or value is float) or float(value)!=floor(float(value)) or int(value)<=0 or int(value)>=192:return false
   var event:=int(value)
   if event not in expected:expected.append(event)
 var observed:Array=[]
 for value in actual:
  var event:=int(value)
  if event in observed:return false
  observed.append(event)
 expected.sort();observed.sort()
 return observed==expected
