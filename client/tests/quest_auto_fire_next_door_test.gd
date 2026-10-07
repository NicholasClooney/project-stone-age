extends SceneTree
## UNRUN draft. Same Backend real adult, stop/return, then first original Nav-selected door only.
const Rules=preload("res://server/original_quests.gd")
const Wait=preload("res://tests/support/wait.gd")
const Progression=preload("res://server/progression.gd")
const SAVE="user://fire-real-next-door.json"
const TRACE="user://fire-real-next-door-trace.json"
const CLIENT="fire-next-door"
const MAX_POINTS=6000
const Nav=preload("res://server/quest_auto_navigation.gd")
const Fire=preload("res://server/quest_auto_spirit_fire_plan.gd")
const NEXT_SOURCE_PATH="res://tests/fixtures/quest_auto_fire_next_door_source.json"
const NEXT_SOURCE_SHA="76700ef4496f8c6ea605895fc133c2f6b85bd2c3d4e89f468abd51875a89476f"
const NEXT_MAX_WALK=200
const RETURN_DOORS=[{"from_map":10204,"cell":[0,6],"to_map":10202,"target":[31,15],"source":"dungeon00.create:268"},{"from_map":10204,"cell":[0,7],"to_map":10202,"target":[31,15],"source":"dungeon00.create:277"}]
# Pending review: passive observation only; each override calls its super exactly once.
class ObservedEntry extends "res://server/quest_auto_entry_routes.gd":
 var grid_observations:Array=[]
 var grid_calls:int=0
 var grid_overflow:int=0
 var current_grid_map:int=-1
 func _grid(b,map_id:int)->Dictionary:
  grid_calls+=1
  current_grid_map=map_id
  var row:Dictionary=last_context.get("maps",{}).get(str(map_id),{})
  var record:Dictionary={"call":grid_calls,"map_id":map_id,"context_width":row.get("width",0),"context_height":row.get("height",0),"cached_before":grids.has(map_id),"loaded_before":loaded_cells,"skipped_before":skipped_large_map,"exhausted_before":exhausted}
  var result:Dictionary=super._grid(b,map_id)
  record.returned_empty=result.is_empty()
  record.loaded_after=loaded_cells
  record.skipped_after=skipped_large_map
  record.exhausted_after=exhausted
  if grid_observations.size()<64:grid_observations.append(record)
  else:grid_overflow+=1
  return result
class ObservedNextNav extends "res://server/quest_auto_navigation.gd":
 var observations:Array=[]
 var phase:String="outside"
 var usable_stats:Dictionary={}
 var counted_edges:Array=[]
 var pending_edge:Dictionary={}
 var attribution_faults:Array=[]
 var attribution_fault_count:int=0
 var entry_diagnostic:ObservedEntry
 var installation:Dictionary={}
 func _init()->void:
  var prior=entry_routes
  var empty:bool=route.is_empty() and key.is_empty() and maps.is_empty() and grid_key.is_empty() and nav==null and block_key.is_empty() and block_cells.is_empty() and entry_context.is_empty() and not entry_active and entry_anchor.is_empty() and entry_pending.is_empty() and entry_repeat.is_empty() and prior.searches==0 and prior.context_copies==0 and prior.output_points==0 and prior.last_reason.is_empty() and prior.last_context.is_empty() and prior.failed_context.is_empty() and prior.failed_origin.is_empty() and not prior.failed_arrival and prior.grids.is_empty() and prior.loaded_cells==0 and prior.visited_cells==0 and prior.edge_count==0 and not prior.exhausted and not prior.skipped_large_map
  installation={"empty_before_install":empty,"installed":false}
  if not empty:
   installation.error="requires_untouched_constructor_state"
   return
  entry_diagnostic=ObservedEntry.new()
  entry_routes=entry_diagnostic
  installation.installed=true
 func observation_fault(record:Dictionary)->void:
  attribution_fault_count+=1
  if attribution_faults.size()<8:attribution_faults.append(record)
 func attribute_pending(current:int,where:String)->void:
  if pending_edge.is_empty():return
  var delta:int=current-int(pending_edge.edge_before)
  if delta==1 and bool(pending_edge.result) and counted_edges.size()<257:
   var record:Dictionary=pending_edge.duplicate(true)
   record.edge_after=current
   record.observed_at=where
   counted_edges.append(record)
  elif delta!=0:
   observation_fault({"kind":"unattributed_delta","delta":delta,"current":current,"where":where})
  pending_edge={}
 func usable(b,link:Dictionary)->bool:
  if phase=="entry":attribute_pending(entry_routes.edge_count,"next_usable")
  var edge_before:int=entry_routes.edge_count
  var result:bool=super.usable(b,link)
  if not usable_stats.has(phase):usable_stats[phase]={"calls":0,"accepted":0,"rejected":0,"from_maps":{},"last_rejected":[]}
  var stats:Dictionary=usable_stats[phase]
  stats.calls+=1
  var outcome:String="accepted" if result else "rejected"
  stats[outcome]+=1
  var from_key:String=str(link.get("from_map",-1))
  if not stats.from_maps.has(from_key):stats.from_maps[from_key]={"calls":0,"accepted":0,"rejected":0}
  stats.from_maps[from_key].calls+=1
  stats.from_maps[from_key][outcome]+=1
  if not result:
   stats.last_rejected.append({"call":stats.calls,"link":link.duplicate(true),"result":result})
   if stats.last_rejected.size()>8:stats.last_rejected.pop_front()
  if phase=="entry":
   pending_edge={"usable_call":stats.calls,"link":link.duplicate(true),"result":result,"edge_before":edge_before,"grid_call":entry_diagnostic.grid_calls if entry_diagnostic!=null else -1,"grid_map":entry_diagnostic.current_grid_map if entry_diagnostic!=null else -1}
  return result
 func map_route(b,origin:int,goal:int)->Array:
  var prior_phase:String=phase
  phase="map_route"
  var result:Array=super.map_route(b,origin,goal)
  phase=prior_phase
  observations.append({"call":"map_route","origin":origin,"goal":goal,"chain":result.duplicate(true)})
  return result
 func local_path(b,map_id:int,origin:Vector2i,goal:Vector2i,occupied:Dictionary)->Array:
  var result:Array=super.local_path(b,map_id,origin,goal,occupied)
  observations.append({"call":"local_path","map_id":map_id,"origin":[origin.x,origin.y],"goal":[goal.x,goal.y],"occupied_origin":occupied.has(origin),"occupied_goal":occupied.has(goal),"points":result.size()})
  return result
 func _entry_fallback(b,npc:Dictionary)->Array:
  var prior_phase:String=phase
  phase="entry"
  if not pending_edge.is_empty():observation_fault({"kind":"pending_before_entry"})
  var result:Array=super._entry_fallback(b,npc)
  attribute_pending(entry_routes.edge_count,"entry_return")
  phase=prior_phase
  observations.append({"call":"entry_fallback","points":result.size(),"last_reason":entry_routes.last_reason,"searches":entry_routes.searches,"context_copies":entry_routes.context_copies,"loaded_cells":entry_routes.loaded_cells,"visited_cells":entry_routes.visited_cells,"edge_count":entry_routes.edge_count,"output_points":entry_routes.output_points,"exhausted":entry_routes.exhausted,"skipped_large_map":entry_routes.skipped_large_map,"failed_origin":entry_routes.failed_origin.duplicate(true),"failed_arrival":entry_routes.failed_arrival})
  return result
 func next(b,npc:Dictionary)->Dictionary:
  observations.append({"call":"next_before","authority":[b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y],"route_points":route.size(),"entry_active":entry_active,"entry_searches":entry_routes.searches})
  var result:Dictionary=super.next(b,npc)
  observations.append({"call":"next_after","point":result.duplicate(true),"route_points":route.size(),"entry_active":entry_active})
  observations.append({"call":"bounded_edge_diagnostics","installation":installation.duplicate(true),"usable_by_phase":usable_stats.duplicate(true),"counted_edges":counted_edges.duplicate(true),"attribution_fault_count":attribution_fault_count,"attribution_faults":attribution_faults.duplicate(true),"grid_calls":entry_diagnostic.grid_calls if entry_diagnostic!=null else 0,"grid_overflow":entry_diagnostic.grid_overflow if entry_diagnostic!=null else 0,"grids":entry_diagnostic.grid_observations.duplicate(true) if entry_diagnostic!=null else []})
  print("NEXT_NAV_OBSERVATION ",JSON.stringify(observations))
  return result
class ObservedBackend extends "res://server/backend.gd":
 var transactions:Array=[]
 var fields:Array=[]
 var diagnostic_errors:Array=[]
 static func bytes_sha(raw:PackedByteArray)->Dictionary:
  var evidence:Dictionary={"ok":false,"start_error":FAILED,"update_error":FAILED,"digest_length":0,"sha256":""}
  var context:HashingContext=HashingContext.new()
  evidence.start_error=context.start(HashingContext.HASH_SHA256)
  if evidence.start_error!=OK:return evidence
  evidence.update_error=context.update(raw)
  if evidence.update_error!=OK:return evidence
  var digest:PackedByteArray=context.finish()
  evidence.digest_length=digest.size()
  if digest.size()!=32:return evidence
  evidence.sha256=digest.hex_encode();evidence.ok=true
  return evidence
 static func read_evidence(path:String)->Dictionary:
  var record:Dictionary={"path":path,"ok":false,"open_error":OK,"length_error":OK,"read_error":OK,"length":-1,"bytes_read":0,"raw_base64":"","sha256":"","parse_error":ERR_PARSE_ERROR,"parsed":null}
  var file:FileAccess=FileAccess.open(path,FileAccess.READ)
  record.open_error=FileAccess.get_open_error()
  if file==null:return record
  var length:int=file.get_length()
  record.length=length;record.length_error=file.get_error()
  if record.length_error!=OK or length<=0:
   file.close();return record
  var raw:PackedByteArray=file.get_buffer(length)
  record.read_error=file.get_error()
  file.close()
  record.length=length;record.bytes_read=raw.size()
  record.raw_base64=Marshalls.raw_to_base64(raw)
  var hash_evidence:Dictionary=bytes_sha(raw)
  record.hash_evidence=hash_evidence;record.sha256=hash_evidence.sha256
  if record.open_error!=OK or record.length_error!=OK or record.read_error!=OK or raw.size()!=length or not hash_evidence.ok:return record
  var parser:JSON=JSON.new()
  record.parse_error=parser.parse(raw.get_string_from_utf8())
  record.parse_line=parser.get_error_line();record.parse_message=parser.get_error_message()
  record.parsed=parser.data if record.parse_error==OK else null
  record.ok=record.parse_error==OK and record.parsed is Dictionary
  return record
 func save_quest_source_transaction(npc_id:String,branch:Dictionary,phase:String)->bool:
  var candidate:Dictionary=session.snapshot()
  var result:bool=super.save_quest_source_transaction(npc_id,branch,phase)
  if npc_id in ["jaruga/event/event04_1","jaruga/event/event04_2"]:
   var evidence:Dictionary=read_evidence(save_path)
   if not evidence.ok:diagnostic_errors.append({"kind":"transaction_read","index":transactions.size(),"evidence":evidence})
   var disk:Variant=evidence.parsed
   transactions.append({"npc_id":npc_id,"branch":branch.duplicate(true),"phase":phase,"ok":result,"candidate":candidate,"disk":disk,"disk_evidence":evidence,"authority":[automation.position_map,[automation.position_cell.x,automation.position_cell.y]],"save_serial":quest_save_serial})
  return result
 func _cmd_field_step(command:Dictionary)->Dictionary:
  var result:Dictionary=super._cmd_field_step(command)
  fields.append({"command":command.duplicate(true),"result":result.duplicate(true)})
  return result
var b
var assertions:int=0
var failures:int=0
var packets:Array=[]
var moves:Array=[]
var saved_seen:int=0
var points:int=0
var saw_completed:bool=false
var final_authority:Array=[]
var final_evidence:Dictionary={}
var trace_reuse_refused:bool=false
var return_nav=Nav.new()
var returning:bool=false
var returned:bool=false
var return_walk:int=0
var return_portals:int=0
var quest_ticks:int=0
var ticks_at_stop:int=-1
var return_trace:Array=[]
var stop_trace:Dictionary={}
var stopped_baseline:Dictionary={}
var baseline_checks:Array=[]
var first_failure:Dictionary={}
var after_stop_events:Array=[]
var stop_started:bool=false
var began:int=Time.get_ticks_msec()
var next_nav=ObservedNextNav.new()
var next_active:bool=false
var next_landed:bool=false
var next_walk:int=0
var next_portals:int=0
var next_target:Dictionary={}
var next_lock:Dictionary={}
var next_trace:Array=[]
var next_start:Dictionary={}
var next_final_authority:Array=[]
func _initialize()->void:call_deferred("run")
static func same(a:Variant,c:Variant)->bool:
 if a is bool or c is bool:return a is bool and c is bool and a==c
 if a is int or a is float:return (c is int or c is float) and is_finite(float(a)) and is_finite(float(c)) and float(a)==floor(float(a)) and float(c)==floor(float(c)) and a==c
 if a is Array and c is Array:
  if a.size()!=c.size():return false
  for i in range(a.size()):
   if not same(a[i],c[i]):return false
  return true
 if a is Dictionary and c is Dictionary:
  if a.size()!=c.size():return false
  for key in a:
   if not c.has(key) or not same(a[key],c[key]):return false
  return true
 return typeof(a)==typeof(c) and a==c
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func saved_transactions()->bool:
 while saved_seen<b.transactions.size():
  var index:int=saved_seen
  var row:Dictionary=b.transactions[index]
  saved_seen+=1
  if not check(index<3 and row.ok and row.disk is Dictionary and same(row.candidate,row.disk),"Original transaction normal save full-profile readback "+str(index)):return false
  var expected_id:String="jaruga/event/event04_2" if index==1 else "jaruga/event/event04_1"
  if not check(row.npc_id==expected_id and int(row.branch.event)==4,"Exact original three-exchange NPC/event order"):return false
  var profile:Dictionary=row.candidate
  if index==0:
   if not check(row.phase=="REQUEST" and Rules.flag(profile,"now",4) and not Rules.flag(profile,"ended",4) and profile.original_items.is_empty(),"Real adult request grants only NOW4"):return false
  elif index==1:
   if not check(row.phase=="reward" and profile.original_items.size()==15 and profile.original_items.count(2417)==15 and not Rules.flag(profile,"ended",4),"Original messenger actually grants fifteen jade"):return false
  else:
   if not check(row.phase=="reward" and profile.original_items==[2418] and Rules.flag(profile,"ended",4) and not Rules.flag(profile,"now",4),"Judge consumes real fifteen jade and grants helmet END4"):return false
 return true
func advance()->bool:
 if failures:return true
 if next_active:return advance_next_leg()
 if returning:return advance_return()
 if not b.diagnostic_errors.is_empty():
  check(false,"Existing transaction I/O diagnostic; do not tick again");return true
 for iteration in range(16):
  var old_map:int=b.automation.position_map
  var old:Vector2i=b.automation.position_cell
  quest_ticks+=1
  b.quest_auto.tick(b,0.21)
  if not b.diagnostic_errors.is_empty():
   check(false,"Transaction evidence I/O failed; stop immediately after original tick");return true
  if not saved_transactions():return true
  var map_id:int=b.automation.position_map
  var cell:Vector2i=b.automation.position_cell
  if old_map!=map_id or old!=cell:
   points+=1
   var link:Dictionary=b.quest_helper.places.links(old_map).get(old,{})
   var move:Dictionary={"from_map":old_map,"from":[old.x,old.y],"map_id":map_id,"cell":[cell.x,cell.y],"link":link.duplicate(true),"phase":b.quest_auto.phase}
   moves.append(move)
   if not check(points<=MAX_POINTS and not saw_completed,"Original path bound; no movement after actual END4"):return true
   if old_map==map_id:
    if not check(absi(old.x-cell.x)+absi(old.y-cell.y)==1,"Mode A remains a single original adjacent logical cell"):return true
   else:
    if not check(not link.is_empty() and not link.get("disabled",false) and int(link.to_map)==map_id and same(link.target,[cell.x,cell.y]),"Every actual cross-map move is its original independent portal"):return true
  while not packets.is_empty():
   var packet:Dictionary=packets.pop_front()
   var command:Dictionary={"type":"report_position","map_id":packet.map_id,"cell":packet.cell.duplicate(),"client":CLIENT,"_quest_connection":71}
   for field in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq"]:
    if packet.has(field):command[field]=packet[field]
   if not check(b.handle(command).get("ok",false),"Acknowledge actual issued receipt without inventing coordinate"):return true
  if not check(not b.battle_open,"Explicit no_random compatibility, no forced enemy or victory"):return true
  if Rules.flag(b.session._profile,"ended",4) and b.session._profile.original_items==[2418]:
   saw_completed=true
   final_authority=[map_id,[cell.x,cell.y]]
   # No further quest_auto tick: normal stop once, then the original return.
   return not begin_return()
  if not b.quest_auto.running:
   check(false,"Adult runner stopped before END4: "+str(b.quest_auto.message));return true
 return false
static func path_exists(path:String)->bool:
 return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))
func run()->void:
 trace_reuse_refused=path_exists(TRACE)
 assertions+=1
 if trace_reuse_refused:
  failures+=1;finish();return
 if not next_nav.installation.get("installed",false):
  first_failure={"kind":"diagnostic_installation","installation":next_nav.installation.duplicate(true)}
  check(false,"Diagnostic Entry installation requires untouched constructor state before adult setup")
  finish();return
 b=ObservedBackend.new();b.set_process(false);b.save_path=SAVE
 for path in [SAVE,SAVE+".bak",SAVE+".tmp",SAVE.get_basename()+".resume.json",SAVE.get_basename()+".resume.json.tmp",SAVE.get_basename()+".resume.json.bak"]:
  if not check(not path_exists(path),"Reject existing save or sidecar: "+path):finish();return
 if not check(not Rules.flag(b.session._profile,"now",4) and not Rules.flag(b.session._profile,"ended",4) and not 2417 in b.session._profile.original_items and not 2418 in b.session._profile.original_items,"Actual fresh profile has no adult completion items or flags"):finish();return
 b.session.gm_raise_level(-1,30)
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 Progression.refresh(b.session._profile.player);b.session._profile.player.hp=b.session._profile.player.max_hp
 # Explicit empty-bag fixture; no original item/flag/proof is manufactured.
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 if not check(b.handle({"type":"no_random_encounters","enabled":true}).get("ok",false),"Disclosed encounter-off compatibility"):finish();return
 var spawn:Array=b.quest_helper.places.info(1000).spawn
 b.automation.position_changed(1000,Vector2i(int(spawn[0]),int(spawn[1])),true,"project")
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"Public initial authority grants no protected proof"):finish();return
 if not check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"A"}}}).get("ok",false),"Original A preference saves through production command"):finish();return
 if not check(b.save(),"Durable initial fixture only, never an extra endpoint save"):finish();return
 b.event.connect(func(event:Dictionary):
  if stop_started:after_stop_events.append(event.duplicate(true))
  if event.get("type")=="position" and event.has("quest_position_seq"):packets.append(event.duplicate(true)))
 if not check(b.handle({"type":"quest_auto_start","quest_id":1,"client":CLIENT,"_quest_connection":71}).get("ok",false),"Actual adult job1 begins from public village"):finish();return
 var completed:bool=await Wait.until(self,advance,90.0)
 if failures:finish();return
 if not check(completed and saw_completed and returned and next_landed and b.transactions.size()==3,"Single shared Wait covers real adult, stop, return and one original next door"):finish();return
 if not check(points>300 and final_authority[0]==10204,"Full original public approach and ritual walks, not direct gate placement"):finish();return
 if not check(b.fields.size()>0 and b.session._profile.original_items==[2418] and Rules.flag(b.session._profile,"ended",4),"Actual field calls and final earned prerequisite preserved"):finish();return
 var final_read:Dictionary=ObservedBackend.read_evidence(SAVE)
 final_evidence=final_read
 if not final_read.ok:
  b.diagnostic_errors.append({"kind":"final_read","evidence":final_read})
  check(false,"Final original save evidence read failed");finish();return
 var disk:Variant=final_read.parsed
 if not check(disk is Dictionary and same(disk,stopped_baseline.files[SAVE].evidence.parsed) and final_read.raw_base64==stopped_baseline.files[SAVE].evidence.raw_base64 and same(disk,b.transactions[-1].candidate),"Final complete original profile and bytes equal frozen post-stop and last real transaction"):finish();return
 if not return_invariants("final_closed_read"):finish();return
 if not check(packets.is_empty() and b.transactions.size()==3 and not b.quest_auto.running and return_portals==1 and return_walk<=200 and quest_ticks==ticks_at_stop and next_landed and next_portals==1 and next_walk<=NEXT_MAX_WALK and same([b.automation.position_map,[b.automation.position_cell.x,b.automation.position_cell.y]],next_final_authority),"Next leg ends at first reviewed original landing without further auto tick"):finish();return
 finish()
func observed_state()->Dictionary:
 return {"map":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"scope":b.quest_arrival._scope,"marks":b.quest_arrival._marks.duplicate(true),"stages":b.quest_arrival._stages.duplicate(true),"running":b.quest_auto.running,"phase":b.quest_auto.phase,"identity":b.quest_auto.identity.checkpoint(),"issued":b.quest_auto.issued.duplicate(true),"motion":b.quest_auto.motion.duplicate(true),"pending":b.original_quests.pending.duplicate(true)}
func disk_set()->Dictionary:
 var records:Dictionary={}
 for path in [SAVE,SAVE+".bak",SAVE+".tmp",SAVE.get_basename()+".resume.json",SAVE.get_basename()+".resume.json.tmp",SAVE.get_basename()+".resume.json.bak"]:
  var directory:bool=DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))
  var exists:bool=FileAccess.file_exists(path)
  var row:Dictionary={"file":exists,"directory":directory}
  if exists and not directory:
   row.evidence=ObservedBackend.read_evidence(path)
   if not row.evidence.ok:b.diagnostic_errors.append({"kind":"sidecar_read","path":path,"evidence":row.evidence})
  if directory:b.diagnostic_errors.append({"kind":"sidecar_directory","path":path})
  records[path]=row
 return records
func begin_return()->bool:
 if not check(b.transactions.size()==3 and packets.is_empty() and not b.battle_open and not b.automation.running and not b.automation.hunt_running and not b.automation.flow_active() and b.automation.pending_resume.is_empty() and b.session._pending.is_empty() and not b.stationary.running,"Actual adult completion and drained issued ACK before stop"):return false
 stop_trace.before=observed_state();stop_trace.files_before=disk_set()
 stop_trace.native_before=b.session._profile.duplicate(true)
 stop_trace.native_before_base64=Marshalls.raw_to_base64(var_to_bytes(b.session._profile))
 stop_trace.cache_before=b.last_saved_payload
 stop_trace.serial_before=b.quest_save_serial
 stop_trace.resume_writes_before=b.resume_writes
 if not check(b.diagnostic_errors.is_empty(),"Pre-stop disk evidence is readable"):return false
 stop_started=true
 var reply:Dictionary=b.handle({"type":"quest_auto_stop"})
 stop_trace.reply=reply.duplicate(true);stop_trace.after=observed_state();stop_trace.files_after=disk_set()
 ticks_at_stop=quest_ticks
 if not check(b.diagnostic_errors.is_empty() and reply.get("ok",false),"Normal handle stop returns with readable sidecar evidence"):return false
 var before:Dictionary=stop_trace.before
 var after:Dictionary=stop_trace.after
 if not check(same(before.map,after.map) and same(before.cell,after.cell) and same(before.scope,after.scope) and same(before.marks,after.marks) and same(before.stages,after.stages),"Stop preserves actual authority and all current arrival proof"):return false
 if not check(not after.running and after.phase=="stopped" and int(after.identity.revision)>int(before.identity.revision) and b.quest_auto.identity.waiting.is_empty() and b.quest_auto.issued.is_empty() and b.quest_auto.motion.is_empty() and b.original_quests.pending.is_empty(),"Normal stop clears old runner receipt and owned dialogue"):return false
 # Freeze once, after the original stop returns; never derive expected from final state.
 stopped_baseline={"native":b.session._profile.duplicate(true),"native_base64":Marshalls.raw_to_base64(var_to_bytes(b.session._profile)),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"resume_writes":b.resume_writes,"files":stop_trace.files_after.duplicate(true)}
 if not check(stopped_baseline.native_base64==stop_trace.native_before_base64 and stopped_baseline.cache==stop_trace.cache_before and stopped_baseline.serial==stop_trace.serial_before,"Idle stop does not rewrite native profile/cache/main-save serial"):return false
 if not check(same(stopped_baseline.files[SAVE],stop_trace.files_before[SAVE]) and same(stopped_baseline.files[SAVE+".bak"],stop_trace.files_before[SAVE+".bak"]),"Idle stop preserves complete main and backup bytes; sidecar effects recorded separately"):return false
 returning=true
 return true
func return_invariants(label:String)->bool:
 var files:Dictionary=disk_set()
 var observed:Dictionary={"label":label,"native_base64":Marshalls.raw_to_base64(var_to_bytes(b.session._profile)),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"resume_writes":b.resume_writes,"files":files,"running":b.quest_auto.running,"issued":b.quest_auto.issued.duplicate(true),"motion":b.quest_auto.motion.duplicate(true),"queued_packets":packets.duplicate(true),"transactions":b.transactions.size(),"ticks":quest_ticks}
 baseline_checks.append(observed)
 if not check(b.diagnostic_errors.is_empty(),"Return evidence readable immediately after "+label):return false
 if not check(not observed.running and observed.issued.is_empty() and observed.motion.is_empty() and observed.queued_packets.is_empty() and observed.transactions==3 and observed.ticks==ticks_at_stop,"No revived runner/receipt/transaction/tick immediately after "+label):return false
 if not check(observed.native_base64==stopped_baseline.native_base64 and observed.cache==stopped_baseline.cache and observed.serial==stopped_baseline.serial and observed.resume_writes==stopped_baseline.resume_writes and same(observed.files,stopped_baseline.files),"Full frozen native/cache/all disk bytes/serial unchanged after "+label):return false
 return true
func advance_return()->bool:
 if failures:return true
 for iteration in range(16):
  if not check(not b.quest_auto.running and quest_ticks==ticks_at_stop and b.transactions.size()==3 and packets.is_empty(),"No old runner tick, receipt or extra transaction after stop"):return true
  for row in RETURN_DOORS:
   var live:Dictionary=b.quest_helper.places.links(10204).get(Vector2i(row.cell[0],row.cell[1]),{})
   if not check(same(live,row),"Both original return doors retain complete source identity"):return true
  var origin:Dictionary=observed_state()
  var point:Dictionary=return_nav.next(b,{"id":"adult-return-geometry","map_id":10202,"cell":[31,15]})
  if point.is_empty():first_failure={"kind":"next_empty","origin":origin,"remaining":return_nav.route.duplicate(true)}
  if not check(not point.is_empty(),"Original A selects among both original return doors"):return true
  var valid:bool=return_nav.validate(b,point)
  return_trace.append({"origin":origin,"point":point.duplicate(true),"valid":valid})
  if not valid:first_failure={"kind":"validate_rejected","origin":origin,"point":point.duplicate(true)}
  if not check(valid and not point.has("gate"),"Original return validation, no scripted gate"):return true
  var portal:bool=point.has("portal")
  if portal:
   var reviewed:bool=false
   for row in RETURN_DOORS:
    if same(point.portal,row):reviewed=true
   if not check(reviewed and return_portals==0 and origin.map==10204 and same(origin.cell,point.portal.cell) and same(point.cell,[31,15]) and int(point.map_id)==10202,"Selected original portal is a separate commit"):return true
   var passage:Dictionary=b.handle({"type":"check_passage","from_map":10204,"to_map":10202})
   return_trace[-1].passage=passage.duplicate(true)
   if not check(passage.get("ok",false),"Original return passage accepts"):return true
  else:
   var cell:Vector2i=Vector2i(point.cell[0],point.cell[1])
   var delta:Vector2i=cell-b.automation.position_cell
   if not check(origin.map==10204 and int(point.map_id)==10204 and absi(delta.x)+absi(delta.y)==1 and return_walk<200,"At most200 original adjacent return walks"):return true
  var moved:Dictionary=b.handle({"type":"report_position","map_id":int(point.map_id),"cell":point.cell.duplicate(),"map_changed":portal,"client":CLIENT})
  return_trace[-1].report=moved.duplicate(true)
  if not return_invariants("report_position"):return true
  return_trace[-1].after=observed_state()
  if not check(moved.get("ok",false) and b.automation.position_map==int(point.map_id) and same([b.automation.position_cell.x,b.automation.position_cell.y],point.cell),"Real ordinary position commits without fabricated authority"):return true
  if not check(b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"Actual arrival checked after original movement"):return true
  if portal:
   return_portals+=1
   # Direct Backend harness only; not production runner reentrancy acceptance.
   if not check(return_nav.portal_committed(b,point),"Notify Nav only after real original landing and arrival"):return true
   returned=true
   stop_trace.files_at_return=disk_set()
   if not check(b.diagnostic_errors.is_empty(),"Final passive sidecar observation readable"):return true
   return not begin_next_leg()
  return_walk+=1
  var field:Dictionary=b.handle({"type":"field_step","map_id":10204,"cell":point.cell.duplicate(),"encounter":true})
  return_trace[-1].field=field.duplicate(true)
  if not return_invariants("field_step"):return true
  if not check(field.get("ok",false) and not field.get("battle",false) and not b.battle_open,"Original field per neighbour, disclosed no_random"):return true
 return false
func no_new_permission(label:String)->bool:
 return check(not b.session.has_travel_pass() and not bool(b.session._profile.get("travel_pass",false)) and not 2422 in b.session._profile.original_items and not Rules.flag(b.session._profile,"now",40) and not Rules.flag(b.session._profile,"ended",40),"No purchased pass, item2422 or Fire flags at "+label)
func begin_next_leg()->bool:
 if not check(returned and return_portals==1 and b.automation.position_map==10202 and b.automation.position_cell==Vector2i(31,15),"Same Backend reached real return landing before next planning"):return false
 if not no_new_permission("next_start") or not return_invariants("next_start"):return false
 var raw:String=FileAccess.get_file_as_string(NEXT_SOURCE_PATH)
 if not check(raw.sha256_text()==NEXT_SOURCE_SHA,"Frozen next-door complete source fixture"):return false
 var parsed:Variant=JSON.parse_string(raw)
 if not check(parsed is Dictionary,"Source fixture dictionary"):return false
 next_lock=parsed
 if not check(next_lock.next_doors.size()==2 and Fire.SOURCE_SHA==next_lock.fire_target_source_sha256,"Two unchanged source doors and original Fire source target"):return false
 var proposal:Dictionary=Fire.request_proposal(b,37)
 if not check(proposal.get("status")=="step" and proposal.step.npc_id==Fire.REQUEST_NPC and proposal.step.map_id==5106 and same(proposal.step.cell,[26,15]),"Real earned END4 only feeds pure original Fire target; never execute REQUEST"):return false
 next_target=proposal.step.duplicate(true)
 next_start={"authority":observed_state(),"profile_base64":Marshalls.raw_to_base64(var_to_bytes(b.session._profile)),"pass":b.session.has_travel_pass(),"gold":b.session._profile.player.gold,"target":next_target.duplicate(true)}
 next_active=true
 return true
func advance_next_leg()->bool:
 if failures or next_landed:return true
 for iteration in range(16):
  if not no_new_permission("before_next") or not return_invariants("before_next"):return true
  if not check(b.automation.position_map==10202 and next_portals==0,"Never plan a second exit or next map"):return true
  for row in next_lock.next_doors:
   var live:Dictionary=b.quest_helper.places.links(10202).get(Vector2i(int(row.cell[0]),int(row.cell[1])),{})
   if not check(same(live,row) and next_nav.usable(b,live),"Both next ordinary source door identities remain frozen"):return true
  var origin:Dictionary=observed_state()
  # Original planner chooses path/door towards original Fire target. No ranking override or retry destination.
  var point:Dictionary=next_nav.next(b,next_target)
  next_trace.append({"origin":origin,"point":point.duplicate(true),"remaining":next_nav.route.duplicate(true)})
  next_trace[-1].navigation_observation=next_nav.observations.duplicate(true)
  var observer_error:bool=next_nav.attribution_fault_count!=0 or next_nav.entry_diagnostic.grid_overflow!=0 or not next_nav.pending_edge.is_empty()
  if observer_error:
   first_failure={"kind":"diagnostic_observation","fault_count":next_nav.attribution_fault_count,"faults":next_nav.attribution_faults.duplicate(true),"grid_overflow":next_nav.entry_diagnostic.grid_overflow,"pending":next_nav.pending_edge.duplicate(true)}
   check(false,"Diagnostic attribution or bounded observation failed after original Nav returned")
   return true
  if point.is_empty():first_failure={"kind":"next_empty","origin":origin,"target":next_target,"remaining":next_nav.route.duplicate(true)}
  if not check(not point.is_empty(),"Original Nav yields next point; empty path stops without alternate door"):return true
  if point.has("gate"):first_failure={"kind":"gate_requires_permission","origin":origin,"point":point.duplicate(true)}
  if not check(not point.has("gate"),"No scripted gate or automatic permit purchase in next-door slice"):return true
  var valid:bool=next_nav.validate(b,point)
  next_trace[-1].valid=valid
  if not valid:first_failure={"kind":"next_validate_rejected","origin":origin,"point":point.duplicate(true)}
  if not check(valid,"Revalidate original next point before ordinary report"):return true
  var portal:bool=point.has("portal")
  if portal:
   var reviewed:bool=false
   for row in next_lock.next_doors:
    if same(point.portal,row):reviewed=true
   if not check(reviewed and same(origin.cell,point.portal.cell) and int(point.map_id)==int(point.portal.to_map) and same(point.cell,point.portal.target),"Selected original exit matches one of both frozen sources"):return true
   var passage:Dictionary=b.handle({"type":"check_passage","from_map":10202,"to_map":int(point.map_id)})
   next_trace[-1].passage=passage.duplicate(true)
   if not check(passage.get("ok",false),"Actual original passage must allow unpermitted next door"):return true
  else:
   var delta:Vector2i=Vector2i(int(point.cell[0]),int(point.cell[1]))-b.automation.position_cell
   if not check(int(point.map_id)==10202 and absi(delta.x)+absi(delta.y)==1 and next_walk<NEXT_MAX_WALK,"Bounded original adjacent next-leg walking only"):return true
  var moved:Dictionary=b.handle({"type":"report_position","map_id":int(point.map_id),"cell":point.cell.duplicate(),"map_changed":portal,"client":CLIENT})
  next_trace[-1].report=moved.duplicate(true)
  if not return_invariants("next_report") or not no_new_permission("next_report"):return true
  next_trace[-1].after=observed_state()
  if not check(moved.get("ok",false) and b.automation.position_map==int(point.map_id) and same([b.automation.position_cell.x,b.automation.position_cell.y],point.cell),"Actual next point commits through ordinary command"):return true
  if not check(b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"Observe actual original arrival; never create a receipt"):return true
  if portal:
   next_portals+=1
   if not check(next_nav.portal_committed(b,point),"Notify Nav only after actual original next landing"):return true
   next_landed=true
   next_final_authority=[b.automation.position_map,[b.automation.position_cell.x,b.automation.position_cell.y]]
   return true
  next_walk+=1
  var field:Dictionary=b.handle({"type":"field_step","map_id":10202,"cell":point.cell.duplicate(),"encounter":true})
  next_trace[-1].field=field.duplicate(true)
  if not return_invariants("next_field") or not no_new_permission("next_field"):return true
  if not check(field.get("ok",false) and not field.get("battle",false) and not b.battle_open,"Actual field step, disclosed no_random, no injected battle outcome"):return true
 return false
func finish()->void:
 # A rejected existing TRACE is never opened, even during failure cleanup.
 if trace_reuse_refused or path_exists(TRACE):
  if failures==0:failures+=1
  print("ADULT_TRACE_IO ",JSON.stringify({"path":TRACE,"error":"existing_trace_file_or_directory","write_attempted":false}))
  if b!=null:b.free()
  print("quest_auto_fire_next_door_test: %d assertions, %d failures"%[assertions,failures])
  quit(1);return
 var result:Dictionary={"assertions":assertions,"failures":failures,"elapsed_msec":Time.get_ticks_msec()-began,"points":points,"moves":moves,"completed":saw_completed,"final_authority":final_authority,"final_evidence":final_evidence,"return_walk":return_walk,"return_portals":return_portals,"returned":returned,"quest_ticks":quest_ticks,"ticks_at_stop":ticks_at_stop,"return_trace":return_trace,"stop_trace":stop_trace,"stopped_baseline":stopped_baseline,"baseline_checks":baseline_checks,"first_failure":first_failure,"after_stop_events":after_stop_events}
 if b!=null:
  result.transactions=b.transactions;result.fields=b.fields;result.diagnostic_errors=b.diagnostic_errors
  # Captured transaction candidate only, never a new snapshot/projection during failure handling.
  result.last_saved_candidate=b.transactions[-1].candidate if not b.transactions.is_empty() else {}
  result.runner={"running":b.quest_auto.running,"phase":b.quest_auto.phase,"message":b.quest_auto.message}
 result.next_leg={"target":next_target,"source_sha":NEXT_SOURCE_SHA,"start":next_start,"trace":next_trace,"walk":next_walk,"portals":next_portals,"landed":next_landed,"final_authority":next_final_authority}
 var bytes:PackedByteArray=JSON.stringify(result).to_utf8_buffer()
 var expected_hash:Dictionary=ObservedBackend.bytes_sha(bytes)
 if not expected_hash.ok:
  failures+=1
  push_error("TRACE hashing start/update/finish failed; no write attempted")
  print("ADULT_TRACE_IO ",JSON.stringify({"path":TRACE,"hash_evidence":expected_hash,"write_attempted":false}))
  if b!=null:b.free()
  print("quest_auto_fire_next_door_test: %d assertions, %d failures"%[assertions,failures])
  quit(1);return
 var expected_sha:String=expected_hash.sha256
 var trace_evidence:Dictionary={"path":TRACE,"expected_length":bytes.size(),"expected_sha256":expected_sha,"expected_hash_evidence":expected_hash}
 var file:FileAccess=FileAccess.open(TRACE,FileAccess.WRITE)
 trace_evidence.open_error=FileAccess.get_open_error()
 var written:bool=file!=null and trace_evidence.open_error==OK
 if file!=null:
  file.store_buffer(bytes);file.flush()
  trace_evidence.write_error=file.get_error();trace_evidence.write_position=file.get_position()
  written=written and trace_evidence.write_error==OK and trace_evidence.write_position==bytes.size()
  file.close()
 var readback:Dictionary=ObservedBackend.read_evidence(TRACE) if written else {}
 trace_evidence.readback={}
 for key in ["path","ok","open_error","length_error","read_error","length","bytes_read","sha256","hash_evidence","parse_error","parse_line","parse_message"]:
  if readback.has(key):trace_evidence.readback[key]=readback[key]
 var verified:bool=expected_hash.ok and written and readback.get("ok",false) and readback.get("hash_evidence",{}).get("ok",false) and int(readback.get("length",-1))==bytes.size() and str(readback.get("sha256",""))==expected_sha
 # This stdout record authenticates the closed TRACE; cannot place its own hash inside itself.
 print("ADULT_TRACE_IO ",JSON.stringify(trace_evidence))
 if not verified:
  failures+=1
  push_error("TRACE open/write/closed-read length or SHA verification failed")
 if b!=null:b.free()
 print("quest_auto_fire_next_door_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
