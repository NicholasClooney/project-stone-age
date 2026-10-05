extends "res://tests/quest_auto_loot_continuation_remote_ui_test.gd"
## TMP / UNRUN. Actual next-open IO rejection; not storage debt or public admission.
class NextOpenFaultSession:
 extends "res://server/game_session.gd"
 var armed:bool=false
 var fired:bool=false
 var fault_error:String=""
 var retired:bool=false
 var expected_owners:Dictionary={}
 var expected_identity:Dictionary={}
 var expected_step:Dictionary={}
 var expected_binding:Dictionary={}
 var expected_position:Dictionary={}
 var expected_serial:int=-1
 var expected_cache:String=""
 var expected_primary:Dictionary={}
 var expected_backup:Dictionary={}
 var chain_serial:int=-1 # Test expectation only; advanced from validated per-command edges.
 var sync_noncommit_verified:bool=false
 var checkpoint_records:Array=[]
 func fail_observation(b,reason:String)->void:
  if fault_error.is_empty():fault_error=reason
  b.latch_error(reason)
 func closed_owner_matches(b)->bool:
  if not is_instance_valid(b) or not owner_is("backend",b) or not owner_is("session",self) or not owner_is("session",b.session):return false
  var q=b.quest_auto
  if not owner_is("runner",q) or not owner_is("identity",q.identity) or not owner_is("timer",b.quest_loot) or not owner_is("battle",b.battle) or not owner_is("automation",b.automation):return false
  return q.identity.checkpoint()==expected_identity and q.step==expected_step and q.connection==expected_binding.connection and q.client==expected_binding.client and q.internal and not q.detached and not q.restored and b.save_path==expected_path and b.automation.position_map==expected_position.map_id and b.automation.position_cell==expected_position.cell
 func closed_record(b)->Dictionary:
  return {"owner_current":closed_owner_matches(b),"state":b.raw_q_evidence(),"path":b.save_path,"serial":b.quest_save_serial,"native":snapshot().duplicate(true),"cache":b.last_saved_payload,"primary":b.disk_evidence(expected_path),"backup":b.disk_evidence(expected_path+".bak"),"pending":_pending.duplicate(true),"settlement":_loot_settlement.duplicate(true),"battle_open":b.battle_open,"auto_running":b.automation.running,"owns_battle":b.quest_auto.owns_battle,"ready":b.value_evidence(b.quest_loot.ready_frame),"open_obligation":b.value_evidence(b.quest_loot.open_obligation)}
 func closed_values_match(record:Dictionary,serial:int)->bool:
  return record.owner_current and record.path==expected_path and record.serial==serial and record.native==expected_closed and record.cache==expected_cache and record.primary==expected_primary and record.backup==expected_backup and record.pending.is_empty() and record.settlement.is_empty() and not record.battle_open and not record.auto_running
 func verify_noncommit(b,reply:Dictionary)->void:
  var observed:Dictionary=closed_record(b)
  var valid:bool=fault_error.is_empty() and b.diagnostic_error.is_empty() and writer_owner_matches() and fired and attempts==1 and writer_records.size()==2 and not writer_records[1].saved and reply.get("ok")==false and reply.get("persisted")==false and closed_values_match(observed,expected_serial)
  print("NEXT OPEN SYNC NONCOMMIT ",JSON.stringify({"valid":valid,"expected_serial":expected_serial,"reply":reply.duplicate(true),"observed":observed}))
  if not valid:fail_observation(b,"Synchronous next-open noncommit changed original serial or closed saved baseline")
  else:sync_noncommit_verified=true
 var original_ticket:WeakRef
 var original_lifetime:WeakRef
 var original_auto_token:WeakRef
 var current_consume:WeakRef
 var context_active:bool=false
 var context_records:Array=[]
 func owner_is(key:String,value)->bool:
  var weak=expected_owners.get(key)
  return weak is WeakRef and is_instance_valid(value) and is_same(weak.get_ref(),value)
 func base_owner_matches(b,required_phase:String)->bool:
  if not is_instance_valid(b) or not owner_is("backend",b) or not owner_is("session",self) or not owner_is("session",b.session):return false
  var q=b.quest_auto
  if not owner_is("runner",q) or not owner_is("identity",q.identity) or not owner_is("timer",b.quest_loot) or not owner_is("battle",b.battle) or not owner_is("automation",b.automation):return false
  return q.identity.checkpoint()==expected_identity and q.step==expected_step and q.connection==expected_binding.connection and q.client==expected_binding.client and b.automation.position_map==expected_position.map_id and b.automation.position_cell==expected_position.cell and q.running and q.internal and not q.detached and not q.restored and q.phase==required_phase and b.save_path==expected_path and b.quest_save_serial==expected_serial and b.last_saved_payload==expected_cache and not b.battle_open and not b.automation.running and _pending.is_empty() and _loot_settlement.is_empty() and _profile==expected_closed and is_same(original_lifetime.get_ref(),b.quest_loot.lifetime) and is_same(original_auto_token.get_ref(),b.automation.start_lifetime)
 func enter_next_open(b,timer,continuation:Dictionary)->void:
  var call=continuation.get("call")
  var valid:bool=not retired and armed and not fired and not context_active and base_owner_matches(b,"loot_admission") and is_same(timer,b.quest_loot) and call is RefCounted and is_same(timer.consume_call,call) and is_same(original_ticket.get_ref(),continuation.get("token")) and continuation.get("retired",false) and continuation.get("identity")==expected_identity and continuation.get("step")==expected_step and continuation.get("serial")==expected_serial and continuation.get("payload")==expected_cache and continuation.get("profile")==expected_closed and continuation.get("connection")==expected_binding.connection and continuation.get("client")==expected_binding.client and continuation.get("map_id")==expected_position.map_id and continuation.get("cell")==expected_position.cell
  if not valid:fault_error="Next-open admission is not the frozen C1 consume call"
  context_active=valid
  current_consume=weakref(call) if call is RefCounted else null
  var record:Dictionary={"stage":"admission.before","valid":valid,"call_id":str(call.get_instance_id()) if is_instance_valid(call) else "absent","serial":b.quest_save_serial,"identity":b.quest_auto.identity.checkpoint().duplicate(true),"connection":str(b.quest_auto.connection),"client":b.quest_auto.client,"token_same":is_same(original_ticket.get_ref(),continuation.get("token"))}
  context_records.append(record);print("NEXT OPEN CALL ",JSON.stringify(record))
 func writer_owner_matches()->bool:
  var weak=expected_owners.get("backend")
  var b=weak.get_ref() if weak is WeakRef else null
  if not context_active or current_consume==null or not base_owner_matches(b,"loot_admission"):return false
  var call=current_consume.get_ref()
  return is_instance_valid(call) and is_same(b.quest_loot.consume_call,call) and b.quest_loot.followup.is_empty() and b.automation.loot_scope.is_empty()
 var expected_path:String=""
 var expected_closed:Dictionary={}
 var expected_open:Dictionary={}
 var attempts:int=0
 var writer_records:Array=[]
 func _write_profile_candidate(candidate:Dictionary,save_path:String)->bool:
  var watching:bool=not retired and (armed or fired)
  if watching:
   attempts+=1
   var owner_current:bool=writer_owner_matches()
   var exact:bool=fault_error.is_empty() and owner_current and armed and not fired and save_path==expected_path and _profile==expected_closed and candidate==expected_open and _pending.is_empty()
   var absolute:String=ProjectSettings.globalize_path(save_path+".tmp")
   if not exact:fault_error="Unexpected writer at next-open fault boundary"
   elif FileAccess.file_exists(absolute) or DirAccess.dir_exists_absolute(absolute):fault_error="Next-open blocker path already exists"
   else:
    var made:int=DirAccess.make_dir_absolute(absolute)
    if made!=OK:fault_error="Cannot create own next-open blocker: "+str(made)
    else:fired=true
   armed=false
   writer_records.append({"stage":"before","exact":exact,"owner_current":owner_current,"consume_id":str(current_consume.get_ref().get_instance_id()) if current_consume!=null and is_instance_valid(current_consume.get_ref()) else "absent","error":fault_error,"candidate":candidate.duplicate(true),"native":_profile.duplicate(true),"path":save_path,"blocker":DirAccess.dir_exists_absolute(absolute)})
   print("NEXT OPEN WRITER BEFORE ",JSON.stringify(writer_records.back()))
  if retired:print("NEXT OPEN RETIRED WRITER BEFORE ",JSON.stringify({"path":save_path,"candidate":candidate.duplicate(true),"native":_profile.duplicate(true)}))
  var saved:bool=super._write_profile_candidate(candidate,save_path) # Exactly once; real IO fails, never fake return.
  if watching:
   writer_records.append({"stage":"after","saved":saved,"last_error":last_error,"native":_profile.duplicate(true),"path":save_path})
   print("NEXT OPEN WRITER AFTER ",JSON.stringify(writer_records.back()))
  if retired:
   print("NEXT OPEN RETIRED WRITER AFTER ",JSON.stringify({"path":save_path,"saved":saved,"last_error":last_error}))
   if not saved:fault_error="Original teardown writer failed with preserved blocker"
  return saved
class NextOpenObservedLoot:
 extends "res://server/quest_auto_loot.gd"
 func admit_prepared_run(b,continuation:Dictionary={})->Dictionary:
  var session=b.session
  var watching:bool=not continuation.is_empty() and (session.armed or session.fired) and not session.retired
  if watching:session.enter_next_open(b,self,continuation)
  var reply:Dictionary=super.admit_prepared_run(b,continuation) # Once; no current/status/clock observation.
  if watching:
   session.context_records.append({"stage":"admission.after","reply":reply.duplicate(true),"context_active":session.context_active,"consume_id":str(consume_call.get_instance_id()) if is_instance_valid(consume_call) else "absent"})
   print("NEXT OPEN CALL ",JSON.stringify(session.context_records.back()))
   session.verify_noncommit(b,reply) # Still the original admission return stack, before manual publication.
   session.context_active=false # Test observation extent only; no production frame change.
  return reply
class CheckpointObservedBackend:
 extends StopObservedBackend
 var checkpoint_active:bool=false
 var save_active:bool=false
 var body_active:bool=false
 var save_count:int=0
 var body_count:int=0
 var chain_events:Array=[]
 func watching_checkpoint_chain()->bool:
  return session is NextOpenFaultSession and not session.retired and (session.armed or session.fired)
 func transport_record(command:Dictionary)->Dictionary:
  var record:Dictionary={"available":false,"backend_matches":false,"incoming_member":false,"members":[],"peer_decimal":str(command.get("_quest_connection",-1))}
  var transport=observer_server.get_ref() if observer_server!=null else null
  if is_instance_valid(transport):
   record.available=true;record.backend_matches=is_same(transport.backend,self)
   for peer in transport.clients():
    record.members.append({"peer":str(peer.get_instance_id()),"state":peer.get_ready_state()})
    if peer.get_instance_id()==command.get("_quest_connection",-1) and peer.get_ready_state()==WebSocketPeer.STATE_OPEN:record.incoming_member=true
  return record
 func chain_event(stage:String,extra:Dictionary={})->Dictionary:
  var record:Dictionary={"stage":stage,"observed":session.closed_record(self),"extra":extra}
  chain_events.append(record);print("NEXT OPEN CHECKPOINT CHAIN ",JSON.stringify(record))
  return record.observed
 func fail_chain(reason:String)->void:
  session.fail_observation(self,reason)
 func manual_closed(record:Dictionary,expected:int)->bool:
  return session.closed_values_match(record,expected) and not record.state.running and not record.owns_battle and record.state.phase=="manual"
 func _cmd_checkpoint(command:Dictionary)->Dictionary:
  var watching:bool=watching_checkpoint_chain()
  var nested:bool=checkpoint_active or save_active or body_active
  var before:Dictionary={};var transport:Dictionary={};var start_serial:int=-1
  if watching:
   start_serial=session.chain_serial;transport=transport_record(command)
   before=chain_event("command.before",{"command":command.duplicate(true),"transport":transport,"expected_serial":start_serial})
   if nested or not session.sync_noncommit_verified or not session.fault_error.is_empty() or not diagnostic_error.is_empty() or not manual_closed(before,start_serial) or not transport.available or not transport.backend_matches or not transport.incoming_member or command.get("type")!="checkpoint" or command.get("map_id")!=session.expected_position.map_id or command.get("x")!=session.expected_position.cell.x or command.get("y")!=session.expected_position.cell.y:
    fail_chain("Unrelated, reentrant or invalid-owner checkpoint inside next-open observation")
   if not nested:
    checkpoint_active=true;save_count=0;body_count=0
  var reply:Dictionary=super._cmd_checkpoint(command) # Exactly one original command, even on observation failure.
  if watching:
   var after:Dictionary=chain_event("command.after",{"reply":reply.duplicate(true),"transport":transport_record(command),"expected_before":start_serial,"save_count":save_count,"body_count":body_count})
   var valid:bool=not nested and session.fault_error.is_empty() and diagnostic_error.is_empty() and save_count==1 and body_count==1 and reply.get("ok")==true and manual_closed(after,start_serial+1) and after.ready==before.ready and after.open_obligation==before.open_obligation and transport_record(command)==transport
   session.checkpoint_records.append({"command":command.duplicate(true),"transport":transport,"before":before,"after":after,"reply":reply.duplicate(true),"valid":valid,"expected_before":start_serial,"expected_after":start_serial+1})
   if not valid:fail_chain("Checkpoint did not prove exactly one successful empty-frame same-payload save")
   else:session.chain_serial=start_serial+1 # Never copy the final current serial into the expectation.
   if not nested:checkpoint_active=false
  return reply
 func save()->bool:
  var watching:bool=watching_checkpoint_chain()
  var nested:bool=save_active or body_active
  var expected:int=session.chain_serial if watching else -1
  var before:Dictionary={}
  if watching:
   before=chain_event("save.before")
   if not checkpoint_active or nested or save_count!=0 or not manual_closed(before,expected):fail_chain("Unrelated or repeated save inside next-open observation")
   save_count+=1
   if not nested:save_active=true
  var saved:bool=super.save() # One original save; derived body wrapper below observes its actual call.
  if watching:
   var after:Dictionary=chain_event("save.after",{"saved":saved})
   if not saved or not manual_closed(after,expected+1) or after.ready!=before.ready or after.open_obligation!=before.open_obligation:fail_chain("Checkpoint save changed closed baseline or serial by other than one")
   if not nested:save_active=false
  return saved
 func _save_profile_boundary(checkpoint:Dictionary={})->bool:
  var watching:bool=watching_checkpoint_chain()
  var nested:bool=body_active
  var expected:int=session.chain_serial if watching else -1
  var before:Dictionary={}
  if watching:
   before=chain_event("body.before",{"frame":checkpoint_frame_evidence(checkpoint)})
   if not checkpoint_active or not save_active or nested or body_count!=0 or not checkpoint.is_empty() or not manual_closed(before,expected):fail_chain("Nonempty, missing or reentrant ordinary checkpoint save body")
   body_count+=1
   if not nested:body_active=true
  var saved:bool=super._save_profile_boundary(checkpoint) # Once; no writes, marks or finish added by observer.
  if watching:
   var after:Dictionary=chain_event("body.after",{"frame":checkpoint_frame_evidence(checkpoint),"saved":saved})
   if not saved or not checkpoint.is_empty() or not manual_closed(after,expected+1) or after.ready!=before.ready or after.open_obligation!=before.open_obligation:fail_chain("Ordinary checkpoint body violated empty-frame same-payload +1 contract")
   if not nested:body_active=false
  return saved
func diagnostic_ok()->bool:
 if not super.diagnostic_ok():return false
 if is_instance_valid(host) and host.session is NextOpenFaultSession and not host.session.fault_error.is_empty():
  return check(false,"Next-open fault observer: "+host.session.fault_error)
 return true
func ready(condition:Callable,note:String)->bool:
 var reached:bool=await Wait.until(self,func():return not host.report_violation.is_empty() or not host.diagnostic_error.is_empty() or not host.session.fault_error.is_empty() or condition.call())
 if not host.report_violation.is_empty():return false
 if not diagnostic_ok():return false
 return check(reached,note)
func run()->void:
 path="user://loot-next-open-failure-remote.json"
 if not await prepare_bound():return
 var identity:Dictionary=host.quest_auto.identity.checkpoint().duplicate(true)
 host.guard_reports=true
 host.encounter_rng.seed=4101;host.encounter_catalog.pressure=50
 var attempt:Dictionary={}
 for index in range(200):
  attempt=host.quest_loot.attempt_once(host)
  if not diagnostic_ok():return
  if not check(attempt.get("ok",false),"Original bounded E2 attempt retains authority"):return
  if attempt.get("battle",false):break
  clock_ms+=500
 if not check(attempt.get("battle",false) and host.battle_open,"One original E2 battle exists"):return
 var battle_id:String=str(host.battle.snapshot().get("battle_id",""))
 if not check(host.session._pending.get("group_id",-1)==169 and host.session._pending.has("quest_loot_receipt"),"Actual seed4101 original169 receipt, not target drop"):return
 for world in worlds:
  if not check(await Wait.settle(self,world),"Actual battle packets and natural UI/report roundtrip"):return
  if not host.report_violation.is_empty():return
 print("C2 WS BEFORE DRIVER ",JSON.stringify({"state":host.report_state(),"reports":host.report_records}))
 if not check(host.quest_auto.running and not host.quest_auto.detached and host.quest_auto.identity.checkpoint()==identity,"Natural UI has not cancelled/replaced the live continuation owner"):return
 for tick in range(100):
  if not host.automation.running:break
  host.evidence("driver.before",{"tick":tick})
  if not diagnostic_ok():return
  clock_ms+=500;host.automation.tick_battle(0.5)
  host.evidence("driver.after",{"tick":tick})
  if not diagnostic_ok():return
  if not host.report_violation.is_empty():return
  if not check(str(host.battle.snapshot().get("battle_id",""))==battle_id and host.quest_auto.identity.checkpoint()==identity and host.quest_auto.running,"Original battle owner persists after driver tick"):return
  host.evidence("scene_yield.before",{"tick":tick})
  if not diagnostic_ok():return
  await process_frame # Normal production consumers remain enabled, no report filtering.
  host.evidence("scene_yield.after",{"tick":tick})
  if not diagnostic_ok():return
  if not host.report_violation.is_empty():return
  if not check(host.quest_auto.running and host.quest_auto.identity.checkpoint()==identity,"Natural scene consumption did not stop/replace original run"):return
 host.evidence("compound.before")
 if not diagnostic_ok():return
 var original_preconditions:bool=not host.automation.running and not host.battle_open and host.session._pending.is_empty()
 var original_status:Dictionary={}
 if original_preconditions:original_status=host.quest_loot.followup_status(host) # Original short-circuit position: at most once.
 host.evidence("compound.after",{"status_called":original_preconditions,"status_return":host.value_evidence(original_status)})
 if not diagnostic_ok():return
 if not check(original_preconditions and original_status.get("closed",false),"Original saved result and original auto close create actual C1"):return
 var closed:Dictionary=entry().duplicate(true)
 if not check(not closed.open_span and closed.saved_battles==1 and closed.new_items==0,"One real non-target result closed same budget"):return
 if not persisted("c2-before-open"):return
 var before:Dictionary=live_recovery_record()
 if not diagnostic_ok():return
 var disk:Dictionary=checked_disk_bytes(path)
 if disk.is_empty():return
 var bak:Dictionary=checked_disk_bytes(path+".bak")
 if bak.is_empty():return
 var old_obligation=host.value_evidence(host.quest_loot.open_obligation)
 var session:NextOpenFaultSession=host.session
 session.expected_path=path
 session.expected_closed=host.session.snapshot().duplicate(true)
 session.expected_open=session.expected_closed.duplicate(true)
 session.expected_open.quest_loot.entries[State.STEP].revision+=1
 session.expected_open.quest_loot.entries[State.STEP].issued_seq+=1
 session.expected_open.quest_loot.entries[State.STEP].open_span=true
 for pair in [["backend",host],["session",session],["runner",host.quest_auto],["identity",host.quest_auto.identity],["timer",host.quest_loot],["battle",host.battle],["automation",host.automation]]:session.expected_owners[pair[0]]=weakref(pair[1])
 session.expected_identity=host.quest_auto.identity.checkpoint().duplicate(true)
 session.expected_step=host.quest_auto.step.duplicate(true)
 session.expected_binding={"connection":host.quest_auto.connection,"client":host.quest_auto.client}
 session.expected_position={"map_id":host.automation.position_map,"cell":host.automation.position_cell}
 session.expected_serial=host.quest_save_serial;session.expected_cache=host.last_saved_payload
 session.chain_serial=session.expected_serial
 session.expected_primary=before.primary.duplicate(true);session.expected_backup=before.backup.duplicate(true)
 session.original_ticket=weakref(original_status.token)
 session.original_lifetime=weakref(host.quest_loot.lifetime)
 session.original_auto_token=weakref(host.automation.start_lifetime)
 if not check(session.base_owner_matches(host,"loot_battle"),"Frozen original C1 owners identity binding and saved baseline exist before arming"):return
 print("NEXT OPEN OWNER FROZEN ",JSON.stringify({"owners":host.value_evidence(session.expected_owners),"identity":session.expected_identity,"binding":host.value_evidence(session.expected_binding),"position":session.expected_position,"step":session.expected_step,"serial":session.expected_serial,"cache_sha256":session.expected_cache.sha256_text(),"ticket_token":host.value_evidence(session.original_ticket)}))
 session.armed=true # Only the future exact candidate writer creates the blocker.
 var published:Array=[]
 host.event.connect(func(event):
  if event.get("type")=="profile":published.append(event.duplicate(true)))
 host.set_process(true) # Original scheduler/queue, never consume or flush directly.
 if not await ready(func():return not session.fault_error.is_empty() or not host.quest_auto.running or host.quest_auto.observed_gate,"Original next-open reaches actual refusal or unexpected successful gate"):return
 if not diagnostic_ok():return
 if not check(session.context_records.size()==2 and session.context_records[0].valid and session.context_records[1].reply.get("persisted",true)==false and not session.context_records[1].reply.get("ok",true),"Same real C1 consume admission returns explicit noncommit"):return
 if not check(session.fired and session.attempts==1 and session.writer_records.size()==2 and not session.writer_records[1].saved,"Exactly one real next-open candidate writer fails on own tmp directory"):return
 var failed_values:Dictionary=live_recovery_record()
 print("NEXT OPEN FAILED VALUES ",JSON.stringify({"actual":failed_values,"expected_native":before.native,"expected_cache":before.cache,"expected_entry":closed,"initial_serial":before.serial,"expected_serial":session.chain_serial,"checkpoints":session.checkpoint_records}))
 if not diagnostic_ok():return
 if not check(session.sync_noncommit_verified,"Actual admission return proves unchanged closed baseline and original serial synchronously"):return
 if not check(failed_values.native==before.native,"Failed next open preserves entire closed native profile"):return
 if not check(failed_values.cache==before.cache,"Failed next open preserves entire saved cache"):return
 if not check(failed_values.serial==session.chain_serial,"Post-refusal serial equals only the complete observed checkpoint chain"):return
 if not check(entry()==closed,"Failed next open preserves full closed entry"):return
 var reason:String="预算保存失败，未启动尝试。"
 if not check(not host.quest_auto.running and not host.quest_auto.owns_battle and host.quest_auto.phase=="manual" and host.quest_auto.message==reason and host.quest_auto.pause_reason==reason,"P1 declares exact failed-open manual reason without storage repair fiction"):return
 if not check(host.quest_loot.anchor_ms<0 and not host.quest_loot.storage_paused and host.value_evidence(host.quest_loot.open_obligation)==old_obligation and host.quest_loot.close_pending.is_empty() and host.quest_loot.battle_receipt.is_empty() and host.value_evidence(host.quest_loot.ready_frame)==before.ready and not host.quest_loot.ready_frame.has("continuation_gate") and not host.battle_open and host.session._pending.is_empty(),"No new open or battle storage obligation remains after noncommit"):return
 if not check(host.quest_auto.identity.checkpoint()==identity and str(host.quest_auto.connection)==before.owner.connection and host.quest_auto.client==before.owner.client,"Failed-open publication retains original run identity and connection binding"):return
 if not check(not published.is_empty(),"Actual P1 failure profile published through original process"):return
 for world in worlds:
  if not await ready(func():return world.state.derived.get("quest_auto",{}).get("phase","")=="manual" and world.state.derived.get("quest_auto",{}).get("pause_reason","")==reason,"Both real remote consumers receive failed-open reason"):return
  var auto:Dictionary=world.state.derived.quest_auto
  var view:Dictionary=budget(world)
  if not check(world.backend==null and not auto.running and auto.message==reason and view.activity=="stopped" and not view.finish_current_battle and not view.recovery_blocked and not view.enabled and view.entry.budget_id==closed.budget_id and view.entry.revision==closed.revision and view.entry.saved_battles==1 and view.entry.new_items==0 and view.entry.saved_used_ms==closed.used_ms,"Both WS projections retain actual closed budget lower bound and no storage pause"):return
  if not check(world.quest_helper_travel.auto_status()==reason and panel(world).content().contains("本步已停止，保留预算历史。") and panel(world).content().contains("已保存战数 1") and not panel(world).content().contains("写盘／保存失败修复等待中"),"Production manual formatter and actual panel expose stopped history, not repair controls"):return
 if not diagnostic_ok():return
 if not persisted("c2-failed-open"):return
 var after_disk:Dictionary=checked_disk_bytes(path)
 if after_disk.is_empty():return
 var after_bak:Dictionary=checked_disk_bytes(path+".bak")
 if after_bak.is_empty():return
 var final_values:Dictionary=live_recovery_record()
 print("NEXT OPEN FINAL VALUES ",JSON.stringify({"actual":final_values,"expected_native":before.native,"expected_cache":before.cache,"expected_serial":session.chain_serial,"checkpoints":session.checkpoint_records}))
 if not diagnostic_ok():return
 if not check(after_disk.bytes==disk.bytes and after_bak.bytes==bak.bytes,"Natural failure publication preserves exact primary and backup bytes"):return
 if not check(final_values.native==before.native,"Final full native remains the closed baseline"):return
 if not check(final_values.cache==before.cache,"Final cache remains the closed baseline"):return
 if not check(final_values.serial==session.chain_serial,"Final serial equals the continuous observed checkpoint chain"):return
 if not check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path+".tmp")),"Own failed-write blocker remains intact without rescue"):return
 if archive("c2-failed-open-final").is_empty():return
 if not diagnostic_ok():return
 if not check(not host.checkpoint_active and not host.save_active and not host.body_active and session.chain_serial==session.expected_serial+session.checkpoint_records.size() and host.quest_save_serial==session.chain_serial,"Checkpoint chain is complete through archive before monitoring retirement"):return
 session.retired=true # Only AFTER all failure, double-WS, full disk and archive checks.
 print("NEXT OPEN FAULT RETIRED ",JSON.stringify({"attempts":session.attempts,"error":session.fault_error,"blocker_preserved":DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path+".tmp"))}))
 if not await dispose_scenes():return
 if not diagnostic_ok():return
 print("LOOT NEXT OPEN FAILURE REMOTE: PASS (closed history/manual only; no repair/retry/second battle)")
 quit(0)
func prepare_bound()->bool:
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 host=CheckpointObservedBackend.new();host.session=NextOpenFaultSession.new();host.quest_loot=NextOpenObservedLoot.new();host.quest_auto=ContinuationRunner.new();root.add_child(host);host.set_process(false);host.save_path=path
 if not source_fixture():return false
 host.event.connect(func(event):observe("backend-final",event))
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 host.observer_server=weakref(server)
 if not check(server.start()==OK,"Detach direct-backend transport starts on actual port0"):return false
 var first=await connect_scene("detach-a")
 if first==null:return false
 if not check(server.clients().size()==1,"Original C1 is sole promoted peer"):return false
 initiating_peer=server.clients()[0].get_instance_id();initiating_client=first._client_id
 first.link.message.connect(func(event):observe("ws-a",event))
 var second=await connect_scene("detach-b")
 if second==null:return false
 second.link.message.connect(func(event):observe("ws-b",event))
 for world in worlds:
  if not await ready(func():return not world.data.is_empty() and int(world.data.map_id)==100 and world.cell==source_cell and not world.area_transition_busy and not world.moving,"Natural scene loads actual ordinary source initial fixture"):return false
  if not check(await Wait.settle(self,world),"Natural initial reports settle before E1"):return false
  if not host.report_violation.is_empty():return false
 if not check(server.clients().size()==2 and server.clients().any(func(peer):return peer.get_instance_id()==initiating_peer) and first._client_id==initiating_client,"Actual initial C1 transport/client retained"):return false
 if not check(host.automation.position_map==100 and host.automation.position_cell==source_cell,"Both natural reports preserve actual source cell"):return false
 var q=host.quest_auto
 q.identity.begin();q.identity.select_step(State.STEP)
 q.running=true;q.internal=true;q.detached=false;q.restored=false
 q.connection=initiating_peer;q.client=initiating_client;q.phase="loot_admission";q.step=Sources.step()
 host.quest_loot.clock=func():return clock_ms
 var admitted:Dictionary=host.quest_loot.admit_prepared_run(host)
 if not diagnostic_ok():return false
 print("LOOT DETACH ADMISSION ",JSON.stringify({"peer":str(initiating_peer),"client":initiating_client,"reply":admitted,"state":host.report_state()}))
 if not check(admitted.get("ok",false),"Real peer-bound E1 admission succeeds once"):return false
 if not check(entry().open_span and host.quest_loot.anchor_ms==clock_ms,"Real durable entry and active timer exist before disconnect"):return false
 if not persisted("detach-admitted"):return false
 return check(q.connection==initiating_peer and q.client==initiating_client,"Actual initiating binding retained; no test admission publication")
