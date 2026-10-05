extends "res://tests/quest_auto_loot_continuation_remote_ui_test.gd"
## TMP / UNPARSED / UNRUN. Real internal E1/169/C1/C2 + four normal-process idle samples.
## Two backend=null scenes; controlled clock and original no-hit seed/pressure disclosed.
const Codec=preload("res://network/codec.gd")
class ProgressLoot:
 extends "res://server/quest_auto_loot.gd"
 ## TMP ONLY / UNPARSED / UNRUN. Requires final committed P2, not current UI HEAD.
 ## Install this test-local subtype before first E1; arm only after real C2/P1 settles.
 var observe_progress:bool=false
 var observation_error:String=""
 var observing:bool=false
 var observation_sequence:int=0
 var value_baselines:Dictionary={} # Protocol-only copies, never seal/frame/Session.
 var value_signatures:Dictionary={} # Typed primitive serialization, never raw owners.
 var observations:Array=[] # Indexes, immutable primitive owner facts and existing revs.
 func fail_observation(reason:String)->void:
  if observation_error.is_empty():observation_error=reason
 func reject_key(container,key,source:String,path:Array)->void:
  if not observation_error.is_empty():return
  var detail:Dictionary={"source":source,"path":path.duplicate(true),"container_type":typeof(container),"container_type_name":type_string(typeof(container)),"key_type":typeof(key),"key_type_name":type_string(typeof(key)),"key_value_recorded":false}
  match typeof(key):
   TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING:
    detail.key_value=key;detail.key_value_recorded=true
   TYPE_FLOAT:
    if is_finite(key):detail.key_value=key;detail.key_value_recorded=true
  fail_observation("Non-string protocol evidence key")
  print("P2 KEY REJECT ",JSON.stringify(detail)) # Safe primitives only; never stringify Object/Callable.
 func pure_copy(value,depth:int=0,source:String="unspecified",path:Array=[]):
  if not observation_error.is_empty():return null
  if depth>64:
   fail_observation("Protocol evidence is cyclic or exceeds bounded depth");return null
  match typeof(value):
   TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING:return value
   TYPE_FLOAT:
    if not is_finite(value):fail_observation("Nonfinite protocol evidence")
    return value
   TYPE_ARRAY:
    var result:Array=[]
    for index in range(value.size()):
     var child_path:Array=path.duplicate(true);child_path.append({"index":index})
     var copied=pure_copy(value[index],depth+1,source,child_path)
     if not observation_error.is_empty():return null
     result.append(copied)
    return result
   TYPE_DICTIONARY:
    var result:Dictionary={}
    for key in value:
     if not key is String and not key is StringName:
      reject_key(value,key,source,path);return null
     var child_path:Array=path.duplicate(true);child_path.append({"key":String(key),"key_type":typeof(key)})
     var copied=pure_copy(value[key],depth+1,source,child_path)
     if not observation_error.is_empty():return null
     result[key]=copied
    return result
  fail_observation("Object, Callable or non-protocol value in queue evidence")
  return null
 func typed_content(value,depth:int=0,source:String="typed-content",path:Array=[]):
  if not observation_error.is_empty():return null
  if depth>64:
   fail_observation("Typed evidence is cyclic or exceeds bounded depth");return null
  var kind:int=typeof(value)
  match kind:
   TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING:return [kind,value]
   TYPE_FLOAT:
    if not is_finite(value):fail_observation("Nonfinite typed evidence");return null
    return [kind,value]
   TYPE_ARRAY:
    var items:Array=[]
    for index in range(value.size()):
     var child_path:Array=path.duplicate(true);child_path.append({"index":index})
     var item=typed_content(value[index],depth+1,source,child_path)
     if not observation_error.is_empty():return null
     items.append(item)
    return [kind,items]
   TYPE_DICTIONARY:
    var entries:Array=[]
    for key in value:
     if not key is String and not key is StringName:
      reject_key(value,key,source,path);return null
     var child_path:Array=path.duplicate(true);child_path.append({"key":String(key),"key_type":typeof(key)})
     var item=typed_content(value[key],depth+1,source,child_path)
     if not observation_error.is_empty():return null
     entries.append([typeof(key),String(key),item]) # Only the two known built-in scalar key types.
    return [kind,entries]
  fail_observation("Object, Callable or non-protocol value in typed evidence")
  return null
 func typed_signature(value,source:String)->String:
  var content=typed_content(value,0,source)
  if not observation_error.is_empty():return ""
  return JSON.stringify(content) # Diagnostic fingerprint only; native values are never replaced.
 func remember(value,source:String)->String:
  var copied=pure_copy(value,0,source)
  if not observation_error.is_empty():return ""
  var signature:String=typed_signature(copied,source+".typed-index")
  if not observation_error.is_empty():return ""
  var key:String=signature.sha256_text()
  if value_baselines.has(key):
   if value_signatures.get(key)!=signature or value_baselines[key]!=copied:fail_observation("Evidence content key collision")
  else:
   value_baselines[key]=copied # Original Dictionary key types retained by result[key].
   value_signatures[key]=signature
   print("P2 VALUE ",JSON.stringify({"sha256":key,"typed_signature":signature,"value":copied}))
  return key
 func scalar_id(value)->String:
  return str(value.get_instance_id()) if typeof(value)==TYPE_OBJECT and is_instance_valid(value) else "invalid"
 func stamp_values()->Dictionary:
  var stamp:Dictionary=progress_stamp
  return {"lifetime_id":scalar_id(stamp.get("lifetime")),"span":pure_copy(stamp.get("span",{}),0,"stamp.span"),"ms":stamp.get("ms"),"used_ms":stamp.get("used_ms")}
 func valid_owner(value,label:String)->bool:
  if typeof(value)!=TYPE_OBJECT or not is_instance_valid(value):
   fail_observation("Invalid owner before property access: "+label);return false
  return true
 func owner_values(b)->Dictionary:
  var result:Dictionary={"complete":false}
  if not observation_error.is_empty() or not valid_owner(b,"backend"):return result
  result.backend=scalar_id(b)
  var q=b.quest_auto
  if not valid_owner(q,"runner"):return result
  result.runner=scalar_id(q)
  var identity_owner=q.identity
  if not valid_owner(identity_owner,"identity"):return result
  result.identity_object=scalar_id(identity_owner)
  var session_owner=b.session
  if not valid_owner(session_owner,"session"):return result
  result.session=scalar_id(session_owner)
  var auto_owner=b.automation
  if not valid_owner(auto_owner,"automation"):return result
  result.automation=scalar_id(auto_owner)
  var battle_owner=b.battle
  if not valid_owner(battle_owner,"battle"):return result
  result.battle=scalar_id(battle_owner)
  var timer_owner=b.quest_loot
  if not valid_owner(timer_owner,"timer") or not is_same(timer_owner,self):
   fail_observation("Foreign timer owner");return result
  result.timer=scalar_id(timer_owner)
  var parsed=JSON.new()
  if parsed.parse(b.last_saved_payload)!=OK:
   fail_observation("Saved cache is not valid JSON");return result
  var profile=parsed.data
  var ledger=profile.get("quest_loot") if profile is Dictionary else null
  var entries=ledger.get("entries") if ledger is Dictionary else null
  var entry=entries.get("jewels:hunt:2760") if entries is Dictionary else null
  if not entry is Dictionary:
   fail_observation("Saved baseline has no actual loot entry");return result
  for pair in [["identity",identity_owner.checkpoint()],["step",q.step],["span",span],["saved_entry",entry]]:
   var copied=pure_copy(pair[1],0,"owner."+pair[0])
   if not observation_error.is_empty():return result
   result[pair[0]]=copied
  result.merge({"lifetime":scalar_id(lifetime),"ready_token":scalar_id(ready_frame.get("ready_token")),"ready_lifetime":scalar_id(ready_frame.get("lifetime")),"ready_capability":scalar_id(ready_frame.get("capability")),"admission":scalar_id(admission),"connection":str(q.connection),"client":q.client,"running":q.running,"internal":q.internal,"detached":q.detached,"restored":q.restored,"phase":q.phase,"path":b.save_path,"map_id":auto_owner.position_map,"cell":[auto_owner.position_cell.x,auto_owner.position_cell.y],"serial":b.quest_save_serial,"depth":b._depth,"process_depth":b._process_depth,"flush_depth":b._flush_depth,"observer_depth":b._observer_depth,"normal_generation":b._normal_process_generation})
  result.complete=true
  return result
 func record_failure(sequence:int,stage:String,extra:Dictionary={})->void:
  var record:Dictionary={"sequence":sequence,"stage":stage,"error":observation_error,"extra":extra}
  observations.append(record);print("P2 OBSERVER ",JSON.stringify(record))
 func publish_attempt_progress(b,s:Dictionary)->void:
  if not observe_progress:
   super.publish_attempt_progress(b,s) # Exactly once, transparent before arming.
   return
  observation_sequence+=1
  var sequence:int=observation_sequence
  if observing:
   fail_observation("Reentrant progress publisher: attribution unavailable")
   super.publish_attempt_progress(b,s) # Never suppress the actual nested production call.
   record_failure(sequence,"nested-return")
   return
  observing=true
  var before:Dictionary=owner_values(b)
  if not observation_error.is_empty() or not before.get("complete",false):
   super.publish_attempt_progress(b,s) # Pre-observation failure still forwards exactly once.
   record_failure(sequence,"pre-owner-return",{"before":before});observing=false;return
  var host_weak:WeakRef=weakref(b)
  var timer_weak:WeakRef=weakref(self)
  var cache_before:String=b.last_saved_payload # Same-call full comparison; never stored in records.
  var clock_before:Callable=clock # Short local, never authority via str(clock).
  var stamp_before:Dictionary=stamp_values()
  var rev_before:int=b.rev
  var queue_ref:Array=b._queue
  var prefix_refs:Array=[]
  var prefix_copy:Array=[]
  var prefix_signatures:Array=[]
  if observation_error.is_empty():
   for prefix_index in range(queue_ref.size()):
    var event=queue_ref[prefix_index]
    if not event is Dictionary:
     fail_observation("Non-Dictionary queue prefix");break
    var copied=pure_copy(event,0,"queue.prefix",[{"index":prefix_index}])
    if not observation_error.is_empty():break
    var signature:String=typed_signature(copied,"queue.prefix.typed-index")
    if not observation_error.is_empty():break
    prefix_refs.append(event);prefix_copy.append(copied);prefix_signatures.append(signature)
  var prefix_key:String=remember(prefix_copy,"remember.prefix") if observation_error.is_empty() else ""
  if observation_error.is_empty() and (before.depth<=0 or before.process_depth<=0 or before.flush_depth!=0 or before.observer_depth!=0 or stamp_before.lifetime_id=="invalid"):
   fail_observation("Progress publisher is outside original owned normal-process queue boundary")
  # s is forwarded only. Never read, retain, duplicate, serialize or replay its seal/frame.
  super.publish_attempt_progress(b,s)
  if not observation_error.is_empty():
   record_failure(sequence,"preflight-or-nested-return",{"before":before,"prefix":prefix_key});observing=false;return
  var current=host_weak.get_ref()
  if not is_instance_valid(current) or not is_same(current,b) or not is_same(timer_weak.get_ref(),self) or not is_same(current.quest_loot,self):
   fail_observation("Publisher host/timer retired or replaced")
   record_failure(sequence,"owner-return",{"prefix":prefix_key});observing=false;return
  var after:Dictionary=owner_values(current)
  if not observation_error.is_empty() or not after.get("complete",false):
   record_failure(sequence,"post-owner-return",{"before":before,"after":after});observing=false;return
  var cache_equal:bool=current.last_saved_payload==cache_before
  var clock_equal:bool=clock==clock_before
  if not cache_equal or not clock_equal:
   fail_observation("Full saved cache or original clock Callable changed")
   record_failure(sequence,"cache-clock-return",{"cache_equal":cache_equal,"clock_equal":clock_equal,"before_cache_sha256":cache_before.sha256_text(),"after_cache_sha256":current.last_saved_payload.sha256_text()});observing=false;return
  var stamp_after:Dictionary=stamp_values()
  if not observation_error.is_empty() or before!=after:
   fail_observation("Owner, identity, binding, saved baseline or dispatch context changed during publish")
   record_failure(sequence,"changed-owner-return",{"before":before,"after":after});observing=false;return
  if not is_same(current._queue,queue_ref) or current._queue.size()<prefix_refs.size():
   fail_observation("Queue replaced, cleared or shortened during publish")
  else:
   for index in range(prefix_refs.size()):
    if not is_same(current._queue[index],prefix_refs[index]) or current._queue[index]!=prefix_copy[index]:
     fail_observation("Original queue prefix replaced, reordered or mutated");break
    var signature:String=typed_signature(current._queue[index],"queue.prefix.typed-recheck")
    if not observation_error.is_empty():break
    if signature!=prefix_signatures[index]:
     fail_observation("Original queue prefix native key/value type changed");break
  if not observation_error.is_empty():
   record_failure(sequence,"unattributable",{"before":before,"after":after,"stamp_before":stamp_before,"stamp_after":stamp_after,"prefix":prefix_key,"queue_size":current._queue.size()})
   observing=false;return
  # Read only extant newly appended events. Never rebuild one from current snapshot.
  var added:Array=[]
  var profiles:Array=[]
  for index in range(prefix_refs.size(),current._queue.size()):
   var copied=pure_copy(current._queue[index],0,"queue.event-copy",[{"index":index}])
   if not observation_error.is_empty():break
   if not copied is Dictionary:
    fail_observation("New queue event is not a protocol Dictionary");break
   var value_key:String=remember(copied,"remember.event-copy")
   if not observation_error.is_empty():break
   added.append({"queue_index":index,"value":value_key,"type":copied.get("type"),"rev":copied.get("rev")})
   if copied.get("type")=="profile":profiles.append(copied)
  if not observation_error.is_empty():
   record_failure(sequence,"event-copy-return",{"prefix":prefix_key,"added":added});observing=false;return
  var advanced:bool=stamp_after!=stamp_before
  var attributable:bool=false
  if advanced:
   if stamp_after.lifetime_id!=stamp_before.lifetime_id or stamp_after.span!=stamp_before.span or not stamp_after.ms is int or not stamp_before.ms is int or stamp_after.ms-stamp_before.ms<1000 or stamp_after.used_ms==stamp_before.used_ms or profiles.size()!=1 or current.rev!=rev_before+1:
    fail_observation("Stamp advance does not identify one original throttled profile publication")
   else:
    var event:Dictionary=profiles[0]
    var derived=event.get("derived")
    var q=derived.get("quest_auto") if derived is Dictionary else null
    var budget=q.get("budget") if q is Dictionary else null
    var entry=budget.get("entry") if budget is Dictionary else null
    if not q is Dictionary or not entry is Dictionary:
     fail_observation("Appended profile has no authoritative quest/budget entry")
    elif event.get("rev")!=current.rev or q.get("run_id")!=before.identity.get("run_id") or q.get("step_id")!=before.identity.get("step_id") or q.get("revision")!=before.identity.get("revision") or entry.get("budget_id")!=stamp_after.span.get("budget_id") or entry.get("generation")!=stamp_after.span.get("generation") or entry.get("budget_id")!=before.saved_entry.get("budget_id") or entry.get("generation")!=before.saved_entry.get("generation") or entry.get("revision")!=before.saved_entry.get("revision") or before.saved_entry.get("issued_seq")!=stamp_after.span.get("issued_seq") or entry.get("used_ms")!=stamp_after.used_ms:
     fail_observation("Appended profile rev/identity/span/sample does not match this publisher")
    else:attributable=true
  elif not added.is_empty() or current.rev!=rev_before:
   fail_observation("Queue events/rev changed without this publisher advancing its stamp")
  var record:Dictionary={"sequence":sequence,"stage":"return","error":observation_error,"before":before,"after":after,"stamp_before":stamp_before,"stamp_after":stamp_after,"prefix":prefix_key,"prefix_count":prefix_refs.size(),"added":added,"rev_before":rev_before,"rev_after":current.rev,"cache_equal":cache_equal,"clock_equal":clock_equal,"cache_sha256":cache_before.sha256_text(),"attributable":attributable and observation_error.is_empty()}
  observations.append(record);print("P2 OBSERVER ",JSON.stringify(record))
  observing=false
class PeriodicBackend:
 extends StopObservedBackend
 var values:Dictionary={}
 var serial_armed:bool=false
 var baseline:Dictionary={}
 var expected_serial:int=-1
 var checkpoint_active:bool=false
 var save_active:bool=false
 var body_active:bool=false
 var save_count:int=0
 var body_count:int=0
 var edges:Array=[]
 var field_calls:int=0
 var field_result:Dictionary={}
 func remember_value(value)->String:
  var encoded:String=JSON.stringify(value)
  var key:String=encoded.sha256_text()
  if values.has(key):
   if values[key]!=encoded:latch_error("Evidence key collision")
  else:
   values[key]=encoded
   print("P2 UI VALUE ",JSON.stringify({"key":key,"value_json":encoded}))
  return key
 func journal(stage:String,value:Dictionary)->void:
  var keys:Dictionary={}
  for key in value:
   if key=="derived" and value[key] is Dictionary:
    var derived:Dictionary={}
    for child in value[key]:derived[child]=remember_value(value[key][child])
    keys[key]={"children":derived}
   else:keys[key]={"value":remember_value(value[key])}
  print("P2 UI RECORD ",JSON.stringify({"stage":stage,"fields":keys}))
 func owners_valid()->bool:
  if not diagnostic_error.is_empty():return false
  for pair in [["session",session],["runner",quest_auto],["timer",quest_loot],["auto",automation],["battle",battle]]:
   if not is_instance_valid(pair[1]):latch_error("Retired diagnostic owner: "+pair[0]);return false
  if not is_instance_valid(quest_auto.identity):latch_error("Retired diagnostic identity");return false
  return true
 func disk_evidence(path:String)->Dictionary:
  if not diagnostic_error.is_empty():return {}
  return super.disk_evidence(path)
 func ticket_evidence()->Dictionary:
  if not owners_valid():return {}
  return super.ticket_evidence()
 func checkpoint_frame_evidence(checkpoint:Dictionary)->Dictionary:
  if not owners_valid():return {}
  return super.checkpoint_frame_evidence(checkpoint)
 func stop_observation()->Dictionary:
  if not owners_valid():return {}
  return super.stop_observation()
 func evidence(stage:String,extra:Dictionary={})->void:
  if not owners_valid():return
  var value:Dictionary=ticket_evidence()
  if not diagnostic_error.is_empty():return
  journal("c1:"+stage,{"value":value,"extra":extra})
 func owner_record()->Dictionary:
  if not owners_valid():return {}
  return {"backend":str(get_instance_id()),"session":str(session.get_instance_id()),"runner":str(quest_auto.get_instance_id()),"identity_owner":str(quest_auto.identity.get_instance_id()),"timer":str(quest_loot.get_instance_id()),"auto":str(automation.get_instance_id()),"battle":str(battle.get_instance_id()),"identity":quest_auto.identity.checkpoint().duplicate(true),"step":quest_auto.step.duplicate(true),"connection":str(quest_auto.connection),"client":quest_auto.client,"path":save_path,"map_id":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y],"running":quest_auto.running,"detached":quest_auto.detached,"phase":quest_auto.phase}
 func saved_record()->Dictionary:
  if not owners_valid():return {}
  var record:Dictionary={"owner":owner_record(),"profile":session.snapshot().duplicate(true),"cache":last_saved_payload,"serial":quest_save_serial,"pending":session._pending.duplicate(true),"settlement":session._loot_settlement.duplicate(true),"battle":battle._state.duplicate(true),"battle_open":battle_open,"auto_running":automation.running}
  record.primary=disk_evidence(save_path)
  if not diagnostic_error.is_empty():return record
  record.backup=disk_evidence(save_path+".bak")
  return record
 func saved_matches(record:Dictionary,serial:int)->bool:
  if not diagnostic_error.is_empty() or record.get("serial")!=serial:return false
  for key in baseline:
   if key!="serial" and record.get(key)!=baseline[key]:return false
  return true
 func transport(command:Dictionary)->Dictionary:
  var result:Dictionary={"same_backend":false,"member":false,"peer":str(command.get("_quest_connection",-1)),"members":[]}
  if not diagnostic_error.is_empty():return result
  var server=observer_server.get_ref() if observer_server!=null else null
  if is_instance_valid(server):
   result.same_backend=is_same(server.backend,self)
   for peer in server.clients():
    if not is_instance_valid(peer):latch_error("Retired diagnostic transport peer");return result
    result.members.append({"id":str(peer.get_instance_id()),"state":peer.get_ready_state()})
    if peer.get_instance_id()==command.get("_quest_connection",-1) and peer.get_ready_state()==WebSocketPeer.STATE_OPEN:result.member=true
  return result
 func _cmd_checkpoint(command:Dictionary)->Dictionary:
  var watch:bool=serial_armed
  var nested:bool=checkpoint_active or save_active or body_active
  var before:Dictionary={};var origin:Dictionary={};var expected:int=expected_serial
  if watch and diagnostic_error.is_empty():
   before=saved_record();origin=transport(command)
   journal("checkpoint.before",{"command":command.duplicate(true),"origin":origin,"before":before,"expected":expected})
   if nested or not saved_matches(before,expected) or not origin.same_backend or not origin.member or command.get("type")!="checkpoint" or command.get("map_id")!=baseline.owner.map_id or command.get("x")!=baseline.owner.cell[0] or command.get("y")!=baseline.owner.cell[1]:latch_error("Unrelated, changed-owner or reentrant sample checkpoint")
   if not nested:checkpoint_active=true;save_count=0;body_count=0
  var reply:Dictionary=super._cmd_checkpoint(command)
  if watch and diagnostic_error.is_empty():
   var after:Dictionary=saved_record()
   var valid:bool=not nested and diagnostic_error.is_empty() and save_count==1 and body_count==1 and reply.get("ok")==true and saved_matches(after,expected+1) and transport(command)==origin
   journal("checkpoint.after",{"after":after,"reply":reply.duplicate(true),"save_count":save_count,"body_count":body_count,"valid":valid})
   edges.append({"peer":origin.peer,"expected_before":expected,"expected_after":expected+1,"valid":valid})
   if valid:expected_serial=expected+1
   else:latch_error("Checkpoint edge did not prove original equal-payload +1")
  if watch and not nested:checkpoint_active=false
  return reply
 func save()->bool:
  var watch:bool=serial_armed;var nested:bool=save_active or body_active;var expected:int=expected_serial
  if watch and diagnostic_error.is_empty():
   var before:Dictionary=saved_record();journal("save.before",before)
   if not checkpoint_active or nested or save_count!=0 or not saved_matches(before,expected):latch_error("Unrelated save in periodic sample interval")
   save_count+=1
   if not nested:save_active=true
  var saved:bool=super.save()
  if watch and diagnostic_error.is_empty():
   var after:Dictionary=saved_record();journal("save.after",{"saved":saved,"after":after})
   if not saved or not saved_matches(after,expected+1):latch_error("Checkpoint save changed baseline or wrong serial delta")
  if watch and not nested:save_active=false
  return saved
 func _save_profile_boundary(checkpoint:Dictionary={})->bool:
  var watch:bool=serial_armed;var nested:bool=body_active;var expected:int=expected_serial
  if watch and diagnostic_error.is_empty():
   var before:Dictionary=saved_record();journal("body.before",{"before":before,"frame":checkpoint_frame_evidence(checkpoint)})
   if not checkpoint_active or not save_active or nested or body_count!=0 or not checkpoint.is_empty() or not saved_matches(before,expected):latch_error("Unrelated or nonempty sample checkpoint body")
   body_count+=1
   if not nested:body_active=true
  var saved:bool=super._save_profile_boundary(checkpoint)
  if watch and diagnostic_error.is_empty():
   var after:Dictionary=saved_record();journal("body.after",{"after":after,"saved":saved,"frame":checkpoint_frame_evidence(checkpoint)})
   if not saved or not checkpoint.is_empty() or not saved_matches(after,expected+1):latch_error("Sample checkpoint body changed baseline")
  if watch and not nested:body_active=false
  return saved
 func _cmd_field_step(command:Dictionary)->Dictionary:
  var reply:Dictionary=super._cmd_field_step(command) # Original roll exactly once; never fake miss.
  field_calls+=1;field_result=reply.duplicate(true)
  if serial_armed and diagnostic_error.is_empty():
   if not is_instance_valid(encounter_rng) or not is_instance_valid(encounter_catalog):
    latch_error("Retired field diagnostic RNG/catalog owner")
    return reply
   journal("field.after",{"command":command.duplicate(true),"reply":field_result,"rng":str(encounter_rng.state),"pressure":encounter_catalog.pressure})
  return reply
class PeriodicRunner:
 extends ContinuationRunner
 var actual_ticks:int=0
 func tick(b,delta:float)->void:
  super.tick(b,delta) # Inherited real consumer then stops NEXT process at real gate only.
  actual_ticks+=1
  if not is_instance_valid(b):return
  if not b.owners_valid():b.set_process(false);return
  if not b.quest_loot.observation_error.is_empty():b.set_process(false)
var delivered:Dictionary={"backend-final":{},"ws-a":{},"ws-b":{}}
var received_frames:Dictionary={"backend-final":{},"ws-a":{},"ws-b":{}}
func observe(stage:String,event:Dictionary)->void:
 if event.get("type")=="profile" and received_frames.has(stage):
  var frame:Dictionary={"process":Engine.get_process_frames(),"physics":Engine.get_physics_frames()}
  var original_rev=event.get("rev")
  if not received_frames[stage].has(original_rev):received_frames[stage][original_rev]=[]
  received_frames[stage][original_rev].append(frame)
  print("P2 RECEIVE FRAME ",JSON.stringify({"stage":stage,"rev":original_rev,"frame":frame}))
 host.journal("event:"+stage,event)
 if event.get("type")=="profile" and delivered.has(stage):
  var wire:Dictionary=Codec.decode(Codec.encode(event)) # Same actual wire normalization, not reconstructed snapshot.
  var rev:int=int(event.rev)
  if delivered[stage].has(rev) and delivered[stage][rev]!=wire:host.latch_error("Same event rev has differing original payloads")
  delivered[stage][rev]=wire
func diagnostic_ok()->bool:
 if not is_instance_valid(host):
  print("FAIL Diagnostic host retired");quit(1);return false
 if not host.owners_valid():return super.diagnostic_ok()
 if host.quest_loot is ProgressLoot and not host.quest_loot.observation_error.is_empty():
  print("FAIL P2 publisher evidence: "+host.quest_loot.observation_error);quit(1);return false
 return super.diagnostic_ok()
func ready(condition:Callable,note:String)->bool:
 var reached:bool=await Wait.until(self,func():return not is_instance_valid(host) or not host.owners_valid() or not host.report_violation.is_empty() or not host.quest_loot.observation_error.is_empty() or condition.call())
 if not diagnostic_ok() or not host.report_violation.is_empty():return false
 return check(reached,note)
func run()->void:
 path="user://loot-periodic-progress-remote.json"
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
  if event.get("type")=="profile":published.append(event.get("rev")))
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
 for world in worlds:
  if not check(await Wait.settle(self,world),"Natural reopened profile/checkpoints settle before P2 baseline"):return
  if not diagnostic_ok():return
 var timer=host.quest_loot
 var anchor:int=timer.anchor_ms
 if not check(timer.progress_stamp.ms==anchor and timer.progress_stamp.used_ms==timer.base_used_ms and timer.progress_stamp.span==timer.span,"Real reopen initializes actual P2 stamp without test gate/stamp writes"):return
 host.baseline=host.saved_record()
 if not diagnostic_ok():return
 host.expected_serial=host.quest_save_serial;host.serial_armed=true
 timer.observe_progress=true
 var initial_serial:int=host.expected_serial
 var initial_fields:int=host.field_calls
 var publications:Array=[]
 for offset in [999,1000,1999,2000]:
  clock_ms=anchor+offset # Pre-E1 Callable unchanged; only external fixture time changes.
  var will_roll:bool=clock_ms>=timer.next_attempt_ms
  if will_roll:host.encounter_rng.seed=4101;host.encounter_catalog.pressure=5
  var rng_before:int=host.encounter_rng.state;var pressure_before:int=host.encounter_catalog.pressure
  var fields_before:int=host.field_calls;var records_before:int=timer.observations.size();var ticks_before:int=host.quest_auto.actual_ticks
  host.set_process(true) # Actual SceneTree _process; inherited gate observer bounds the next tick only.
  if not await ready(func():return host.quest_auto.actual_ticks>ticks_before,"One original normal process returns at requested boundary"):return
  if not check(host.quest_auto.actual_ticks==ticks_before+1 and not host.is_processing(),"Exactly one normal process; no extra rescue tick"):return
  if not check(timer.observations.size()==records_before+1,"Original P2 publish-attempt called once by that process"):return
  var observed:Dictionary=timer.observations.back()
  if not check(observed.get("stage")=="return" and observed.get("error","").is_empty(),"Publisher attribution remains complete and owned"):return
  if will_roll:
   var area:Dictionary=host.encounter_catalog.area_at(100,host.automation.position_cell)
   var low:int=clampi(int(area.probability_min),0,100);var high:int=clampi(int(area.probability_max),0,100)
   var expected_pressure:int=mini(clampi(pressure_before,low,high)+1,high)
   if not check(host.field_calls==fields_before+1 and host.field_result.get("ok",false) and not host.field_result.get("hit",true) and host.encounter_rng.state!=rng_before and host.encounter_catalog.pressure==expected_pressure,"Approved original deterministic no-hit changes only actual RNG/pressure"):return
  elif not check(host.field_calls==fields_before and host.encounter_rng.state==rng_before and host.encounter_catalog.pressure==pressure_before,"Early sample does not roll or consume RNG"):return
  var due:bool=offset==1000 or offset==2000
  if not check(observed.attributable==due,"999/1000/1999/2000 attributable P2 publication cadence"):return
  if due:
   var candidates:Array=observed.added.filter(func(value):return value.type=="profile")
   if not check(candidates.size()==1,"One extant original queue profile belongs to this sample"):return
   var source:Dictionary=timer.value_baselines[candidates[0].value]
   var expected_wire:Dictionary=Codec.decode(Codec.encode(source))
   var event_rev:int=int(source.rev);publications.append(event_rev)
   for stage in ["backend-final","ws-a","ws-b"]:
    if not await ready(func():return delivered[stage].has(event_rev),"Original sample rev reaches "+stage):return
    if not check(delivered[stage][event_rev]==expected_wire,"Exact original sample wire event consumed coherently: "+stage):return
   for world in worlds:
    if not await ready(func():return world.state.rev>=event_rev and budget(world).get("entry",{}).get("used_ms",-1)==opened.used_ms+offset,"Production state consumes actual same-revision sample"):return
    var view:Dictionary=budget(world);var got:Dictionary=view.entry
    if not check(world.backend==null and got.budget_id==opened.budget_id and got.generation==opened.generation and got.revision==opened.revision and got.used_ms==opened.used_ms+offset and got.saved_used_ms==opened.used_ms and got.saved_battles==1 and got.new_items==0 and got.existing_items==opened.existing_items and not view.enabled and not view.can_start and not view.can_stop and not view.can_adjust_limit and not view.can_reset,"Same ledger revision exposes new sample and original saved lower bounds"):return
    var checked_frame:Dictionary={"process":Engine.get_process_frames(),"physics":Engine.get_physics_frames()}
    var panel_text:String=panel(world).content()
    var status_text:String=world.quest_helper_travel.auto_status()
    var expected_used:String="本步已用 %s ms / 上限 %s ms"%[str(opened.used_ms+offset),str(opened.limit_ms)]
    var expected_saved:String="可信已存用时 %s ms"%str(opened.used_ms)
    var expected_status:String="本步已用 %s ms"%str(opened.used_ms+offset)
    var contains_used:bool=panel_text.contains(expected_used)
    var contains_saved:bool=panel_text.contains(expected_saved)
    var contains_status:bool=status_text.contains(expected_status)
    var scene_index:int=worlds.find(world)
    var receive_stage:String="ws-a" if scene_index==0 else "ws-b"
    print("P2 DISPLAY CHECK ",JSON.stringify({"world_id":str(world.get_instance_id()),"scene_index":scene_index,"client":world._client_id,"event_rev":event_rev,"state_rev":world.state.rev,"used_ms":got.used_ms,"saved_used_ms":got.saved_used_ms,"phase":world.state.derived.get("quest_auto",{}).get("phase"),"auto_pending":world.quest_helper_travel.auto_pending(),"travel_active":world.quest_helper_travel.active,"travel_phase":world.quest_helper_travel.phase,"scene_processing":world.is_processing(),"transition":world.area_transition_busy,"moving":world.moving,"check_frame":checked_frame,"receive_frames":received_frames[receive_stage].get(event_rev,[]),"actual_panel":panel_text,"actual_status":status_text,"expected_used":expected_used,"expected_saved":expected_saved,"expected_status":expected_status,"contains_used":contains_used,"contains_saved":contains_saved,"contains_status":contains_status}))
    var waiting_world_id:int=world.get_instance_id()
    var waiting_clock:int=clock_ms
    var waiting_fields:int=host.field_calls
    var waiting_ticks:int=host.quest_auto.actual_ticks
    var presented:bool=await Wait.until(self,func():
     if not is_instance_valid(host) or not host.owners_valid():return true
     if not host.report_violation.is_empty() or not host.quest_loot.observation_error.is_empty():return true
     if host.is_processing() or clock_ms!=waiting_clock or host.field_calls!=waiting_fields or host.quest_auto.actual_ticks!=waiting_ticks:
      host.latch_error("Presentation wait changed stopped backend/clock/field/ticks");return true
     if not is_instance_id_valid(waiting_world_id):host.latch_error("Presentation scene retired");return true
     var current=instance_from_id(waiting_world_id)
     var current_panel=panel(current)
     if not is_instance_valid(current_panel):host.latch_error("Presentation panel retired");return true
     var current_text:String=current_panel.content()
     var current_status:String=current.quest_helper_travel.auto_status()
     return current.state.rev>=event_rev and budget(current).get("entry",{}).get("used_ms",-1)==opened.used_ms+offset and current_text.contains(expected_used) and current_text.contains(expected_saved) and current_status.contains(expected_status))
    if not diagnostic_ok() or not host.report_violation.is_empty():
     print("P2 DISPLAY POSTWAIT ABORT ",JSON.stringify({"world_id":str(waiting_world_id),"event_rev":event_rev,"diagnostic_error":host.diagnostic_error if is_instance_valid(host) else "host retired","report_error":host.report_violation if is_instance_valid(host) else "host retired","frame":{"process":Engine.get_process_frames(),"physics":Engine.get_physics_frames()}}))
     return
    checked_frame={"process":Engine.get_process_frames(),"physics":Engine.get_physics_frames()}
    panel_text=panel(world).content();status_text=world.quest_helper_travel.auto_status()
    contains_used=panel_text.contains(expected_used);contains_saved=panel_text.contains(expected_saved);contains_status=status_text.contains(expected_status)
    got=budget(world).get("entry",{})
    print("P2 DISPLAY POSTWAIT ",JSON.stringify({"presented":presented,"world_id":str(waiting_world_id),"scene_index":scene_index,"event_rev":event_rev,"state_rev":world.state.rev,"used_ms":got.get("used_ms"),"saved_used_ms":got.get("saved_used_ms"),"auto_pending":world.quest_helper_travel.auto_pending(),"check_frame":checked_frame,"receive_frames":received_frames[receive_stage].get(event_rev,[]),"actual_panel":panel_text,"actual_status":status_text,"expected_used":expected_used,"expected_saved":expected_saved,"expected_status":expected_status,"contains_used":contains_used,"contains_saved":contains_saved,"contains_status":contains_status,"backend_processing":host.is_processing(),"clock_ms":clock_ms,"field_calls":host.field_calls,"actual_ticks":host.quest_auto.actual_ticks}))
    if not check(presented,"Exact existing panel/status naturally present sample before original deadline"):return
    if not check(contains_used and contains_saved and contains_status,"Actual production panel/chip uses exact server sample values"):return
  for world in worlds:
   if not check(await Wait.settle(self,world),"Natural consumer roundtrip completes without filtering checkpoints"):return
   if not diagnostic_ok():return
  if not check(timer.observations.size()==records_before+1 and host.saved_matches(host.saved_record(),host.expected_serial),"No extra P2 process; full saved baseline remains with only proven checkpoint serial edges"):return
  if not persisted("p2-offset-"+str(offset)):return
  print("P2 UI BOUNDARY ",JSON.stringify({"offset":offset,"event_revs":publications,"serial_expected":host.expected_serial,"edges":host.edges,"sample":timer.stamp_values()}))
 if not check(publications.size()==2 and host.field_calls==initial_fields+2 and host.expected_serial==initial_serial+host.edges.size(),"Two real sample publications and two original no-hit rolls; complete checkpoint chain"):return
 if archive("p2-open-sampled").is_empty():return
 if not diagnostic_ok():return
 host.serial_armed=false;timer.observe_progress=false # Only after complete assertions/archive; teardown remains original.
 if not await dispose_scenes():return
 if not diagnostic_ok():return
 print("LOOT PERIODIC PROGRESS REMOTE: PASS (idle samples only; no second result/2760/public/P3)")
 quit(0)
func prepare_bound()->bool:
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 host=PeriodicBackend.new();host.quest_loot=ProgressLoot.new();host.quest_auto=PeriodicRunner.new();root.add_child(host);host.set_process(false);host.save_path=path
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
