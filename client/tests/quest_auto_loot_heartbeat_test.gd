extends "res://tests/quest_auto_loot_sample_clock_test.gd"
## P3 candidate only: real E1/E2 receipt, then one actual outer SceneTree process.
## Fixed seed is only a reproducible original-pool test fixture; no group/drop is selected.
class HeartbeatLoot:
 extends "res://server/quest_auto_loot.gd"
 var full_owner_checks:=0
 var owner_diagnostic_armed:=false
 var owner_observations:Array[Dictionary]=[]
 var owner_observations_overflow:=false
 var retire_rows:Array[Dictionary]=[]
 var retire_overflow:=false
 var retire_observer:Callable
 var expected_clock_call:RefCounted
 var retired_expected_clock_call:=false
 func heartbeat_owner_current(b,generation:int,entry_epoch:int)->bool:
  full_owner_checks+=1
  var accepted:bool=super.heartbeat_owner_current(b,generation,entry_epoch)
  if owner_diagnostic_armed:
   if owner_observations.size()>=16:
    owner_observations_overflow=true
   else:
    var q=b.quest_auto
    var auto=b.automation
    var scope:Dictionary=auto.loot_scope
    var authority:Dictionary=scope.get("authority",{})
    var state:Dictionary=b.battle._state
    var pending:Dictionary=b.session._pending
    var receipt:Dictionary=battle_receipt
    var ledger:Variant=b.session._profile.get("quest_loot",{})
    var entry:Dictionary={}
    if ledger is Dictionary:
     var entries:Variant=ledger.get("entries",{})
     if entries is Dictionary:
      var saved_entry:Variant=entries.get(key,{})
      if saved_entry is Dictionary:entry=saved_entry.duplicate(true)
    owner_observations.append({
     "generation_arg":generation,"entry_epoch_arg":entry_epoch,
     "generation":b._normal_process_generation,"entry_epoch":b._normal_process_entry_epoch,"dispatch_epoch":b._dispatch_epoch,
     "depths":[b._process_depth,b._dispatch_boundary_depth,b._observer_depth,b._flush_depth,b._depth],
     "save_path_present":not b.save_path.is_empty(),"stationary_running":b.stationary.running,"original_pending_empty":b.original_quests.pending.is_empty(),
     "timer":{"anchor_ms":anchor_ms,"key":key,"frozen":frozen,"blocked":blocked,"storage_paused":storage_paused,"receipt_present":not receipt.is_empty()},
     "runner":{"running":q.running,"internal":q.internal,"detached":q.detached,"restored":q.restored,"owns_battle":q.owns_battle,"phase":q.phase,"step_action":q.step.get("action"),"identity":q.identity.checkpoint()},
     "automation":{"running":auto.running,"single_battle":auto.single_battle,"preset":auto.settings.get("preset"),"compact_setting":auto.settings.get("compact",false),"compact_active":auto.compact_active,"clone_override":auto.clone_override_active,"hunt_running":auto.hunt_running,"training_borrow_pending":not auto.training_borrow_pending.is_empty(),"map":auto.position_map,"cell":str(auto.position_cell)},
     "scope":{"empty":scope.is_empty(),"keys":scope.keys(),"path":scope.get("path"),"battle_id":scope.get("battle_id"),"receipt_matches":scope.get("receipt",{})==receipt,"authority":authority.duplicate(true)},
     "battle":{"open":b.battle_open,"active":state.get("active",false),"outcome":state.get("outcome",""),"battle_id":state.get("battle_id","")},
     "pending":{"empty":pending.is_empty(),"battle_id":pending.get("battle_id",""),"source":pending.get("wild_drop_source",{}).duplicate(true),"receipt_matches":pending.get("quest_loot_receipt",{})==receipt},
     "settlement_empty":b.session._loot_settlement.is_empty(),"ledger_entry":entry,
     "owner_check_result":accepted,"owner_checks":full_owner_checks,"retire_rows":retire_rows.size()
    })
  return accepted
 func retire_heartbeat_call(call:RefCounted)->void:
  super.retire_heartbeat_call(call)
  if retire_rows.size()>=64:retire_overflow=true;return
  retire_rows.append({"last_ms":last_ms,"cached_sample":cached_sample.duplicate(true),"progress_stamp":progress_stamp.duplicate(true),"blocked":blocked,"frozen":frozen,"storage_paused":storage_paused,"receipt":battle_receipt.duplicate(true),"call_retired":heartbeat_call==null})
  if retire_observer.is_valid():retire_observer.call(call)
var p3_armed:=false
var p3_mode:="valid"
var p3_clock_reads:=0
var p3_clock_rows:Array[Dictionary]=[]
var p3_clock_rows_overflow:=false
var p3_clock_scope_mismatch:=false
var p3_action_fired:=false
var p3_clock_action_ok:=false
var p3_clock_action_record:Dictionary={}
var p3_clock_action_read_ok:=false
var p3_retire_record:Dictionary={}
func reset_p3(mode:String)->void:
 p3_armed=false;p3_mode=mode;p3_clock_reads=0;p3_clock_rows=[];p3_clock_rows_overflow=false;p3_clock_scope_mismatch=false;p3_action_fired=false;p3_clock_action_ok=false;p3_clock_action_record={};p3_clock_action_read_ok=false;p3_retire_record={}
func p3_clock(weak_host:WeakRef,time:Array)->Variant:
 if not p3_armed:return time[0]
 var b=weak_host.get_ref()
 if not is_instance_valid(b):
  p3_clock_scope_mismatch=true
  return time[0]
 var timer:HeartbeatLoot=b.quest_loot
 # Other original settlement/attempt clock calls remain untouched. The
 # injected action is armed only for the live P3 call inside its outer normal
 # process boundary, identified by production's invocation frame.
 if timer.heartbeat_call==null:return time[0]
 if b._process_depth!=1 or b._dispatch_boundary_depth!=1 or b._observer_depth!=0 or b._flush_depth!=0 or b._depth!=1 or b._normal_process_generation<=0 or timer.heartbeat_generation!=b._normal_process_generation or b._normal_process_entry_epoch!=b._dispatch_epoch:
  p3_clock_scope_mismatch=true
  return time[0]
 p3_clock_reads+=1
 if timer.expected_clock_call!=null and not is_same(timer.expected_clock_call,timer.heartbeat_call):
  p3_clock_scope_mismatch=true
  return time[0]
 timer.expected_clock_call=timer.heartbeat_call
 if p3_clock_rows.size()>=64:p3_clock_rows_overflow=true;return time[0]
 p3_clock_rows.append({"call":timer.heartbeat_call,"receipt":timer.battle_receipt.duplicate(true),"active_after_automation_tick":bool(b.battle._state.get("active",false)),"automation_running":b.automation.running,"single_battle":b.automation.single_battle,"phase":b.quest_auto.phase,"group_id":int(b.session._pending.get("group_id",-1)),"battle_id":str(b.battle._state.get("battle_id","")),"pending_id":str(b.session._pending.get("battle_id","")),"receipt_id":str(timer.battle_receipt.get("ledger",{}).get("battle_id","")),"normal_generation":b._normal_process_generation,"process_depth":b._process_depth,"dispatch_depth":b._dispatch_boundary_depth,"observer_depth":b._observer_depth,"flush_depth":b._flush_depth,"backend_depth":b._depth,"wall_ticks":Time.get_ticks_msec(),"sample_input":time[0]})
 if p3_mode in ["clock_save_stop","clock_same_save"]:
  if p3_action_fired:p3_clock_scope_mismatch=true;return time[0]
  p3_action_fired=true
  var before_profile:Dictionary=b.session._profile.duplicate(true)
  var before_payload:String=b.last_saved_payload
  var before_serial:int=b.quest_save_serial
  var before_disk:Dictionary=strict_disk_read(b.save_path)
  check(before_disk.get("ok",false),"Clock callback reads the complete existing primary with checked I/O")
  if failures:return time[0]
  if p3_mode=="clock_save_stop":b.session._profile.player.gold+=13
  p3_clock_action_ok=b.save()
  if failures:return time[0]
  if p3_mode=="clock_same_save":
   check(p3_clock_action_ok and b.session._profile==before_profile and b.last_saved_payload==before_payload and b.quest_save_serial==before_serial+1,"Same-payload save is a real backend save call that advances only its save serial")
   if failures:return time[0]
   var after_disk:Dictionary=strict_disk_read(b.save_path)
   check(after_disk.get("ok",false) and after_disk.bytes==before_disk.bytes,"Same-payload save leaves the existing complete primary bytes intact")
   if failures:return time[0]
  elif p3_clock_action_ok:
   b.quest_auto.stop(b,"P3 test clock reentry")
  p3_clock_action_record=p3_storage_record(b)
  p3_clock_action_read_ok=bool(p3_clock_action_record.get("disk_read_ok",false))
  check(p3_clock_action_read_ok,"Clock successor record has a complete checked disk read")
  if failures:return time[0]
 if p3_mode=="bool":return true
 if p3_mode=="fraction":return float(time[0])+0.25
 if p3_mode=="backward":return 0
 if p3_mode=="overflow":return State.MAX_MSEC+1
 if p3_mode=="nan":return NAN
 if p3_mode=="infinity":return INF
 return time[0]
func observe_p3_retirement(_call:RefCounted,weak_host:WeakRef)->void:
 var b=weak_host.get_ref()
 if not is_instance_valid(b):p3_clock_scope_mismatch=true;return
 var timer:HeartbeatLoot=b.quest_loot
 timer.retired_expected_clock_call=timer.expected_clock_call!=null and is_same(_call,timer.expected_clock_call)
 p3_retire_record=p3_storage_record(b)
 check(p3_retire_record.get("disk_read_ok",false),"Retired heartbeat record reads all current primary bytes")
func prepare_attempt(b,path:String,time:Array)->bool:
 if not setup(b,path):return false
 check(b.session.gm_raise_level(-1,60),"Disclosed original GM fixture raises only the original scholar level gate")
 if failures:return false
 var player:Dictionary=b.session._profile.player
 var points_before:int=int(player.get("stat_points",-1))
 check(points_before==177,"Level-60 fixture exposes exactly the 177 original earned points")
 if failures:return false
 var allocated_before:Dictionary=player.get("allocated_stats",{}).duplicate(true)
 var distributed:bool=b.session.distribute_stats(["vitality","strength","toughness"])
 check(distributed,"Original Session distribution API allocates earned points")
 if failures:return false
 player=b.session._profile.player
 check(player.stat_points==0 and player.allocated_stats.get("vitality",0)-int(allocated_before.get("vitality",0))==59 and player.allocated_stats.get("strength",0)-int(allocated_before.get("strength",0))==59 and player.allocated_stats.get("toughness",0)-int(allocated_before.get("toughness",0))==59,"Fixture allocates exactly 59/59/59 without direct combat-stat writes")
 if failures:return false
 if not b.save():return false
 b.quest_loot=HeartbeatLoot.new()
 b.quest_loot.clock=Callable(self,"p3_clock").bind(weakref(b),time)
 var opened:Dictionary=b.quest_loot.admit_prepared_run(b)
 check(opened.get("ok",false) and opened.get("persisted",false),"Actual E1 durable open precedes original E2")
 return failures==0
func strict_disk_read(path:String)->Dictionary:
 if path.is_empty():return {"ok":false,"open_error":ERR_INVALID_PARAMETER,"read_error":ERR_INVALID_PARAMETER,"declared_length":-1,"actual_length":-1,"bytes":PackedByteArray()}
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null:return {"ok":false,"open_error":FileAccess.get_open_error(),"read_error":ERR_FILE_CANT_OPEN,"declared_length":-1,"actual_length":-1,"bytes":PackedByteArray()}
 var declared:int=file.get_length()
 if declared<=0:
  var length_error:int=file.get_error();file.close()
  return {"ok":false,"open_error":OK,"read_error":length_error,"declared_length":declared,"actual_length":-1,"bytes":PackedByteArray()}
 var bytes:PackedByteArray=file.get_buffer(declared)
 var read_error:int=file.get_error()
 file.close()
 return {"ok":read_error==OK and bytes.size()==declared,"open_error":OK,"read_error":read_error,"declared_length":declared,"actual_length":bytes.size(),"bytes":bytes}
func p3_storage_record(b)->Dictionary:
 var disk:Dictionary=strict_disk_read(b.save_path)
 var timer:Dictionary=b.quest_loot.heartbeat_timer_snapshot()
 # The in-flight call is expected to retire after a stale same-save frame;
 # all durable timer/ticket/capability fields remain part of the comparison.
 timer.erase("heartbeat_call")
 timer.erase("attempt_call")
 return {"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"pending_ref":b.session._pending,"pending":b.session._pending.duplicate(true),"settlement":b.session._loot_settlement.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"disk_read_ok":disk.ok,"disk_open_error":disk.open_error,"disk_read_error":disk.read_error,"disk_declared_length":disk.declared_length,"disk_actual_length":disk.actual_length,"disk":disk.bytes,"timer":timer,"runner":{"identity":b.quest_auto.identity.checkpoint(),"running":b.quest_auto.running,"phase":b.quest_auto.phase,"pause_reason":b.quest_auto.pause_reason},"scope":b.automation.loot_scope.duplicate(true),"auto_token":b.automation.start_lifetime}
func p3_lite_record(b)->Dictionary:return p3_storage_record(b)
func outer_process_returned(b)->bool:
 return b._process_depth==0 and b._dispatch_boundary_depth==0 and b._observer_depth==0 and b._flush_depth==0 and b._depth==0
func process_until_p3_retired(b)->bool:
 if b.get_parent()==null:root.add_child(b)
 var timer:HeartbeatLoot=b.quest_loot
 timer.owner_diagnostic_armed=true
 timer.retire_observer=Callable(self,"observe_p3_retirement").bind(weakref(b))
 var generation_before:int=b._normal_process_generation
 var retire_before:int=timer.retire_rows.size()
 b.set_process(true)
 var arrived:bool=await Wait.until(self,func():
  if failures:return true
  if not outer_process_returned(b) or b._normal_process_generation<=generation_before:return false
  return timer.retire_rows.size()>retire_before or not b.battle_open or not b.quest_auto.running
 )
 var release_reason:String="wait_deadline_or_unclassified"
 if failures>0:release_reason="prior_assertion_failure"
 elif timer.retire_rows.size()>retire_before:release_reason="heartbeat_retired"
 elif not b.battle_open:release_reason="battle_closed"
 elif not b.quest_auto.running:release_reason="quest_runner_stopped"
 var state:Dictionary=b.battle._state
 print("P3 HEARTBEAT DIAGNOSTIC ",JSON.stringify({"arrived":arrived,"release_reason":release_reason,"battle_open":b.battle_open,"battle_active":state.get("active",false),"battle_outcome":state.get("outcome",""),"battle_id":state.get("battle_id",""),"q_running":b.quest_auto.running,"q_phase":b.quest_auto.phase,"q_pause_reason":b.quest_auto.pause_reason,"automation_running":b.automation.running,"automation_compact":b.automation.compact_active,"pending_empty":b.session._pending.is_empty(),"settlement_empty":b.session._loot_settlement.is_empty(),"normal_generation":b._normal_process_generation,"depths":[b._process_depth,b._dispatch_boundary_depth,b._observer_depth,b._flush_depth,b._depth],"owner_checks":timer.full_owner_checks,"owner_observations":timer.owner_observations,"owner_observations_overflow":timer.owner_observations_overflow,"clock_reads":p3_clock_reads,"retire_rows":timer.retire_rows.size()}))
 b.set_process(false)
 if failures:return false
 check(arrived and b._normal_process_generation>generation_before and outer_process_returned(b),"Observed an actual outer normal-process generation unwind")
 if failures:return false
 check(timer.retire_rows.size()>retire_before,"Actual post-automation active receipt reached and retired its P3 heartbeat call")
 return failures==0
func settle_using_real_normal_frames(b)->bool:
 b.set_process(true)
 var arrived:=await Wait.until(self,func():return failures>0 or (not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty() and b.battle_state.get("settled",false) and outer_process_returned(b)))
 b.set_process(false)
 if failures:return false
 check(arrived,"Original automation reaches settlement through normal processing before the generous wait deadline")
 if failures:return false
 check(not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty() and b.battle_state.get("settled",false),"Original active battle reaches its normal settlement without a direct/manual battle tick")
 if failures:return false
 check(b.session._profile.quest_loot.entries[KEY].saved_battles==1 and complete_disk(b),"Original settled receipt is durably saved exactly once")
 return failures==0
func start_real_receipt(b,path:String,time:Array)->bool:
 if not real_battle(b,path,time):return false
 check(b.battle_open and b.battle._state.get("active",false) and b.session._pending.has("quest_loot_receipt") and b.quest_auto.phase=="loot_battle" and b.automation.single_battle,"Positive fixture starts from the actual original-pool active receipt")
 return failures==0
func complete_disk(b)->bool:
 var disk:Dictionary=strict_disk_read(b.save_path)
 check(disk.get("ok",false),"Complete primary read checks open error, read error and exact declared/actual length")
 if failures:return false
 var copied:Dictionary=ProfileCompare.validated_copy(b.session,disk.bytes.get_string_from_utf8())
 check(copied.get("ok",false),"Complete primary is a valid full profile before comparison normalization")
 if failures:return false
 check(copied.profile==b.session.snapshot(),"Complete normalized primary equals the complete native profile")
 return failures==0
func heartbeat_projection(b)->Dictionary:
 return {"last_ms":b.quest_loot.last_ms,"cached_sample":b.quest_loot.cached_sample.duplicate(true),"progress_stamp":b.quest_loot.progress_stamp.duplicate(true),"blocked":b.quest_loot.blocked,"receipt":b.quest_loot.battle_receipt.duplicate(true)}
func check_retirement_matches_before(before:Dictionary,row:Dictionary,label:String)->void:
 check(row.get("last_ms")==before.last_ms and row.get("cached_sample",{})==before.cached_sample and row.get("progress_stamp",{})==before.progress_stamp and row.get("blocked")==before.blocked and row.get("receipt",{})==before.receipt and row.get("call_retired",false),label)
func process_next_normal_generation(b)->bool:
 var generation_before:int=b._normal_process_generation
 b.set_process(true)
 var arrived:bool=await Wait.until(self,func():return failures>0 or (b._normal_process_generation>generation_before and outer_process_returned(b)))
 b.set_process(false)
 if failures:return false
 check(arrived and b._normal_process_generation>generation_before and outer_process_returned(b),"A later real normal generation returned from the complete Backend process")
 return failures==0
func verify_subsecond_real_throttle(b,timer:HeartbeatLoot)->bool:
 var clock_reads_before:int=p3_clock_reads
 var owner_checks_before:int=timer.full_owner_checks
 var retires_before:int=timer.retire_rows.size()
 var sample_wall:int=int(p3_clock_rows[0].wall_ticks)
 var receipt:Dictionary=timer.battle_receipt.duplicate(true)
 check(Time.get_ticks_msec()-sample_wall<1000,"Real fixture reaches the next process while the one-second wall throttle can be observed")
 if failures:return false
 p3_armed=true
 if not await process_next_normal_generation(b):p3_armed=false;return false
 p3_armed=false
 check(Time.get_ticks_msec()-sample_wall<1000 and b.battle_open and b.battle._state.get("active",false) and b.session._pending.get("quest_loot_receipt",{})==receipt and b.quest_auto.running and p3_clock_reads==clock_reads_before and timer.full_owner_checks==owner_checks_before and timer.retire_rows.size()==retires_before,"A second actual normal generation within one second leaves the same battle active and exits at cheap throttle before clock/full profile validation")
 return failures==0
func run()->void:
 for mode in ["valid","valid_999","bool","fraction","backward","overflow","nan","infinity"]:
  reset_p3(mode)
  var b=SampleBackend.new();var time:Array=[1000]
  if not await start_real_receipt(b,"user://loot-p3-heartbeat-"+mode+".json",time):b.free();quit(1);return
  var timer:HeartbeatLoot=b.quest_loot
  var before:Dictionary=heartbeat_projection(b)
  var disk_before:Dictionary=strict_disk_read(b.save_path)
  check(disk_before.get("ok",false),"Pre-sample primary bytes are read with checked open/read/length evidence")
  if failures:b.free();quit(1);return
  var serial:int=b.quest_save_serial;var payload:String=b.last_saved_payload;var disk:PackedByteArray=disk_before.bytes;var field_calls:int=b.field_calls
  time[0]=timer.anchor_ms+(999 if mode=="valid_999" else 1000)
  p3_armed=true
  var checks_before:int=timer.full_owner_checks
  var process_ok:bool=await process_until_p3_retired(b)
  p3_armed=false
  check(process_ok and p3_clock_reads==1 and p3_clock_rows.size()==1 and p3_clock_rows[0].active_after_automation_tick and p3_clock_rows[0].automation_running and p3_clock_rows[0].single_battle and p3_clock_rows[0].phase=="loot_battle" and p3_clock_rows[0].group_id==169 and p3_clock_rows[0].battle_id==p3_clock_rows[0].pending_id and p3_clock_rows[0].pending_id==p3_clock_rows[0].receipt_id and p3_clock_rows[0].receipt==before.receipt and timer.retired_expected_clock_call and is_same(p3_clock_rows[0].call,timer.expected_clock_call) and p3_clock_rows[0].process_depth==1 and p3_clock_rows[0].dispatch_depth==1 and p3_clock_rows[0].observer_depth==0 and p3_clock_rows[0].flush_depth==0 and p3_clock_rows[0].backend_depth==1 and not p3_clock_rows_overflow and not p3_clock_scope_mismatch,"After the real automation tick, original group169 receipt remains active inside one outer normal heartbeat call")
  if failures:b.free();quit(1);return
  check(timer.full_owner_checks==checks_before+2 and timer.retire_rows.size()==1 and not timer.retire_overflow and b.field_calls==field_calls,"One due sample performs only pre/post-clock full owner checks and never issues a field step")
  if failures:b.free();quit(1);return
  var row:Dictionary=timer.retire_rows[0]
  if mode=="valid":
   check(row.last_ms==time[0] and not row.blocked and row.cached_sample.get("used_ms",-1)==timer.base_used_ms+time[0]-timer.anchor_ms,"Valid sample installs only monotonic same-span time/cache")
   if failures:b.free();quit(1);return
   check(row.progress_stamp.get("ms",-1)==time[0] and row.progress_stamp.get("used_ms",-1)==timer.base_used_ms+1000,"Exactly 1000ms advances the shared span stamp and queued progress threshold")
   if failures:b.free();quit(1);return
   if not await verify_subsecond_real_throttle(b,timer):b.free();quit(1);return
  elif mode=="valid_999":
   check(row.last_ms==time[0] and row.cached_sample.get("used_ms",-1)==timer.base_used_ms+999 and row.progress_stamp==before.progress_stamp,"A real accepted 999ms heartbeat does not advance the shared one-second publication stamp")
   if failures:b.free();quit(1);return
  else:
   check_retirement_matches_before(before,row,"Invalid bool/fraction/backward/overflow clock rejects only this sample")
   if failures:b.free();quit(1);return
  # No active heartbeat path calls a Session writer. A settlement later in this
  # same normal process is allowed only through the original atomic battle path.
  if b.battle_open:
   var after_disk:Dictionary=strict_disk_read(b.save_path)
   check(after_disk.get("ok",false) and b.quest_save_serial==serial and b.last_saved_payload==payload and after_disk.bytes==disk and b.session._pending.get("quest_loot_receipt",{})==before.receipt,"Heartbeat itself adds no save and leaves original receipt and complete primary bytes intact")
  else:
   check(b.session._pending.is_empty() and b.session._loot_settlement.is_empty() and b.session._profile.quest_loot.entries[KEY].saved_battles==1 and complete_disk(b),"Any same-tick close remains the original durable settlement, not a heartbeat writer")
  if failures:b.free();quit(1);return
  p3_armed=false
  if not await settle_using_real_normal_frames(b):b.free();quit(1);return
  print("P3 HEARTBEAT COMPLETE ",mode," generation=",b._normal_process_generation," reads=",p3_clock_reads)
  b.free()
 print("QUEST AUTO LOOT HEARTBEAT: %d failures; 8 original-pool normal-process fixtures (7 clock modes plus the 999ms shared-stamp boundary)"%failures)
 quit(0)
