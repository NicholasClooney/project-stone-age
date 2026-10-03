extends RefCounted
# Independent source identities, shared by all active catalog readers.
static var review:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/prison-identities.json"))
static func same(actual,expected)->bool:
 if expected is Dictionary:
  if not actual is Dictionary or actual.size()!=expected.size():return false
  for key in expected:
   if not actual.has(key) or not same(actual[key],expected[key]):return false
  return true
 if expected is Array:
  if not actual is Array or actual.size()!=expected.size():return false
  for index in range(expected.size()):
   if not same(actual[index],expected[index]):return false
  return true
 return actual==expected
static func valid(npc:Dictionary)->bool:
 if npc.has("prison_role"):return false
 for actor in review.actors:
  if str(npc.get("id",""))!=str(actor.id):continue
  for field in actor:
   if not npc.has(field) or not same(npc[field],actor[field]):return false
  return true
 return false
