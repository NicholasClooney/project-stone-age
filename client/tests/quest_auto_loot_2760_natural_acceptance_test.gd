extends "res://tests/quest_auto_loot_crystal_prerequisite_test.gd"
## UNRUN static candidate: one authenticated natural pilot, default E1 30 minutes.
## Historical pilots remain byte-identical; no test registration or product change.
const Server=preload("res://server/ws_server.gd")
const Game=preload("res://scripts/game.gd")
const MapFile=preload("res://scripts/map_file.gd")
const Sources=preload("res://server/quest_auto_loot_sources.gd")
const Plan=preload("res://server/quest_auto_jewel_loot_plan.gd")
const PetProgression=preload("res://server/progression.gd")
const PetLoyalty=preload("res://server/loyalty.gd")
const OriginalEquipment=preload("res://server/original_equipment.gd")
const GENOU="sainasu/event/genou_3@100:346:356"
const MAX_ROUTE_BATTLES:=20 # Setup collision route only, never an E1 battle cap.
const MAX_SOURCE_CELLS:=1800
const MAX_PATH_QUERIES:=8
const MAX_ASTAR_SEARCH_WINDOWS:=32
const MAX_ROUTE_SEARCH_WINDOWS:=64
const MAX_ROUTE_SEARCH_CELL_VISITS:=24000000
const MAX_ROUTE_WALK_REPLANS:=20
const MAX_ROUTE_CELLS:=4096
const MAX_MAP_CELLS:=1000000
const MAX_ASTAR_CELL_VISITS:=12000000
const MAX_ROUTE_REPORTS:=4096
const NaturalBackend=preload("res://tests/support/quest_loot_natural_acceptance_backend.gd")
const HubType=preload("res://server/profile_hub.gd")
const SaveLockType=preload("res://server/save_lock.gd")
const Settings=preload("res://server/quest_auto_settings_rules.gd")
const ACCEPTANCE_ROOT:="user://loot-natural-30m-acceptance"
const OUTER_MS:=2400000
const SETUP_MS:=300000
const ACTIVE_MS:=1800000
const SETTLEMENT_MS:=180000
const VERIFY_MS:=120000
const ATTEMPTS_LIMIT:=3601
class NaturalHub extends HubType:
 const BackendType=preload("res://server/backend.gd")
 const ObserverType=preload("res://tests/support/quest_loot_natural_acceptance_backend.gd")
 func _new_profile_backend()->BackendType:return ObserverType.new()
var host
var server
var world
var hub
var profile_id:=""
var accepted_peer_id:=-1
var accepted_binding:RefCounted
var pilot_started_ms:=0
var pilot_deadline_ms:=0
var e1_anchor:=-1
var stage:="setup"
var failure_saved:=false
var route_destination:=Vector2i(-1,-1)
var route_search_candidates:int=0
var route_search_queries:int=0
var route_path_cells:Array=[]
var route_report_start:=0
var route_battle_count:=0
var route_walk_replans:=0
var route_search_map_cells:=0
var route_search_cell_visits:=0
var route_search_windows:=0
var candidate_search_windows:=0
var route_search_searches_baseline:=0
var route_search_cells_baseline:=0

func emit_pilot_trace(label:String,value:Variant)->bool:
 var ok:bool=host!=null and host.trace_event(label,value)
 if not ok:check(false,"Bounded event evidence failed: "+label)
 return ok
func pilot_remaining_seconds()->float:
 return maxf(0.0,float(pilot_deadline_ms-Time.get_ticks_msec())/1000.0)
func pilot_trace_ok()->bool:
 return host==null or (not host.route_trace_overflow and not host.settlement_trace_overflow and not host.settlement_failed and not host.settlement_observation_failed and not host.close_observation_failed and not host.transport_binding_changed and not host.invalid_transport_binding and not host.trace_output_overflow and not host.observation_failed and not host.quest_loot.observation_failed)
func pilot_wait(condition:Callable,label:String)->bool:
 while Time.get_ticks_msec()<pilot_deadline_ms:
  if failures:return false
  if not pilot_trace_ok():check(false,"Evidence/receipt observation failure: "+label);return false
  if condition.call():return true
  await physics_frame
 check(false,"UNCOMPLETE stage deadline: "+stage+" / "+label)
 return false
func check(ok:bool,label:String)->void:
 if ok and pilot_deadline_ms>0 and Time.get_ticks_msec()>=pilot_deadline_ms:
  ok=false;label="UNCOMPLETE stage deadline: "+stage+" / "+label
 if ok:return
 failures+=1
 if not failure_saved:
  failure_saved=true
  # Do not stop/close/save/disconnect the live run to rescue a failed oracle.
  var row:Dictionary={"result":"UNCOMPLETE" if Time.get_ticks_msec()>=pilot_deadline_ms or label.contains("UNCOMPLETE") else "FAIL","stage":stage,"reason":label,"elapsed_ms":Time.get_ticks_msec()-pilot_started_ms}
  if host!=null:
   row.profile=host.session._profile.duplicate(true)
   row.pending=host.session._pending.duplicate(true)
   row.settlement=host.session._loot_settlement.duplicate(true)
   row.raw_battle=host.battle._state.duplicate(true)
   row.backend_view=host.battle_state.duplicate(true)
   row.cache=host.last_saved_payload
   row.primary=host._capture_disk(host.save_path)
   row.backup=host._capture_disk(host.save_path+".bak")
   host.trace_event("ACCEPTANCE_FAILURE",row)
   if host.evidence!=null:host.evidence.flush()
  var bytes:PackedByteArray=JSON.stringify(row).to_utf8_buffer()
  if bytes.size()<=8388608 and not FileAccess.file_exists(ACCEPTANCE_ROOT+"/failure.json"):
   var file:=FileAccess.open(ACCEPTANCE_ROOT+"/failure.json",FileAccess.WRITE)
   if file!=null:file.store_buffer(bytes);file.flush();file.close()
  print("ACCEPTANCE_FAILURE ",JSON.stringify({"result":row.result,"stage":stage,"reason":label,"evidence":ACCEPTANCE_ROOT,"no_rescue_save":true}))
 push_error(label) # Emit engine error only after the isolated failure evidence is flushed.
func request_world(command:Dictionary,label:String)->Dictionary:
 var reply:Array=[{}]
 world.link.request(command,func(value):reply[0]=value.duplicate(true))
 var arrived:bool=await pilot_wait(func():return not reply[0].is_empty(),label)
 if not arrived:return {}
 return reply[0]
func checked_pilot_disk(b,stage:String)->bool:
 var raw:Dictionary=read_disk(b.save_path)
 if failures:return false
 var backup:Dictionary=read_disk(b.save_path+".bak")
 if failures:return false
 var native:Dictionary=b.session._profile.duplicate(true)
 var normalized_native:Dictionary=b.session._normalize_numbers(native.duplicate(true))
 var primary_copy:Dictionary=ProfileCompare.validated_copy(b.session,raw.bytes.get_string_from_utf8())
 var backup_copy:Dictionary=ProfileCompare.validated_copy(b.session,backup.bytes.get_string_from_utf8())
 var cache_copy:Dictionary=ProfileCompare.validated_copy(b.session,b.last_saved_payload)
 check(primary_copy.get("ok",false) and backup_copy.get("ok",false) and cache_copy.get("ok",false) and b.session._valid_profile(native),stage+" primary/backup/cache all pass complete original profile validation")
 if failures:return false
 check(primary_copy.profile==normalized_native and cache_copy.profile==normalized_native and raw.bytes.get_string_from_utf8()==b.last_saved_payload,stage+" primary and exact writer cache match full copied native profile")
 if failures:return false
 # A rotating backup is the previous complete original profile, not a copy of current state.
 check(backup_copy.profile is Dictionary and b.session._valid_profile(backup_copy.profile),stage+" rotated backup is a complete valid prior profile")
 return failures==0
func checkpoint_world(label:String)->bool:
 var reply:Dictionary=await request_world({"type":"checkpoint","map_id":world.data.map_id,"x":world.cell.x,"y":world.cell.y},label)
 if failures:return false
 check(reply.get("ok",false),label+" uses the original checkpoint transaction")
 return failures==0
func original_yes_end(npc_id:String,label:String)->bool:
 var talk:Dictionary=await request_world({"type":"quest_talk","npc_id":npc_id},label+" original talk")
 if failures:return false
 check(talk.get("ok",false) and talk.has("dialogue"),label+" original page opens")
 if failures:return false
 var token:String=str(talk.dialogue.get("token",""))
 check(not token.is_empty(),label+" original token is captured")
 if failures:return false
 var yes:Dictionary=await request_world({"type":"quest_choose","token":token,"choice":"yes"},label+" original yes")
 if failures:return false
 check(yes.get("ok",false) and yes.has("dialogue"),label+" original yes transaction succeeds")
 if failures:return false
 var ok:Dictionary=await request_world({"type":"quest_choose","token":str(yes.dialogue.get("token",token)),"choice":"ok"},label+" original end ok")
 if failures:return false
 check(ok.get("ok",false) and host.original_quests.pending.is_empty(),label+" original end page closes")
 return failures==0
func prepare_near(npc_id:String,map_id:int,label:String)->bool:
 var travel=world.quest_helper_travel
 var required_packs:Array=world._areas.area_packs(map_id)
 check(world.asset_packs.is_ready(required_packs),"Original helper target packs are already ready, keeping the existing callback inside the single pilot deadline")
 if failures:return false
 travel.cancel()
 travel.active=true
 travel.phase="request"
 travel.target={"quest_id":-1,"id":"","mode":"near"}
 var ticket:int=travel.generation
 var reply:Array=[{}]
 world.link.request({"type":"quest_visit","npc_id":npc_id,"mode":"near","client":world._client_id},func(value:Dictionary):
  reply[0]=value.duplicate(true)
  travel._visited(reply[0],ticket)
 )
 if not await pilot_wait(func():return not reply[0].is_empty(),label+" original near helper reply"):return false
 if failures:return false
 var near_target_value:Variant=reply[0].get("target",{})
 var near_target:Dictionary=near_target_value if near_target_value is Dictionary else {}
 var near_reply_clauses:Dictionary={"ok":reply[0].get("ok",false)==true,"target_dictionary":near_target_value is Dictionary,"npc_id":near_target.get("npc_id","")==npc_id,"map_id":NumericSource.same_source(near_target.get("map_id",-1),map_id),"cell_matches_authority":NumericSource.same_source(near_target.get("cell",[]),[host.automation.position_cell.x,host.automation.position_cell.y]),"authority_map_id":host.automation.position_map==map_id}
 print("PILOT_NEAR_REPLY_OBSERVATION ",JSON.stringify({"reply":reply[0].duplicate(true),"clauses":near_reply_clauses,"authority":{"map_id":host.automation.position_map,"cell":[host.automation.position_cell.x,host.automation.position_cell.y]}}))
 check(reply[0].get("ok",false) and reply[0].get("target",{}).get("npc_id","")==npc_id and NumericSource.same_source(reply[0].get("target",{}).get("map_id",-1),map_id) and NumericSource.same_source(reply[0].get("target",{}).get("cell",[]),[host.automation.position_cell.x,host.automation.position_cell.y]),"Near helper provides only disclosed ordinary setup point: "+label)
 if failures:return false
 # The raw-NPC server helper has no quest-helper menu step to call visit() with;
 # the actual response callback invokes the existing helper's production landing consumer.
 if not await pilot_wait(func():return not travel.active and travel.report_ok and NumericSource.same_source(world.data.map_id,map_id) and NumericSource.same_source(reply[0].target.cell,[world.cell.x,world.cell.y]) and host.automation.position_map==map_id and host.automation.position_cell==world.cell and not world.moving and not world.area_transition_busy,label+" existing helper consumes response, loads scene, and receives original report ack"):return false
 var ping:Dictionary=await request_world({"type":"ping"},label+" bounded real roundtrip")
 if failures or not pilot_trace_ok():return false
 check(ping.get("ok",false),"Real roundtrip completes inside setup stage")
 return failures==0
func choose_safe_source_destination()->Vector2i:
 route_search_candidates=0;route_search_queries=0;route_search_cell_visits=0;route_search_windows=0;candidate_search_windows=0;route_path_cells.clear()
 var data:Dictionary=MapFile.load_map(host.quest_helper.places.file(100))
 if not host.quest_loot.admission_terrain_valid(data):
  print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"terrain_invalid","area":56}))
  return Vector2i(-1,-1)
 route_search_map_cells=int(data.get("width",0))*int(data.get("height",0))
 if route_search_map_cells<=0 or route_search_map_cells>MAX_MAP_CELLS or world.navigation.region.get_area()!=route_search_map_cells:
  print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"map_cell_bound_or_navigation_region_mismatch","map_cells":route_search_map_cells,"max_map_cells":MAX_MAP_CELLS,"nav_region_cells":world.navigation.region.get_area()}))
  return Vector2i(-1,-1)
 var occupied:Dictionary={}
 for npc in host.quest_catalog.active_npcs():
  if int(npc.map_id)==100:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 for npc in host.quest_helper.places.residents:
  if int(npc.map_id)==100:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 var links:Dictionary=host.quest_helper.places.links(100)
 var candidates:Array[Vector2i]=[]
 for y in range(341,413):
  for x in range(621,646):
   var cell:=Vector2i(x,y)
   if host.encounter_catalog.area_at(100,cell).get("id")!=56 or not host.quest_helper.safe(data,cell,occupied,links):continue
   if links.has(cell) or not world.is_walkable(cell):continue
   candidates.append(cell)
 if candidates.size()>MAX_SOURCE_CELLS:
  print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"candidate_scan_overflow","candidate_cells":candidates.size(),"limit":MAX_SOURCE_CELLS}))
  return Vector2i(-1,-1)
 var origin:Vector2i=world.cell
 candidates.sort_custom(func(a:Vector2i,b:Vector2i)->bool:
  var da:int=absi(a.x-origin.x)+absi(a.y-origin.y)
  var db:int=absi(b.x-origin.x)+absi(b.y-origin.y)
  if da!=db:return da<db
  if a.y!=b.y:return a.y<b.y
  return a.x<b.x
 )
 var queries:=0
 route_search_candidates=candidates.size()
 route_search_cells_baseline=world.navigation.searched_cells
 route_search_searches_baseline=world.navigation.searches
 var searched_cells_before:int=route_search_cells_baseline
 var searches_before:int=route_search_searches_baseline
 for cell in candidates:
  if queries>=MAX_PATH_QUERIES:break
  if candidate_search_windows>=MAX_ASTAR_SEARCH_WINDOWS:break
  if Time.get_ticks_msec()>=pilot_deadline_ms:
   route_search_queries=queries
   route_search_candidates=candidates.size()
   print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"hard_deadline_before_next_astar","candidate_cells":route_search_candidates,"queries":route_search_queries,"query_limit":MAX_PATH_QUERIES,"searched_cells":route_search_cell_visits,"cell_visit_limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells,"stage_deadline_ms":pilot_deadline_ms,"outer_limit_ms":OUTER_MS}))
   return Vector2i(-1,-1)
  queries+=1
  route_search_queries=queries
  var candidate:Array=world.navigation.get_id_path(origin,cell)
  candidate_search_windows=world.navigation.searches-searches_before
  route_search_cell_visits=world.navigation.searched_cells-searched_cells_before
  route_search_windows=world.navigation.searches-route_search_searches_baseline
  if route_search_cell_visits>MAX_ASTAR_CELL_VISITS:
   print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"astar_cell_visit_overflow","queries":queries,"search_windows":route_search_windows,"candidate_search_windows":candidate_search_windows,"searched_cells":route_search_cell_visits,"limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells}))
   return Vector2i(-1,-1)
  if candidate_search_windows>MAX_ASTAR_SEARCH_WINDOWS or route_search_windows>MAX_ROUTE_SEARCH_WINDOWS:
   print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"astar_window_overflow","queries":queries,"search_windows":route_search_windows,"route_window_limit":MAX_ROUTE_SEARCH_WINDOWS,"candidate_search_windows":candidate_search_windows,"candidate_window_limit":MAX_ASTAR_SEARCH_WINDOWS,"searched_cells":route_search_cell_visits,"cell_visit_limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells}))
   return Vector2i(-1,-1)
  if Time.get_ticks_msec()>=pilot_deadline_ms:
   print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"hard_deadline_during_bounded_astar","candidate_cells":candidates.size(),"queries":queries,"query_limit":MAX_PATH_QUERIES,"searched_cells":route_search_cell_visits,"cell_visit_limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells,"stage_deadline_ms":pilot_deadline_ms,"outer_limit_ms":OUTER_MS}))
   return Vector2i(-1,-1)
  if candidate.is_empty() or candidate.back()!=cell or candidate.size()>MAX_ROUTE_CELLS:continue
  var crosses_portal:=false
  for route_cell in candidate:
   if links.has(route_cell):crosses_portal=true;break
  if crosses_portal:continue
  route_search_queries=queries
  route_search_candidates=candidates.size()
  route_path_cells=candidate.duplicate(true)
  return cell
 route_search_queries=queries
 route_search_candidates=candidates.size()
 print("PILOT_ROUTE_SEARCH_REJECT ",JSON.stringify({"reason":"no_reachable_safe_destination_within_bounded_queries","candidate_cells":route_search_candidates,"queries":route_search_queries,"query_limit":MAX_PATH_QUERIES,"search_windows":route_search_windows,"route_window_limit":MAX_ROUTE_SEARCH_WINDOWS,"candidate_search_windows":candidate_search_windows,"candidate_window_limit":MAX_ASTAR_SEARCH_WINDOWS,"searched_cells":route_search_cell_visits,"cell_visit_limit":MAX_ASTAR_CELL_VISITS,"map_cells":route_search_map_cells}))
 return Vector2i(-1,-1)
func continue_actual_walk(goal:Vector2i)->bool:
 var initial_map:int=int(world.data.map_id)
 check(initial_map==100 and host.automation.position_map==100,"Actual route begins on ordinary map100 after public near")
 if failures:return false
 while pilot_remaining_seconds()>0:
  if failures>0 or not pilot_trace_ok():
   check(false,"Pilot route observation remains complete during ordinary walking")
   return false
  if host.battle_open:
   if not await settle_route_battle():return false
   if not request_route_walk(goal):return false
   continue
  var reported_map:int=int(world.data.map_id)
  var projected_position:Dictionary=world.state.automation.get("position",{}).duplicate(true)
  var reported_automation_map:int=int(projected_position.get("map_id",-1))
  if reported_map!=100 or reported_automation_map!=100:
   emit_pilot_trace("PILOT_ROUTE_MAP_ASSERTION_OBSERVATION",{"clauses":{"world_data_map_is_100":reported_map==100,"client_automation_map_is_100":reported_automation_map==100},"world_data_map":reported_map,"client_automation_position":projected_position,"world_cell":[world.cell.x,world.cell.y],"authority_automation_map":host.automation.position_map,"authority_automation_cell":[host.automation.position_cell.x,host.automation.position_cell.y],"profile_location":host.session._profile.get("location",{}).duplicate(true),"player_hp":host.session._profile.get("player",{}).get("hp",-1),"player_max_hp":host.session._profile.get("player",{}).get("max_hp",-1),"battle_open":host.battle_open,"battle_state":{"active":bool(host.battle._state.get("active",false)),"outcome":str(host.battle._state.get("outcome","")),"battle_id":str(host.battle._state.get("battle_id",""))},"pending_battle_id":str(host.session._pending.get("battle_id",""))})
   check(false,"Ordinary walk never substitutes a direct map transfer")
   return false
  if world.cell==goal and not world.moving:return true
  await physics_frame
 check(false,"Actual collision walk did not reach area56 before pilot deadline")
 return false
func request_route_walk(goal:Vector2i)->bool:
 if route_walk_replans>=MAX_ROUTE_WALK_REPLANS:
  check(false,"Actual walk replans reached the fixed cap; no extra AStar route request")
  return false
 route_walk_replans+=1
 world.walk_to(goal)
 route_search_windows=world.navigation.searches-route_search_searches_baseline
 route_search_cell_visits=world.navigation.searched_cells-route_search_cells_baseline
 if route_search_windows>MAX_ROUTE_SEARCH_WINDOWS or route_search_cell_visits>MAX_ROUTE_SEARCH_CELL_VISITS:
  check(false,"Actual route planner crossed the fixed aggregate AStar search bound")
  return false
 return true

func write_load_copy(path:String,bytes:PackedByteArray,label:String)->Dictionary:
 if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
  check(false,"Independent load copy path is new: "+label)
  return {"ok":false,"path":path,"reason":"destination_exists"}
 var file:=FileAccess.open(path,FileAccess.WRITE)
 var opened:int=FileAccess.get_open_error()
 if file==null:
  check(false,"Independent load copy opens: "+label)
  return {"ok":false,"path":path,"open_error":opened}
 file.store_buffer(bytes);file.flush()
 var write_error:int=file.get_error();file.close()
 if opened!=OK or write_error!=OK:
  check(false,"Independent load copy writes/flushed exact source bytes: "+label)
  return {"ok":false,"path":path,"open_error":opened,"write_error":write_error}
 var copied:Dictionary=read_disk(path)
 if failures:return {"ok":false,"path":path,"reason":"copy_read_failed"}
 check(copied.get("ok",false) and copied.bytes==bytes,"Independent load copy readback equals exact source bytes: "+label)
 return copied

func expected_cold_ledger_from_source(profile:Dictionary,from_backup:bool)->Dictionary:
 # Independent oracle from the selected normalized source, never State.recovered.
 var expected:Dictionary=profile.quest_loot.duplicate(true)
 if expected.entries.is_empty():
  if from_backup:expected.recovery_blocked=true
  return expected
 var prior_root_blocked:bool=expected.recovery_blocked
 for key in expected.entries:
  var entry:Dictionary=expected.entries[key]
  if from_backup or prior_root_blocked or entry.recovery_blocked or entry.open_span:
   entry.open_span=false
   entry.settled_seq=entry.issued_seq
   if entry.revision<2147483647:entry.revision+=1
   entry.recovery_blocked=false
 expected.recovery_blocked=false
 return expected
func verify_loaded_budget_remainder(source:Dictionary,loaded:Dictionary,label:String)->bool:
 var original_ledger:Dictionary=source.quest_loot
 var actual_ledger:Dictionary=loaded.quest_loot
 if original_ledger.entries.is_empty():
  check(actual_ledger.entries.is_empty(),label+" empty source never manufactures an entry")
  return failures==0
 var prior:Dictionary=original_ledger.entries[State.STEP]
 var entry:Dictionary=actual_ledger.entries[State.STEP]
 for key in ["budget_id","origin_run_id","generation","limit_ms","used_ms","existing_items","new_items","saved_battles","issued_seq"]:
  check(entry[key]==prior[key],label+" retains selected-source field "+key)
  if failures:return false
 check(maxi(0,int(entry.limit_ms)-int(entry.used_ms))==maxi(0,int(prior.limit_ms)-int(prior.used_ms)),label+" remaining budget uses only selected-source stored lower bound")
 if failures:return false
 # Pure candidate exercise only: no actual restart, writer, reward or timer.
 var new_run:String="cccccccccccccccccccccccccccccccc" if prior.origin_run_id!="cccccccccccccccccccccccccccccccc" else "dddddddddddddddddddddddddddddddd"
 var acquired:Dictionary=State.acquire(actual_ledger,State.STEP,"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",new_run,180,999)
 check(acquired.get("ok",false) and acquired.get("ledger",{})==actual_ledger,label+" another run/limit/baseline cannot refresh existing budget")
 if failures:return false
 var identity:Dictionary={"budget_id":entry.budget_id,"generation":entry.generation,"revision":entry.revision}
 var opened:Dictionary=State.open(acquired.ledger,State.STEP,identity)
 if entry.used_ms>=entry.limit_ms or entry.revision>=2147483647 or entry.issued_seq>=2147483647:
  check(not opened.get("ok",false),label+" exhausted balance/counters cannot open a new span")
 else:
  var expected_open:Dictionary=actual_ledger.duplicate(true)
  expected_open.entries[State.STEP].open_span=true
  expected_open.entries[State.STEP].revision+=1
  expected_open.entries[State.STEP].issued_seq+=1
  check(opened.get("ok",false) and opened.get("ledger",{})==expected_open,label+" same-step new span changes only open/revision/issued, never limit/used/rewards")
 return failures==0
func independent_load_readback(b,primary:Dictionary,backup:Dictionary)->bool:
 if failures:return false
 for pair in [["primary",primary,false],["backup-direct",backup,false],["corrupt-primary-fallback",backup,true]]:
  var label:String=str(pair[0])
  var source:Dictionary=pair[1]
  var from_backup:bool=bool(pair[2])
  if not source.get("ok",false) or not source.get("bytes") is PackedByteArray:
   check(false,"Independent "+label+" load has a complete original source capture")
   return false
  var raw=JSON.parse_string(source.bytes.get_string_from_utf8())
  check(raw is Dictionary and b.session._valid_profile(raw),"Independent "+label+" source is a complete valid saved profile")
  if failures:return false
  check(int(raw.get("version",-1))==Session.SAVE_VERSION,"Independent "+label+" source uses the current save shape")
  if failures:return false
  var player:Dictionary=raw.get("player",{})
  var luck_time:Variant=player.get("last_luck_time",null)
  check(luck_time is int or luck_time is float,"Independent "+label+" load can pin login-luck to the source's existing timestamp")
  if failures:return false
  var stable_day:int=int(luck_time)
  var loader=Session.new(func():return stable_day)
  var copy_path:String=b.save_path+".evidence/load-"+label+".json"
  var copy:Dictionary={}
  var copy_backup:String=copy_path+".bak"
  var copy_backup_before:Dictionary={}
  if from_backup:
   # Independent corrupt-primary / exact-good-backup fallback; originals untouched.
   copy_backup_before=write_load_copy(copy_backup,source.bytes,label+" backup fallback")
   if failures or not copy_backup_before.get("ok",false):return false
   var corrupt:Dictionary=write_load_copy(copy_path,"{broken-primary".to_utf8_buffer(),"corrupt primary fixture")
   check(corrupt.get("ok",false),"Independent fallback starts with a corrupt primary and exact good backup")
   if failures:return false
   copy={"ok":true,"path":copy_path,"bytes":PackedByteArray(),"sha256":copy_backup_before.sha256,"declared":0}
  else:
   copy=write_load_copy(copy_path,source.bytes,label)
   if failures or not copy.get("ok",false):return false
   check(not FileAccess.file_exists(copy_backup) and not DirAccess.dir_exists_absolute(copy_backup),"Independent primary loader cannot fall through to another backup")
   if failures:return false
  var loaded:bool=loader.load_game(copy_path)
  check(loaded and loader.last_error.is_empty() and loader.last_load_source==("backup" if from_backup else "primary"),"Fresh Session.load_game accepts the isolated "+label+" profile")
  if failures:return false
  var expected:Dictionary=loader._normalize_numbers(raw.duplicate(true))
  var source_profile:Dictionary=expected.duplicate(true)
  var expected_ledger:Dictionary=expected_cold_ledger_from_source(source_profile,from_backup)
  check(not expected_ledger.is_empty(),"Independent "+label+" profile has a valid deterministic recovered ledger")
  if failures:return false
  expected.quest_loot=loader._normalize_numbers(expected_ledger)
  var actual:Dictionary=loader._profile.duplicate(true)
  check(actual==expected,"Fresh "+label+" load preserves the complete v8 profile; only numeric normalization and independently specified cold retirement are expected")
  if failures:return false
  var copy_after:Dictionary=read_disk(copy_path)
  if failures or not copy_after.get("ok",false):return false
  var copy_after_profile=JSON.parse_string(copy_after.bytes.get_string_from_utf8())
  check(copy_after_profile is Dictionary and loader._valid_profile(copy_after_profile),"Isolated "+label+" load copy remains a complete valid save after GameSession.load_game")
  if failures:return false
  check(loader._normalize_numbers(copy_after_profile)==actual,"The isolated "+label+" post-load bytes represent the entire loaded profile")
  if failures:return false
  if from_backup:
   check(loader._normalize_numbers(copy_after_profile.quest_loot)==expected_ledger,"Independent selected-backup cold ledger is durably written only to isolated load copy")
   if failures:return false
   var copy_backup_after:Dictionary=read_disk(copy_backup)
   if failures or not copy_backup_after.get("ok",false):return false
   check(copy_backup_after.bytes==source.bytes and copy_backup_after.sha256==source.sha256,"Fallback backup source bytes remain exact after GameSession.load_game")
   if failures:return false
  elif expected_ledger==loader._normalize_numbers(raw.duplicate(true)).quest_loot:
   check(copy_after.bytes==source.bytes and copy_after.sha256==source.sha256,"Current primary load is read-only and leaves its isolated source copy byte-identical")
   if failures:return false
  if not from_backup and expected_ledger!=loader._normalize_numbers(raw.duplicate(true)).quest_loot:
   var rotated_copy:Dictionary=read_disk(copy_backup)
   if failures:return false
   check(rotated_copy.get("ok",false) and rotated_copy.bytes==source.bytes,"Direct backup load with open span rotates only its own original copy while durably retiring that selected generation")
   if failures:return false
  check(actual.get("original_items",[])==expected.get("original_items",[]) and actual.get("original_instances",[])==expected.get("original_instances",[]),"Independent "+label+" load preserves every original item and UID instance")
  if failures:return false
  check(actual.get("quest_loot",{})==expected.get("quest_loot",{}),"Independent "+label+" load preserves the complete ledger with only independently specified span/revision retirement")
  if failures:return false
  if from_backup:
   check(actual.quest_loot==expected_ledger and (actual.quest_loot.recovery_blocked if source_profile.quest_loot.entries.is_empty() else not actual.quest_loot.recovery_blocked),"Fallback empty history stays blocked; known budget retires without refresh")
   if failures:return false
  elif label=="primary":
   check(not actual.quest_loot.entries.get(State.STEP,{}).get("open_span",true),"Primary load reads the naturally closed final span")
   if failures:return false
  if not verify_loaded_budget_remainder(source_profile,actual,label):return false
  print("PILOT_LOAD_READBACK ",JSON.stringify({"source":label,"source_sha256":source.sha256,"source_length":source.declared,"copy_before_load_sha256":copy.sha256,"copy_backup_before_load_sha256":copy_backup_before.get("sha256",""),"loaded":loaded,"full_profile_equal":actual==expected,"item_count":actual.get("original_items",[]).size(),"uid_count":actual.get("original_instances",[]).size(),"ledger":actual.get("quest_loot",{}),"last_error":loader.last_error}))
  if failures:return false
 var primary_after:Dictionary=read_disk(b.save_path)
 if failures:return false
 var backup_after:Dictionary=read_disk(b.save_path+".bak")
 if failures:return false
 check(primary_after.get("ok",false) and primary_after.bytes==primary.bytes and primary_after.sha256==primary.sha256,"Independent load never changes the original primary bytes")
 if failures:return false
 check(backup_after.get("ok",false) and backup_after.bytes==backup.bytes and backup_after.sha256==backup.sha256,"Independent load never changes the original backup bytes")
 return failures==0
func settle_route_battle()->bool:
 route_battle_count+=1
 var reached_route_battle_limit:bool=route_battle_count>=MAX_ROUTE_BATTLES
 var state:Dictionary=host.battle._state.duplicate(true)
 var battle_id:String=str(state.get("battle_id",""))
 check(not battle_id.is_empty() and state.get("active",false),"Route encounter is a real active original battle")
 if failures:return false
 var turns:=0
 while bool(host.battle._state.get("active",false)) and pilot_remaining_seconds()>0 and turns<100:
  var live:Dictionary=host.battle._state.duplicate(true)
  var target:=-1
  for index in range(live.get("enemies",[]).size()):
   if int(live.enemies[index].get("hp",0))>0:target=index;break
  if target<0:break
  var reply:Dictionary=await request_world({"type":"battle_command","action":"attack","target":target},"Original route battle attack")
  if failures:return false
  var reply_state:Dictionary=reply.get("state",{})
  var battle_state:Dictionary=host.battle._state
  var attack_observed:bool=emit_pilot_trace("PILOT_ROUTE_ATTACK_OBSERVATION",{"battle_id":battle_id,"reply_ok":bool(reply.get("ok",false)),"reply_state":{"active":bool(reply_state.get("active",false)),"outcome":str(reply_state.get("outcome","")),"player_hp":int(reply_state.get("player_hp",-1)),"battle_id":str(reply_state.get("battle_id",""))},"authority_state":{"active":bool(battle_state.get("active",false)),"outcome":str(battle_state.get("outcome","")),"player_hp":int(battle_state.get("player_hp",-1)),"battle_id":str(battle_state.get("battle_id",""))},"battle_open":host.battle_open,"profile_location":host.session._profile.get("location",{}).duplicate(true),"player_hp":host.session._profile.get("player",{}).get("hp",-1),"player_max_hp":host.session._profile.get("player",{}).get("max_hp",-1)})
  check(attack_observed,"Attack observation fits the bounded pilot trace")
  if failures:return false
  check(reply.get("ok",false),"Original battle attack command accepted")
  if failures:return false
  turns+=1
 var finished:bool=not bool(host.battle._state.get("active",false))
 check(finished and host.battle._state.get("outcome","")=="win","Original route battle wins without escape/forced result; defeat preserves disk without test close")
 if failures:return false
 var closed:Dictionary=await request_world({"type":"battle_close","battle_id":battle_id},"Original route battle close")
 if failures:return false
 var closed_state:Dictionary=host.battle._state
 var close_observed:bool=emit_pilot_trace("PILOT_ROUTE_CLOSE_OBSERVATION",{"battle_id":battle_id,"reply":closed.duplicate(true),"raw_combat_state":{"active":bool(closed_state.get("active",false)),"outcome":str(closed_state.get("outcome","")),"player_hp":int(closed_state.get("player_hp",-1)),"battle_id":str(closed_state.get("battle_id",""))},"backend_result_view":{"active":bool(host.battle_state.get("active",false)),"outcome":str(host.battle_state.get("outcome","")),"settled":bool(host.battle_state.get("settled",false)),"settlement_error":str(host.battle_state.get("settlement_error","")),"battle_id":str(host.battle_state.get("battle_id",""))},"battle_open":host.battle_open,"pending_battle_id":str(host.session._pending.get("battle_id","")),"profile_location":host.session._profile.get("location",{}).duplicate(true),"player_hp":host.session._profile.get("player",{}).get("hp",-1),"player_max_hp":host.session._profile.get("player",{}).get("max_hp",-1),"authority_automation_map":host.automation.position_map,"authority_automation_cell":[host.automation.position_cell.x,host.automation.position_cell.y]})
 check(close_observed,"Close observation fits the bounded pilot trace")
 if failures:return false
 check(closed.get("ok",false) and not host.battle_open and host.session._pending.is_empty(),"Original route battle settles and closes normally")
 if failures:return false
 if reached_route_battle_limit:
  check(false,"Twenty route encounters reached; do not issue another walk replan or start another route battle")
  return false
 return failures==0
func expected_profile_after_original_save(profile:Dictionary)->Dictionary:
 var expected:Dictionary=profile.duplicate(true)
 var owner:Dictionary=expected.get("player",{}).duplicate(true)
 var equipment:Dictionary=OriginalEquipment.mods(expected)
 owner.charm=clampi(int(owner.get("charm",60))+int(equipment.get("charm",0)),0,100)
 for owned in expected.get("pets",[])+expected.get("pet_storage",[]):
  if owned.has("variable_ai"):
   PetLoyalty.refresh(owned,owner,int(owner.get("transmigration",0)))
 return expected

func expected_existing_starter_growth(profile:Dictionary,pet_id:String,target:int)->Dictionary:
 var expected:Dictionary=profile.duplicate(true)
 var index:=-1
 for i in range(expected.get("pets",[]).size()):
  if str(expected.pets[i].get("pet_id",""))==pet_id:index=i;break
 if index!=0:return {}
 var source_pet:Dictionary=expected.pets[index].duplicate(true)
 var projected:Dictionary=PetProgression.project_pet(source_pet,target)
 if projected.is_empty():return {}
 for level in range(int(source_pet.get("level",1))+1,target+1):
  PetLoyalty.add_variable(projected,PetLoyalty.AI_PET_LEVEL_UP)
 projected.level=target
 projected.xp=0
 projected.hp=projected.max_hp
 projected.skill_unlocked=not projected.get("learned_skills",[]).is_empty()
 expected.pets[index]=projected
 return expected_profile_after_original_save(expected)

func prepare_existing_starter_pet()->bool:
 if failures:return false
 if Time.get_ticks_msec()>=pilot_deadline_ms or host.battle_open or not host.session._pending.is_empty():
  check(false,"Existing-starter preparation begins before the shared deadline and outside battle/receipt")
  return false
 var before:Dictionary=host.session._profile.duplicate(true)
 var expected_ids:Array=["pet-1","pet-2","pet-3"]
 var expected_species:Array=["blue_dragon","golden_tiger","red_rex"]
 var roster_ok:bool=host.session._valid_profile(before) and bool(before.get("default_companions_claimed",false)) and bool(before.get("gm_modified",false)) and bool(before.get("player",{}).get("gm_modified",false)) and before.get("pet_storage",[]).is_empty() and int(before.get("active_pet",-2))==-1 and int(before.get("next_pet_id",0))==4 and before.get("pets",[]).size()==3
 if roster_ok:
  for i in range(3):
   if str(before.pets[i].get("pet_id",""))!=expected_ids[i] or str(before.pets[i].get("species",""))!=expected_species[i] or before.pets[i].has("gm_modified") or not before.pets[i].has("growth_seed") or not before.pets[i].has("growth_weights") or not before.pets[i].has("base_stats"):roster_ok=false
 check(roster_ok,"Freeze the three actual remote-GameScene default companions before route walking; no added/deleted pet")
 if failures:return false
 var expected_level:Dictionary=expected_existing_starter_growth(before,"pet-1",Session.MAX_LEVEL)
 check(not expected_level.is_empty() and host.session._valid_profile(expected_level),"Original seeded Progression projection describes only legal pet-1 level growth plus save-time loyalty refresh")
 if failures:return false
 if not checked_pilot_disk(host,"before-starter-growth"):return false
 var level_serial:int=host.quest_save_serial
 var level_reply:Dictionary=await request_world({"type":"level_pet_to","pet_id":"pet-1","target":Session.MAX_LEVEL},"Original owned starter pet level_pet_to request")
 if failures:return false
 if Time.get_ticks_msec()>=pilot_deadline_ms:
  check(false,"Shared outer deadline remains before any later pet-preparation action")
  return false
 check(level_reply.get("ok",false)==true and str(level_reply.get("type",""))=="ack" and not level_reply.get("pending",false) and host.quest_save_serial==level_serial+1 and not host.battle_open and host.session._pending.is_empty(),"Wait for the actual level_pet_to server ACK and its original save boundary; do not treat SessionClient's pending bool as completion")
 if failures:return false
 var after_level:Dictionary=host.session._profile.duplicate(true)
 check(after_level==expected_level,"Complete post-ACK profile equals the fixed pet-1 seeded-growth projection and source-defined save refresh")
 if failures:return false
 if not checked_pilot_disk(host,"starter-growth-ack"):return false
 var expected_selected:Dictionary=expected_level.duplicate(true)
 expected_selected.active_pet=0
 expected_selected=expected_profile_after_original_save(expected_selected)
 var select_serial:int=host.quest_save_serial
 var select_reply:Dictionary=await request_world({"type":"select_pet","index":0},"Original select_pet request for fixed pet-1 index")
 if failures:return false
 if Time.get_ticks_msec()>=pilot_deadline_ms:
  check(false,"Shared outer deadline remains before checkpoint/disk verification")
  return false
 check(select_reply.get("ok",false)==true and str(select_reply.get("type",""))=="ack" and not select_reply.get("pending",false) and host.quest_save_serial==select_serial+1 and not host.battle_open and host.session._pending.is_empty(),"Wait for the actual select_pet server ACK and original save boundary")
 if failures:return false
 var after_select:Dictionary=host.session._profile.duplicate(true)
 check(after_select==expected_selected and host.session._valid_profile(after_select),"Complete post-selection profile changes only pet-1 growth/selection and save-derived loyalty fields")
 if failures:return false
 if not checked_pilot_disk(host,"starter-selection-ack"):return false
 if not await checkpoint_world("Persist original starter-pet growth and selection through checkpoint"):return false
 if failures:return false
 check(host.session._profile.duplicate(true)==expected_selected,"Original checkpoint adds no unrelated profile mutation")
 if failures:return false
 if not await checked_pilot_disk(host,"original-starter-pet-growth-selected"):return false
 if failures:return false
 if not emit_pilot_trace("PILOT_EXISTING_STARTER_PET_PREP",{"target_pet_id":"pet-1","target_species":"blue_dragon","target_level":Session.MAX_LEVEL,"level_reply":level_reply,"select_reply":select_reply,"baseline":before,"expected_after_level":expected_level,"actual_after_level":after_level,"expected_after_select":expected_selected,"actual_after_select":after_select,"quest_save_serial_after":host.quest_save_serial,"checkpoint_ack":true,"primary_cache_verified":true,"growth_source":"GameSession.level_pet_to via normal _gain_xp/Progression.grow_pet; declared fixture convenience"}):return false
 return failures==0


func authenticated_setup()->bool:
 check(not DirAccess.dir_exists_absolute(ACCEPTANCE_ROOT),"Fresh one-run account directory; never delete/reuse an old result")
 if failures:return false
 check(DirAccess.make_dir_recursive_absolute(ACCEPTANCE_ROOT)==OK,"Create isolated account directory")
 if failures:return false
 hub=NaturalHub.new(ACCEPTANCE_ROOT+"/accounts.json")
 hub.share_dir="" # No live fast-hunt registry; ordinary Hub ticking/resume stays on.
 root.add_child(hub)
 check(hub.start(),"Real Hub loads fresh isolated Accounts")
 if failures:return false
 var created:Dictionary=hub.accounts.create("NaturalPilot","3141",false)
 check(created.get("ok",false) and created.get("entry",{}) is Dictionary,"Original Accounts creates isolated PIN profile")
 if failures:return false
 profile_id=str(created.entry.id)
 var path:String=hub.accounts.save_path(created.entry)
 if not fresh_paths(path):return false
 check(hub.open_profile(profile_id).is_empty(),"Real Hub factory opens fresh profile and SaveLock")
 if failures:return false
 host=hub.backends.get(profile_id)
 check(host is NaturalBackend and host.save_path==path and SaveLockType.holder_pid(path)==OS.get_process_id() and host.admin and host.is_processing() and host.automation.auto_tick and host.keep_resume_current,"Hub owns the live original processing/admin/save/resume contract")
 if failures:return false
 check(host.open_evidence(ACCEPTANCE_ROOT+"/events.jsonl"),"Open new bounded append-only event evidence")
 if failures:return false
 check(Backend.QUEST_LOOT_PUBLIC_ENABLED==false and host._quest_loot_public_enabled(),"Production false; sole immutable test getter controls both projection and admission")
 if failures:return false
 emit_pilot_trace("ACCEPTANCE_FIRST_RNG",{"encounter_seed":host.initial_encounter_seed,"encounter_state":host.initial_encounter_state,"current_encounter_state":str(host.encounter_rng.state),"no_seed_assignment":true})
 if failures:return false
 server=Server.new(hub,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK and server.hub==hub and server.backend==null,"Actual isolated authenticated WS server on port zero")
 if failures:return false
 Game.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();Game.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path=ACCEPTANCE_ROOT+"/viewer.cfg";root.add_child(world)
 if not await pilot_wait(func():return world.link.awaiting_login and is_instance_valid(world.login_screen) and world.login_screen.visible,"Actual PIN LoginScreen"):return false
 # This is the shipped screen's selection/submit path, not a direct Hub login.
 var choice=world.login_screen.find_child("Profile_NaturalPilot",true,false)
 check(choice is Button and not choice.disabled,"Real profile button exists")
 if failures:return false
 choice.pressed.emit()
 world.login_screen.pin.text="3141"
 check(not world.login_screen.login_button.disabled,"Real PIN submit enabled")
 if failures:return false
 world.login_screen.login_button.pressed.emit()
 if not await pilot_wait(func():return world.link.online and not world.data.is_empty() and not world.area_transition_busy and host.session._profile.get("default_companions_claimed",false),"Authenticated snapshot and original default three companions"):return false
 var peers:Array=hub.connections_of(profile_id)
 check(peers.size()==1 and peers[0] is int,"One actual accepted peer maps to the authenticated profile")
 if failures:return false
 accepted_peer_id=int(peers[0]);accepted_binding=host._fee_bindings.get(accepted_peer_id)
 host.expected_client_id=world._client_id
 check(auth_owner_current() and world.backend==null and not world.link.is_local() and not world.link.login_token.is_empty() and world.link.account.get("name")=="NaturalPilot" and world.state.quest_loot_enabled(),"Real PIN/token/Hub/backend/binding chain and strict capability projection")
 if failures:return false
 if not await checkpoint_world("Post-login original default companion checkpoint"):return false
 if not checked_pilot_disk(host,"authenticated-default-companions"):return false
 var level:Dictionary=await request_world({"type":"gm_raise_level","index":-1,"target":120},"Disclosed original GM120 request")
 check(level.get("ok",false) and level.get("type")=="ack" and host.session._profile.player.stat_points==357,"Real GM120 ACK grants 357 ordinary points")
 if failures:return false
 if not checked_pilot_disk(host,"gm120-ack"):return false
 var before:Dictionary=host.session._profile.duplicate(true)
 var allocation:Dictionary=await request_world({"type":"distribute_stats","stats":["vitality","toughness"]},"Original V/T allocation request")
 check(allocation.get("ok",false) and allocation.get("type")=="ack","Original stat allocation ACK")
 if failures:return false
 var after:Dictionary=host.session._profile.duplicate(true)
 check(after.player.allocated_stats=={"vitality":179,"strength":0,"toughness":178,"dexterity":0} and after.player.stat_points==0 and after.player.base_stats=={"vitality":18800,"strength":700,"toughness":17800,"dexterity":400} and after.player.hp==941 and after.player.max_hp==941 and after.player.attack==43 and after.player.defence==197 and after.player.speed==4,"Pinned original GM120 V179/T178 derived stats")
 if failures:return false
 var before_rest:Dictionary=before.duplicate(true)
 var after_rest:Dictionary=after.duplicate(true)
 for profile in [before_rest,after_rest]:
  for field in ["allocated_stats","base_stats","stat_points","hp","max_hp","attack","defence","speed"]:profile.player.erase(field)
 check(before_rest==after_rest,"Full allocation profile differs only in original derived/stat fields")
 if failures:return false
 return checked_pilot_disk(host,"allocation-ack")

func auth_owner_current()->bool:
 if not is_instance_valid(hub) or not is_instance_valid(host) or not is_instance_valid(world) or not is_instance_valid(server):return false
 if hub.profile_of(accepted_peer_id)!=profile_id or not is_same(hub.backend_of(accepted_peer_id),host) or not is_same(host._fee_bindings.get(accepted_peer_id),accepted_binding) or accepted_binding==null:return false
 if not world.link.online or not is_instance_valid(world.link._peer) or world.link._peer.get_ready_state()!=WebSocketPeer.STATE_OPEN or world.link._peer.get_instance_id()==accepted_peer_id:return false
 for peer in server.clients():
  if peer.get_instance_id()==accepted_peer_id:return peer.get_ready_state()==WebSocketPeer.STATE_OPEN
 return false

func open_authenticated_e1()->bool:
 var overrides:Dictionary=host.session.automation_settings()
 var quest_override:Variant=overrides.get("quest",{})
 check(auth_owner_current() and quest_override is Dictionary and not quest_override.has("loot_minutes"),"Fresh profile has no explicit quest.loot_minutes override; no preference request was sent")
 if failures:return false
 var effective:Dictionary=Settings.effective(overrides)
 check(effective.get("loot_minutes") is int and effective.loot_minutes==30 and effective.loot_minutes*60000==ACTIVE_MS,"Original server settings API returns top-level default loot_minutes=30 / 1800000ms")
 if failures:return false
 var reply:Dictionary=await request_world({"type":"quest_loot_start"},"Actual authenticated public quest_loot_start ACK")
 if failures:return false
 var record:Dictionary=host.e1_record
 var wire_body:Dictionary=reply.duplicate(true)
 check(wire_body.get("reply",false)==true,"Real WS reply marker")
 if failures:return false
 wire_body.erase("reply")
 check(reply.get("ok",false) and reply.get("persisted",false) and reply.get("type")=="ack" and wire_body==record.get("reply",{}),"Actual wire ACK equals the original durable handler result")
 if failures:return false
 var run:Dictionary=record.reply.get("run_identity",{})
 var budget:Dictionary=record.reply.get("budget_identity",{})
 check(not run.is_empty() and not budget.is_empty() and record.command.get("_quest_connection")==accepted_peer_id and record.binding_current and auth_owner_current(),"Server-injected peer/binding owns both returned identities")
 if failures:return false
 var acquired:Dictionary=State.acquire(record.before.quest_loot,State.STEP,str(budget.budget_id),str(run.run_id),30,0)
 check(acquired.get("ok",false),"Independent E1 acquire from pre-handler ledger and returned IDs")
 if failures:return false
 var opened:Dictionary=State.open(acquired.ledger,State.STEP,State.identity(acquired.ledger.entries[State.STEP]))
 check(opened.get("ok",false),"Independent E1 open candidate")
 if failures:return false
 var expected:Dictionary=record.before.duplicate(true);expected.quest_loot=opened.ledger
 var prior:Dictionary=record.before.duplicate(true);prior.quest_loot=acquired.ledger
 var primary:Dictionary=ProfileCompare.validated_copy(host.session,record.primary.bytes.get_string_from_utf8())
 var backup:Dictionary=ProfileCompare.validated_copy(host.session,record.backup.bytes.get_string_from_utf8())
 check(record.after==expected and primary.get("ok",false) and primary.profile==host.session._normalize_numbers(expected.duplicate(true)) and backup.get("ok",false) and backup.profile==host.session._normalize_numbers(prior.duplicate(true)) and record.primary.bytes.get_string_from_utf8()==record.cache and record.serial_after==record.serial_before+2 and record.writer_after==record.writer_before+2,"Full E1 acquire/open two-write oracle and primary/previous-generation backup match")
 if failures:return false
 var entry:Dictionary=record.after.quest_loot.entries[State.STEP]
 check(entry.limit_ms==ACTIVE_MS and entry.open_span and State.identity(entry)==budget and entry.origin_run_id==run.run_id and entry.generation==0,"Default 1800000ms E1 budget and generation match durable ACK")
 if failures:return false
 e1_anchor=int(record.anchor_ms)
 check(e1_anchor>=pilot_started_ms and e1_anchor<pilot_started_ms+SETUP_MS,"E1 begins within setup hard limit")
 return failures==0

func finished_original_run()->bool:
 return not host.quest_auto.running and not host.battle_open and host.session._pending.is_empty() and host.session._loot_settlement.is_empty()

func final_oracles()->bool:
 if not checked_pilot_disk(host,"natural-final") or not archive_pair(host,"natural-final"):return false
 var primary:Dictionary=host._capture_disk(host.save_path)
 var backup:Dictionary=host._capture_disk(host.save_path+".bak")
 check(primary.get("ok",false) and backup.get("ok",false) and primary.bytes.get_string_from_utf8()==host.disk_primary_expected and backup.bytes.get_string_from_utf8()==host.disk_backup_expected,"Final primary and backup match their separately observed actual writer generations")
 if failures:return false
 if not independent_load_readback(host,primary,backup):return false
 var received:=0
 var uids:Array=[]
 for row in host.closed_receipts:
  received+=int(row.received_target)
  for uid in row.received_target_uids:
   check(not uids.has(uid),"Each received target has a unique original UID")
   if failures:return false
   uids.append(uid)
 var entry:Dictionary=host.session._profile.quest_loot.entries[State.STEP]
 check(host.settlement_commits.size()==host.retired_battles.size() and host.retired_battles.size()==host.closed_receipts.size() and entry.saved_battles==host.settlement_commits.size() and entry.new_items==received and not entry.open_span and finished_original_run(),"Exactly-once receipt settlement/retirement/closed span ledger")
 if failures:return false
 var actual_uids:Array=[]
 for item in host.session._profile.original_instances:
  if int(item.get("item_id",-1))==2760:actual_uids.append(int(item.uid))
 check(actual_uids==uids and host.session._profile.original_items.count(2760)==received,"Actual original inventory and complete ordered UID instances match only received terminal drops")
 if failures:return false
 var attempts_ok:bool=host.field_steps.size()==host.pilot_attempt_count and host.pilot_attempt_count>0 and host.pilot_attempt_count<=ATTEMPTS_LIMIT
 for attempt in host.field_steps:
  if attempt.map!=100 or attempt.area!=56:attempts_ok=false
  if attempt.reply.get("battle",false) and (attempt.receipt.is_empty() or str(attempt.pending_battle_id)!=str(attempt.receipt.get("ledger",{}).get("battle_id",""))):attempts_ok=false
 check(attempts_ok,"Every natural public E2 field_step is source-area and receipt attributed")
 if failures:return false
 var p3_proven:bool=host.quest_loot.accepted_active>0 and host.quest_loot.owner_accepts>0 and host.p3_publications>0 and host.p3_queued.is_empty()
 var sampled_settled:=false
 for battle_id in host.quest_loot.sample_ids:
  if host.closed_receipts.any(func(row):return row.battle_id==battle_id):sampled_settled=true
 p3_proven=p3_proven and sampled_settled
 var target_proven:bool=received>0 and Plan.select(host,Sources.matches_backend).get("status")=="done"
 check(received>0 or int(entry.used_ms)>=ACTIVE_MS,"Zero target can be TARGET_UNPROVEN only after the original full default budget naturally completes")
 if failures:return false
 check(pilot_trace_ok() and Time.get_ticks_msec()<pilot_deadline_ms,"Final oracle stays within evidence and verification hard limits")
 if failures:return false
 var summary:Dictionary={"result":"PASS" if target_proven and p3_proven else "UNPROVEN","target":"PROVEN" if target_proven else "TARGET_UNPROVEN","p3":"PROVEN" if p3_proven else "P3_NATURAL_UNPROVEN","received_2760":received,"target_uids":uids,"attempts":host.pilot_attempt_count,"route_battles":route_battle_count,"e1_saved_battles":entry.saved_battles,"budget_limit_ms":entry.limit_ms,"budget_used_ms":entry.used_ms,"e1_anchor_ms":e1_anchor,"elapsed_ms":Time.get_ticks_msec()-pilot_started_ms,"p3_samples":host.quest_loot.accepted_active,"p3_publications":host.p3_publications,"primary_sha256":primary.sha256,"backup_sha256":backup.sha256,"primary_and_backup_may_differ":true,"event_bytes":host.trace_output_bytes,"event_count":host.trace_count,"blob_bytes_by_class":host.evidence.charged.duplicate(),"unique_blobs":host.evidence.index.size(),"run_once_no_retry":true,"setup_conveniences":["original remote default three companions","original GM120","original V179/T178 allocation","fixed pet-1 original level_pet_to120/select_pet0","original near scholar and GENOU; last collision leg only"],"rendered_pixels_proven":false,"cpu":"UNKNOWN","external_watchdog_exit":"record separately by approved supervisor"}
 check(emit_pilot_trace("ACCEPTANCE_RESULT",summary),"Persist complete independent result categories")
 if failures:return false
 print("NATURAL_ACCEPTANCE_RESULT ",JSON.stringify(summary))
 # No disconnect/stop/save here: preserve observed final bytes. Process exit is
 # the supervisor's normal completion; no shutdown writer can improve the evidence.
 quit(0 if target_proven and p3_proven else 3)
 return true

func run()->void:
 pilot_started_ms=Time.get_ticks_msec();pilot_deadline_ms=pilot_started_ms+SETUP_MS
 check(OS.get_cmdline_user_args().is_empty(),"Fixed single-run protocol accepts no seed/mode/budget arguments")
 if failures:quit(1);return
 if not await authenticated_setup():quit(1);return
 if not await prepare_near(SCHOLAR,6000,"Scholar prerequisite convenience"):quit(1);return
 var scholar:Dictionary=host.original_quests.npc_by_id(SCHOLAR)
 check(not scholar.is_empty() and scholar.map_id==6000 and NumericSource.same_source(scholar.cell,[58,44]) and scholar.source_script=="extra/event/hougyoku","Frozen scholar source identity")
 if failures:quit(1);return
 check(scholar.branches[1].type=="REQUEST" and scholar.branches[1].condition=="LV>59" and scholar.branches[1].actions=={"GetItem":"2764*1"},"Original scholar REQUEST=yes is the only 2764 grant")
 if failures:quit(1);return
 if not await original_yes_end(SCHOLAR,"Scholar 2764 prerequisite"):quit(1);return
 check(host.session._profile.original_items.count(2764)==1 and Rules.flag(host.session._profile,"now",45) and host.session._profile.original_instances.any(func(row):return int(row.get("item_id",-1))==2764),"Actual saved original REQUEST grants one UID-backed 2764 and NOW45")
 if failures:quit(1);return
 if not await checkpoint_world("Persist actual scholar completion"):quit(1);return
 var before_mhasah:Dictionary=host.session._profile.duplicate(true)
 if not await prepare_near(GENOU,100,"Map100 Mhasah setup convenience"):quit(1);return
 check(before_mhasah.original_items.count(2764)==1 and host.session._profile.original_items.count(2764)==1 and host.session._profile.original_instances==before_mhasah.original_instances,"Second near setup grants no source proof or item")
 if failures:quit(1);return
 if not await checkpoint_world("Persist actual map100 starting cell"):quit(1);return
 if not await prepare_existing_starter_pet():quit(1);return
 var position_start:Vector2i=world.cell
 route_destination=choose_safe_source_destination()
 check(route_destination.x>=0 and host.automation.position_map==100 and host.automation.position_cell==position_start and host.encounter_catalog.area_at(100,route_destination).get("id")==56,"Safe reachable area56 destination chosen from actual map collision/path data")
 if failures:quit(1);return
 check(world.random_encounters and not host.session._profile.no_random_encounters,"Original map walking encounters remain enabled; no safe bypass")
 if failures:quit(1);return
 route_report_start=host.route_reports.size()
 host.route_trace_enabled=true
 check(emit_pilot_trace("PILOT_ROUTE_START",{"map":100,"from":[position_start.x,position_start.y],"to":[route_destination.x,route_destination.y],"area":host.encounter_catalog.area_at(100,route_destination),"route_cells":route_path_cells.map(func(cell):return [cell.x,cell.y]),"map_cells":route_search_map_cells,"astar_queries":route_search_queries,"candidate_search_windows":candidate_search_windows,"astar_search_windows":route_search_windows,"astar_searched_cells":route_search_cell_visits,"candidate_cells":route_search_candidates,"candidate_scan_limit":MAX_SOURCE_CELLS,"astar_query_limit":MAX_PATH_QUERIES,"candidate_window_limit":MAX_ASTAR_SEARCH_WINDOWS,"route_window_limit":MAX_ROUTE_SEARCH_WINDOWS,"candidate_cell_visit_limit":MAX_ASTAR_CELL_VISITS,"route_cell_visit_limit":MAX_ROUTE_SEARCH_CELL_VISITS,"route_replan_limit":MAX_ROUTE_WALK_REPLANS,"route_battle_limit":MAX_ROUTE_BATTLES,"near_convenience":GENOU,"near_not_route_proof":true}),"Complete bounded route evidence fits output limit")
 if failures:quit(1);return
 if not request_route_walk(route_destination):quit(1);return
 if not await continue_actual_walk(route_destination):quit(1);return
 check(world.cell==route_destination and host.automation.position_map==100 and host.automation.position_cell==route_destination,"Every final route cell arrived through normal report_position/field_step authority")
 if failures:quit(1);return
 var route_reports:Array=host.route_reports.slice(route_report_start)
 var route_reports_valid:bool=not route_reports.is_empty()
 for row in route_reports:
  var command:Dictionary=row.command
  var authority:Dictionary=row.authority
  if not bool(row.get("reply_ok",false)) or bool(command.get("map_changed",false)) or not NumericSource.same_source(command.get("map_id",-1),100) or not NumericSource.same_source(authority.get("map",-1),100) or not NumericSource.same_source(command.get("cell",[]),authority.get("cell",[])):route_reports_valid=false
 var final_route_report_matches:bool=not route_reports.is_empty() and NumericSource.same_source(route_reports.back().authority.cell,[route_destination.x,route_destination.y])
 check(route_reports_valid and final_route_report_matches,"Every post-start route report was an ordinary same-map position accepted at the identical backend cell")
 if failures:quit(1);return
 if not await checkpoint_world("Persist actual walked source-area checkpoint"):quit(1);return
 check(host.encounter_catalog.area_at(100,host.automation.position_cell).get("id")==56 and host.session._profile.original_items.count(2764)==1 and not host.session._profile.original_items.has(2760) and host.session._valid_profile(host.session._profile),"Actual area56, original prerequisite and complete native/cache baseline before E1")
 if failures:quit(1);return
 if not checked_pilot_disk(host,"source-before-open"):quit(1);return
 if not archive_pair(host,"source-before-open"):quit(1);return
 if not await open_authenticated_e1():quit(1);return
 stage="natural-active"
 pilot_deadline_ms=mini(pilot_started_ms+OUTER_MS,e1_anchor+ACTIVE_MS+SETTLEMENT_MS)
 var outstanding_battle:=""
 var outstanding_since:=-1
 while Time.get_ticks_msec()<pilot_deadline_ms:
  if not pilot_trace_ok():check(false,"Passive observation/evidence failed; preserve original disk");quit(1);return
  if not auth_owner_current():check(false,"Authenticated owner/peer/binding changed during natural run");quit(1);return
  if host.pilot_attempt_count>ATTEMPTS_LIMIT:check(false,"Natural attempt monitor exceeded 3601; no Stop/save rescue");quit(1);return
  var battle_id:String=str(host.session._pending.get("battle_id",""))
  if battle_id.is_empty() and (host.battle_open or not host.session._loot_settlement.is_empty()):battle_id=str(host.battle._state.get("battle_id","unidentified-open-obligation"))
  if not battle_id.is_empty() and battle_id!=outstanding_battle:
   outstanding_battle=battle_id;outstanding_since=Time.get_ticks_msec()
  if not battle_id.is_empty() and Time.get_ticks_msec()-outstanding_since>=SETTLEMENT_MS:
   check(false,"UNCOMPLETE original battle exceeded 180s settlement hard limit");quit(1);return
  if not host.retired_battles.is_empty() and host.retired_battles.back().get("outcome","")!="win":
   check(false,"Natural battle did not end in original victory; no recovery fixture");quit(1);return
  if finished_original_run():break
  if Time.get_ticks_msec()>=e1_anchor+ACTIVE_MS:stage="original-settlement"
  await physics_frame
 check(finished_original_run() and Time.get_ticks_msec()<pilot_deadline_ms,"UNCOMPLETE active/settlement stage hard limit; original pending receipt is preserved")
 if failures:quit(1);return
 stage="verification"
 pilot_deadline_ms=mini(pilot_started_ms+OUTER_MS,Time.get_ticks_msec()+VERIFY_MS)
 if not final_oracles():quit(1);return

func archive_pair(b,stage_name:String)->bool:
 for suffix in ["", ".bak"]:
  var captured:Dictionary=read_disk(b.save_path+suffix)
  if failures:return false
  var reference:Dictionary=b._archive_commit_bytes(stage_name+(".primary" if suffix.is_empty() else ".backup"),captured.bytes,captured.sha256)
  check(reference.get("ok",false),"Complete primary/backup content-addressed archive: "+stage_name+suffix)
  if failures:return false
 return true
