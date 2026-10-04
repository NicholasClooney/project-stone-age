extends RefCounted
## Reviewed static identities only. No service questions, tokens or execution.
const DATA_PATH:="res://server/quest_auto_golden_bui_sources.json"
const DATA_SHA:="e5ccf199c0e3a06756370ee1ce40efe6501bdcf6f40501379a9960e9a07a00d8"
static func table()->Dictionary:
 var raw:=FileAccess.get_file_as_string(DATA_PATH)
 if raw.sha256_text()!=DATA_SHA:return {}
 var value=JSON.parse_string(raw)
 return value if value is Dictionary else {}
static func integer(value:Variant)->bool:
 return typeof(value)==TYPE_INT or (typeof(value)==TYPE_FLOAT and is_finite(value) and floor(value)==value and absf(value)<9007199254740992.0)
static func point(value:Variant)->bool:
 return value is Array and value.size()==2 and integer(value[0]) and integer(value[1])
static func same(actual:Variant,expected:Variant)->bool:
 if expected is Dictionary:
  if not actual is Dictionary or actual.size()!=expected.size():return false
  for field in expected:
   if not actual.has(field) or not same(actual[field],expected[field]):return false
  return true
 if expected is Array:
  if not actual is Array or actual.size()!=expected.size():return false
  for index in range(expected.size()):
   if not same(actual[index],expected[index]):return false
  return true
 if integer(expected):return integer(actual) and actual==expected
 return typeof(actual)==typeof(expected) and actual==expected
static func portal_row(portal:Dictionary)->Dictionary:
 if portal.size()!=4 or not integer(portal.get("from_map")) or not integer(portal.get("to_map")) or not point(portal.get("from_cell")) or not point(portal.get("to_cell")):return {}
 for row in table().get("portals",[]):
  var identity:Dictionary={"from_map":row.from_map,"from_cell":row.from_cell,"to_map":row.to_map,"to_cell":row.to_cell}
  if same(portal,identity):return row.duplicate(true)
 return {}
static func npc(b,expected:Dictionary)->Dictionary:
 var found:Dictionary={}
 var count:=0
 # The public active projection already applies personal relocation/hiding.
 # Do not call npc_by_id: it refreshes mutable NPC state in current backend.
 for candidate in b.quest_catalog.active_npcs():
  if str(candidate.get("id",""))==str(expected.id) or (str(candidate.get("source_script",""))==str(expected.source_script) and same(candidate.get("map_id"),expected.map_id)):
   count+=1;found=candidate
 if count!=1:return {}
 for field in found:
  if not expected.has(field) and field not in ["bitmap_id","source_pose","path","offset"]:return {}
 for field in expected:
  if not found.has(field) or not same(found[field],expected[field]):return {}
 return found.duplicate(true)
