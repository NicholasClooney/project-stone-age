extends "res://tests/quest_auto_loot_sample_clock_test.gd"
func run()->void:
 reset_probe("throttle")
 var b=SampleBackend.new();var time:Array=[1000]
 if not await reopen_fixture(b,"user://loot-p2-throttle.json",time):b.free();quit(1);return
 var baseline:Dictionary=progress_record(b)
 var anchor:int=b.quest_loot.anchor_ms
 var fields:int=b.field_calls;var commits:int=b.commits
 var old_revision:int=b.session._profile.quest_loot.entries[KEY].revision
 for offset in [999,1000,1999,2000]:
  time[0]=anchor+offset
  var will_roll:bool=time[0]>=b.quest_loot.next_attempt_ms
  # Explicit fixed no-hit fixture for each due step; no seed search/group roll.
  # This is NOT evidence for uninterrupted natural encounter probabilities.
  if will_roll:b.encounter_rng.seed=4101;b.encounter_catalog.pressure=5
  var rng_before:int=b.encounter_rng.state;var pressure_before:int=b.encounter_catalog.pressure
  var count_before:int=b.field_calls
  if not await one_normal_tick(b):b.free();quit(1);return
  if will_roll:
   var area:Dictionary=b.encounter_catalog.area_at(100,b.automation.position_cell)
   var expected_pressure:int=mini(clampi(pressure_before,clampi(int(area.probability_min),0,100),clampi(int(area.probability_max),0,100))+1,int(area.probability_max))
   check(b.field_calls==count_before+1 and b.field_result.get("ok",false) and not b.field_result.get("hit",true) and not b.battle_open and b.encounter_rng.state!=rng_before and b.encounter_catalog.pressure==expected_pressure,"Original no-hit changes exactly allowed RNG/pressure, at most one field_step")
   if failures:b.free();quit(1);return
  else:
   check(b.field_calls==count_before and b.encounter_rng.state==rng_before and b.encounter_catalog.pressure==pressure_before,"Early deadline samples without roll or RNG consumption")
   if failures:b.free();quit(1);return
  var expected_profiles:int=0 if offset==999 else (2 if offset==2000 else 1)
  check(p2_profiles.size()==expected_profiles and b.commits==commits and b.quest_save_serial==baseline.serial and b.last_saved_payload==baseline.cache and b.session.snapshot()==baseline.profile and b.session._pending==baseline.pending and b.battle.snapshot()==baseline.battle and FileAccess.get_file_as_bytes(b.save_path)==baseline.disk,"999/1000/1999/2000 throttle: original complete profile/cache/pending/battle/disk never sampled as new CAS")
  if failures:b.free();quit(1);return
  if offset in [1000,2000]:
   var view:Dictionary=p2_profiles.back().derived.quest_auto.budget
   check(view.entry.used_ms==b.quest_loot.base_used_ms+offset and view.entry.saved_used_ms==baseline.profile.quest_loot.entries[KEY].used_ms and view.entry.revision==old_revision and not view.enabled,"Queued v1 sample changes used_ms within same saved revision; still disabled")
   if failures:b.free();quit(1);return
 check(b.field_calls==fields+2,"Four actual processes, exactly two original no-hit steps")
 if failures:b.free();quit(1);return
 # Public timer API cannot restart an already-open anchor or reset stamp.
 var stamp:Dictionary=b.quest_loot.progress_stamp.duplicate(true)
 var accepted:bool=b.quest_loot.start_after_commit(KEY,b.session._profile.quest_loot.entries[KEY],b.quest_auto.identity.checkpoint())
 if failures:b.free();quit(1);return
 check(not accepted and b.quest_loot.progress_stamp==stamp,"Public start_after_commit refusal cannot reset active progress throttle")
 if failures:b.free();quit(1);return
 print("P2 PROGRESS COMPLETE throttle")
 b.free()
 reset_probe("battle_transfer")
 b=SampleBackend.new();time=[1000]
 if not await reopen_fixture(b,"user://loot-p2-battle-transfer.json",time):b.free();quit(1);return
 b.encounter_rng.seed=4101;b.encounter_catalog.pressure=50
 var reached:bool=false
 for index in range(200):
  time[0]=maxi(time[0],b.quest_loot.next_attempt_ms)
  var before:Dictionary=b.quest_loot.progress_stamp.duplicate(true)
  if not await one_normal_tick(b):b.free();quit(1);return
  if b.battle_open:
   check(b.session._pending.has("quest_loot_receipt") and b.session._pending.group_id==169 and b.quest_auto.phase=="loot_battle" and b.automation.running and b.quest_loot.progress_stamp==before,"Actual original full-pool battle transfer retains receipt and does not publish an idle sample stamp")
   if failures:b.free();quit(1);return
   reached=true;break
  time[0]+=500
 check(reached,"Fixed seed full-pool battle transfer within original bounded attempts")
 if failures:b.free();quit(1);return
 print("P2 PROGRESS COMPLETE battle_transfer; second battle started ONLY, NOT second result/drop")
 b.free()
 print("QUEST AUTO LOOT SAMPLE PROGRESS: 0 failures; 2 internal real-continuation fixtures")
 quit(0)
