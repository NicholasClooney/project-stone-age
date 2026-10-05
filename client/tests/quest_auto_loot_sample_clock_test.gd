extends "res://tests/quest_auto_loot_continuation_test.gd"
## TMP / UNPARSED. Real original169 -> close -> normal-process E1 open.
## Internal connection71; no public/authentication/2760 evidence.
var p2_mode:String=""
var p2_armed:bool=false
var p2_fired:bool=false
var p2_clock_reads:int=0
var p2_visits:int=0
var p2_parties:int=0
var p2_successor:Dictionary={}
var p2_profiles:Array=[]
var p2_queue_seen:bool=false
var p2_after_seen:bool=false
var p2_last_field:Dictionary={}
class SampleBackend:
 extends CountedBackend
 var field_observer:Callable
 var field_result:Dictionary={}
 func _cmd_field_step(command:Dictionary)->Dictionary:
  var reply:Dictionary=super._cmd_field_step(command)
  field_result=reply.duplicate(true)
  if field_observer.is_valid():return field_observer.call(self,reply)
  return reply
func reset_probe(mode:String)->void:
 p2_mode=mode;p2_armed=false;p2_fired=false;p2_clock_reads=0;p2_visits=0;p2_parties=0
 p2_successor={};p2_profiles=[];p2_queue_seen=false;p2_after_seen=false;p2_last_field={}
func progress_record(b)->Dictionary:
 var record:Dictionary=frozen_record(b)
 # Only the currently-unwinding CHECKING/ROLLING handles may retire.
 record.timer.erase("attempt_call");record.timer.erase("attempt_frame")
 record.profile_ref=b.session._profile;record.pending_ref=b.session._pending
 record.pending=b.session._pending.duplicate(true);record.settlement=b.session._loot_settlement.duplicate(true)
 record.battle=b.battle.snapshot();record.battle_open=b.battle_open
 record.runner={"running":b.quest_auto.running,"phase":b.quest_auto.phase,"message":b.quest_auto.message,"pause_reason":b.quest_auto.pause_reason,"connection":b.quest_auto.connection,"client":b.quest_auto.client,"detached":b.quest_auto.detached}
 record.clock=b.quest_loot.clock;record.life=b.quest_loot.lifetime
 record.stamp=b.quest_loot.progress_stamp.duplicate(true)
 record.guards=[b.quest_visit_guard,b.party_guard]
 return record
func check_record(b,expected:Dictionary,label:String)->void:
 check(is_same(b.session._profile,expected.profile_ref) and is_same(b.session._pending,expected.pending_ref) and progress_record(b)==expected,label)
func remember_successor(b)->void:
 # Test-SceneTree member, NOT an array captured by clock/guard closures.
 p2_successor=progress_record(b)
func mutate_owner(b,operation:String)->void:
 match operation:
  "save":
   b.session._profile.player.gold+=13
   var saved:bool=b.save()
   if failures:return
   check(saved,"Original full successor save")
   if failures:return
  "same_save":
   var saved:bool=b.save()
   if failures:return
   check(saved,"Original same-payload successor save")
   if failures:return
  "identity":
   # Internal identity API, not a public start.
   b.quest_auto.identity.begin();b.quest_auto.identity.select_step(KEY)
   b.quest_auto.navigation.key="p2-internal-successor"
  "lifetime":
   # Token replacement only, not start_after_commit lifecycle acceptance.
   b.quest_loot.lifetime=RefCounted.new()
  "stop":
   b.quest_auto.stop(b,"P2 callback stop")
   if failures:return
 remember_successor(b)
func read_probe_clock(weak_host:WeakRef,time:Array):
 if not p2_armed:return time[0]
 p2_clock_reads+=1
 var b=weak_host.get_ref()
 check(b!=null,"Clock owner still alive")
 if failures:return time[0]
 if not p2_fired and p2_mode.begins_with("clock_"):
  p2_fired=true
  mutate_owner(b,p2_mode.trim_prefix("clock_"))
  if failures:return time[0]
 match p2_mode:
  "bool":return true
  "fraction":return float(time[0])+0.25
  "backward":return b.quest_loot.anchor_ms-1
  "outside":return State.MAX_MSEC+1
  "integer_float":return float(time[0])
 return time[0]
func visit_probe(weak_host:WeakRef)->String:
 if not p2_armed:return ""
 p2_visits+=1
 var b=weak_host.get_ref()
 check(b!=null,"Visit guard owner alive")
 if failures:return "test assertion"
 var selected:bool=(p2_mode in ["first_same_save","first_save","nested"] and p2_visits==1) or (p2_mode=="last_save" and p2_visits==2)
 if selected and not p2_fired:
  p2_fired=true
  if p2_mode=="nested":
   var prior:Dictionary=progress_record(b)
   var fields:int=b.field_calls
   b.quest_loot.tick_internal(b) # Real nested tail; not a normal generation.
   if failures:return "test assertion"
   check_record(b,prior,"Nested busy tick cannot stop outer execution")
   if failures:return "test assertion"
   check(b.field_calls==fields,"Nested call never rolls")
   if failures:return "test assertion"
  else:
   mutate_owner(b,"same_save" if p2_mode=="first_same_save" else "save")
   if failures:return "test assertion"
 if p2_mode=="guard_denied":return "real host denial"
 return ""
func party_probe(_weak_host:WeakRef)->String:
 if p2_armed:p2_parties+=1
 return ""
func prepare_attempt(b,path:String,time:Array)->bool:
 if not setup(b,path):return false
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 if not b.save():return false
 # Installed BEFORE E1 captures exact clock and guard Callables. No ready edits.
 var weak_host:WeakRef=weakref(b)
 b.quest_loot.clock=read_probe_clock.bind(weak_host,time)
 b.quest_visit_guard=visit_probe.bind(weak_host);b.party_guard=party_probe.bind(weak_host)
 var reply:Dictionary=b.quest_loot.admit_prepared_run(b)
 if failures:return false
 check(reply.get("ok",false),"Real E1 open with original frozen callbacks")
 return failures==0
func reopen_fixture(b,path:String,time:Array)->bool:
 if not closed_fixture(b,path,time):return false
 var reached:Array=[false]
 b.quest_auto.after_tick=func(host):
  if failures:host.set_process(false);return
  if not host.quest_loot.ready_frame.has("continuation_gate"):return
  reached[0]=true;host.set_process(false)
 root.add_child(b);b.set_process(true)
 var arrived:bool=await Wait.until(self,func():return failures>0 or reached[0])
 if failures:return false
 check(arrived and reached[0] and b.quest_loot.ready_frame.clock==b.quest_loot.clock,"Actual C1/barrier/E1 next span, not a synthetic gate")
 if failures:return false
 check(b.quest_loot.progress_stamp.ms==b.quest_loot.anchor_ms and b.quest_loot.progress_stamp.used_ms==b.quest_loot.base_used_ms,"New sealed span initializes progress stamp at real anchor/baseline")
 if failures:return false
 b.encounter_rng.seed=4101;b.encounter_catalog.pressure=5
 b.quest_auto.after_tick=after_probe_tick
 b.event.connect(observe_probe.bind(weakref(b)))
 p2_armed=true;p2_clock_reads=0;p2_visits=0;p2_parties=0
 return true
func after_probe_tick(b)->void:
 b.set_process(false)
 if failures:return
 p2_after_seen=true
 for event in b._queue:
  if event.get("type")=="profile":p2_queue_seen=true
func observe_probe(message:Dictionary,weak_host:WeakRef)->void:
 if failures or not p2_armed or message.get("type")!="profile":return
 var b=weak_host.get_ref()
 check(b!=null,"Queued profile host alive")
 if failures:return
 check(p2_after_seen and p2_queue_seen and b._depth==0 and b._flush_depth>0 and b._observer_depth>0,"Real original queue flush after normal tick")
 if failures:return
 p2_profiles.append(message.duplicate(true))
 if p2_mode.begins_with("observer_") and not p2_fired:
  p2_fired=true
  mutate_owner(b,p2_mode.trim_prefix("observer_"))
  if failures:return
func one_normal_tick(b)->bool:
 p2_after_seen=false;p2_queue_seen=false
 b.set_process(true)
 var arrived:bool=await Wait.until(self,func():return failures>0 or p2_after_seen)
 if failures:return false
 check(arrived and p2_after_seen,"One actual SceneTree process finished")
 return failures==0
func run()->void:
 for mode in ["integer_float","bool","fraction","backward","outside","clock_save","clock_identity","clock_lifetime","clock_stop"]:
  reset_probe(mode)
  var b=SampleBackend.new();var time:Array=[1000]
  if not await reopen_fixture(b,"user://loot-p2-clock-"+mode+".json",time):b.free();quit(1);return
  var prior:Dictionary=progress_record(b);var fields:int=b.field_calls;var commits:int=b.commits
  time[0]=b.quest_loot.anchor_ms+1000
  if not await one_normal_tick(b):b.free();quit(1);return
  if mode=="integer_float":
   check(b.field_calls==fields+1 and not b.battle_open and b.quest_auto.running and p2_profiles.size()==1,"Finite mathematical integer clock uses real no-hit and queued sample")
   if failures:b.free();quit(1);return
  elif mode.begins_with("clock_"):
   check(p2_fired and not p2_successor.is_empty() and b.field_calls==fields,"Clock callback invalidates old attempt before original roll")
   if failures:b.free();quit(1);return
   check_record(b,p2_successor,"Old clock return/tick tail preserves whole successor")
   if failures:b.free();quit(1);return
  else:
   check(b.field_calls==fields and not b.quest_auto.running and b.quest_loot.blocked and not b.quest_loot.close_pending.is_empty() and not b.quest_loot.close_pending.sample_ok,"Same-owner invalid clock reaches REAL stop and unverified-close obligation")
   if failures:b.free();quit(1);return
   check(b.session.snapshot()==prior.profile and b.last_saved_payload==prior.cache and b.quest_save_serial==prior.serial and FileAccess.get_file_as_bytes(b.save_path)==prior.disk and b.commits==commits and b.session._profile.quest_loot.entries[KEY].open_span,"Invalid clock cannot fake durable close or alter original disk")
   if failures:b.free();quit(1);return
  print("P2 CLOCK COMPLETE ",mode," visits=",p2_visits," parties=",p2_parties," clock=",p2_clock_reads)
  b.free()
 print("QUEST AUTO LOOT SAMPLE CLOCK: 0 failures; 9 internal real-continuation fixtures")
 quit(0)
