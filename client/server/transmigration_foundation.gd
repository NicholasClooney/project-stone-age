extends RefCounted
## Reserved, independent four-spirit helper interfaces; no rebirth settlement.
const Registry = preload("res://scripts/quest_module_registry.gd")
const EVENTS := {39:"transmigration-earth",40:"transmigration-fire",41:"transmigration-wind",42:"transmigration-wind",46:"transmigration-water"}
var helpers := {}

func _init() -> void:
 for module in Registry.entries():
  if str(module.id) not in EVENTS.values() or module.get("enabled_events",[]).is_empty():continue
  var path := "res://server/"+str(module.id).replace("-","_")+"_helper.gd"
  if str(module.get("helper",""))!=path or not ResourceLoader.exists(path):continue
  helpers[str(module.id)] = load(path).new()

func stage_key(helper, backend) -> Array:
 var result:Array=[]
 for id in helpers:
  result.append(helpers[id].stage_key(helper,backend))
 return result

func steps(helper, backend, profile:Dictionary, quest:Dictionary) -> void:
 var id:String=EVENTS.get(int(quest.event),"")
 if helpers.has(id):helpers[id].steps(helper,backend,profile,quest)
 else:quest.blocked_reason="转生主线尚未开放"

func can_visit(helper, backend, event:int, step:Dictionary) -> bool:
 var id:String=EVENTS.get(event,"")
 return helpers.has(id) and helpers[id].can_visit(helper,backend,step)
