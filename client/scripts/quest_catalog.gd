extends RefCounted
## Read-only original quest data; public activation is tracked separately.
const ROOT := "res://assets/legacy/"
var items: Dictionary = {}
var npcs: Array = []
var service_npcs: Array = []
var jobs: Array = []
var reward_pets: Dictionary = {}
var enabled_events: Array = []
func _init() -> void:
 var config = JSON.parse_string(FileAccess.get_file_as_string("res://data/early-quests.json"))
 if config is Dictionary:
  for event in config.get("enabled_events", []):
   if (event is int or event is float) and float(event) == floor(float(event)) and int(event) > 0 and int(event) < 192:
    enabled_events.append(int(event))
 var modules = JSON.parse_string(FileAccess.get_file_as_string("res://data/quest-modules.json"))
 if modules is Dictionary and int(modules.get("version",0))==1:
  for module in modules.get("modules",[]):
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
  if not _enabled(npc.get("events", [])): continue
  var active: Dictionary = npc.duplicate(true)
  active.branches = []
  for branch in npc.get("branches", []):
   if branch.get("enabled", false) and _enabled(branch.get("events", [])):
    active.branches.append(branch.duplicate(true))
  if not active.branches.is_empty(): result.append(active)
 result.append_array(service_npcs.duplicate(true))
 return result
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
