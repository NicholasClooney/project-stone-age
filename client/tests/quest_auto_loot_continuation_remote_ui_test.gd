extends "res://tests/quest_auto_loot_active_detach_remote_ui_test.gd"
## UNRUN static draft. Internal E1, original169; not public/account/target-drop proof.
## Never calls test publish/sample/consume_followup or suppresses natural UI cancel/report.
class StopObservedBackend:
 extends ReportObservedBackend
 var diagnostic_error:String=""
 func latch_error(reason:String)->void:
  if diagnostic_error.is_empty():diagnostic_error=reason
 var evidence_sequence:int=0
 var evidence_origins:Array[String]=[]
 func value_evidence(value):
  if typeof(value)==TYPE_OBJECT and not is_instance_valid(value):return {"object_id":"invalid"}
  if value is WeakRef:
   var owner=value.get_ref()
   return {"weak_owner_id":str(owner.get_instance_id()) if is_instance_valid(owner) else "retired"}
  if value is Object:return {"object_id":str(value.get_instance_id())}
  if value is Callable:return {"callable":str(value)} # No Callable retained in record.
  if value is Dictionary:
   var result:Dictionary={}
   for key in value:result[str(key)]=value_evidence(value[key])
   return result
  if value is Array:
   var result:Array=[]
   for item in value:result.append(value_evidence(item))
   return result
  return value
 func disk_evidence(path:String)->Dictionary:
  if path.is_empty() or not FileAccess.file_exists(path):return {"exists":false,"content_state":"absent"}
  var file=FileAccess.open(path,FileAccess.READ)
  if file==null:
   var error:int=FileAccess.get_open_error();latch_error("Evidence open failed: "+path+" error="+str(error))
   return {"exists":true,"read_error":error}
  var length:int=file.get_length()
  var bytes:PackedByteArray=file.get_buffer(length)
  var read_error:int=file.get_error();file.close()
  if bytes.size()!=length or read_error!=OK:
   latch_error("Evidence read failed: "+path+" length="+str(length)+" got="+str(bytes.size())+" error="+str(read_error))
   return {"exists":true,"expected_size":length,"size":bytes.size(),"read_error":read_error}
  var hashing=HashingContext.new()
  var started:int=hashing.start(HashingContext.HASH_SHA256)
  if started!=OK:
   latch_error("Evidence hash start failed: "+path+" error="+str(started))
   return {"exists":true,"size":bytes.size(),"hash_error":started}
  if not bytes.is_empty():
   var updated:int=hashing.update(bytes)
   if updated!=OK:
    latch_error("Evidence hash update failed: "+path+" error="+str(updated))
    return {"exists":true,"size":bytes.size(),"hash_error":updated}
  var digest:PackedByteArray=hashing.finish()
  if digest.size()!=32:
   latch_error("Evidence hash finish failed: "+path+" size="+str(digest.size()))
   return {"exists":true,"size":bytes.size(),"digest_size":digest.size()}
  return {"exists":true,"size":bytes.size(),"content_state":"empty" if bytes.is_empty() else "nonempty","sha256":digest.hex_encode()}
 func raw_q_evidence()->Dictionary:
  var q=quest_auto
  return {"identity":q.identity.checkpoint().duplicate(true),"running":q.running,"internal":q.internal,"detached":q.detached,"restored":q.restored,"phase":q.phase,"connection":str(q.connection),"client":q.client,"step":q.step.duplicate(true),"map_id":automation.position_map,"cell":automation.position_cell,"battle_id":battle._state.get("battle_id",""),"scope":value_evidence(automation.loot_scope),"runner_id":str(q.get_instance_id()),"identity_object_id":str(q.identity.get_instance_id())}
 func ticket_evidence()->Dictionary:
  var ticket:Dictionary=quest_loot.followup # Read directly; NEVER status/current.
  var native:Dictionary=session.snapshot()
  var same_owner:Dictionary={}
  for pair in [["session",session],["battle",battle],["automation",automation],["runner",quest_auto],["identity_object",quest_auto.identity],["timer",quest_loot]]:
   var weak=ticket.get(pair[0])
   same_owner[pair[0]]=weak is WeakRef and is_same(weak.get_ref(),pair[1])
  return {"origins":evidence_origins.duplicate(),"state":raw_q_evidence(),"auto_running":automation.running,"battle_open":battle_open,"pending":session._pending.duplicate(true),"battle_state":battle_state.duplicate(true),"followup":value_evidence(ticket),"weak_owner_matches":same_owner,"serial":quest_save_serial,"ticket_serial":ticket.get("serial"),"serial_equal":ticket.has("serial") and quest_save_serial==ticket.serial,"profile_equal":ticket.has("profile") and native==ticket.profile,"cache_equal":ticket.has("payload") and last_saved_payload==ticket.payload,"identity_equal":ticket.has("identity") and quest_auto.identity.checkpoint()==ticket.identity,"binding_equal":ticket.get("connection") == quest_auto.connection and ticket.get("client") == quest_auto.client,"lifetime_equal":ticket.has("lifetime") and is_same(ticket.lifetime,quest_loot.lifetime),"auto_token_equal":ticket.has("auto_token") and is_same(ticket.auto_token,automation.start_lifetime),"path_equal":ticket.get("path")==save_path,"native_profile":native,"native_sha256":JSON.stringify(native).sha256_text(),"cache_sha256":last_saved_payload.sha256_text(),"primary":disk_evidence(save_path),"backup":disk_evidence(save_path+".bak")}
 func evidence(stage:String,extra:Dictionary={})->void:
  evidence_sequence+=1
  print("C1 EVIDENCE ",JSON.stringify({"ordinal":evidence_sequence,"stage":stage,"value":ticket_evidence(),"extra":extra}))
 func save()->bool:
  evidence("save.before",{"stack":get_stack()})
  var saved:bool=super.save() # One original save, no observer save.
  evidence("save.after",{"saved":saved})
  return saved
 func checkpoint_frame_evidence(checkpoint:Dictionary)->Dictionary:
  # Convert references to scalar IDs immediately; never retain or mutate the frame.
  var call=checkpoint.get("call")
  var saved_call=checkpoint.get("saved_call")
  return {"nonempty":not checkpoint.is_empty(),"frame":value_evidence(checkpoint),"written":checkpoint.get("written",false),"has_call":checkpoint.has("call"),"has_saved_call":checkpoint.has("saved_call"),"saved_call_is_call":checkpoint.has("call") and checkpoint.has("saved_call") and is_instance_valid(call) and is_instance_valid(saved_call) and is_same(saved_call,call),"serial":quest_save_serial,"ticket_serial":quest_loot.followup.get("serial")}
 func _save_profile_boundary(checkpoint:Dictionary={})->bool:
  evidence("save_body.before",{"checkpoint":checkpoint_frame_evidence(checkpoint),"stack":get_stack()})
  var saved:bool=super._save_profile_boundary(checkpoint) # Exactly once, even when observation latched an error.
  evidence("save_body.after",{"checkpoint":checkpoint_frame_evidence(checkpoint),"saved":saved})
  return saved
 func close_battle()->String:
  evidence_origins.append("close_battle")
  evidence("close.before")
  var result:String=super.close_battle()
  evidence("close.after",{"outcome":result})
  evidence_origins.pop_back()
  return result
 func _cmd_checkpoint(command:Dictionary)->Dictionary:
  evidence_origins.append("checkpoint")
  evidence("checkpoint.before",{"command":command.duplicate(true),"peer_decimal":str(command.get("_quest_connection",-1))})
  var result:Dictionary=super._cmd_checkpoint(command)
  evidence("checkpoint.after",{"reply":result.duplicate(true)})
  evidence_origins.pop_back()
  return result
 func _loot_settlement_written(payload:String,owner,path:String)->void:
  evidence("candidate_cache.before",{"payload_sha256":payload.sha256_text(),"owner_id":str(owner.get_instance_id()) if is_instance_valid(owner) else "invalid","path":path})
  super._loot_settlement_written(payload,owner,path)
  evidence("candidate_cache.after",{"payload_sha256":payload.sha256_text()})
 func stop_observation()->Dictionary:
  var value:Dictionary=report_state() # Original read-only copied identity/binding/receipt/scope scalars.
  value.strict_walk=quest_auto.strict_walk
  value.message=quest_auto.message
  value.pause_reason=quest_auto.pause_reason
  value.runner_id=str(quest_auto.get_instance_id())
  value.identity_object_id=str(quest_auto.identity.get_instance_id())
  value.auto_id=str(automation.get_instance_id())
  value.auto_token_id=str(automation.start_lifetime.get_instance_id())
  var scope:Dictionary=automation.loot_scope
  value.scope_capability_id=str(scope.capability.get_instance_id()) if scope.get("capability") is RefCounted else "absent"
  return value
 func _cmd_quest_auto_stop(command:Dictionary)->Dictionary:
  var observed:Dictionary=command.duplicate(true)
  var before:Dictionary=stop_observation()
  var transport:Dictionary={"available":false,"incoming_member":false,"members":[]}
  var current_server=observer_server.get_ref() if observer_server!=null else null
  if is_instance_valid(current_server):
   transport.available=true
   transport.server_id=str(current_server.get_instance_id())
   transport.backend_matches=is_same(current_server.backend,self)
   transport.backend_id=str(current_server.backend.get_instance_id()) if is_instance_valid(current_server.backend) else "absent"
   transport.session_id=str(current_server.backend.session.get_instance_id()) if is_instance_valid(current_server.backend) and is_instance_valid(current_server.backend.session) else "absent"
   for peer in current_server.clients():
    transport.members.append({"peer":str(peer.get_instance_id()),"ready_state":peer.get_ready_state()})
    if peer.get_instance_id()==command.get("_quest_connection",-1):transport.incoming_member=true
  print("C2 WS STOP BEFORE ",JSON.stringify({"command":observed,"peer_decimal":str(observed.get("_quest_connection",-1)),"transport":transport,"state":before}))
  var reply:Dictionary=super._cmd_quest_auto_stop(command) # Exactly once, never suppress actual Stop.
  print("C2 WS STOP AFTER ",JSON.stringify({"command":observed,"peer_decimal":str(observed.get("_quest_connection",-1)),"before":before,"after":stop_observation(),"reply":reply.duplicate(true)}))
  return reply
class ContinuationRunner:
 extends "res://server/quest_auto.gd"
 var observed_gate:bool=false
 func tick(b,delta:float)->void:
  super.tick(b,delta) # Actual production consumer exactly once per real process.
  if not b.diagnostic_error.is_empty():b.set_process(false);return
  if b.quest_loot.ready_frame.has("continuation_gate"):
   observed_gate=true;b.set_process(false) # Bound after original consumer; original flush still runs.
func diagnostic_ok()->bool:
 if is_instance_valid(host) and not host.diagnostic_error.is_empty():
  print("FAIL Diagnostic evidence: "+host.diagnostic_error);quit(1);return false
 return true
func check(ok:bool,note:String)->bool:
 if not diagnostic_ok():return false
 return super.check(ok,note)
func ready(condition:Callable,note:String)->bool:
 var reached:bool=await Wait.until(self,func():return not host.diagnostic_error.is_empty() or not host.report_violation.is_empty() or condition.call())
 if not diagnostic_ok():return false
 if not host.report_violation.is_empty():return false
 return check(reached,note)
func run()->void:
 path="user://loot-continuation-remote.json"
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
 var original_profile:Dictionary=host.session.snapshot().duplicate(true)
 var published:Array=[]
 host.event.connect(func(event):
  if event.get("type")=="profile":published.append(event.duplicate(true)))
 host.set_process(true) # Real normal generation; never direct _process/tick/consume.
 if not await ready(func():return host.quest_auto.observed_gate or not host.quest_auto.running,"Normal process reaches continuation gate or actual stop"):return
 if not check(host.quest_auto.observed_gate and host.quest_auto.running,"C2 really installed continuation gate without UI stop rescue"):return
 var opened:Dictionary=entry().duplicate(true)
 if not check(opened.open_span and opened.budget_id==closed.budget_id and opened.generation==closed.generation and opened.revision==closed.revision+1 and opened.issued_seq==closed.issued_seq+1 and opened.used_ms==closed.used_ms and opened.saved_battles==closed.saved_battles and opened.new_items==closed.new_items and opened.existing_items==closed.existing_items,"Actual next open keeps cumulative budget and advances only real entry transaction"):return
 var expected:Dictionary=original_profile.duplicate(true)
 expected.quest_loot.entries[State.STEP]=opened
 if not check(host.session.snapshot()==expected,"Next open preserves full original profile outside actual entry"):return
 if not check(not published.is_empty(),"P1 original process emitted a real profile, no test publication"):return
 for world in worlds:
  if not await ready(func():return budget(world).get("entry",{}).get("revision",-1)==opened.revision,"Both backend-null consumers receive real reopened revision"):return
  var got:Dictionary=budget(world).entry
  if not check(world.backend==null and got.budget_id==opened.budget_id and got.generation==opened.generation and got.saved_used_ms==opened.used_ms and got.saved_battles==1 and got.new_items==0 and not budget(world).enabled,"Actual P1 WS projection preserves cumulative saved lower bound and unavailable controls"):return
  if not check(panel(world).content().contains("已保存战数 1") and panel(world).content().contains("本步累计实际获得 0"),"Actual panel consumes reopened cumulative counts"):return
 if not persisted("c2-after-open"):return
 if not verify_isolated_recovery():return
 if archive("c2-open-final").is_empty():return
 if not await dispose_scenes():return
 if not diagnostic_ok():return
 print("LOOT CONTINUATION REMOTE: PASS (one same-budget reopen only; no periodic sample/second battle/target drop)")
 quit(0)
func checked_disk_bytes(file_path:String)->Dictionary:
 var evidence:Dictionary=host.disk_evidence(file_path)
 if not diagnostic_ok():return {}
 if not check(evidence.get("exists",false),"Required isolated recovery evidence file exists: "+file_path):return {}
 var file=FileAccess.open(file_path,FileAccess.READ)
 if not check(file!=null,"Actual recovery evidence opens: "+file_path):return {}
 var length:int=file.get_length()
 var bytes:PackedByteArray=file.get_buffer(length)
 var error:int=file.get_error();file.close()
 if not check(error==OK and bytes.size()==length and length==evidence.get("size",-1),"Actual recovery evidence read is complete: "+file_path):return {}
 var hashing=HashingContext.new()
 if not check(hashing.start(HashingContext.HASH_SHA256)==OK,"Recovery copy hash starts"):return {}
 if not bytes.is_empty():
  if not check(hashing.update(bytes)==OK,"Recovery copy hash accepts actual bytes"):return {}
 var digest:PackedByteArray=hashing.finish()
 if not check(digest.size()==32 and digest.hex_encode()==evidence.get("sha256",""),"Recovery copy length and SHA match actual file evidence"):return {}
 return {"bytes":bytes,"evidence":evidence}
func live_recovery_record()->Dictionary:
 # Pure scalar/value evidence; no current/status/sample or ownership operation.
 return {"native":host.session.snapshot().duplicate(true),"cache":host.last_saved_payload,"serial":host.quest_save_serial,"owner":host.raw_q_evidence(),"session_id":str(host.session.get_instance_id()),"backend_id":str(host.get_instance_id()),"timer_id":str(host.quest_loot.get_instance_id()),"timer_lifetime":host.value_evidence(host.quest_loot.lifetime),"automation_id":str(host.automation.get_instance_id()),"auto_token":host.value_evidence(host.automation.start_lifetime),"auto_running":host.automation.running,"battle_open":host.battle_open,"pending":host.session._pending.duplicate(true),"ready":host.value_evidence(host.quest_loot.ready_frame),"gate":host.value_evidence(host.quest_loot.ready_frame.get("continuation_gate",{})),"primary":host.disk_evidence(path),"backup":host.disk_evidence(path+".bak")}
func verify_isolated_recovery()->bool:
 # Synchronous only. Loading an open span is recovery, never a neutral live read.
 var live_before:Dictionary=live_recovery_record()
 if not diagnostic_ok():return false
 var ready_ref:Dictionary=host.quest_loot.ready_frame
 var gate_ref:Dictionary=ready_ref.get("continuation_gate",{})
 if not check(not gate_ref.is_empty(),"Actual continuation gate exists before isolated loader"):return false
 var primary:Dictionary=checked_disk_bytes(path)
 if primary.is_empty():return false
 var backup:Dictionary=checked_disk_bytes(path+".bak")
 if backup.is_empty():return false
 var source_profile:Dictionary=ProfileCompare.validated_copy(host.session,primary.bytes.get_string_from_utf8())
 if not check(source_profile.get("ok",false) and source_profile.profile==live_before.native,"Actual source bytes validate as the complete live reopened profile"):return false
 var expected:Dictionary=live_before.native.duplicate(true)
 if not check(expected.quest_loot.entries.size()==1 and expected.quest_loot.entries.has(State.STEP) and expected.quest_loot.entries[State.STEP].open_span and not expected.quest_loot.entries[State.STEP].recovery_blocked and not expected.quest_loot.recovery_blocked,"Isolated recovery precondition is the sole actual unlocked open entry"):return false
 # Independent cold retirement from the exact primary; no recovered()/reset() oracle.
 var cold_entry:Dictionary=expected.quest_loot.entries[State.STEP]
 if not check(cold_entry.revision<2147483647,"Source revision permits the single cold-retirement transition"):return false
 cold_entry.open_span=false
 cold_entry.settled_seq=cold_entry.issued_seq
 cold_entry.revision+=1
 cold_entry.recovery_blocked=false
 expected.quest_loot.recovery_blocked=false
 var copy_path:String="user://loot-continuation-independent-recovery.json"
 for suffix in ["",".bak",".tmp"]:
  if not check(not FileAccess.file_exists(copy_path+suffix) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(copy_path+suffix)),"Isolated recovery destination is new: "+suffix):return false
 var output=FileAccess.open(copy_path,FileAccess.WRITE)
 if not check(output!=null,"Isolated primary byte-copy destination opens"):return false
 output.store_buffer(primary.bytes);output.flush()
 var write_error:int=output.get_error();var written_length:int=output.get_length();output.close()
 if not check(write_error==OK and written_length==primary.bytes.size(),"Actual primary byte copy is fully written without production save"):return false
 var copied:Dictionary=checked_disk_bytes(copy_path)
 if copied.is_empty():return false
 if not check(copied.bytes==primary.bytes and copied.evidence==primary.evidence,"Independent copy exactly preserves original primary length SHA and bytes"):return false
 print("ISOLATED RECOVERY BEFORE ",JSON.stringify({"path":copy_path,"live":live_before,"copy":copied.evidence,"expected":expected}))
 # This audit isolates cold ledger retirement, not native-day login luck.
 # Preserve every profile field by keeping this independent login on the source day.
 # Cross-day clock/seed behavior is covered by classic_luck_test.
 var source_login_time:int=int(source_profile.profile.player.last_luck_time)
 var independent=Session.new(func():return source_login_time)
 var loaded:bool=independent.load_game(copy_path) # Original loader once, own independent path only.
 print("ISOLATED RECOVERY RETURN ",JSON.stringify({"loaded":loaded,"last_error":independent.last_error}))
 var loaded_profile:Dictionary=independent.snapshot().duplicate(true)
 print("ISOLATED RECOVERY SNAPSHOT ",JSON.stringify(loaded_profile))
 var live_after:Dictionary=live_recovery_record()
 print("ISOLATED RECOVERY LIVE AFTER ",JSON.stringify(live_after))
 if not diagnostic_ok():return false
 if not check(live_after==live_before and is_same(host.quest_loot.ready_frame,ready_ref) and is_same(host.quest_loot.ready_frame.get("continuation_gate"),gate_ref),"Isolated loader preserves full live primary backup cache native serial owner ready and gate"):return false
 if not check(loaded,"Independent copy loads through the actual recovery loader"):return false
 if not check(loaded_profile==expected,"Complete loaded profile equals independent cold retirement, preserving budget lower bound, rewards and UIDs"):return false
 var source_entry:Dictionary=live_before.native.quest_loot.entries[State.STEP]
 var loaded_entry:Dictionary=loaded_profile.quest_loot.entries[State.STEP]
 for key in ["budget_id","origin_run_id","generation","limit_ms","used_ms","existing_items","new_items","saved_battles","issued_seq"]:
  if not check(loaded_entry[key]==source_entry[key],"Cold retirement preserves source entry field: "+key):return false
 if not check(maxi(0,loaded_entry.limit_ms-loaded_entry.used_ms)==maxi(0,source_entry.limit_ms-source_entry.used_ms),"Cold retirement preserves same-step remaining budget without reset"):return false
 var recovered_primary:Dictionary=checked_disk_bytes(copy_path)
 if recovered_primary.is_empty():return false
 var recovered_backup:Dictionary=checked_disk_bytes(copy_path+".bak")
 if recovered_backup.is_empty():return false
 var recovered_profile:Dictionary=ProfileCompare.validated_copy(independent,recovered_primary.bytes.get_string_from_utf8())
 var backup_profile:Dictionary=ProfileCompare.validated_copy(independent,recovered_backup.bytes.get_string_from_utf8())
 if not check(recovered_profile.get("ok",false) and recovered_profile.profile==expected and recovered_primary.bytes==JSON.stringify(loaded_profile).to_utf8_buffer(),"Isolated primary persists the complete recovered snapshot with exact serialized bytes"):return false
 if not check(backup_profile.get("ok",false) and backup_profile.profile==live_before.native and recovered_backup.bytes==primary.bytes and recovered_backup.evidence==primary.evidence,"Isolated backup preserves the exact original unlocked open-span primary"):return false
 var final_primary:Dictionary=checked_disk_bytes(path)
 if final_primary.is_empty():return false
 var final_backup:Dictionary=checked_disk_bytes(path+".bak")
 if final_backup.is_empty():return false
 var live_final:Dictionary=live_recovery_record()
 if not diagnostic_ok():return false
 if not check(final_primary.bytes==primary.bytes and final_backup.bytes==backup.bytes and live_final==live_before and is_same(host.quest_loot.ready_frame,ready_ref) and is_same(host.quest_loot.ready_frame.get("continuation_gate"),gate_ref),"Entire synchronous copy recovery audit leaves live bytes and exact execution owners unchanged"):return false
 print("ISOLATED RECOVERY AFTER ",JSON.stringify({"path":copy_path,"primary":recovered_primary.evidence,"backup":recovered_backup.evidence,"live":live_final}))
 return true
func prepare_bound()->bool:
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 host=StopObservedBackend.new();host.quest_auto=ContinuationRunner.new();root.add_child(host);host.set_process(false);host.save_path=path
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
