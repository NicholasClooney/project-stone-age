extends "res://tests/quest_auto_loot_state_test.gd"
const ProfileCompare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
const Session=preload("res://server/game_session.gd")
func write_json(path:String,value:Dictionary)->void:
 var file:=FileAccess.open(path,FileAccess.WRITE)
 check(file!=null,"Test file opens")
 if file!=null:file.store_string(JSON.stringify(value));file.close()
# Match the existing historical migration fixture; never lower a modern snapshot
# into versions whose storage/equipment fields did not yet exist.
func legacy_profile(version:int)->Dictionary:
 if version==7:
  var previous:Dictionary=Session.new().snapshot()
  previous.version=7
  previous.erase("quest_loot")
  return previous
 var p:Dictionary={"version":version,"profile_id":"samgir-singleplayer-v1","player":{"hp":40,"max_hp":48,"level":33,"xp":12,"gold":1234567,"attack":10,"defence":0},"inventory":{"potion":2,"club":0},"equipped":false,"pets":[],"active_pet":-1,"quest":{"accepted":false,"wins":0,"boss_defeated":false,"claimed":false},"location":{"map_id":1000,"x":80,"y":90},"completed_battles":[],"next_battle":1}
 if version>=2:p.pet_storage=[];p.next_pet_id=1
 if version>=4:p.player.mp=37;p.equipment={"body":"","amulet":""}
 if version>=5:p.merge(Session.ORIGINAL_DEFAULT.duplicate(true),true)
 if version>=6:
  p.original_instances=[];p.original_equipment={"arm":0,"bracelet":0,"amulet":0};p.next_original_uid=1
 return p
func write_input_bytes(path:String,payload:String)->bool:
 var file:=FileAccess.open(path,FileAccess.WRITE)
 if file==null:return false
 file.store_string(payload)
 file.flush()
 var error:=file.get_error()
 file.close()
 return error==OK and FileAccess.get_file_as_string(path)==payload
func readback_diagnostic(s,path:String,loaded:bool)->void:
 var profile:Dictionary=s._profile.duplicate(true)
 var ledger:Variant=profile.get("quest_loot")
 print("LOOT READBACK load=",loaded," last_error=",s.last_error)
 print("LOOT READBACK version type=",typeof(profile.get("version"))," value=",var_to_str(profile.get("version")))
 print("LOOT READBACK ledger type=",typeof(ledger)," full=",var_to_str(ledger))
 if ledger is Dictionary:
  print("LOOT READBACK ledger.version type=",typeof(ledger.get("version"))," value=",var_to_str(ledger.get("version")))
  if ledger.get("entries") is Dictionary:
   for key in ledger.entries:
    var entry:Variant=ledger.entries[key]
    if entry is Dictionary:
     for field in entry:
      if entry[field] is int or entry[field] is float:
       print("LOOT READBACK entry=",key," field=",field," type=",typeof(entry[field])," value=",var_to_str(entry[field]))
 print("LOOT READBACK profile full=",var_to_str(profile))
 for suffix in [".input.json","",".bak"]:
  var evidence_path:String=path+suffix
  print("LOOT READBACK file=",evidence_path," exists=",FileAccess.file_exists(evidence_path)," sha256=",FileAccess.get_sha256(evidence_path) if FileAccess.file_exists(evidence_path) else "missing")
func run()->void:
 var session=Session.new()
 check(Session.SAVE_VERSION==8 and State.valid(session.snapshot().quest_loot),"New v8 requires real ledger")
 if failures:quit(1);return
 var helper_profile:Dictionary=session.snapshot()
 var helper_good:Dictionary=ProfileCompare.validated_copy(session,JSON.stringify(helper_profile))
 check(helper_good.ok and helper_good.profile==helper_profile and helper_good.profile.quest_loot.recovery_blocked is bool,"Validated integer JSON normalizes only comparison copy and preserves bool flags")
 if failures:quit(1);return
 for invalid_number in [true,1.5]:
  var helper_bad:Dictionary=helper_profile.duplicate(true)
  helper_bad.quest_loot.version=invalid_number
  check(not ProfileCompare.validated_copy(session,JSON.stringify(helper_bad)).ok,"Raw numeric ledger bool/fraction rejected before normalization")
  if failures:quit(1);return
 for version in range(1,8):
  var old:Dictionary=legacy_profile(version)
  check(session._valid_profile(old),"Historical input valid before write "+str(version))
  if failures:quit(1);return
  var original:Dictionary=old.duplicate(true)
  var original_bytes:String=JSON.stringify(original)
  var path:="user://loot-migration-%d.json"%version
  # Keep exact pre-load bytes outside the writer's primary/bak/tmp rotation.
  check(not FileAccess.file_exists(path+".input.json"),"Fresh immutable input evidence path "+str(version))
  if failures:quit(1);return
  check(write_input_bytes(path+".input.json",original_bytes),"Original input bytes retained before primary write "+str(version))
  if failures:quit(1);return
  check(write_input_bytes(path,original_bytes),"Primary initially equals retained input bytes "+str(version))
  if failures:quit(1);return
  var migrated=Session.new()
  check(migrated.load_game(path),"Original valid version migrates "+str(version))
  if failures:quit(1);return
  check(old==original and FileAccess.get_file_as_string(path+".input.json")==original_bytes,"Migration preserves original input evidence "+str(version))
  if failures:quit(1);return
  check(migrated.snapshot().version==8 and migrated.snapshot().quest_loot==State.empty(),"Absent legacy ledger begins empty only in old schemas")
  if failures:quit(1);return
  check(migrated.save_game(path),"Migrated v8 saves normally")
  if failures:quit(1);return
  var reread=Session.new()
  var loaded:bool=reread.load_game(path)
  if not loaded:readback_diagnostic(reread,path,loaded)
  check(loaded,"Real disk reload succeeds "+str(version)+"; last_error="+reread.last_error)
  if failures:quit(1);return
  var reloaded:Dictionary=reread.snapshot()
  if reloaded.quest_loot!=State.empty():readback_diagnostic(reread,path,loaded)
  check(reloaded.quest_loot==State.empty(),"Real disk reload retains migrated ledger")
  if failures:quit(1);return
 var broken:Dictionary=session.snapshot();broken.erase("quest_loot")
 check(not session._valid_profile(broken),"Missing v8 ledger rejected, not sanitized")
 if failures:quit(1);return
 broken=session.snapshot();broken.quest_loot={}
 check(not session._valid_profile(broken),"Malformed v8 ledger rejected")
 if failures:quit(1);return
 for invalid_kind in ["missing","malformed"]:
  var invalid:Dictionary=session.snapshot()
  if invalid_kind=="missing":invalid.erase("quest_loot")
  else:invalid.quest_loot={}
  var invalid_path:="user://loot-invalid-v8-no-backup-%s.json"%invalid_kind
  write_json(invalid_path,invalid)
  if failures:quit(1);return
  var invalid_bytes:=FileAccess.get_file_as_string(invalid_path)
  var rejected=Session.new()
  var prior:Dictionary=rejected.snapshot()
  var prior_rng:int=rejected.login_rng.state
  check(not FileAccess.file_exists(invalid_path+".bak"),"Invalid v8 fixture has no backup "+invalid_kind)
  if failures:quit(1);return
  check(not rejected.load_game(invalid_path),"Invalid v8 direct load refused "+invalid_kind)
  if failures:quit(1);return
  check(FileAccess.get_file_as_string(invalid_path)==invalid_bytes and rejected.snapshot()==prior and rejected.login_rng.state==prior_rng,"Rejected v8 preserves disk/profile/login RNG "+invalid_kind)
  if failures:quit(1);return
 var ledger:Dictionary=State.acquire(State.empty(),KEY,ID,RUN,30,2).ledger
 var old:Dictionary=session.snapshot();old.version=7;old.quest_loot=ledger
 write_json("user://loot-old-present.json",old)
 if failures:quit(1);return
 var old_present=Session.new()
 check(old_present.load_game("user://loot-old-present.json") and old_present.snapshot().quest_loot==ledger,"Valid field in old version preserved")
 if failures:quit(1);return
 session._profile.quest_loot=State.open(ledger,KEY,State.identity(ledger.entries[KEY])).ledger
 var active:Dictionary=session.snapshot().quest_loot
 check(session.save_game("user://loot-crash.json"),"Committed open span persisted")
 if failures:quit(1);return
 var recovered=Session.new()
 check(recovered.load_game("user://loot-crash.json"),"Crash recovers original profile conservatively")
 if failures:quit(1);return
 var cold_expected:Dictionary=active.duplicate(true)
 cold_expected.entries[KEY].open_span=false;cold_expected.entries[KEY].settled_seq=cold_expected.entries[KEY].issued_seq;cold_expected.entries[KEY].revision+=1
 check(recovered.snapshot().quest_loot==cold_expected,"Independent exact cold retirement retains unknown elapsed as saved lower bound")
 if failures:quit(1);return
 var disk_copy:Dictionary=ProfileCompare.validated_copy(recovered,FileAccess.get_file_as_string("user://loot-crash.json"))
 check(disk_copy.ok,"Complete recovery disk profile validates before comparison normalization")
 if failures:quit(1);return
 var recovered_profile:Dictionary=recovered.snapshot()
 check(disk_copy.profile==recovered_profile,"Cold retirement and complete profile durable before successful load")
 if failures:quit(1);return
 var repeat=Session.new()
 check(repeat.load_game("user://loot-crash.json"),"Restart loads persisted retired budget")
 if failures:quit(1);return
 check(repeat.snapshot().quest_loot==recovered_profile.quest_loot and repeat.snapshot().quest_loot==disk_copy.profile.quest_loot,"Restart never refreshes retired budget or changes its counters")
 if failures:quit(1);return
 var baseline:Dictionary=session.snapshot();baseline.quest_loot=ledger
 write_json("user://loot-backup.json.bak",baseline)
 if failures:quit(1);return
 write_json("user://loot-backup.json",broken)
 if failures:quit(1);return
 var backup=Session.new()
 var backup_expected:Dictionary=ledger.duplicate(true)
 backup_expected.entries[KEY].revision+=1
 check(backup.load_game("user://loot-backup.json") and backup.snapshot().quest_loot==backup_expected,"Bad primary fallback retires only the selected old generation, without inventing newer counters")
 if failures:quit(1);return
 baseline.version=7;baseline.erase("quest_loot")
 write_json("user://loot-missing-backup.json.bak",baseline)
 if failures:quit(1);return
 write_json("user://loot-missing-backup.json",broken)
 if failures:quit(1);return
 var missing=Session.new()
 check(missing.load_game("user://loot-missing-backup.json") and missing.snapshot().quest_loot.recovery_blocked,"Older empty backup cannot reset budget")
 if failures:quit(1);return
 write_json("user://loot-lock-failure.json",session.snapshot())
 if failures:quit(1);return
 DirAccess.make_dir_absolute("user://loot-lock-failure.json.tmp")
 var failed_load=Session.new();var before:Dictionary=failed_load.snapshot()
 check(not failed_load.load_game("user://loot-lock-failure.json") and failed_load.snapshot()==before,"Failed uncertainty-lock persistence refuses load, preserves prior profile")
 if failures:quit(1);return
 DirAccess.remove_absolute("user://loot-lock-failure.json.tmp")
 # Trusted settings-only path uses saved ledger verbatim even while live battle
 # state differs. It never authorizes a ledger delta through settings validation.
 session._profile.quest_loot=active
 check(session.save_game("user://loot-settings.json"),"Trustworthy pre-battle baseline")
 if failures:quit(1);return
 var saved_payload:=FileAccess.get_file_as_string("user://loot-settings.json")
 session._pending={"battle_id":"fixture-active"}
 session._profile.player.hp-=1
 var live:Dictionary=session.snapshot()
 check(not session.save_game("user://loot-settings.json"),"Ordinary pending save still prohibited")
 if failures:quit(1);return
 var saved:=session.save_settings_on_saved_profile(saved_payload,{"quest":{"loot_minutes":60}},"user://loot-settings.json")
 check(saved.ok,"LAN settings candidate remains supported during battle")
 if failures:quit(1);return
 var candidate_copy:Dictionary=ProfileCompare.validated_copy(session,saved.payload)
 var baseline_copy:Dictionary=ProfileCompare.validated_copy(session,saved_payload)
 check(candidate_copy.ok and baseline_copy.ok,"Complete settings candidate and original baseline validate before normalization")
 if failures:quit(1);return
 var expected_candidate:Dictionary=baseline_copy.profile.duplicate(true)
 expected_candidate.automation_settings={"quest":{"loot_minutes":60}}
 check(candidate_copy.profile==expected_candidate and candidate_copy.profile.quest_loot==active and session.snapshot()==live and session._pending.battle_id=="fixture-active","Settings-only full profile changes only preferences; live ledger/HP/pending untouched")
 if failures:quit(1);return
 check(not session.save_settings_on_saved_profile(saved_payload,{"quest_loot":ledger},"user://loot-settings.json").ok,"Settings patch cannot smuggle ledger")
 if failures:quit(1);return
 DirAccess.make_dir_absolute("user://loot-settings.json.tmp")
 var disk:=FileAccess.get_file_as_string("user://loot-settings.json")
 check(not session.save_settings_on_saved_profile(saved.payload,{"quest":{"loot_minutes":90}},"user://loot-settings.json").ok,"Actual tmp failure rejects settings candidate")
 if failures:quit(1);return
 check(FileAccess.get_file_as_string("user://loot-settings.json")==disk and session.snapshot()==live,"Disk failure preserves saved ledger and live battle")
 if failures:quit(1);return
 DirAccess.remove_absolute("user://loot-settings.json.tmp")
 print("QUEST AUTO LOOT PERSISTENCE: %d failures; actual files, schema and settings path only"%failures)
 quit(1 if failures else 0)
