extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## Preserve the catalog replacement contract while avoiding one full resident
## scan for every quest NPC. Compare to the former algorithm on actual data.
const WorldCatalog = preload("res://scripts/world_catalog.gd")
const QuestCatalog = preload("res://scripts/quest_catalog.gd")
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures += 1
func replaced(residents: Array, previous, provider, note: String) -> Array:
 var expected := residents.duplicate(true)
 var started := Clock.ticks_usec()
 for entry in previous.npcs+previous.service_npcs:
  expected = expected.filter(func(resident):return str(resident.get("id",""))!=str(entry.id))
 expected.append_array(provider.active_npcs())
 print("PROJECTION reference %s: %.3fms" % [note,(Clock.ticks_usec()-started)/1000.0])
 return expected
func compare(world, provider, note: String) -> void:
 var expected := replaced(world.residents,world.quest_catalog,provider,note)
 var started := Clock.ticks_usec()
 world.set_quest_catalog(provider)
 print("PROJECTION %s: %.3fms" % [note,(Clock.ticks_usec()-started)/1000.0])
 check(world.residents==expected,note+": exact residents, order and nested fields")
func run() -> void:
 var world = WorldCatalog.new()
 var provider = QuestCatalog.new()
 # Ordinary residents (including duplicate and absent IDs) must stay in place.
 world.residents.push_front({"name":"ordinary no id","map_id":1000,"cell":[1,2],"nested":{"value":[1,2]}})
 world.residents.append_array([{"id":"test-ordinary","map_id":1000},{"id":"test-ordinary","map_id":2000}])
 # Old duplicates and Charm service NPCs must all be replaced, not retained.
 var duplicate: Dictionary = world.quest_catalog.npcs[0].duplicate(true)
 world.quest_catalog.npcs.append(duplicate)
 world.residents.append_array([duplicate.duplicate(true),duplicate.duplicate(true)])
 compare(world,provider,"replace provider including duplicate old IDs and service NPCs")
 compare(world,provider,"repeat same provider")
 var moved := ""
 var spawned := ""
 for npc in provider.active_npcs():
  if moved.is_empty() and not npc.get("branches",[]).is_empty():moved=str(npc.id)
 for npc in provider.npcs:
  if npc.has("source_spawn") and npc.get("events",[]).any(func(e):return int(e) in provider.enabled_events):spawned=str(npc.id);break
 check(not moved.is_empty() and not spawned.is_empty(),"actual movable and source-area NPC fixtures exist")
 provider.npc_overrides[moved]={"map_id":2000,"cell":[17,18]}
 provider.npc_overrides[spawned]={"map_id":100,"cell":[637,493]}
 compare(world,provider,"per-character moved and area-born NPCs across maps")
 check(world.residents.any(func(row):return str(row.get("id",""))==spawned and int(row.map_id)==100 and row.cell==[637,493]),"area-born NPC uses authoritative projected cell")
 provider.npc_overrides[moved]={"hidden":true}
 provider.npc_overrides.erase(spawned)
 compare(world,provider,"hidden NPC and absent area spawn removed")
 var other = QuestCatalog.new()
 other.enabled_events=[]
 compare(world,other,"new character has independent activation and projection")
 check(world.residents.filter(func(row):return str(row.get("id",""))=="test-ordinary").size()==2,"duplicate ordinary residents survive all replacements")
 print("WORLD CATALOG PROJECTION: %d failures" % failures)
 quit(1 if failures else 0)
