extends "res://tests/quest_auto_loot_recovery_remote_ui_test.gd"
## UNRUN: isolated real empty-ledger backup -> truncated primary -> NEW first loader.
## Only the owned test primary is corrupted. No ledger/lock/profile injection or repair.
func empty_disk(stage:String)->Dictionary:
 var files:Dictionary=archive(stage)
 if files.is_empty():return {}
 for key in ["primary","backup"]:
  if not check(files[key].exists and not files[key].bytes.is_empty(),"Actual nonempty disk file exists: "+stage+"/"+key):return {}
  var copy:Dictionary=ProfileCompare.validated_copy(host.session,files[key].bytes.get_string_from_utf8())
  if not check(copy.get("ok",false),"Complete actual disk profile validates: "+stage+"/"+key):return {}
  if not check(copy.profile==host.session.snapshot(),"Full actual disk profile equals native owner: "+stage+"/"+key):return {}
  if not check(copy.profile.quest_loot==State.empty(),"Actual disk ledger is empty and unlocked: "+stage+"/"+key):return {}
 return files
func run()->void:
 path="user://loot-root-backup-remote.json"
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 if not check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".bak"),"Fault fixture starts in a fresh isolated user directory"):return
 host=Backend.new();root.add_child(host);host.set_process(false);host.save_path=path
 if not check(host.save(),"H1 actual initial save"):return
 var first_host_id:int=host.get_instance_id()
 var first_session_id:int=host.session.get_instance_id()
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Root fixture S1 starts on port0"):return
 var first=await connect_scene("root-h1")
 if first==null:return
 if not check(budget(first).entry==null and not budget(first).recovery_blocked,"Original remote empty ledger is not locked"):return
 # Backend.save may deduplicate equal payloads. These are two actual Session writers.
 if not check(host.session.save_game(path),"First real Session.save_game writer succeeds"):return
 var first_saved:Dictionary=ProfileCompare.validated_copy(host.session,FileAccess.get_file_as_string(path))
 if not check(first_saved.get("ok",false) and first_saved.profile==host.session.snapshot(),"First writer produces a complete valid native-equivalent primary"):return
 var first_bytes:PackedByteArray=FileAccess.get_file_as_bytes(path)
 if not check(host.session.save_game(path),"Second real Session.save_game writer succeeds"):return
 if not check(FileAccess.get_file_as_bytes(path+".bak")==first_bytes,"Second writer actually backs up first valid primary"):return
 var written:Dictionary=empty_disk("root-two-writers")
 if written.is_empty():return
 if not check(host.save(),"Backend confirms actual saved profile cache"):return
 if not persisted("root-cache-confirmed"):return
 if not check(FileAccess.get_file_as_bytes(path+".bak")==written.backup.bytes,"Cache confirmation preserves actual backup bytes"):return
 var before:Dictionary=empty_disk("root-before-retire")
 if before.is_empty():return
 lifecycle("root-h1-before-retire")
 var retired_scene_id:int=first.get_instance_id()
 var retired_server_id:int=server.get_instance_id()
 first.link.close();first.music.stop();first.effect.stop();first.queue_free()
 if not await ready(func():return not is_instance_id_valid(retired_scene_id) and is_instance_id_valid(retired_server_id) and instance_from_id(retired_server_id).clients().is_empty(),"Root C1 retired and actual S1 socket removed"):return
 worlds.clear()
 if not check(host.session._pending.is_empty() and not host.battle_open and not host.quest_auto.running,"No pending battle or active run before root fixture retirement"):return
 server.stop()
 if not check(not server.is_listening(),"Root S1.stop really stops listener"):return
 var retired:Dictionary=empty_disk("root-after-stop")
 if retired.is_empty():return
 if not check(retired.primary.bytes==before.primary.bytes and retired.backup.bytes==before.backup.bytes,"Real retirement preserves both primary and backup; resume archived separately"):return
 var backup_profile:Dictionary=ProfileCompare.validated_copy(host.session,retired.backup.bytes.get_string_from_utf8())
 if not check(backup_profile.get("ok",false),"Retired backup full-profile baseline validated before any loader"):return
 server.queue_free()
 if not await ready(func():return not is_instance_id_valid(retired_server_id),"Root S1 freed before fault injection"):return
 host.queue_free()
 if not await ready(func():return not is_instance_id_valid(first_host_id),"Root H1 freed before fault injection"):return
 # Explicit one-byte fault in our isolated R only, AFTER both old owners retire.
 var fault=FileAccess.open(path,FileAccess.WRITE)
 if not check(fault!=null,"Owned primary opens for explicit truncated-JSON fault"):return
 fault.store_string("{");fault.flush()
 var fault_error:int=fault.get_error();fault.close()
 if not check(fault_error==OK and FileAccess.get_file_as_bytes(path)=="{".to_utf8_buffer(),"Only owned primary is exactly one truncated byte"):return
 if not check(FileAccess.get_file_as_bytes(path+".bak")==retired.backup.bytes,"Fault leaves valid backup byte-for-byte intact"):return
 var parser=JSON.new()
 var parse_error:int=parser.parse(FileAccess.get_file_as_string(path))
 print("ROOT PRIMARY FAULT ",JSON.stringify({"parse_error":parse_error,"line":parser.get_error_line(),"message":parser.get_error_message()}))
 if not check(parse_error!=OK,"JSON.new.parse rejects fault without parse_string error logging"):return
 # A fresh H2 is the FIRST actual loader; archive does not load or mutate saves.
 host=Backend.new();host.set_process(false);host.save_path=path
 if not check(host.get_instance_id()!=first_host_id and host.session.get_instance_id()!=first_session_id,"Root H2 has a distinct real host and Session"):return
 var corrupted:Dictionary=archive("root-corrupted-before-load")
 if corrupted.is_empty():return
 var second_session_id:int=host.session.get_instance_id()
 if not check(host.load_profile(path),"H2 first production loader recovers actual backup"):return
 if not check(host.session.get_instance_id()==second_session_id,"Root load preserves new H2 Session ownership"):return
 root.add_child(host);host.set_process(false)
 if not persisted("root-h2-first-load"):return
 var loaded:Dictionary=host.session.snapshot()
 if not check(loaded.quest_loot.recovery_blocked and loaded.quest_loot.entries.is_empty(),"Production backup recovery persists root lock without fabricating entry"):return
 var expected:Dictionary=backup_profile.profile.duplicate(true)
 expected.quest_loot.recovery_blocked=true # Expected-copy comparison only; never installed.
 if not check(loaded==expected,"Entire loaded native profile changes only actual backup-recovery root lock"):return
 var recovered:Dictionary=archive("root-h2-loaded")
 if recovered.is_empty():return
 if not check(recovered.backup.bytes==retired.backup.bytes,"Recovery writer does not replace good backup with truncated primary"):return
 var independent=Session.new()
 if not check(independent.load_game(path) and independent.snapshot()==loaded,"Independent second Session reads full root-locked primary"):return
 if not check(FileAccess.get_file_as_bytes(path)==recovered.primary.bytes and FileAccess.get_file_as_bytes(path+".bak")==retired.backup.bytes,"Independent read changes neither primary nor protected backup"):return
 if not persisted("root-independent-read"):return
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Root S2 starts only after durable lock and independent read"):return
 var restored=await connect_scene("root-h2")
 if restored==null:return
 if not await ready(func():return budget(restored).get("recovery_blocked",false) and budget(restored).get("entry")==null and panel(restored).visible and panel(restored).content().contains("中断时段用时不确定"),"Real backend-null scene displays root lock with null entry"):return
 if not check(budget(restored).activity=="recovery_locked","Authority chooses recovery-locked activity even without entry"):return
 for key in ["enabled","can_start","can_stop","can_adjust_limit","can_reset"]:
  if not check(budget(restored).get(key)==false,"Root lock cannot enable "+key):return
 var content:String=panel(restored).content()
 if not check(content.contains("尚未开放") and not content.contains("本步已用") and not content.contains("已保存战数") and not content.contains("0/0"),"Null entry displays lock and unavailability without invented counters"):return
 if not check(panel(restored).controls.disabled and panel(restored).controls.pressed.get_connections().is_empty(),"Root lock panel has no control command"):return
 lifecycle("root-h2-authenticated-locked")
 var final_files:Dictionary=archive("root-after-authentication")
 if final_files.is_empty():return
 if not check(final_files.primary.bytes==recovered.primary.bytes and final_files.backup.bytes==retired.backup.bytes,"Real scene authentication preserves recovered disk and good backup"):return
 var restored_id:int=restored.get_instance_id()
 restored.link.close();restored.music.stop();restored.effect.stop();restored.queue_free()
 if not await ready(func():return not is_instance_id_valid(restored_id),"Root recovered scene retired"):return
 worlds.clear();server.stop();server.queue_free();host.queue_free()
 print("LOOT ROOT RECOVERY REMOTE UI: PASS (isolated real backup only; no battle/storage/active-run coverage)")
 quit(0)
