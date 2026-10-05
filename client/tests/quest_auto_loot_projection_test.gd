extends "res://tests/quest_auto_loot_state_test.gd"
const Backend=preload("res://server/backend.gd")
const Sources=preload("res://server/quest_auto_loot_sources.gd")
func run()->void:
 var b=Backend.new();b.set_process(false);b.save_path="user://loot-projection.json"
 var created:Dictionary=State.acquire(State.empty(),KEY,ID,RUN,1,0)
 check(created.get("ok",false),"Projection ledger acquire fixture succeeds")
 if failures:b.free();quit(1);return
 var ledger:Dictionary=created.ledger
 var opened:Dictionary=State.open(ledger,KEY,State.identity(ledger.entries[KEY]))
 check(opened.get("ok",false),"Projection ledger open fixture succeeds")
 if failures:b.free();quit(1);return
 b.session._profile.quest_loot=opened.ledger
 check(b.save(),"Projection has actual trusted persisted baseline")
 if failures:b.free();quit(1);return
 var q=b.quest_auto;q.identity.begin();q.identity.select_step(KEY)
 q.running=true;q.step=Sources.step()
 var t=b.quest_loot
 var calls:Array=[0];var time:Array=[1000]
 t.clock=func():calls[0]+=1;return time[0]
 check(t.start_after_commit(KEY,b.session._profile.quest_loot.entries[KEY],q.identity.checkpoint()),"Explicit internal timer owner fixture")
 if failures:b.free();quit(1);return
 time[0]=2000;check(t.sample_active(),"Scheduling sample explicit outside snapshot")
 if failures:b.free();quit(1);return
 var before:Dictionary=b.session._profile.duplicate(true)
 var sample:Dictionary=t.cached_sample.duplicate(true);var sampled_last:int=t.last_ms
 var clock_calls:int=calls[0];var serial:int=b.quest_save_serial
 var pressure:int=b.encounter_catalog.pressure;var rng:int=b.encounter_rng.state
 var disk:=FileAccess.get_file_as_string(b.save_path)
 var first:Dictionary=q.snapshot(b).budget
 check(first.get("entry") is Dictionary,"Persisted projection exposes current entry")
 if failures:b.free();quit(1);return
 for i in range(3):q.snapshot(b)
 check(calls[0]==clock_calls and t.last_ms==sampled_last and t.cached_sample==sample,"Snapshots do not call clock or advance cached sample")
 if failures:b.free();quit(1);return
 check(b.session._profile==before and b.quest_save_serial==serial and b.encounter_catalog.pressure==pressure and b.encounter_rng.state==rng and FileAccess.get_file_as_string(b.save_path)==disk,"Snapshot preserves profile/RNG/pressure/disk")
 if failures:b.free();quit(1);return
 check(not first.enabled and not first.can_start and not first.can_stop and not first.can_adjust_limit and not first.can_reset,"Projection never enables unregistered feature or commands")
 if failures:b.free();quit(1);return
 check(first.entry.used_ms==1000 and first.entry.saved_used_ms==0,"Live sample separate from durable lower bound")
 if failures:b.free();quit(1);return
 time[0]=3000;check(t.sample_active(),"Second sample succeeds outside snapshot")
 if failures:b.free();quit(1);return
 var next:Dictionary=q.snapshot(b).budget
 check(next.get("entry") is Dictionary,"Second projection retains entry")
 if failures:b.free();quit(1);return
 check(next.entry.revision==first.entry.revision and next.entry.used_ms==2000,"Same durable revision legitimately has later sample")
 if failures:b.free();quit(1);return
 # Unsaved counts must never leak through the live profile candidate.
 b.session._profile.quest_loot.entries[KEY].new_items=5
 b.session._profile.quest_loot.entries[KEY].saved_battles=7
 check(q.snapshot(b).budget.entry.new_items==0 and q.snapshot(b).budget.entry.saved_battles==0,"Counters use committed baseline, not live candidate")
 if failures:b.free();quit(1);return
 b.session._profile=before.duplicate(true)
 b.session._profile.automation_settings={"quest":{"loot_minutes":180}}
 check(q.snapshot(b).budget.default_limit_minutes==30,"Uncommitted global preference not projected as saved")
 if failures:b.free();quit(1);return
 b.session._profile=before.duplicate(true)
 check(b._cmd_set_automation_settings({"settings":{"quest":{"loot_minutes":180}}}).ok,"Existing settings path persists preference")
 if failures:b.free();quit(1);return
 next=q.snapshot(b).budget
 check(next.default_limit_minutes==180 and next.entry.limit_ms==60000,"Saved global preference does not resize prior budget")
 if failures:b.free();quit(1);return
 b.session._profile=before.duplicate(true)
 check(t.pause_storage_for(t.lifetime),"Explicit storage cutoff fixture")
 if failures:b.free();quit(1);return
 time[0]+=100000
 next=q.snapshot(b).budget
 check(next.activity=="storage_paused" and next.entry.used_ms==2000 and calls[0]==clock_calls+2,"Storage pause projection never extrapolates time")
 if failures:b.free();quit(1);return
 q.identity.begin();q.identity.select_step(KEY)
 next=q.snapshot(b).budget
 check(next.entry.used_ms==next.entry.saved_used_ms and next.activity=="stopped","New run cannot relabel an old cached timer sample")
 if failures:b.free();quit(1);return
 # Owned original outstanding receipt is a labelled projection-only fixture,
 # not a battle/source transaction test and not evidence for drop eligibility.
 t.owner_session_id=b.session.get_instance_id()
 t.battle_receipt={"ledger":{"battle_id":"projection-original-battle"}}
 b.session._pending={"battle_id":"projection-original-battle","quest_loot_receipt":t.battle_receipt.duplicate(true)}
 next=q.snapshot(b).budget
 check(next.activity=="storage_paused" and next.finish_current_battle,"Cancelled old matching battle keeps budget obligation without a new-run label")
 if failures:b.free();quit(1);return
 b.session._pending={};t.battle_receipt={}
 b.session._profile=before.duplicate(true)
 ledger=b.session._profile.quest_loot
 var completed:Dictionary=State.progress(ledger,KEY,State.identity(ledger.entries[KEY]),60000,true)
 check(completed.get("ok",false),"Completed-limit projection fixture closes original span")
 if failures:b.free();quit(1);return
 ledger=completed.ledger
 b.session._profile.quest_loot=ledger
 b.session.OriginalEquipment.add(b.session._profile,2760)
 check(b.save(),"Saved completed-and-limit internal projection fixture")
 if failures:b.free();quit(1);return
 next=q.snapshot(b).budget
 check(next.activity=="completed" and next.entry.limit_reached,"Actual saved target wins over reached limit without an obligation")
 if failures:b.free();quit(1);return
 b.session._profile.quest_loot.entries[KEY].recovery_blocked=true
 check(b.save(),"Entry recovery fixture persisted")
 if failures:b.free();quit(1);return
 check(q.snapshot(b).budget.recovery_blocked and q.snapshot(b).budget.activity=="recovery_locked","Entry recovery lock overrides completion")
 if failures:b.free();quit(1);return
 b.session._profile.quest_loot=State.empty();b.session._profile.quest_loot.recovery_blocked=true
 check(b.save(),"Missing-entry root recovery fixture persisted")
 if failures:b.free();quit(1);return
 next=q.snapshot(b).budget
 check(next.entry==null and next.recovery_blocked and next.activity=="recovery_locked","Root OR lock remains with null entry")
 if failures:b.free();quit(1);return
 b.free()
 print("QUEST AUTO LOOT PROJECTION: %d failures; snapshots only, no UI or transport acceptance"%failures)
 quit(1 if failures else 0)
