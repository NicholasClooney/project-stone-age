extends "res://tests/quest_auto_loot_persistence_test.gd"
const Backend=preload("res://server/backend.gd")
func recovering_profile()->Dictionary:
 var s=Session.new()
 var ledger:Dictionary=State.acquire(State.empty(),KEY,ID,RUN,30,0).ledger
 s._profile.quest_loot=State.open(ledger,KEY,State.identity(ledger.entries[KEY])).ledger
 s._profile.player.last_luck_time=912771809
 return s.snapshot()
func target_session():
 var s=Session.new()
 s.login_clock=func():return 912771809+5400
 s.login_rng.seed=17
 s.last_note="previous-note"
 s.release_events=[{"fixture":"release"}];s.capture_events=[{"fixture":"capture"}]
 s._training_preview={"fixture":"preview"}
 return s
func record_event(value:Dictionary)->void:
 print("LOOT_RECOVERY_EVENT "+JSON.stringify(value))
func preserved(s,path:String,label:String,copy_fault:bool=false)->bool:
 var prior_profile:Dictionary=s._profile
 var before:Dictionary=s.snapshot()
 var random_state:int=s.login_rng.state
 var events:Array=[s.release_events.duplicate(true),s.capture_events.duplicate(true)]
 var primary:String=""
 var primary_sha:String=""
 if copy_fault:
  primary=FileAccess.get_file_as_string(path)
  primary_sha=FileAccess.get_sha256(path)
  var parsed=JSON.parse_string(primary)
  check(parsed is Dictionary and s._valid_profile(parsed) and DirAccess.dir_exists_absolute(path+".bak") and FileAccess.file_exists(path+".bak/keep.json"),"Exact valid-primary/nonempty-backup-directory injection")
  if failures:return false
  record_event({"stage":"copy_backup_directory","event":"begin","path":ProjectSettings.globalize_path(path),"backup_path":ProjectSettings.globalize_path(path+".bak"),"primary_sha256":primary_sha})
 var loaded:bool=s.load_game(path)
 if copy_fault:record_event({"stage":"copy_backup_directory","event":"return","load_ok":loaded,"last_error":s.last_error})
 check(not loaded,label+" refuses failed recovery write")
 if failures:return false
 check(s.snapshot()==before,label+" restores complete profile")
 if failures:return false
 if copy_fault:record_event({"stage":"copy_backup_directory","event":"assert","id":"profile_value","ok":true})
 check(s.login_rng.state==random_state,label+" restores consumed login RNG")
 if failures:return false
 if copy_fault:record_event({"stage":"copy_backup_directory","event":"assert","id":"login_rng_state","ok":true})
 check(is_same(s._profile,prior_profile),label+" restores original profile object identity")
 if failures:return false
 if copy_fault:record_event({"stage":"copy_backup_directory","event":"assert","id":"profile_reference","ok":true})
 check(s.last_note=="previous-note" and s.release_events==events[0] and s.capture_events==events[1] and s._training_preview=={"fixture":"preview"} and s._pending.is_empty(),label+" retains unrelated Session state")
 if failures:return false
 if copy_fault:
  record_event({"stage":"copy_backup_directory","event":"assert","id":"unrelated_session_state","ok":true})
  var after_sha:String=FileAccess.get_sha256(path)
  check(FileAccess.get_file_as_string(path)==primary and after_sha==primary_sha,"Valid primary survives backup-copy failure")
  if failures:return false
  record_event({"stage":"copy_backup_directory","event":"assert","id":"primary_bytes","ok":true,"before_sha256":primary_sha,"after_sha256":after_sha})
  record_event({"stage":"copy_backup_directory","event":"end","load_ok":loaded,"rollback_ok":true,"primary_unchanged":true})
 return true
func run()->void:
 var profile:=recovering_profile()
 var fallback:=Session.new().snapshot()
 # Corrupt primary selects valid backup; temporary open failure must not
 # touch its bytes, and repaired storage must still load that same backup.
 var path:="user://loot-recovery-tmp.json"
 write_json(path,{"invalid":true});write_json(path+".bak",fallback)
 if failures:quit(1);return
 var backup:=FileAccess.get_file_as_string(path+".bak")
 DirAccess.make_dir_absolute(path+".tmp")
 if not preserved(target_session(),path,"Backup tmp-open failure"):quit(1);return
 check(FileAccess.get_file_as_string(path+".bak")==backup,"Sole valid backup survives failed tmp-open")
 if failures:quit(1);return
 DirAccess.remove_absolute(path+".tmp")
 var repaired=target_session()
 check(repaired.load_game(path) and repaired.snapshot().quest_loot.recovery_blocked,"Same backup restores after storage repair")
 if failures:quit(1);return
 check(FileAccess.get_file_as_string(path+".bak")==backup,"Successful fallback write also does not rotate over source backup")
 if failures:quit(1);return
 record_event({"stage":"tmp_open_complete","event":"complete"})
 # Primary is a directory, so loader selects .bak and final rename cannot
 # replace it; writer still never copies invalid primary over valid .bak.
 path="user://loot-recovery-rename.json"
 DirAccess.make_dir_absolute(path)
 write_json(path+"/keep.json",{"fixture":true});write_json(path+".bak",fallback)
 if failures:quit(1);return
 backup=FileAccess.get_file_as_string(path+".bak")
 if not preserved(target_session(),path,"Backup rename failure"):quit(1);return
 check(FileAccess.get_file_as_string(path+".bak")==backup,"Sole backup survives final rename failure")
 if failures:quit(1);return
 DirAccess.remove_absolute(path+"/keep.json");DirAccess.remove_absolute(path)
 record_event({"stage":"rename_complete","event":"complete"})
 # Valid open-span primary: backup copy fails because destination is a dir.
 # A possibly damaged/absent backup is not the sole recovery copy: primary
 # remains the original complete valid bytes until final rename succeeds.
 path="user://loot-recovery-copy.json"
 write_json(path,profile)
 if failures:quit(1);return
 var primary:=FileAccess.get_file_as_string(path)
 DirAccess.make_dir_absolute(path+".bak")
 write_json(path+".bak/keep.json",{"fixture":true})
 if failures:quit(1);return
 if not preserved(target_session(),path,"Primary backup-copy failure",true):quit(1);return
 check(FileAccess.get_file_as_string(path)==primary,"Valid primary survives backup-copy failure")
 if failures:quit(1);return
 DirAccess.remove_absolute(path+".bak/keep.json");DirAccess.remove_absolute(path+".bak")
 record_event({"stage":"copy_complete","event":"complete"})
 var b=Backend.new();b.set_process(false)
 b.save_path="user://loot-original-backend.json"
 check(b.save(),"Original backend saved baseline")
 if failures:quit(1);return
 var payload:String=b.last_saved_payload
 var serial:int=b.quest_save_serial
 var old_path:String=b.save_path
 var current:Dictionary=b.session.snapshot()
 path="user://loot-backend-load-failure.json"
 write_json(path,profile);DirAccess.make_dir_absolute(path+".tmp")
 if failures:quit(1);return
 var random_state:int=b.session.login_rng.state
 check(not b.load_profile(path),"Backend refuses uncommitted recovered candidate")
 if failures:quit(1);return
 check(b.last_saved_payload==payload and b.save_path==old_path and b.quest_save_serial==serial and b.session.snapshot()==current and b.session.login_rng.state==random_state,"Failed load leaves saved-payload/dedup/path/prior profile/RNG intact")
 if failures:quit(1);return
 DirAccess.remove_absolute(path+".tmp")
 b.free()
 record_event({"stage":"backend_complete","event":"complete"})
 print("QUEST AUTO LOOT RECOVERY: %d failures; original writer failure stages"%failures)
 quit(1 if failures else 0)
