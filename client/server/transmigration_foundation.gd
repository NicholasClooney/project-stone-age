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
  var key:Array=helpers[id].stage_key(helper,backend)
  if not key.is_empty():result.append([id,key])
 return result

func steps(helper, backend, profile:Dictionary, quest:Dictionary) -> void:
 var id:String=EVENTS.get(int(quest.event),"")
 if helpers.has(id):helpers[id].steps(helper,backend,profile,quest)
 else:quest.blocked_reason="转生主线尚未开放"

func can_visit(helper, backend, event:int, step:Dictionary) -> bool:
 var id:String=EVENTS.get(event,"")
 return helpers.has(id) and helpers[id].can_visit(helper,backend,step)

func owns(npc:Dictionary) -> bool:
 if npc.get("events",[]).any(func(event):return int(event) in EVENTS):return true
 for module in helpers.values():
  if module.owns(npc):return true
 return false

func destination(helper, backend, npc:Dictionary, mode:String) -> Dictionary:
 if mode not in ["near","arrival"]:return {}
 # Rebuild eligibility from server steps even for raw npc_id requests. A
 # caller-supplied old step, map or cell cannot grant navigation authority.
 for quest in helper.snapshot(backend).quests:
  var event:=int(quest.event)
  if event not in backend.quest_catalog.enabled_events:continue
  var id:String=EVENTS.get(event,"")
  if not helpers.has(id) or not helpers[id].owns(npc):continue
  for step in quest.steps:
   if str(step.get("npc_id",""))!=str(npc.get("id","")):continue
   if str(npc.get("id","")).is_empty() and (int(step.get("map_id",-1))!=int(npc.get("map_id",-2)) or step.get("cell",[])!=npc.get("cell",[])):continue
   if not helpers[id].can_visit(helper,backend,step):continue
   var target:Dictionary=helpers[id].destination(helper,backend,npc,mode)
   if not target.is_empty():return target
 return {}
