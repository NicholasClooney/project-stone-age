extends RefCounted
## Exact reviewed source definitions; this never rolls, moves, saves or grants proof.
const State=preload("res://server/quest_auto_loot_state.gd")
const Policy=preload("res://server/quest_wild_drop_policy.gd")
const PATH="res://data/quest-auto-loot-sources.json"
const DIGEST="97c680e16befd2de159349c7b75ac7a9f0dc387f94c9b35c13141cd846d0dc0e"
const SIGNATURE="sha256:"+DIGEST
static func source()->Dictionary:
 return {"policy":"jewels_2760_area56_v1","map_id":100,"area_id":56,"group_id":711,"enemy_id":1305,"drop_slot":0,"requires_item":2764,"excludes_item":2760,"signature":SIGNATURE}
static func step()->Dictionary:
 return {"id":State.STEP,"action":"loot","target":{"item_id":2760,"count":1},"source":source()}
static func same(a:Variant,b:Variant)->bool:
 # JSON integer/floating codecs are equivalent only for finite actual numbers.
 if a is bool or b is bool:return a is bool and b is bool and a==b
 if a is int or a is float:
  return (b is int or b is float) and is_finite(float(a)) and is_finite(float(b)) and a==b
 if typeof(a)!=typeof(b):return false
 if a is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same(a[key],b[key]):return false
  return true
 if a is Array:
  if a.size()!=b.size():return false
  for i in range(a.size()):
   if not same(a[i],b[i]):return false
  return true
 return a==b
static func manifest()->Dictionary:
 if FileAccess.get_sha256(PATH)!=DIGEST:return {}
 var parsed=JSON.parse_string(FileAccess.get_file_as_string(PATH))
 return parsed if parsed is Dictionary else {}
static func rect_valid(rect:Variant)->bool:
 return rect is Array and rect.size()==4 and rect.all(func(n):return State.integer(n,-State.MAX_COUNTER,State.MAX_COUNTER)) and rect[0]<=rect[2] and rect[1]<=rect[3]
static func definitions(catalog:Dictionary,quests:Dictionary,rules:Array,rare_sha:String)->bool:
 var frozen:=manifest()
 if frozen.is_empty() or rare_sha!=frozen.rare_overlay.sha256:return false
 if not catalog.get("areas") is Array:return false
 var overlaps:Array=[]
 var target:Array=frozen.effective_area.rect
 for area in catalog.areas:
  if not area is Dictionary or not State.integer(area.get("map_id")) or not rect_valid(area.get("rect")):return false
  var r:Array=area.rect
  if area.map_id==100 and r[0]<=target[2] and r[2]>=target[0] and r[1]<=target[3] and r[3]>=target[1]:overlaps.append(area)
 if not same(overlaps,frozen.overlapping_areas):return false
 for pair in [["groups","effective_groups"],["enemies","effective_enemies"],["templates","effective_templates"]]:
  var current=catalog.get(pair[0])
  if not current is Dictionary:return false
  for key in frozen[pair[1]]:
   if not same(current.get(key),frozen[pair[1]][key]):return false
 if not same(catalog.get("provenance"),frozen.encounter_provenance) or not quests.get("items") is Dictionary:return false
 for key in frozen.items:
  if not same(quests.items.get(key),frozen.items[key]):return false
 var reviewed=quests.get("reviewed_drops")
 if not reviewed is Dictionary:return false
 var relevant:Dictionary={}
 for module in reviewed:
  if not reviewed[module] is Dictionary or not reviewed[module].get("entries") is Array:return false
  var entries:Array=[]
  for entry in reviewed[module].entries:
   if not entry is Dictionary or not State.integer(entry.get("enemy_id")):return false
   if frozen.effective_enemies.has(str(int(entry.enemy_id))):entries.append(entry)
  if not entries.is_empty():
   relevant[module]=reviewed[module].duplicate(true);relevant[module].entries=entries
 if not same(relevant,frozen.reviewed_drops):return false
 var matches:Array=[]
 for row in rules:
  if not row is Dictionary:return false
  for key in ["map","area","group","enemy","item","slot"]:
   if not State.integer(row.get(key)):return false
  if row.map!=100 or row.area!=56:continue
  var group:Dictionary=frozen.effective_groups.get(str(int(row.group)),{})
  if group.is_empty() or not group.enemies.any(func(enemy):return enemy.id==row.enemy):continue
  for drop in frozen.effective_enemies[str(int(row.enemy))].drops:
   if drop.item_id==row.item and drop.slot==row.slot:matches.append(row)
 return same(matches,frozen.protected_policy_matches)
static func current(catalog:Dictionary,quests:Dictionary)->bool:
 var policy=JSON.parse_string(FileAccess.get_file_as_string("res://data/quest-wild-drop-policy.json"))
 if not policy is Dictionary or not policy.get("rules") is Array:return false
 if not definitions(catalog,quests,policy.rules,FileAccess.get_sha256("res://data/rare-encounters.json")):return false
 # Also reject a stale/nonempty runtime rule index, not just a changed file.
 var frozen:=manifest()
 for group in frozen.effective_groups.values():
  for enemy in group.enemies:
   for drop in frozen.effective_enemies[str(int(enemy.id))].drops:
    if not Policy.match_rule(100,56,int(group.id),int(enemy.id),int(drop.item_id),int(drop.slot)).is_empty():return false
 return true
## Trusted read-only plan preflight, not a persistent capability or command field.
## Backend execution must call this again, plus actual admission/position checks.
static func matches_backend(b,expected_source:Dictionary)->bool:
 if not same(expected_source,source()):return false
 var quests=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/quests/catalog.json"))
 if not quests is Dictionary:return false
 # Check both imported definitions and this backend's actual item projection.
 if not current(b.encounter_catalog.data,quests):return false
 var frozen:=manifest()
 for key in frozen.items:
  if not same(b.quest_catalog.items.get(key),frozen.items[key]):return false
 return true
