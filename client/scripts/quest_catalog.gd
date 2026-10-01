extends RefCounted
## Read-only original quest data; public activation is tracked separately.
const ROOT := "res://assets/legacy/"
var items: Dictionary = {}
var npcs: Array = []
var jobs: Array = []
var enabled_events: Array = []
func _init() -> void:
 var config = JSON.parse_string(FileAccess.get_file_as_string("res://data/early-quests.json"))
 if config is Dictionary: enabled_events = config.get("enabled_events", []).duplicate()
 if not FileAccess.file_exists(ROOT + "quests/catalog.json"): return
 var data = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "quests/catalog.json"))
 if not data is Dictionary or int(data.get("version", 0)) != 1: return
 items = data.get("items", {})
 npcs = data.get("npcs", [])
 jobs = data.get("jobs", [])
func active_npcs() -> Array:
 var result: Array = []
 for npc in npcs:
  for branch in npc.get("branches", []):
   if int(branch.get("event", -1)) > 0 and int(branch.event) in enabled_events:
    result.append(npc.duplicate(true))
    break
 return result
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
