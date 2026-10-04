extends "res://tests/quest_auto_loot_state_test.gd"
const Sources=preload("res://server/quest_auto_loot_sources.gd")
func run()->void:
 var frozen:=Sources.manifest()
 check(not frozen.is_empty() and FileAccess.get_sha256(Sources.PATH)==Sources.DIGEST,"Exact frozen manifest bytes, not alternate JSON encoding")
 if frozen.is_empty():quit(1);return
 var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/encounters/catalog.json"))
 var quests:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/quests/catalog.json"))
 var policy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/quest-wild-drop-policy.json"))
 var rare_sha:=FileAccess.get_sha256("res://data/rare-encounters.json")
 check(Sources.definitions(catalog,quests,policy.rules,rare_sha),"Actual complete imported pool accepted without rolling")
 var before:Dictionary=catalog.duplicate(true)
 check(Sources.current(catalog,quests) and catalog==before,"Runtime rule cache + raw definitions read-only")
 var changed:=catalog.duplicate(true)
 var added:Dictionary=frozen.effective_area.duplicate(true);added.id=999999
 changed.areas.append(added)
 check(not Sources.definitions(changed,quests,policy.rules,rare_sha),"New overlapping area refused even with same rect and lower/equal priority")
 changed=catalog.duplicate(true)
 changed.areas.reverse()
 check(not Sources.definitions(changed,quests,policy.rules,rare_sha),"Overlapping tie precedence order preserved")
 changed=catalog.duplicate(true);changed.groups["711"].enemies.reverse()
 check(not Sources.definitions(changed,quests,policy.rules,rare_sha),"Original enemy order never replaced with target-only or reordered troop")
 changed=catalog.duplicate(true);changed.groups["169"].enemies[0].weight+=1
 check(not Sources.definitions(changed,quests,policy.rules,rare_sha),"Non-target ordinary source change invalidates pin too")
 var changed_quests:=quests.duplicate(true)
 changed_quests.reviewed_drops["new-matching-module"]={"active":true,"entries":[{"enemy_id":1305,"item_id":2760}]}
 check(not Sources.definitions(catalog,changed_quests,policy.rules,rare_sha),"New reviewed matching module cannot hide outside original module list")
 var rules:Array=policy.rules.duplicate(true)
 rules.append({"map":100,"area":56,"group":711,"enemy":1305,"item":2760,"slot":0,"scope":"new-protected"})
 check(not Sources.definitions(catalog,quests,rules,rare_sha),"New protected exact tuple refused; no proof invented")
 check(not Sources.definitions(catalog,quests,policy.rules,"changed"),"Rare overlay SHA drift refused")
 for value in [true,711.1,NAN,INF]:
  var source:=Sources.source();source.group_id=value
  check(not Sources.same(source,Sources.source()),"Numeric source identity rejects boolean/fraction/nonfinite")
 var source:=Sources.source();source.group_id=711.0
 check(Sources.same(source,Sources.source()),"Finite mathematical JSON integer codec accepted")
 check(Sources.step().target.count==1 and Sources.step().source.signature==Sources.SIGNATURE,"Exact target means current inventory reaches1")
 print("QUEST AUTO LOOT SOURCES: %d failures; no rollout or source battle acceptance"%failures)
 quit(1 if failures else 0)
