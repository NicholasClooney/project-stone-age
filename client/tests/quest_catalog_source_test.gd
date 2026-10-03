extends "res://tests/quest_catalog_lookup_test.gd"
const Backend=preload("res://server/backend.gd")
class FullCatalog extends "res://scripts/quest_catalog.gd":
 func active_npcs_by_source(_source_script:String)->Array:return active_npcs()
var scripts:Array=["","missing/source"]
func compare_sources(catalog,label:String)->void:
 var original:Array=catalog.npcs.duplicate(true)
 var services:Array=catalog.service_npcs.duplicate(true)
 var expected:Array=reference(catalog)
 var equal:bool=true;var isolated:bool=true
 for source in scripts:
  var filtered:Array=expected.filter(func(n):return str(n.get("source_script",""))==source)
  var actual:Array=catalog.active_npcs_by_source(source)
  if actual!=filtered:equal=false;push_error(label+" "+source)
  mutate_nested(actual)
  if catalog.active_npcs_by_source(source)!=filtered:isolated=false
 check(equal,label+" all actual/empty/missing scripts full fields and source/branch order")
 check(isolated and catalog.npcs==original and catalog.service_npcs==services,label+" every nested return and source remain isolated")
func sync_old(catalog,old)->void:
 old.npcs=catalog.npcs.duplicate(true);old.service_npcs=catalog.service_npcs.duplicate(true)
 old.enabled_events=catalog.enabled_events.duplicate();old.npc_overrides=catalog.npc_overrides.duplicate(true)
func compare_entries(catalog,old,label:String)->void:
 sync_old(catalog,old)
 var pairs:Array=[
  ["dragon_cave","jaruga/event/event17_4"],["goya_deliveries","jaruga/event/event06_1"],
  ["jan_cave","jaruga/event/event20_1"],["marju","extra/event/marju"],
  ["miner_contest","giiru/event/giruev2_1"],["munde_cave","sainasu/event/event12"],
  ["saton_cave","sainasu/event/event13_1"],["transmigration_earth","jaruga/event/ruri02"],
  ["dream_cave","seimu/event/event01_2"],["transmigration_wind","sainasu/event/event12"],
  ["four_jewels","extra/event/hougyoku"],["katan","seimu/event/event02_1"]]
 for pair in pairs:
  var helper=load("res://server/"+pair[0]+"_helper.gd").new();var equal:bool=true
  for index in [-1,0,1,2,99]:
   var args:Array=[pair[1],index]
   if pair[0] in ["four_jewels","katan"]:args=[index]
   var variants:Array=[args]
   if pair[0]=="dream_cave":
    variants=[]
    for map_id in [-1,41,42,300]:variants.append(args+[map_id])
   if pair[0]=="transmigration_wind":
    variants=[args+[""],args+["missing/id"]]
    for npc in reference(catalog):
     if str(npc.get("source_script",""))==pair[1]:variants.append(args+[str(npc.id)])
   for arguments in variants:
    if helper.callv("entry",[{"quest_catalog":catalog}]+arguments)!=helper.callv("entry",[{"quest_catalog":old}]+arguments):equal=false
  check(equal,label+" "+pair[0]+" entry preserves source/map/id/branch/first selection")
func run()->void:
 var catalog=Catalog.new();var old=FullCatalog.new()
 for npc in catalog.npcs+catalog.service_npcs:
  var source:String=str(npc.get("source_script",""))
  if not source in scripts:scripts.append(source)
 check_final_services(catalog)
 compare_sources(catalog,"all enabled")
 var final_enabled:Array=catalog.enabled_events.duplicate()
 for event in FINAL_TAGS:catalog.enabled_events.erase(event)
 compare_sources(catalog,"explicit final-module disabled fixture")
 for id in FINAL_SERVICE_IDS:
  var source:String=str(first(reviewed_final,id).source_script)
  check(catalog.active_npcs_by_source(source).is_empty(),"explicit disabled service source absent "+source)
 catalog.enabled_events=final_enabled
 compare_entries(catalog,old,"all enabled")
 var enabled:Array=catalog.enabled_events.duplicate()
 for events in [[9],[41],[42],[9,41,42],[]]:
  catalog.enabled_events=events;compare_sources(catalog,"shared event12 "+str(events))
 catalog.enabled_events=enabled;catalog.enabled_events.erase(46)
 compare_sources(catalog,"water disabled")
 catalog.enabled_events=enabled
 var first_npc:Dictionary=catalog.npcs[0]
 catalog.npc_overrides[str(first_npc.id)]={"map_id":300,"cell":[1,2]}
 compare_sources(catalog,"personal move")
 catalog.npc_overrides[str(first_npc.id)].hidden=true
 compare_sources(catalog,"personal hidden")
 catalog.npc_overrides.clear()
 for npc in catalog.npcs:
  if npc.has("source_spawn"):catalog.npc_overrides[str(npc.id)]={"map_id":int(npc.map_id),"cell":npc.cell.duplicate()}
 compare_sources(catalog,"regional births")
 var duplicate:Dictionary=first_npc.duplicate(true);duplicate.map_id=300;duplicate.cell=[3,4]
 catalog.npcs.push_front(duplicate)
 # Ensure duplicate first-choice and multi-map selection affect the actual
 # twelve entry lookups, rather than only an unrelated catalog record.
 for source in ["jaruga/event/event17_4","jaruga/event/event06_1","jaruga/event/event20_1","extra/event/marju","giiru/event/giruev2_1","sainasu/event/event12","sainasu/event/event13_1","jaruga/event/ruri02","seimu/event/event01_2","extra/event/hougyoku","seimu/event/event02_1"]:
  for npc in catalog.npcs.duplicate():
   if str(npc.get("source_script",""))!=source:continue
   var copy:Dictionary=npc.duplicate(true);copy.map_id=300;copy.cell=[3,4]
   catalog.npcs.push_front(copy);break
 compare_sources(catalog,"duplicate ID and same source multi-map")
 compare_entries(catalog,old,"duplicate ID and same source multi-map")
 catalog=Catalog.new();old=FullCatalog.new()
 var start:int=Time.get_ticks_usec()
 for source in scripts:old.active_npcs().filter(func(n):return str(n.get("source_script",""))==source)
 var old_us:int=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
 for source in scripts:catalog.active_npcs_by_source(source)
 print("SOURCE LOOKUP scripts=",scripts.size()," full_us=",old_us," projected_us=",Time.get_ticks_usec()-start)
 var b=Backend.new();b.session.gm_raise_level(-1,80)
 for state in [0,1,2]:
  catalog.npc_overrides.clear()
  if state==1:catalog.npc_overrides[str(first_npc.id)]={"map_id":31705,"cell":[2,3],"hidden":true}
  if state==2:catalog.enabled_events.erase(46)
  sync_old(catalog,old)
  b.automation.position_changed(100 if state==0 else 31705,Vector2i(10,10))
  b.quest_catalog=old;b.original_quests.catalog=old;b.quest_helper.cached_key=""
  start=Time.get_ticks_usec();var expected:Dictionary=b.quest_helper.snapshot(b);old_us=Time.get_ticks_usec()-start
  b.quest_catalog=catalog;b.original_quests.catalog=catalog;b.quest_helper.cached_key=""
  start=Time.get_ticks_usec();var actual:Dictionary=b.quest_helper.snapshot(b);var new_us:int=Time.get_ticks_usec()-start
  check(actual==expected,"representative complete snapshot exact old full-array input state"+str(state))
  print("SOURCE SNAPSHOT state=",state," old_us=",old_us," new_us=",new_us)
 b.free()
 print("QUEST CATALOG SOURCE: %d failures"%failures);quit(1 if failures else 0)
