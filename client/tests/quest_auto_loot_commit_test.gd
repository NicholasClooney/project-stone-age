extends "res://tests/quest_auto_loot_battle_test.gd"
## Explicit strong-character prepared-span fixture; actual original roll/apply/
## candidate writer. Observer runs at the narrow commit return boundary, after
## actual write/cache update, never by substituting a fabricated save serial.
const Session=preload("res://server/game_session.gd")
const LootTimer=preload("res://server/quest_auto_loot.gd")
class ObservedBackend:
 extends "res://server/backend.gd"
 var test_check:Callable
 var after_commit:Callable
 var observed:Dictionary={}
 var observed_frame:Dictionary={}
 var writes:=0
 var cache_at_commit:=""
 var candidate_tamper:=false
 var invalid_candidate_rejected:=false
 var invalid_capability_rejected:=false
 var pending_rejected:=false
 var replay_rejected:=false
 func _commit_loot_settlement(frame:Dictionary)->Dictionary:
  observed_frame=frame
  if candidate_tamper:
   var bad:Dictionary=frame.profile.duplicate(true);bad.player.gold+=1
   var live:Dictionary=session._profile
   session._profile=bad
   var candidate_probe:Dictionary=frame.session.commit_loot_settlement(frame.capability,bad,frame.path,_loot_settlement_written.bind(frame.session,frame.path))
   invalid_candidate_rejected=not candidate_probe.get("ok",false)
   session._profile=live
   test_check.call(invalid_candidate_rejected,"Tampered candidate rejected before real commit")
   if not invalid_candidate_rejected:return candidate_probe
   var capability_probe:Dictionary=frame.session.commit_loot_settlement(RefCounted.new(),frame.profile,frame.path,_loot_settlement_written.bind(frame.session,frame.path))
   invalid_capability_rejected=not capability_probe.get("ok",false)
   test_check.call(invalid_capability_rejected,"Wrong capability rejected before real commit")
   if not invalid_capability_rejected:return capability_probe
   var pending:Dictionary=session._pending
   session._pending={"battle_id":"test-pending-no-bypass"}
   var pending_probe:Dictionary=frame.session.commit_loot_settlement(frame.capability,frame.profile,frame.path,_loot_settlement_written.bind(frame.session,frame.path))
   pending_rejected=not pending_probe.get("ok",false)
   session._pending=pending
   test_check.call(pending_rejected,"Pending refused before real commit")
   if not pending_rejected:return pending_probe
  var result:Dictionary=super._commit_loot_settlement(frame)
  if result.get("ok",false):writes+=1
  observed=result.duplicate(true)
  cache_at_commit=last_saved_payload
  if result.get("ok",false):
   replay_rejected=not frame.session.commit_loot_settlement(frame.capability,frame.profile,frame.path,_loot_settlement_written.bind(frame.session,frame.path)).get("ok",false)
   test_check.call(replay_rejected,"Consumed capability replay refused before observer")
   if not replay_rejected:return result
  if after_commit.is_valid():
   var observer:=after_commit;after_commit=Callable();observer.call(self,result,frame)
  return result
func open_case(name:String,setup:Callable=Callable()):
 var b=ObservedBackend.new();b.save_path="user://loot-commit-%s.json"%name
 b.test_check=func(ok:bool,label:String):check(ok,label)
 if not prepare(b,setup):b.free();return null
 return b
func run()->void:
 # 1. Real write failure: original pending/rewards survive; repair waits freeze.
 var b=open_case("failure")
 if b==null:quit(1);return
 if b!=null:
  var time:Array=[1000];b.quest_loot.clock=func():return time[0]
  # Timer began on real monotonic clock; continue relative to that exact anchor.
  time[0]=b.quest_loot.last_ms+100
  var before:Dictionary=b.session.snapshot();var disk:=FileAccess.get_file_as_string(b.save_path)
  check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own tmp blocker created")
  if failures:b.free();quit(1);return
  if not finish(b):b.free();quit(1);return
  var sampled:int=b.quest_loot.used_ms()
  check(sampled>=0 and b.quest_loot.storage_paused,"Failed original settlement pauses storage clock")
  if failures:b.free();quit(1);return
  check(b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==disk,"Actual tmp failure rolls back unchanged frame and disk")
  if failures:b.free();quit(1);return
  time[0]+=100000
  check(not b.handle({"type":"battle_close"}).get("ok",false),"Blocked original close remains rejected")
  if failures:b.free();quit(1);return
  check(b.quest_loot.used_ms()==sampled and b.writes==0,"Retry after repair wait neither charges twice nor commits failed write")
  if failures:b.free();quit(1);return
  check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Own tmp blocker removed after failure checks")
  if failures:b.free();quit(1);return
  check(b.handle({"type":"battle_close"}).get("ok",false),"Repaired original close accepted")
  if failures:b.free();quit(1);return
  check(b.writes==1 and b.session._profile.quest_loot.entries[KEY].used_ms==sampled,"Repair commits same battle/sample exactly once")
  if failures:b.free();quit(1);return
  b.free()
 # 2. Successful write -> synchronous cancel: actual committed outcome retained.
 b=open_case("cancel")
 if b==null:quit(1);return
 if b!=null:
  b.after_commit=func(host,_result,_frame):host.quest_auto.stop(host,"Commit observer cancellation")
  if not finish(b):b.free();quit(1);return
  check(b.observed.get("ok",false) and b.writes==1 and not b.quest_auto.running,"Postwrite cancellation cannot uncommit or revive")
  if failures:b.free();quit(1);return
  check(b.cache_at_commit==b.observed.payload,"Exact saved payload cached before observer")
  if failures:b.free();quit(1);return
  check(b.quest_loot.battle_receipt.is_empty(),"Only captured old receipt retired")
  if failures:b.free();quit(1);return
  var disk_copy:Dictionary=ProfileCompare.validated_copy(b.session,FileAccess.get_file_as_string(b.save_path))
  check(disk_copy.ok,"Cancelled full disk profile validates before normalization")
  if failures:b.free();quit(1);return
  check(disk_copy.profile==b.observed.profile,"Cancelled immutable full original result actually on disk")
  if failures:b.free();quit(1);return
  b.free()
 # 3. Observer installs another timer/run/profile and performs real later save.
 b=open_case("replacement")
 if b==null:quit(1);return
 if b!=null:
  var replacement:Array=[]
  b.after_commit=func(host,_result,_frame):
   host.quest_auto.stop(host,"Replace old run")
   host.quest_auto.identity.begin()
   host.quest_loot=LootTimer.new();host.quest_loot.battle_receipt={"new_owner":true}
   host.session._profile=host.session._profile.duplicate(true)
   host.session._profile.player.gold+=1
   check(host.save(),"Observer later manual save really succeeds")
   if failures:return
   replacement.append(host.session.snapshot());replacement.append(host.last_saved_payload)
  if not finish(b):b.free();quit(1);return
  check(replacement.size()==2 and b.session.snapshot()==replacement[0] and b.last_saved_payload==replacement[1],"Old completion cannot overwrite later profile/cache")
  if failures:b.free();quit(1);return
  check(b.quest_loot.battle_receipt=={"new_owner":true},"Old completion cannot clear replacement timer")
  if failures:b.free();quit(1);return
  check(b.observed_frame.timer.battle_receipt.is_empty(),"Captured committed old timer independently retires")
  if failures:b.free();quit(1);return
  var disk_copy:Dictionary=ProfileCompare.validated_copy(b.session,FileAccess.get_file_as_string(b.save_path))
  var later_copy:Dictionary=ProfileCompare.validated_copy(b.session,replacement[1])
  check(disk_copy.ok and later_copy.ok,"Full later disk and payload validate before normalization")
  if failures:b.free();quit(1);return
  check(disk_copy.profile==later_copy.profile and disk_copy.profile==replacement[0],"Later full saved profile wins on disk")
  if failures:b.free();quit(1);return
  b.free()
 # 4. Failed writer -> new manual pending/profile: no old rollback or publication.
 b=open_case("failed-reentry")
 if b==null:quit(1);return
 if b!=null:
  var replacement:Array=[]
  var before_disk:=FileAccess.get_file_as_string(b.save_path)
  check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own tmp blocker created")
  if failures:b.free();quit(1);return
  b.after_commit=func(host,_result,_frame):
   host.session._profile=host.session._profile.duplicate(true)
   host.session._profile.player.gold+=7
   host.session._pending={"battle_id":"manual-after-failure","manual_fixture":true}
   host.battle_state={"battle_id":"manual-after-failure","active":true}
   replacement.append(host.session._profile.duplicate(true))
  if not finish(b):b.free();quit(1);return
  check(not b.observed.get("ok",false) and replacement.size()==1 and b.session._profile==replacement[0],"Old failed rollback never overwrites replacement profile")
  if failures:b.free();quit(1);return
  check(b.session._pending.get("battle_id")=="manual-after-failure" and b.battle_state.get("battle_id")=="manual-after-failure","Old failure preserves new manual pending and battle state")
  if failures:b.free();quit(1);return
  check(FileAccess.get_file_as_string(b.save_path)==before_disk,"Failed reentry still has unchanged actual disk")
  if failures:b.free();quit(1);return
  check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Own tmp blocker removed after failure checks")
  if failures:b.free();quit(1);return
  b.free()
 # 4b. Reuse the SAME timer object after failed save without touching profile,
 # pending or battle ownership. This is an explicit lifecycle stress fixture,
 # not permission to treat the uncommitted candidate as a durable new span.
 for replace_run in [false,true]:
  b=open_case("reuse-%s"%str(replace_run))
  if b==null:quit(1);return
  var before:Dictionary=b.session.snapshot()
  var old_timer=b.quest_loot
  var old_lifetime:RefCounted=old_timer.lifetime
  var next_lifetime:Array=[]
  var disk:=FileAccess.get_file_as_string(b.save_path)
  check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own tmp blocker created")
  if failures:b.free();quit(1);return
  b.after_commit=func(host,_result,frame):
   var profile_ref:Dictionary=host.session._profile
   var profile_value:Dictionary=profile_ref.duplicate(true)
   check(frame.timer.accept_commit(frame.profile.quest_loot),"Lifecycle stress closes timer only; disk failure remains failure")
   if failures:return
   if replace_run:
    host.quest_auto.identity.begin();host.quest_auto.identity.select_step(KEY)
   var next_span:=State.open(frame.profile.quest_loot,KEY,State.identity(frame.profile.quest_loot.entries[KEY]))
   check(next_span.ok and frame.timer.start_after_commit(KEY,next_span.ledger.entries[KEY],host.quest_auto.identity.checkpoint()),"Actual start_after_commit reuses same timer with new lifetime")
   if failures:return
   check(is_same(host.session._profile,profile_ref) and host.session._profile==profile_value,"Observer changed no checked profile reference/value")
   if failures:return
   next_lifetime.append(frame.timer.lifetime)
  if not finish(b):b.free();quit(1);return
  check(not b.observed.get("ok",false) and is_same(b.quest_loot,old_timer) and not is_same(old_lifetime,b.quest_loot.lifetime),"Failed writer returns to reused same timer object")
  if failures:b.free();quit(1);return
  check(next_lifetime.size()==1 and is_same(next_lifetime[0],b.quest_loot.lifetime) and not b.quest_loot.frozen and not b.quest_loot.storage_paused,"Old rollback never pauses new lifetime")
  if failures:b.free();quit(1);return
  check(b.quest_auto.running,"Old rollback cannot handoff new timer even with unchanged run identity")
  if failures:b.free();quit(1);return
  check(b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==disk,"Owned original profile still rolls back failed write atomically")
  if failures:b.free();quit(1);return
  check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Own tmp blocker removed after failure checks")
  if failures:b.free();quit(1);return
  b.free()
 # 5. Player/pet XP boundary plus migration-derived fields are in one candidate.
 b=open_case("fields",func(host):
  check(host.session.grant_starter_pets() and not host.session._profile.pets.is_empty(),"Original starter pet setup succeeds")
  if failures:return
  var pet:Dictionary=host.session._profile.pets[0]
  pet.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
  host.Progression.refresh(pet);pet.hp=pet.max_hp;pet.xp=int(pet.level)*30-1
  host.session._profile.player.xp=int(host.session._profile.player.level)*30-1
  host.session._profile.active_pet=0
  host.session.OriginalEquipment.add(host.session._profile,1052)
 )
 if b==null:quit(1);return
 if b!=null:
  var before:Dictionary=b.session.snapshot()
  b.candidate_tamper=true
  # Player defends so the original pet actions earn the level-up credit.
  for turn in range(100):
   if not b.battle.snapshot().active:break
   var reply:Dictionary=b.handle({"type":"battle_command","action":"defend"})
   check(reply.get("ok",false),"Original defend command accepted")
   if failures:b.free();quit(1);return
  check(not b.battle.snapshot().active and b.observed.get("ok",false),"Actual original pet battle settles")
  if failures:b.free();quit(1);return
  if b.observed.get("ok",false):
   var committed:Dictionary=b.observed.profile
   check(committed.player.level>before.player.level and committed.pets[0].level>before.pets[0].level,"Both actual XP boundaries crossed")
   if failures:b.free();quit(1);return
   check(b.invalid_candidate_rejected and b.invalid_capability_rejected and b.pending_rejected and b.replay_rejected and b.writes==1,"Exact original candidate/capability, pending ban, one-shot commit retained")
   if failures:b.free();quit(1);return
   var disk_copy:Dictionary=ProfileCompare.validated_copy(b.session,FileAccess.get_file_as_string(b.save_path))
   var payload_copy:Dictionary=ProfileCompare.validated_copy(b.session,b.observed.payload)
   check(disk_copy.ok and payload_copy.ok,"Full atomic disk and exact saved payload validate before normalization")
   if failures:b.free();quit(1);return
   check(disk_copy.profile==payload_copy.profile and disk_copy.profile==committed,"Full original immutable candidate, including UID/profile/ledger, equals disk")
   if failures:b.free();quit(1);return
   check(b.session.snapshot()==committed,"Later normalization is idempotent on committed candidate")
   if failures:b.free();quit(1);return
   var loaded=Session.new(b.session.login_clock)
   check(loaded.load_game(b.save_path),"Fresh Session accepts full candidate")
   if failures:b.free();quit(1);return
   var reread:Dictionary=loaded.snapshot()
   for field in ["pets","next_pet_id","original_instances","original_equipment","location","quest_loot"]:
    check(reread[field]==committed[field],"Full derived field survives new Session "+field)
    if failures:b.free();quit(1);return
   for field in ["level","xp","hp","stat_points","allocated_stats"]:
    check(reread.player[field]==committed.player[field],"Player derived field survives "+field)
    if failures:b.free();quit(1);return
   check(reread.pets[0].skill_unlocked==(not reread.pets[0].learned_skills.is_empty()),"Skill flag remains original learned-skill projection")
   if failures:b.free();quit(1);return
  b.free()
 print("QUEST AUTO LOOT COMMIT: %d failures; explicit prepared-span observer fixtures"%failures)
 quit(1 if failures else 0)
