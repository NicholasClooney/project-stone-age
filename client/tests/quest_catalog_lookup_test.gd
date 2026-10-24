extends SceneTree
const Clock=preload("res://scripts/clock.gd")
const Catalog=preload("res://scripts/quest_catalog.gd")
const FINAL_TAGS=[48,49,50,51,52]
const FINAL_SERVICE_IDS=["777/ten.arg@32021:31:28","genout/wpm_117_6_5@117:6:5","genout/wpm_110_37_20@110:37:20","genout/wpm_110_37_24@110:37:24","genout/wpm_110_37_28@110:37:28","genout/wpm_110_37_32@110:37:32"]
var reviewed_final:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-final-source.json")).npcs
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func first(rows:Array,id:String)->Dictionary:
 for npc in rows:
  if str(npc.id)==id:return npc
 return {}
func compare(catalog,label:String)->void:
 var source_before:Array=catalog.npcs.duplicate(true)
 var expected:Array=reference(catalog)
 check(catalog.active_npcs()==expected,label+" full projection retains original order and fields")
 var same:bool=true
 for row in catalog.npcs+catalog.service_npcs:
  if catalog.active_npc(str(row.id))!=first(expected,str(row.id)):same=false;push_error(label+" differs "+str(row.id))
 check(same,label+" every catalog ID equals original full-array lookup")
 var returned:Array=catalog.active_npcs()
 for row in returned:mutate_nested(row)
 check(catalog.npcs==source_before and catalog.active_npcs()==expected,label+" all nested returns isolated and source branch order unchanged")
 check(catalog.active_npc("missing/source@0:0:0").is_empty(),label+" absent ID remains empty")
func mutate_nested(value)->void:
 if value is Dictionary:
  for key in value.keys():mutate_nested(value[key])
  value["isolation_probe"]=[-909]
 elif value is Array:
  for entry in value:mutate_nested(entry)
  value.append(-909)
func run()->void:
 var catalog=Catalog.new();var other=Catalog.new()
 check_final_services(catalog)
 compare(catalog,"all actual enabled modules")
 var enabled_final:Array=catalog.enabled_events.duplicate()
 for event in FINAL_TAGS:catalog.enabled_events.erase(event)
 compare(catalog,"explicit final-module disabled fixture")
 for id in FINAL_SERVICE_IDS:check(catalog.active_npc(id).is_empty(),"explicit disabled service absent "+id)
 catalog.enabled_events=enabled_final
 var initial:Array=reference(catalog);var ids:Array=initial.map(func(n):return str(n.id))
 var start:int=Clock.ticks_usec()
 for id in ids:first(reference(catalog),id)
 var old_usec:int=Clock.ticks_usec()-start;start=Clock.ticks_usec()
 for id in ids:catalog.active_npc(id)
 print("LOOKUP COST ids=",ids.size()," original_us=",old_usec," single_us=",Clock.ticks_usec()-start)
 var ordinary_branches:int=0
 for npc in catalog.npcs:
  if npc.get("handler","")=="TimeMan" or str(npc.get("kind","")) in ["golden_bui_quiz","golden_bui_janken","golden_bui_gate","original_jug_shop"]:continue
  if catalog._enabled(npc.get("events",[])) and not npc.has("source_spawn"):ordinary_branches+=npc.get("branches",[]).size()
 start=Clock.ticks_usec()
 for i in 100:reference(catalog)
 var reference_us:int=Clock.ticks_usec()-start;start=Clock.ticks_usec()
 for i in 100:catalog.active_npcs()
 print("PROJECTION COST iterations=100 old_us=",reference_us," new_us=",Clock.ticks_usec()-start," discarded_branch_copies_avoided_per_projection=",ordinary_branches)
 var events:Array=catalog.enabled_events.duplicate();catalog.enabled_events.erase(46)
 compare(catalog,"water46 disabled with independent event4 gates")
 catalog.enabled_events=events
 var moved:Dictionary=initial[0];var moved_id:String=str(moved.id)
 catalog.npc_overrides[moved_id]={"map_id":300,"cell":[3,4]}
 compare(catalog,"personal moved NPC")
 check(catalog.active_npc(moved_id).cell==[3,4] and other.active_npc(moved_id)==first(reference(other),moved_id),"movement is per character")
 catalog.npc_overrides[moved_id].hidden=true;compare(catalog,"personal hidden NPC")
 catalog.npc_overrides.clear()
 var spawned:Array=catalog.npcs.filter(func(n):return n.has("source_spawn"))
 check(not spawned.is_empty(),"actual regional spawn source exists")
 for npc in spawned:
  check(catalog.active_npc(str(npc.id)).is_empty(),"unborn regional NPC stays absent "+str(npc.id))
  catalog.npc_overrides[str(npc.id)]={"map_id":int(npc.map_id),"cell":npc.cell.duplicate()}
 compare(catalog,"regional actors born via personal overrides")
 var event12:Array=catalog.npcs.filter(func(n):return str(n.get("source_script",""))=="sainasu/event/event12")
 check(not event12.is_empty(),"actual shared Munde/wind event12 source exists")
 for enabled in [[9],[41],[42],[9,41,42],[]]:
  catalog.enabled_events=enabled;compare(catalog,"shared event12 activation "+str(enabled))
 catalog.enabled_events=events;catalog.npc_overrides.clear()
 for npc in catalog.npcs:
  if npc.get("handler","")=="TimeMan":catalog.npc_overrides[str(npc.id)]={"time_mode":"changed"}
 compare(catalog,"personal TimeMan changed visual")
 catalog.npc_overrides.clear()
 for service in catalog.service_npcs:
  check(catalog.active_npc(str(service.id))==service,"independent Charm service projection "+str(service.id))
 var picked:Dictionary=catalog.active_npc(moved_id)
 picked.cell[0]=-900
 if picked.has("branches") and not picked.branches.is_empty():picked.branches[0]["probe_mutation"]={"values":[1]}
 check(catalog.active_npc(moved_id)==first(initial,moved_id) and other.active_npc(moved_id)==first(reference(other),moved_id),"returned nested dictionaries cannot mutate source or another character")
 for service in catalog.service_npcs:
  var copy:Dictionary=catalog.active_npc(str(service.id));copy.cell[0]=-901
  check(catalog.active_npc(str(service.id))==service,"service return is deep isolated "+str(service.id))
 catalog.npcs.push_front(catalog.npcs[0].duplicate(true));compare(catalog,"duplicate ID first-active ordering")
 print("QUEST CATALOG LOOKUP: %d failures"%failures);quit(1 if failures else 0)
func reference(catalog) -> Array:
 var result: Array = []
 for npc in catalog.npcs:
  if not catalog._enabled(npc.get("events", [])): continue
  var override:Dictionary=catalog.npc_overrides.get(str(npc.id),{})
  if bool(override.get("hidden",false)):continue
  if npc.has("source_spawn") and not override.has("map_id"):continue
  var active: Dictionary = npc.duplicate(true)
  # Source-fixture oracle for branchless services added in stage three.
  # No production projection or identity helper supplies the expected result.
  if str(npc.get("kind","")) in ["original_transmigration","original_prison"]:
   if override.is_empty() and reviewed_service(npc):result.append(active)
   continue
  if override.has("map_id"):
   active.map_id=int(override.map_id);active.cell=override.cell.duplicate()
  if active.get("handler","")=="TimeMan":
   var visual:Dictionary=active.get("time_visuals",{}).get(str(override.get("time_mode","main")),{})
   for field in ["graphic","text","path","offset","bitmap_id","source_pose"]:
    if visual.has(field):active[field]=visual[field]
   result.append(active)
   continue
  if str(active.get("kind","")) in ["golden_bui_quiz","golden_bui_janken","golden_bui_gate"] and 44 in catalog.enabled_events:
   result.append(active)
   continue
  if str(active.get("kind",""))=="original_jug_shop" and 40 in catalog.enabled_events:
   result.append(active)
   continue
  active.branches = []
  for branch in npc.get("branches", []):
   if branch.get("enabled", false) and catalog._enabled(branch.get("events", [])):
    active.branches.append(branch.duplicate(true))
  if not active.branches.is_empty(): result.append(active)
 result.append_array(catalog.service_npcs.duplicate(true))
 return result

func reviewed_service(npc:Dictionary)->bool:
 var source:Dictionary=first(reviewed_final,str(npc.id))
 if source.is_empty() or str(npc.id) not in FINAL_SERVICE_IDS:return false
 for field in ["id","source_script","source_create","source_create_index","events","name","map_id","cell","graphic","facing","branches","kind","handler","service_id"]:
  if npc.get(field)!=source.get(field):return false
 if str(npc.kind)=="original_prison":
  return not npc.has("prison_role") and npc.get("prison")==source.prison and npc.get("source_fields")==source.source_fields
 var service=npc.get("transmigration",{})
 return service is Dictionary and service.get("schema")==source.transmigration.schema and service.get("rules")==source.transmigration.rules

func check_final_services(catalog)->void:
 var present:Array=[]
 for npc in catalog.active_npcs():
  if str(npc.get("kind","")) in ["original_transmigration","original_prison"]:present.append(str(npc.id))
 var wanted:Array=FINAL_SERVICE_IDS.duplicate();present.sort();wanted.sort()
 check(present==wanted,"production activation contains exact reviewed king and five Prison identities")
 for id in FINAL_SERVICE_IDS:
  var source:Dictionary=first(reviewed_final,id);var actual:Dictionary=catalog.active_npc(id)
  var same:bool=not source.is_empty() and not actual.is_empty()
  for field in source: same=same and actual.get(field)==source[field]
  check(same,"production service source fields exactly match independent fixture "+id)
