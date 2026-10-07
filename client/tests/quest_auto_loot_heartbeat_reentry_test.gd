extends "res://tests/quest_auto_loot_heartbeat_test.gd"
var p3_event_fired:=false
var p3_event_record:Dictionary={}
var p3_expected_used:=-1
var p3_was_queued:=false
func observe_p3_profile(message:Dictionary,weak_host:WeakRef)->void:
 if p3_event_fired or message.get("type")!="profile":return
 var budget:Dictionary=message.get("derived",{}).get("quest_auto",{}).get("budget",{})
 var entry:Dictionary=budget.get("entry",{})
 if int(entry.get("used_ms",-1))!=p3_expected_used:return
 var b=weak_host.get_ref()
 if not is_instance_valid(b):return
 p3_event_fired=true
 p3_was_queued=b._observer_depth>0 and b._flush_depth>0 and b._depth==0
 b.quest_auto.stop(b,"P3 queued observer successor")
 p3_event_record=p3_lite_record(b)
 check(p3_event_record.get("disk_read_ok",false),"Queued observer successor record reads the complete primary without I/O error")
func run()->void:
 # A real clock callback changes a saved profile and stops the runner while the
 # heartbeat invocation is on stack. The old frame must reject without writes.
 reset_p3("clock_save_stop")
 var b=SampleBackend.new();var time:Array=[1000]
 if not await start_real_receipt(b,"user://loot-p3-heartbeat-clock-reentry.json",time):b.free();quit(1);return
 var timer:HeartbeatLoot=b.quest_loot
 var before:Dictionary=heartbeat_projection(b)
 time[0]=maxi(time[0],timer.anchor_ms+1000);p3_armed=true
 if not await process_until_p3_retired(b):p3_armed=false;b.free();quit(1);return
 p3_armed=false
 check(p3_clock_reads==1 and not p3_clock_scope_mismatch and p3_action_fired and timer.retired_expected_clock_call and p3_clock_action_ok and p3_clock_action_read_ok and not p3_clock_action_record.is_empty() and timer.retire_rows.size()==1,"Only the one real P3 heartbeat clock call performs changed-save/stop reentry and retires its exact old call")
 if failures:b.free();quit(1);return
 check_retirement_matches_before(before,timer.retire_rows[0],"Old clock return does not overwrite saved successor sample, receipt or stamp")
 if failures:b.free();quit(1);return
 check(p3_retire_record==p3_clock_action_record,"The old P3 call retires after the callback without changing its committed successor state")
 if failures:b.free();quit(1);return
 check(p3_lite_record(b)==p3_clock_action_record,"After clock callback stop, the rest of the same normal process cannot write over its successor")
 if failures:b.free();quit(1);return
 check(b.session._pending.get("quest_loot_receipt",{})==before.receipt and b.battle_open,"Reentrant stop preserves the already-issued original battle for its normal settlement")
 if failures:b.free();quit(1);return
 b.free()

 # Isolate the exact same-payload Backend.save() case from stop and profile
 # mutation. It advances the backend save serial while preserving full profile
 # and disk bytes; the old P3 frame must retire without installing its sample.
 reset_p3("clock_same_save")
 b=SampleBackend.new();time=[1000]
 if not await start_real_receipt(b,"user://loot-p3-heartbeat-same-save.json",time):b.free();quit(1);return
 timer=b.quest_loot
 before=heartbeat_projection(b)
 var same_serial:int=b.quest_save_serial
 time[0]=timer.anchor_ms+1000
 p3_armed=true
 if not await process_until_p3_retired(b):p3_armed=false;b.free();quit(1);return
 p3_armed=false
 check(p3_clock_reads==1 and not p3_clock_scope_mismatch and p3_action_fired and timer.retired_expected_clock_call and p3_clock_action_ok and p3_clock_action_read_ok and p3_clock_action_record.serial==same_serial+1 and timer.retire_rows.size()==1,"A same-payload save is injected once inside the exact real P3 heartbeat call")
 if failures:b.free();quit(1);return
 check_retirement_matches_before(before,timer.retire_rows[0],"Same-payload save invalidates the old P3 sample without changing heartbeat state")
 if failures:b.free();quit(1);return
 check(p3_retire_record==p3_clock_action_record,"Post-save old-call retirement preserves exact full profile, cache, serial and primary bytes")
 if failures:b.free();quit(1);return
 check(b.battle_open and b.session._pending.get("quest_loot_receipt",{})==before.receipt and b.session._profile==p3_clock_action_record.profile and b.quest_save_serial==same_serial+1,"Same-payload callback keeps the original issued battle and committed native profile")
 if failures:b.free();quit(1);return
 if not await settle_using_real_normal_frames(b):b.free();quit(1);return
 b.free()

 # A valid sample publishes only through the actual queued profile event. The
 # observer stops the runner after the heartbeat has returned; no synthetic
 # synchronous observer or manual flush is used.
 reset_p3("valid")
 p3_event_fired=false;p3_event_record={};p3_was_queued=false
 b=SampleBackend.new();time=[1000]
 if not await start_real_receipt(b,"user://loot-p3-heartbeat-queued-reentry.json",time):b.free();quit(1);return
 timer=b.quest_loot
 time[0]=maxi(time[0],timer.anchor_ms+1000)
 p3_expected_used=timer.base_used_ms+time[0]-timer.anchor_ms
 b.event.connect(observe_p3_profile.bind(weakref(b)))
 p3_armed=true
 if not await process_until_p3_retired(b):p3_armed=false;b.free();quit(1);return
 p3_armed=false
 check(p3_clock_reads==1 and not p3_clock_scope_mismatch and timer.retire_rows.size()==1 and timer.retire_rows[0].last_ms==time[0],"One valid real normal heartbeat installs before queued publish")
 if failures:b.free();quit(1);return
 check(p3_event_fired and p3_was_queued and not p3_event_record.is_empty() and b._observer_depth==0 and b._flush_depth==0,"Original queued observer receives the real progress publication")
 if failures:b.free();quit(1);return
 check(p3_lite_record(b)==p3_event_record,"No old heartbeat tail writes after queued observer stops the original runner")
 if failures:b.free();quit(1);return
 print("QUEST AUTO LOOT HEARTBEAT REENTRY: %d failures; changed-save/stop, same-payload save, and real queued observer"%failures)
 b.free();quit(0)
