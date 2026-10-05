extends "res://tests/quest_auto_loot_battle_cancel_test.gd"
func run()->void:
 for mode in ["stop","detach"]:
  var b=CountedBackend.new();var time:Array=[1000]
  if not real_battle(b,"user://loot-battle-retry-"+mode+".json",time):b.free();quit(1);return
  var pending:Dictionary=b.session._pending.duplicate(true);var before:Dictionary=b.session.snapshot()
  var disk:String=FileAccess.get_file_as_string(b.save_path);var fields:int=b.field_calls
  var original_battle:WeakRef=weakref(b.battle)
  var original_id:String=str(pending.battle_id)
  if mode=="stop":b.quest_auto.stop(b,"Cancel before real storage failure")
  else:b.quest_auto.detach(b,71)
  check(b.session._pending==pending and b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==disk,"Actual pending cancellation leaves full pre-cancel baseline unchanged; no position fixture")
  if failures:b.free();quit(1);return
  check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Block only own original writer tmp")
  if failures:b.free();quit(1);return
  if not drive_original(b,time):b.free();quit(1);return
  check(is_same(original_battle.get_ref(),b.battle) and b.battle_open and str(b.battle.snapshot().get("battle_id",""))==original_id and str(b.session._pending.get("battle_id",""))==original_id and not b.battle.snapshot().active,"Original actual battle and pending ID remain before reading drop claims")
  if failures:b.free();quit(1);return
  var expected:Dictionary=pending.duplicate(true)
  expected.loot_claims=b.battle.drop_claims_for()
  check(b.battle_open and not b.battle.snapshot().active and not b.battle_state.get("settled",true) and b.session._pending==expected,"Failure keeps entire original pending including actual original battle claims")
  if failures:b.free();quit(1);return
  check(b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==disk and b.quest_loot.storage_paused,"Atomic failure preserves complete profile/disk and freezes cutoff")
  if failures:b.free();quit(1);return
  var frozen:Dictionary=b.quest_loot.cached_sample.duplicate(true)
  time[0]+=999999;b.automation.tick_battle(0.5)
  check(b.battle_open and b.session._pending==expected and b.quest_loot.cached_sample==frozen,"Stopped failed auto never closes pending or resamples storage wait")
  if failures:b.free();quit(1);return
  check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Remove own blocker only after strict failed-state checks")
  if failures:b.free();quit(1);return
  check(b.handle({"type":"battle_close","battle_id":pending.battle_id}).get("ok",false),"Real original battle_close retries same actual battle")
  if failures:b.free();quit(1);return
  var entry:Dictionary=b.session._profile.quest_loot.entries[KEY]
  check(entry.saved_battles==1 and entry.new_items==0 and entry.used_ms==frozen.used_ms and not entry.open_span and not b.battle_open and b.session._pending.is_empty() and not b.automation.running and not b.quest_auto.running and b.field_calls==fields,"Repair commits exact frozen sample once without reviving any runner")
  if failures:b.free();quit(1);return
  var saved:Dictionary=b.session.snapshot();var saved_disk:String=FileAccess.get_file_as_string(b.save_path)
  check(not b.handle({"type":"battle_close","battle_id":pending.battle_id}).get("ok",true) and b.session.snapshot()==saved and FileAccess.get_file_as_string(b.save_path)==saved_disk,"Repeated actual-ID close cannot reaward or rewrite profile")
  if failures:b.free();quit(1);return
  if not complete_disk(b):b.free();quit(1);return
  b.free()
 print("QUEST AUTO LOOT BATTLE RETRY: 0 failures; 2 original battle storage fixtures")
 quit(0)
