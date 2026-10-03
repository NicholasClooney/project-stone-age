extends RefCounted
## Read-only original quest data; public activation is tracked separately.
const ROOT := "res://assets/legacy/"
var items: Dictionary = {}
var npcs: Array = []
var service_npcs: Array = []
var jobs: Array = []
var reward_pets: Dictionary = {}
var enabled_events: Array = []
## Trusted per-character runtime projection; never loaded from the save.
var npc_overrides: Dictionary = {}
func _init() -> void:
 var config = JSON.parse_string(FileAccess.get_file_as_string("res://data/early-quests.json"))
 if config is Dictionary:
  for event in config.get("enabled_events", []):
   if (event is int or event is float) and float(event) == floor(float(event)) and int(event) > 0 and int(event) < 192:
    enabled_events.append(int(event))
 for module in preload("res://scripts/quest_module_registry.gd").entries():
  for event in module.get("enabled_events",[]):
   if (event is int or event is float) and float(event)==floor(float(event)) and int(event)>0 and int(event)<192 and not int(event) in enabled_events:
    enabled_events.append(int(event))
 if not FileAccess.file_exists(ROOT + "quests/catalog.json"): return
 var data = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "quests/catalog.json"))
 if not data is Dictionary or int(data.get("version", 0)) != 1: return
 items = data.get("items", {})
 npcs = data.get("npcs", [])
 service_npcs = data.get("service_npcs", []).filter(func(npc):return str(npc.get("handler",""))=="Charm" and str(npc.get("id","")) in ["original/charm/1005","original/charm/2005"])
 jobs = data.get("jobs", [])
 reward_pets = data.get("reward_pets", {})
func active_npcs() -> Array:
 var result: Array = []
 for npc in npcs:
  var active: Dictionary=_project_active_npc(npc)
  if not active.is_empty():result.append(active)
 result.append_array(service_npcs.duplicate(true))
 return result

## Same ordered projection as active_npcs(); no cross-character cache and no
## mutable catalog record escapes. A lookup copies only its matching record.
func active_npc(id: String) -> Dictionary:
 for npc in npcs:
  if str(npc.id)!=id:continue
  var active: Dictionary=_project_active_npc(npc)
  if not active.is_empty():return active
 for npc in service_npcs:
  if str(npc.id)==id:return npc.duplicate(true)
 return {}

## Filter on the effective personal map before projecting/copying records.
## Preserve source order, duplicates, birth/hidden rules and service semantics.
func active_npcs_on_map(map_id: int) -> Array:
 var result: Array=[]
 for npc in npcs:
  var override:Dictionary=npc_overrides.get(str(npc.id),{})
  if int(override.get("map_id",npc.map_id))!=map_id:continue
  var active:Dictionary=_project_active_npc(npc)
  if not active.is_empty():result.append(active)
 for npc in service_npcs:
  if int(npc.map_id)==map_id:result.append(npc.duplicate(true))
 return result

func _project_active_npc(npc: Dictionary) -> Dictionary:
 if not _enabled(npc.get("events", [])): return {}
 var override:Dictionary=npc_overrides.get(str(npc.id),{})
 if bool(override.get("hidden",false)):return {}
 if npc.has("source_spawn") and not override.has("map_id"):return {}
 var active: Dictionary = npc.duplicate(true)
 if override.has("map_id"):
  active.map_id=int(override.map_id);active.cell=override.cell.duplicate()
 if active.get("handler","")=="TimeMan":
  var visual:Dictionary=active.get("time_visuals",{}).get(str(override.get("time_mode","main")),{})
  for field in ["graphic","text","path","offset","bitmap_id","source_pose"]:
   if visual.has(field):active[field]=visual[field]
  return active
 if str(active.get("kind","")) in ["golden_bui_quiz","golden_bui_janken","golden_bui_gate"] and 44 in enabled_events:
  return active
 if str(active.get("kind",""))=="original_jug_shop" and 40 in enabled_events:
  return active
 active.branches = []
 for branch in npc.get("branches", []):
  if branch.get("enabled", false) and _enabled(branch.get("events", [])):
   active.branches.append(branch.duplicate(true))
 return active if not active.branches.is_empty() else {}
func _enabled(events: Array) -> bool:
 for event in events:
  if int(event) in enabled_events: return true
 return false
func journal(profile: Dictionary) -> Array:
 var result: Array = []
 var events: Dictionary = profile.get("original_events", {})
 for job in jobs:
  var event := int(job.event)
  if not event in enabled_events: continue
  var state := ""
  if _flag(events.get("ended", []), event): state = str(job.completed_label)
  elif _flag(events.get("now", []), event): state = str(job.active_label)
  if not state.is_empty(): result.append({"id": int(job.id), "event": event, "title": str(job.title), "state": state})
 return result
func _flag(words: Array, event: int) -> bool:
 var index := event >> 5
 return index >= 0 and index < words.size() and (int(words[index]) & (1 << (event & 31))) != 0
