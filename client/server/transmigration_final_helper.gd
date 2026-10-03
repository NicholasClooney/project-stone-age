extends RefCounted
## Project navigation only. Never creates, updates or consumes arrival proofs.
const Rules=preload("res://server/original_quests.gd")
const Interaction=preload("res://scripts/npc_interaction.gd")
const OUTER="genout/wpm_300_103_228@300:103:228"
const ROOT="genout/wpm_300_108_225@300:108:225"
const KING="777/ten.arg@32021:31:28"
const GATES=[OUTER,ROOT,"genout/wpm_32016_31_39@32016:31:39","genout/wpm_32021_31_51@32021:31:51"]
static func owns(npc:Dictionary)->bool:
 return int(npc.get("map_id",-1)) in range(32001,32022) or str(npc.get("id","")) in GATES
static func trusted(backend,npc:Dictionary)->Dictionary:
 var actual:Dictionary=backend.quest_catalog.active_npc(str(npc.get("id","")))
 if actual.is_empty() or not owns(actual):return {}
 for key in ["id","source_script","source_create","source_create_index","map_id","cell","graphic","facing","kind","handler","service_id"]:
  if actual.get(key)!=npc.get(key):return {}
 return actual
static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if mode not in ["near","arrival"] or not owns(npc):return {}
 var actual:Dictionary=trusted(backend,npc)
 if actual.is_empty():return {}
 var map_id:int=int(actual.map_id)
 var current:Vector2i=backend.automation.position_cell
 if str(actual.id)==OUTER:
  # Original public side immediately before the first same-map gate. No
  # target NPC auto-interaction and no approach proof is granted by this move.
  var point:=Vector2i(102,228)
  var map_file:=preload("res://scripts/map_file.gd")
  if not helper.maps.has(300):helper.maps[300]=map_file.load_map(helper.places.file(300))
  if not helper.safe(helper.maps[300],point,{},helper.places.links(300)):return {}
  return {"map_id":300,"cell":[point.x,point.y],"npc_id":""}
 if backend.automation.position_map!=map_id:return {}
 if current-Vector2i(int(actual.cell[0]),int(actual.cell[1])) not in Interaction.offsets():return {}
 if map_id in range(32001,32022) and not backend.quest_arrival.has_arrival(backend,map_id,current):return {}
 if not backend.original_quests.allowed(backend,actual):return {}
 var branch:Dictionary={}
 if str(actual.id)==KING:
  if str(actual.get("kind",""))!="original_transmigration" or str(actual.get("handler",""))!="Transmigration" or str(actual.get("service_id",""))!="777/ten.arg":return {}
  if not Rules.matches(backend.session._profile,"LV>79&ENDEV=39&ENDEV=40&ENDEV=42&ENDEV=46"):return {}
 else:
  branch=backend.original_quests.branch_for(actual,backend.session._profile)
  if branch.is_empty():return {}
 if not backend.quest_arrival.check_action(backend,actual,branch,"talk").is_empty():return {}
 # Both modes preserve the legitimate near position. In particular, a
 # service preview's frozen proof cannot be invalidated by helper rendering.
 return {"map_id":map_id,"cell":[current.x,current.y],"npc_id":str(actual.id)}
static func can_visit(helper,backend,step:Dictionary)->bool:
 if not bool(step.get("current",false)) or not bool(step.get("actionable",false)):return false
 var npc:Dictionary=backend.quest_catalog.active_npc(str(step.get("npc_id","")))
 if npc.is_empty():return false
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session._profile)
 if str(npc.id)!=KING and (branch.is_empty() or branch!=step.get("source",{}).get("branch_data",{})):return false
 return not destination(helper,backend,npc,"near").is_empty()
