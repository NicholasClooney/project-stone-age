extends "res://tests/quest_auto_loot_state_test.gd"
const ProfileCompare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
const Backend=preload("res://server/backend.gd")
func transact(b,operation:String,args:Dictionary,observer:Callable=Callable())->Dictionary:
 var expected:Dictionary=b.session.snapshot()
 var owner=b.session
 var path:String=b.save_path
 var previous_profile:Dictionary=owner._profile
 var acknowledged:Callable=func(payload:String):
  var payload_copy:Dictionary=ProfileCompare.validated_copy(owner,payload)
  check(payload_copy.ok,"Complete idle acknowledgement profile validates before normalization")
  if failures:return
  check(owner._profile==payload_copy.profile and not is_same(owner._profile,previous_profile),"Full independent candidate installed BEFORE acknowledgement observer")
  if failures:return
  b._loot_settlement_written(payload,owner,path)
  check(b.last_saved_payload==payload,"Exact payload cache confirmed at commit boundary")
  if failures:return
  if observer.is_valid():observer.call()
 var result:Dictionary=owner.commit_loot_idle_transition(expected,expected.quest_loot.duplicate(true),operation,args,path,acknowledged)
 if failures:return {"ok":false,"test_comparison_failed":true}
 return result
func entry_args(b)->Dictionary:
 return {"step_id":KEY,"expected_entry":State.identity(b.session._profile.quest_loot.entries[KEY])}
func run()->void:
 var b=Backend.new();b.set_process(false);b.save_path="user://loot-idle.json"
 check(b.save(),"Actual baseline before idle transaction")
 if failures:b.free();quit(1);return
 var first:Dictionary={"step_id":KEY,"budget_id":ID,"run_id":RUN,"minutes":30,"existing_items":0}
 var result:=transact(b,"acquire",first)
 if failures:b.free();quit(1);return
 check(result.ok and result.installed and b.session._profile.quest_loot.entries[KEY].limit_ms==1800000,"First create uses finite operation, real disk")
 if failures:b.free();quit(1);return
 var old:Dictionary=b.session.snapshot()
 var stale:=old.duplicate(true);stale.player.gold+=1
 check(not b.session.commit_loot_idle_transition(stale,stale.quest_loot,"open",entry_args(b),b.save_path,func(_p):pass).ok,"Full profile CAS rejects stale non-ledger state")
 if failures:b.free();quit(1);return
 var ledger_stale:Dictionary=old.quest_loot.duplicate(true);ledger_stale.entries[KEY].revision+=1
 check(not b.session.commit_loot_idle_transition(old,ledger_stale,"open",entry_args(b),b.save_path,func(_p):pass).ok,"Full ledger CAS independently required")
 if failures:b.free();quit(1);return
 b.session._pending={"battle_id":"real-pending-protection-fixture"}
 check(not transact(b,"open",entry_args(b)).ok and b.session._pending.has("battle_id"),"Any pending refused and never cleared")
 if failures:b.free();quit(1);return
 b.session._pending={}
 for operation in ["replace_profile","settle","unknown"]:
  check(not transact(b,operation,{}).ok,"Unknown/real-battle operation cannot use idle writer")
  if failures:b.free();quit(1);return
 var malformed:=first.duplicate(true);malformed.extra=true
 check(not transact(b,"acquire",malformed).ok,"Extra input cannot smuggle profile fields")
 if failures:b.free();quit(1);return
 malformed=first.duplicate(true);malformed.existing_items=1
 check(not transact(b,"acquire",malformed).ok,"Initial existing count must match actual original inventory")
 if failures:b.free();quit(1);return
 check(transact(b,"open",entry_args(b)).ok,"Durable open transition")
 if failures:b.free();quit(1);return
 var change:=entry_args(b);change.minutes=60
 check(not transact(b,"adjust",change).ok,"Live open span cannot adjust")
 if failures:b.free();quit(1);return
 change.acknowledge_recovery=false
 check(not transact(b,"reset",change).ok,"Unclosed normal span cannot reset")
 if failures:b.free();quit(1);return
 var close:=entry_args(b);close.total_used_ms=3210
 check(transact(b,"close",close).ok,"No-battle close updates total without battle counter")
 if failures:b.free();quit(1);return
 check(b.session._profile.quest_loot.entries[KEY].saved_battles==0,"Idle closure is not a saved battle")
 if failures:b.free();quit(1);return
 change=entry_args(b);change.minutes=60
 var before:Dictionary=b.session.snapshot();var disk:=FileAccess.get_file_as_string(b.save_path);var cache:String=b.last_saved_payload
 var original_ref:Dictionary=b.session._profile
 check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own idle tmp blocker created")
 if failures:b.free();quit(1);return
 check(not transact(b,"adjust",change).ok and b.session.snapshot()==before and is_same(b.session._profile,original_ref) and b.last_saved_payload==cache and FileAccess.get_file_as_string(b.save_path)==disk,"Real tmp failure keeps memory/cache/disk unchanged")
 if failures:b.free();quit(1);return
 check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Own idle blocker removed only after full failure checks")
 if failures:b.free();quit(1);return
 var later:Array=[]
 result=transact(b,"adjust",change,func():
  b.session._profile.player.gold+=3
  check(b.save(),"Reentrant later save succeeds")
  if failures:return
  later.append(b.session.snapshot());later.append(b.last_saved_payload);later.append(b.session._profile)
 )
 if failures:b.free();quit(1);return
 check(result.ok and result.profile.player.gold+3==b.session._profile.player.gold,"Return old immutable result does not reinstall over observer")
 if failures:b.free();quit(1);return
 check(later.size()==3 and is_same(b.session._profile,later[2]) and b.session.snapshot()==later[0] and b.last_saved_payload==later[1] and FileAccess.get_file_as_string(b.save_path)==later[1],"Later profile/cache/disk win")
 if failures:b.free();quit(1);return
 result.profile.player.gold=0
 check(is_same(b.session._profile,later[2]) and not is_same(result.profile,b.session._profile) and b.session._profile.player.gold==later[0].player.gold,"Returned candidate does not alias or replace installed profile")
 if failures:b.free();quit(1);return
 var entry:Dictionary=b.session._profile.quest_loot.entries[KEY].duplicate(true)
 var reopen:=first.duplicate(true);reopen.budget_id=RUN;reopen.run_id=ID;reopen.minutes=1
 check(transact(b,"acquire",reopen).ok and b.session._profile.quest_loot.entries[KEY]==entry,"Ordinary new run does not reset/resize existing budget")
 if failures:b.free();quit(1);return
 change=entry_args(b);change.minutes=30;change.acknowledge_recovery=false
 check(transact(b,"reset",change).ok and b.session._profile.quest_loot.entries[KEY].generation==entry.generation+1 and b.session._profile.quest_loot.entries[KEY].used_ms==0,"Explicit reset changes generation only after write")
 if failures:b.free();quit(1);return
 check(not transact(b,"reset",change).ok,"Old revision cannot reset again")
 if failures:b.free();quit(1);return
 # Root uncertainty with no entry needs a distinct explicit operation/ack.
 b.session._profile.quest_loot=State.empty();b.session._profile.quest_loot.recovery_blocked=true
 check(b.save(),"Explicit internal recovered-root fixture saved")
 if failures:b.free();quit(1);return
 check(not transact(b,"acquire",first).ok,"Root missing history cannot be normal acquire")
 if failures:b.free();quit(1);return
 var recover:=first.duplicate(true);recover.acknowledge_recovery=false
 check(not transact(b,"reset_missing",recover).ok,"Missing history reset requires explicit boolean acknowledgement")
 if failures:b.free();quit(1);return
 recover.acknowledge_recovery=true
 check(transact(b,"reset_missing",recover).ok and not b.session._profile.quest_loot.recovery_blocked,"Acknowledged missing history uses exact independent transition")
 if failures:b.free();quit(1);return
 b.free()
 print("QUEST AUTO LOOT IDLE: %d failures; internal finite operations, not public admission"%failures)
 quit(1 if failures else 0)
