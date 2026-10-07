extends "res://tests/quest_auto_loot_battle_cancel_test.gd"
## Controlled transaction regression, NOT the natural 2760 pilot or public entry.
## Existing seed4101/group169 E1/E2 fixture; no seed search or injected receipt.
## auto_tick=false holds the original active battle across real wall deadlines.
## The original compact driver resumes only after queued cancellation is checked.
const Wait=preload("res://tests/support/wait.gd")
const Loot=preload("res://server/quest_auto_loot.gd")
const PATH="user://loot-heartbeat-controlled-cancel.json"
const MAX_SETTLEMENT_TICKS:=100

class ControlledBackend:
 extends CountedBackend
 var pause_after_process:=true
 var process_count:=0
 var settlement_ticks:=0
 var after_process:Callable
 func _process(delta:float)->void:
  super._process(delta)
  process_count+=1
  if not pause_after_process:settlement_ticks+=1
  if pause_after_process or settlement_ticks>=MAX_SETTLEMENT_TICKS:set_process(false)
  if after_process.is_valid():after_process.call(self)

class ObservedHeartbeat:
 extends "res://server/quest_auto_loot.gd"
 var context:Dictionary={}
 var before_call:Callable
 var after_call:Callable
 var invalid_reentry:Callable
 func heartbeat_normal_process(b,generation:int,entry_epoch:int)->void:
  if not context.is_empty():
   invalid_reentry.call()
   return
  var invocation:Dictionary={"backend":weakref(b),"generation":generation,"entry_epoch":entry_epoch,"dispatch_epoch":b._dispatch_epoch,"process_depth":b._process_depth,"dispatch_depth":b._dispatch_boundary_depth,"observer_depth":b._observer_depth,"flush_depth":b._flush_depth,"depth":b._depth,"claimed":false,"call":null,"kind":""}
  var prior:Dictionary=before_call.call(b)
  context=invocation
  super.heartbeat_normal_process(b,generation,entry_epoch)
  context={}
  after_call.call(b,invocation,prior)
 func same_generation_probe(b,generation:int,entry_epoch:int)->void:
  super.heartbeat_normal_process(b,generation,entry_epoch)

var phase:="setup"
var clock_base:Array=[]
var wall_origin:=0
var clock_calls:=0
var unmatched_clock_calls:=0
var matched_clock_calls:=0
var invalid_samples:=0
var accepted_samples:=0
var cancelled_samples:=0
var same_generation_rejections:=0
var nested_rejections:=0
var queued_observers:=0
var cancel_observers:=0
var cancel_armed:=false
var expected_revision:=-1
var expected_event_kind:=""
var stop_baseline:Dictionary={}
var stop_profile_ref:Dictionary={}
var stop_pending_ref:Dictionary={}
var stop_after_heartbeat:=false
var stop_after_observer:=false
var held_battle:Dictionary={}
var receipt:Dictionary={}
var field_baseline:=0
var commit_baseline:=0
var sample_records:Array[Dictionary]=[]
var observer_records:Array[Dictionary]=[]

func prepare_attempt(b,path:String,time:Array)->bool:
 if not setup(b,path):return false
 # Unchanged prerequisites from the existing E2 transaction fixture.
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 if not b.save():return false
 clock_base=time;wall_origin=Time.get_ticks_msec()
 # Install once BEFORE E1 seals the Callable. E2's existing explicit 500 ms
 # increments remain disclosed fixture input; P3/settlement use only wall time.
 b.quest_loot.clock=read_clock.bind(weakref(b))
 var admitted:Dictionary=b.quest_loot.admit_prepared_run(b)
 check(admitted.get("ok",false),"Controlled fixture uses actual durable E1 open")
 return failures==0

func real_clock()->int:
 return int(clock_base[0])+Time.get_ticks_msec()-wall_origin

func clock_context_current(b,timer:ObservedHeartbeat)->bool:
 var c:Dictionary=timer.context
 if c.is_empty() or c.claimed or timer.heartbeat_call==null:return false
 if not c.backend is WeakRef or not is_same(c.backend.get_ref(),b) or not is_same(b.quest_loot,timer):return false
 if b._process_depth!=1 or b._dispatch_boundary_depth!=1 or b._observer_depth!=0 or b._flush_depth!=0 or b._depth!=1:return false
 if c.process_depth!=1 or c.dispatch_depth!=1 or c.observer_depth!=0 or c.flush_depth!=0 or c.depth!=1:return false
 return b._normal_process_generation==c.generation and b._normal_process_entry_epoch==c.entry_epoch and b._dispatch_epoch==c.dispatch_epoch and c.entry_epoch==c.dispatch_epoch

func read_clock(owner:WeakRef)->Variant:
 clock_calls+=1
 var b=owner.get_ref()
 if not is_instance_valid(b):
  check(false,"Clock cannot outlive its exact backend")
  return real_clock()
 var timer:ObservedHeartbeat=b.quest_loot
 if not clock_context_current(b,timer):
  unmatched_clock_calls+=1
  return real_clock()
 var c:Dictionary=timer.context
 c.claimed=true;c.call=timer.heartbeat_call
 matched_clock_calls+=1
 var value:int=real_clock()
 c.value=value
 match phase:
  "invalid":
   check(invalid_samples==0,"Only one exact heartbeat consumes the invalid override")
   c.kind="invalid"
   return true
  "progress":c.kind="progress"
  "cancel":
   check(cancel_armed and cancelled_samples==0,"Only the successful queued progress observer arms cancellation")
   if failures:return value
   cancel_armed=false;c.kind="cancel"
   b.quest_auto.stop(b,"Controlled P3 clock cancellation")
   stop_profile_ref=b.session._profile;stop_pending_ref=b.session._pending
   stop_baseline=successor(b)
   expect_queued_profile(b,"cancel")
  _:
   check(false,"No extra eligible P3 call outside the three controlled stages")
 return value

func durable(b)->Dictionary:
 return {"profile":b.session.snapshot(),"pending":b.session._pending.duplicate(true),"settlement":b.session._loot_settlement.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"primary":FileAccess.get_file_as_bytes(b.save_path),"backup":FileAccess.get_file_as_bytes(b.save_path+".bak"),"fields":b.field_calls,"commits":b.commits,"rng":b.encounter_rng.state,"pressure":b.encounter_catalog.pressure}

func successor(b)->Dictionary:
 var timer:Dictionary=b.quest_loot.heartbeat_timer_snapshot()
 timer.erase("heartbeat_call") # Only the old in-flight call may retire.
 var q=b.quest_auto;var auto=b.automation
 var result:Dictionary=durable(b)
 result.merge({"clock":b.quest_loot.clock,"visit_guard":b.quest_visit_guard,"party_guard":b.party_guard,"stationary_running":b.stationary.running,"path":b.save_path,"session_id":b.session.get_instance_id(),"runner_id":q.get_instance_id(),"battle_object_id":b.battle.get_instance_id(),"timer_id":b.quest_loot.get_instance_id(),"automation_id":auto.get_instance_id(),"storage_json":b._storage_json,"revision":b.rev,"original_pending":b.original_quests.pending.duplicate(true),"battle_open":b.battle_open,"battle":b.battle._state.duplicate(true),"backend_battle":b.battle_state.duplicate(true),"runner":{"running":q.running,"internal":q.internal,"detached":q.detached,"restored":q.restored,"phase":q.phase,"step":q.step.duplicate(true),"identity":q.identity.checkpoint(),"identity_object":q.identity.get_instance_id(),"connection":q.connection,"client":q.client,"owns_battle":q.owns_battle,"message":q.message,"pause_reason":q.pause_reason},"automation":{"running":auto.running,"auto_tick":auto.auto_tick,"settings":auto.settings.duplicate(true),"position_map":auto.position_map,"position_cell":auto.position_cell,"single_battle":auto.single_battle,"compact_active":auto.compact_active,"clone_override":auto.clone_override_active,"hunt_running":auto.hunt_running,"flow_active":auto.flow_active(),"scope":auto.loot_scope.duplicate(true),"token":auto.start_lifetime,"turns":auto.turns,"battles":auto.battles,"reason":auto.stop_reason},"timer":timer})
 return result

func before_heartbeat(b)->Dictionary:
 if phase=="settlement":return {}
 return successor(b)

func invalid_reentry()->void:
 check(false,"Instrumentation must not mask a reentrant heartbeat invocation")

func expect_queued_profile(b,kind:String)->void:
 check(expected_revision==-1,"Previous exact queued profile has been consumed")
 var matches:=0
 for message in b._queue:
  if message.get("type")=="profile" and message.get("rev")==b.rev:matches+=1
 check(matches==1 and b._depth==1 and b._flush_depth==0 and b._observer_depth==0,"Original publish enqueues exactly its profile before outer flush")
 expected_revision=b.rev;expected_event_kind=kind

func after_heartbeat(b,c:Dictionary,prior:Dictionary)->void:
 if c.kind=="":return # Nested rejection / owner rejection consumes no clock.
 var timer:ObservedHeartbeat=b.quest_loot
 check(c.claimed and c.call is RefCounted and timer.heartbeat_call==null,"Exact P3 clock call is retired before queued observers")
 check(b.battle._state==held_battle and b.battle._state.active and not b.automation.auto_tick,"Held original battle remains active without a fabricated turn/result")
 if failures:return
 if c.kind=="invalid":
  invalid_samples+=1
  var after:Dictionary=successor(b)
  # A valid invocation records its generation/wall even when its sample is bad.
  for name in ["heartbeat_generation","heartbeat_wall_ms"]:
   prior.timer.erase(name);after.timer.erase(name)
  check(after==prior,"Invalid clock changes no trusted sample, stamp, owner, native profile, receipt or disk")
 elif c.kind=="progress":
  accepted_samples+=1
  check(timer.last_ms==c.value and timer.last_ms>int(prior.timer.last_ms) and timer.cached_sample.used_ms==timer.base_used_ms+timer.last_ms-timer.anchor_ms,"Real wall-derived sample installs exact active elapsed time")
  check(is_same(timer.progress_stamp.lifetime,timer.lifetime) and timer.progress_stamp.span==timer.span and timer.progress_stamp.ms==timer.last_ms and timer.progress_stamp.used_ms==timer.cached_sample.used_ms and timer.last_ms-int(prior.timer.progress_stamp.ms)>=Loot.PROGRESS_INTERVAL_MS,"Unchanged product progress threshold produces an actual stamp")
  check(durable(b)==durable_part(prior),"Heartbeat publication changes no profile, receipt, disk, RNG or transaction count")
  expect_queued_profile(b,"progress")
  var installed:Dictionary=successor(b)
  var queue_before:Array=b._queue.duplicate(true)
  var reads:int=clock_calls
  timer.same_generation_probe(b,int(c.generation),int(c.entry_epoch))
  check(successor(b)==installed and b._queue==queue_before and clock_calls==reads and timer.heartbeat_call==null,"Same real generation rejects a second heartbeat before sampling")
  if failures==0:same_generation_rejections+=1
 elif c.kind=="cancel":
  cancelled_samples+=1
  check(timer.last_ms==prior.timer.last_ms and timer.cached_sample==prior.timer.cached_sample and timer.progress_stamp==prior.timer.progress_stamp,"Stop invalidates only the old clock return; it cannot install its sample")
  check_stop_successor(b,"Old heartbeat retirement preserves the complete post-stop successor")
  stop_after_heartbeat=failures==0
 sample_records.append({"kind":c.kind,"generation":c.generation,"entry_epoch":c.entry_epoch,"wall_ms":timer.heartbeat_wall_ms,"sample_ms":timer.last_ms,"used_ms":timer.cached_sample.get("used_ms",-1),"battle_id":b.battle._state.battle_id,"call_retired":timer.heartbeat_call==null})
 check(sample_records.size()<=3,"Three controlled calls keep complete bounded evidence")

func durable_part(record:Dictionary)->Dictionary:
 var result:Dictionary={}
 for key in ["profile","pending","settlement","cache","serial","primary","backup","fields","commits","rng","pressure"]:result[key]=record[key]
 return result

func check_stop_successor(b,label:String)->void:
 check(not stop_baseline.is_empty() and is_same(b.session._profile,stop_profile_ref) and is_same(b.session._pending,stop_pending_ref) and successor(b)==stop_baseline,label)

func observe_profile(message:Dictionary,owner:WeakRef)->void:
 if message.get("type")!="profile" or int(message.get("rev",-1))!=expected_revision:return
 var b=owner.get_ref()
 check(is_instance_valid(b),"Queued profile retains its original host")
 if failures:return
 var kind:String=expected_event_kind
 expected_revision=-1;expected_event_kind=""
 queued_observers+=1
 check(b._depth==0 and b._flush_depth>0 and b._observer_depth>0 and b._process_depth==1 and b._dispatch_boundary_depth==1,"Matching profile comes through the original normal-process queued flush")
 check(b.quest_loot.heartbeat_call==null,"Queued observer sees no in-flight old heartbeat")
 if kind=="cancel":check_stop_successor(b,"Queued stop publication preserves the complete post-stop successor")
 if failures:return
 var before:Dictionary=successor(b)
 var queue_before:Array=b._queue.duplicate(true)
 var reads:int=clock_calls
 b.quest_loot.heartbeat_normal_process(b,b._normal_process_generation,b._normal_process_entry_epoch)
 check(successor(b)==before and b._queue==queue_before and clock_calls==reads and b.quest_loot.heartbeat_call==null,"Nested observer heartbeat rejects without clock/sample/receipt/owner mutation")
 if failures:return
 if kind=="progress":nested_rejections+=1;cancel_armed=true
 elif kind=="cancel":cancel_observers+=1;stop_after_observer=true
 else:check(false,"Only original progress and stop profile events count")
 observer_records.append({"kind":kind,"revision":message.rev,"generation":b._normal_process_generation,"call_retired":true,"nested_rejected":true,"state_unchanged":true})
 check(observer_records.size()<=2,"Both queued observer records are retained without overflow")

func after_process(b)->void:
 if failures:b.set_process(false);return
 if phase=="cancel":check_stop_successor(b,"Completed outer flush leaves the whole stop successor intact")
 if phase=="settlement" and not b.automation.running:b.set_process(false)

func one_process(b)->bool:
 var count:int=b.process_count
 b.set_process(true)
 var arrived:bool=await Wait.until(self,func():return failures>0 or b.process_count>count)
 check(arrived and b.process_count==count+1 and not b.is_processing(),"Exactly one real SceneTree process completes, including its queued flush")
 check(b._depth==0 and b._process_depth==0 and b._dispatch_boundary_depth==0 and b._observer_depth==0 and b._flush_depth==0 and b._queue.is_empty(),"Original complete dispatch boundary is retired without synthesized counters")
 return failures==0

func wait_due(b)->bool:
 var arrived:bool=await Wait.until(self,func():return Time.get_ticks_msec()>=b.quest_loot.heartbeat_wall_ms+Loot.HEARTBEAT_INTERVAL_MS and real_clock()>=int(b.quest_loot.progress_stamp.ms)+Loot.PROGRESS_INTERVAL_MS)
 check(arrived and not b.is_processing() and not b.automation.auto_tick and b.battle._state==held_battle and b.battle._state.active,"Real wall gates expire while the same original active battle is held")
 return failures==0

func read_bytes(path:String)->Dictionary:
 var file=FileAccess.open(path,FileAccess.READ)
 if file==null:check(false,"Evidence opens: "+path);return {}
 var length:int=file.get_length()
 var bytes:PackedByteArray=file.get_buffer(length)
 var error:int=file.get_error();file.close()
 check(length>0 and bytes.size()==length and error==OK,"Evidence read has complete length and successful I/O")
 if failures:return {}
 var digest:=HashingContext.new()
 check(digest.start(HashingContext.HASH_SHA256)==OK and digest.update(bytes)==OK,"Evidence SHA256 hashes the exact original bytes")
 if failures:return {}
 return {"bytes":bytes,"sha256":digest.finish().hex_encode(),"length":length}

func archive_pair(b,label:String)->bool:
 for suffix in ["",".bak"]:
  var source:Dictionary=read_bytes(b.save_path+suffix)
  if failures:return false
  var validated:Dictionary=ProfileCompare.validated_copy(b.session,source.bytes.get_string_from_utf8())
  check(validated.get("ok",false),"Whole "+label+suffix+" profile validates, including all UIDs and ledger fields")
  if failures:return false
  var path:String=b.save_path+".evidence/"+label+(".primary" if suffix.is_empty() else ".backup")
  check(not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path),"Never overwrite previous evidence")
  if failures:return false
  var file=FileAccess.open(path,FileAccess.WRITE)
  if file==null:check(false,"Archive opens for writing");return false
  file.store_buffer(source.bytes);file.flush()
  var error:int=file.get_error();file.close()
  check(error==OK,"Archive flush succeeds")
  var copied:Dictionary=read_bytes(path)
  if failures:return false
  check(copied==source,"Archived primary/backup exactly matches length, bytes and SHA256")
  print("CONTROLLED_P3_DISK ",JSON.stringify({"stage":label,"source":suffix,"length":source.length,"sha256":source.sha256}))
 return failures==0

func fresh_paths()->bool:
 for suffix in ["",".bak",".tmp",".resume.json",".resume.json.tmp",".resume.json.bak",".evidence"]:
  check(not FileAccess.file_exists(PATH+suffix) and not DirAccess.dir_exists_absolute(PATH+suffix),"Refuse reused controlled fixture path: "+suffix)
  if failures:return false
 check(DirAccess.make_dir_absolute(PATH+".evidence")==OK,"Create isolated evidence directory")
 return failures==0

func exercise(b)->bool:
 var time:Array=[1000]
 if not fresh_paths() or not real_battle(b,PATH,time):return false
 check(b.battle._state.active and b.automation.auto_tick and not b.keep_resume_current,"E2 actually starts an active original battle without resume side effects")
 if failures:return false
 held_battle=b.battle._state.duplicate(true)
 receipt=b.session._pending.quest_loot_receipt.duplicate(true)
 field_baseline=b.field_calls;commit_baseline=b.commits
 var opened:Dictionary=b.session._profile.quest_loot.entries[KEY].duplicate(true)
 var auto_token:RefCounted=b.automation.start_lifetime
 if not archive_pair(b,"opened"):return false
 # The sole controlled scheduling change. Never edit active/HP/turn/receipt,
 # compact policy, heartbeat generations, clock gates or product constants.
 b.automation.auto_tick=false
 b.set_process(false);root.add_child(b)
 b.event.connect(observe_profile.bind(weakref(b)))
 phase="invalid"
 if not await one_process(b):return false
 check(invalid_samples==1 and matched_clock_calls==1 and accepted_samples==0 and queued_observers==0,"Invalid first heartbeat is observed without publishing or poisoning the active owner")
 if failures or not archive_pair(b,"invalid"):return false
 phase="progress"
 if not await wait_due(b) or not await one_process(b):return false
 check(accepted_samples==1 and nested_rejections==1 and same_generation_rejections==1 and queued_observers==1 and cancel_armed,"A real accepted heartbeat publishes and only its queued nested-reject observer arms stop")
 if failures or not archive_pair(b,"progress"):return false
 phase="cancel"
 if not await wait_due(b) or not await one_process(b):return false
 check(cancelled_samples==1 and matched_clock_calls==3 and invalid_samples==1 and accepted_samples==1 and queued_observers==2 and nested_rejections+cancel_observers==queued_observers and cancel_observers==1 and not cancel_armed and expected_revision==-1 and stop_after_heartbeat and stop_after_observer,"Complete invalid-real-publish-nested-next-clock-stop sequence reaches both queued observers exactly once")
 check(not b.quest_auto.running and b.automation.running and is_same(b.automation.start_lifetime,auto_token) and b.session._pending.quest_loot_receipt==receipt and not b.quest_loot.frozen and b.battle._state==held_battle,"Cancellation preserves only the actual original active receipt and its original automation")
 check(clock_calls==matched_clock_calls+unmatched_clock_calls and unmatched_clock_calls>0,"Only exact real P3 clock calls consume one-shot actions; E1/E2 use normal clock values")
 if failures or not archive_pair(b,"cancelled"):return false
 phase="settlement"
 b.automation.auto_tick=true;b.pause_after_process=false;b.set_process(true)
 var finished:bool=await Wait.until(self,func():return failures>0 or not b.automation.running or b.settlement_ticks>=MAX_SETTLEMENT_TICKS)
 check(finished and not b.automation.running and b.settlement_ticks<=MAX_SETTLEMENT_TICKS,"Restored original compact driver completes within the existing 100 normal-tick bound")
 b.set_process(false)
 if failures:return false
 var entry:Dictionary=b.session._profile.quest_loot.entries[KEY]
 check(not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty() and b.battle_state.get("settled",false) and b.battle_state.get("battle_id")==receipt.ledger.battle_id and b.battle_state.get("outcome")=="win","The exact held receipt finishes through original battle settlement and close")
 check(b.commits==commit_baseline+1 and entry.saved_battles==opened.saved_battles+1 and entry.new_items==0 and entry.budget_id==opened.budget_id and entry.generation==opened.generation and entry.issued_seq==opened.issued_seq and entry.settled_seq==entry.issued_seq and not entry.open_span,"One original non-target transaction closes the same budget/span without a fabricated reward")
 check(not b.quest_auto.running and b.field_calls==field_baseline and not b.quest_loot.attempt_once(b).get("ok",true),"Cancelled runner never resurrects or rolls another field step")
 check(b.session._profile.original_items.count(2760)==0 and b.session._profile.original_instances.filter(func(row):return int(row.get("item_id",-1))==2760).is_empty(),"Original non-target fixture never creates a target item or UID")
 if failures or not complete_disk(b):return false
 var cache:Dictionary=ProfileCompare.validated_copy(b.session,b.last_saved_payload)
 check(cache.get("ok",false) and cache.get("profile",{})==b.session.snapshot(),"Complete cache matches native profile, UID inventory and ledger")
 if failures or not archive_pair(b,"settled"):return false
 var saved:Dictionary=durable(b)
 var repeated:Dictionary=b.handle({"type":"battle_close","battle_id":receipt.ledger.battle_id})
 check(not repeated.get("ok",true) and durable(b)==saved,"Repeated original battle ID cannot save/count/reward twice or mutate either disk file")
 if failures or not archive_pair(b,"repeated_close"):return false
 check(sample_records.size()==3 and observer_records.size()==2 and matched_clock_calls==3,"Original settlement consumes no fourth P3 call or extra observer")
 print("CONTROLLED_P3_EVIDENCE ",JSON.stringify({"samples":sample_records,"observers":observer_records,"clock_calls":clock_calls,"unmatched_clock_calls":unmatched_clock_calls,"settlement_ticks":b.settlement_ticks,"field_calls":b.field_calls,"commits_after_e2":b.commits-commit_baseline,"ledger":entry}))
 return failures==0

func run()->void:
 var b=ControlledBackend.new()
 b.quest_loot=ObservedHeartbeat.new()
 b.quest_loot.before_call=before_heartbeat
 b.quest_loot.after_call=after_heartbeat
 b.quest_loot.invalid_reentry=invalid_reentry
 b.after_process=after_process
 var ok:bool=await exercise(b)
 if not ok and failures==0:check(false,"Controlled fixture setup/completion returned failure")
 b.set_process(false)
 var retained_scope:Dictionary={}
 var weak_owners:Dictionary={}
 if ok:
  retained_scope=b.automation._loot_frame()
  weak_owners={"session":weakref(b.session),"battle":weakref(b.battle),"automation":weakref(b.automation),"runner":weakref(b.quest_auto),"timer":weakref(b.quest_loot)}
  for key in weak_owners:
   check(retained_scope.get(key) is WeakRef and Loot.scope_owner_matches(retained_scope,key,weak_owners[key].get_ref()),"Retained original scope keeps only weak owner backlinks")
 # Drop test-owned inspection snapshots; never clear any production ticket.
 stop_baseline={};stop_profile_ref={};stop_pending_ref={}
 b.free()
 for key in weak_owners:
  check(weak_owners[key].get_ref()==null and retained_scope[key].get_ref()==null,"Controlled host retirement releases every original scope owner")
 print("QUEST AUTO LOOT HEARTBEAT CONTROLLED CANCEL: %d failures; internal seed4101/group169; held auto_tick; natural pilot unchanged"%failures)
 quit(0 if ok and failures==0 else 1)
