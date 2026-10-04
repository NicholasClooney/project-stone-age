extends SceneTree
## Pure plan contract only, not source-verifier or loot execution proof.
const Plan = preload("res://server/quest_auto_jewel_loot_plan.gd")
const Catalog = preload("res://server/encounter_catalog.gd")
var failures := 0
var assertions := 0
var calls := 0
var last_source:Dictionary = {}

func check(value:bool,label:String) -> void:
 assertions+=1
 if not value:
  failures+=1
  push_error(label)

func verified(_b,expected:Dictionary) -> bool:
 calls+=1
 last_source=expected.duplicate(true)
 expected.clear() # The trusted callback cannot mutate the eventual proposal.
 return true

func rejected(_b,_expected:Dictionary) -> bool:return false
func malformed(_b,_expected:Dictionary):return 1
func fixture() -> Dictionary:
 # Exercise the actual area_at implementation and original overlap precedence.
 # These minimal rows are unit fixtures, not a copy of the signed source table.
 var catalog=Catalog.new({"areas":[
  {"id":41,"map_id":100,"rect":[587,331,630,343],"priority":110},
  {"id":54,"map_id":100,"rect":[556,345,621,393],"priority":50},
  {"id":56,"map_id":100,"rect":[621,341,645,412],"priority":50}]})
 return {"session":{"_profile":{"original_items":[2764]}},
  "automation":{"position_map":100,"position_cell":Vector2i(622,350)},
  "encounter_catalog":catalog}

func _initialize() -> void:call_deferred("run")
func run() -> void:
 var b=fixture()
 var before:Dictionary=b.session._profile.duplicate(true)
 var result:Dictionary=Plan.select(b,verified)
 var expected_source:Dictionary={"policy":"jewels_2760_area56_v1","map_id":100,"area_id":56,
  "group_id":711,"enemy_id":1305,"drop_slot":0,"requires_item":2764,"excludes_item":2760,
  "signature":"sha256:97c680e16befd2de159349c7b75ac7a9f0dc387f94c9b35c13141cd846d0dc0e"}
 check(result=={"status":"step","step":{"id":"jewels:hunt:2760","action":"loot",
  "target":{"item_id":2760,"count":1},"source":expected_source}},"exact proposal; no runtime authority fields")
 check(calls==1 and last_source==expected_source,"one delegated source check with exact source")
 check(b.session._profile==before and b.automation.position_cell==Vector2i(622,350),"no profile or movement writes")
 check(b.encounter_catalog.pressure==0,"no encounter sampling or pressure mutation")
 check(Plan.select(b).status=="manual","missing core dependency fails closed")
 check(Plan.select(b,rejected).status=="manual","changed source is manual")
 check(Plan.select(b,malformed).status=="manual","truthy non-bool cannot authorize source")
 var saved_calls:=calls
 b.session._profile.original_items=[2760]
 check(Plan.select(b,verified)=={"status":"done"},"existing jewel is done without prerequisite")
 b.session._profile.original_items=[]
 check(Plan.select(b,verified).status=="manual","missing 2764 is manual")
 check(calls==saved_calls,"done/missing prerequisite do not validate a new hunt")
 b.session._profile.original_items=[2764.0]
 check(Plan.select(b,verified).status=="step","mathematical integer IDs accepted; no level or NOW45 requirement")
 for bad in [true,2764.5,INF,NAN]:
  b.session._profile.original_items=[bad]
  check(Plan.select(b,verified).status=="manual","invalid inventory ID rejected: "+str(bad))
 b.session._profile.original_items=[2764]
 for cell in [Vector2i(621,350),Vector2i(622,342),Vector2i(646,350)]:
  b.automation.position_cell=cell
  check(Plan.select(b,verified).status=="manual","actual overlap/outside area is manual: "+str(cell))
 b.automation.position_cell=Vector2i(622,350)
 b.automation.position_map=300
 check(Plan.select(b,verified).status=="manual","wrong map cannot propose loot")
 print("quest_auto_jewel_loot_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
