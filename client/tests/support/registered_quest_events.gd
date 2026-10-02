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
 for module in registry.get("modules",[]):
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
