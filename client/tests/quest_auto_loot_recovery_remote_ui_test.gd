extends "res://tests/quest_auto_loot_projection_remote_ui_test.gd"
## UNRUN separate window: actual retired H1 -> first-loader NEW H2 -> new scene.
## No active Session replacement, primary backfill, fabricated locks or battles.
func archive(stage:String)->Dictionary:
 var result:Dictionary={}
 for pair in [["primary",path],["backup",path+".bak"],["resume",host._resume_file()]]:
  var exists:bool=FileAccess.file_exists(pair[1])
  var bytes:PackedByteArray=PackedByteArray()
  if exists:
   var input=FileAccess.open(pair[1],FileAccess.READ)
   if not check(input!=null,"Existing evidence opens for reading: "+stage):return {}
   var length:int=input.get_length()
   bytes=input.get_buffer(length);input.close()
   if not check(bytes.size()==length,"Evidence read retains exact byte length: "+stage):return {}
  result[pair[0]]={"exists":exists,"bytes":bytes}
  if exists:
   var output=FileAccess.open("user://loot-recovery-"+stage+"-"+pair[0]+".bin",FileAccess.WRITE)
   if not check(output!=null,"Recovery byte archive opens: "+stage):return {}
   output.store_buffer(bytes);output.flush()
   var write_error:int=output.get_error();output.close()
   if not check(write_error==OK,"Raw evidence archive write succeeds: "+stage):return {}
  var digest=HashingContext.new()
  if not check(digest.start(HashingContext.HASH_SHA256)==OK,"Evidence SHA256 starts: "+stage):return {}
  if not bytes.is_empty():
   if not check(digest.update(bytes)==OK,"Nonempty evidence SHA256 updates: "+stage):return {}
  var hash:PackedByteArray=digest.finish()
  if not check(hash.size()==32,"Evidence SHA256 finishes: "+stage):return {}
  print("RECOVERY DISK ",JSON.stringify({"stage":stage,"kind":pair[0],"exists":exists,"bytes":bytes.size(),"content_state":"absent" if not exists else ("empty" if bytes.is_empty() else "nonempty"),"sha256":hash.hex_encode()}))
 return result
func run()->void:
 path="user://loot-recovery-remote.json"
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 host=preload("res://tests/support/loot_display_enabled_backend.gd").new();root.add_child(host);host.set_process(false);host.save_path=path
 if not check(host.save(),"H1 actual primary baseline"):return
 var first_host:int=host.get_instance_id()
 var first_session:int=host.session.get_instance_id()
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"S1 actual port0"):return
 var first=await connect_scene("recovery-h1")
 if first==null:return
 var q=host.quest_auto
 q.identity.begin();q.identity.select_step(State.STEP)
 if not idle("acquire",{"step_id":State.STEP,"budget_id":ID,"run_id":q.identity.run_id,"minutes":30,"existing_items":host.session.snapshot().get("original_items",[]).count(2760)}):return
 if not idle("open",entry_args()):return
 q.running=true;q.step=Sources.step();q.detached=false
 host.publish()
 if not await ready(func():return budget(first).get("entry") is Dictionary,"H1 real authentication/publication consumer sees durable entry"):return
 var open_entry:Dictionary=entry().duplicate(true)
 if not check(open_entry.open_span and not open_entry.recovery_blocked,"Real stored entry open and not pre-locked"):return
 var before:Dictionary=archive("before-retire")
 if before.is_empty():return
 lifecycle("h1-before-retire")
 var retired_first_id:int=first.get_instance_id()
 var retired_server_id:int=server.get_instance_id()
 first.link.close();first.music.stop();first.effect.stop();first.queue_free()
 if not await ready(func():return not is_instance_id_valid(retired_first_id) and is_instance_id_valid(retired_server_id) and instance_from_id(retired_server_id).clients().is_empty(),"C1 disposed and S1 has processed real socket closure"):return
 worlds.clear()
 if not check(host.session._pending.is_empty() and not host.battle_open,"No real pending/battle before H1 retirement"):return
 server.stop() # Production suspend/resume side save is intentionally exercised.
 if not check(not server.is_listening(),"Real S1.stop no longer listens"):return
 var retired:Dictionary=archive("after-stop")
 if retired.is_empty():return
 if not check(retired.primary.bytes==before.primary.bytes,"S1 stop may write resume but cannot silently close primary span"):return
 if not check(host.session._pending.is_empty() and not host.battle_open,"Stop retained empty pending/battle without fixture clearing"):return
 server.queue_free()
 if not await ready(func():return not is_instance_id_valid(retired_server_id),"S1 removed with old event subscription"):return
 var retired_host_id:int=host.get_instance_id()
 host.queue_free()
 if not await ready(func():return not is_instance_id_valid(retired_host_id),"H1 retired before new owner exists"):return
 # H2 is first loader of primary R. Do not independently load R beforehand.
 host=preload("res://tests/support/loot_display_enabled_backend.gd").new();host.set_process(false);host.save_path=path
 if not check(host.get_instance_id()!=first_host and host.session.get_instance_id()!=first_session,"New H2 naturally owns new Session"):return
 var second_session:int=host.session.get_instance_id()
 if not check(host.load_profile(path),"H2 production load is first primary recovery loader"):return
 if not check(host.session.get_instance_id()==second_session,"load_profile does not replace H2 Session"):return
 root.add_child(host);host.set_process(false)
 if not persisted("h2-first-load"):return
 var loaded:Dictionary=host.session.snapshot()
 var expected_retired:Dictionary=open_entry.duplicate(true)
 expected_retired.open_span=false;expected_retired.settled_seq=expected_retired.issued_seq;expected_retired.revision+=1
 if not check(loaded.quest_loot.entries[State.STEP]==expected_retired and not loaded.quest_loot.recovery_blocked,"Actual loader retires span and preserves all independent original budget/reward fields"):return
 var disk_after_load:Dictionary=archive("h2-loaded")
 if disk_after_load.is_empty():return
 var independent=Session.new()
 if not check(independent.load_game(path) and independent.snapshot()==loaded,"Independent second loader verifies complete persisted native profile"):return
 if not check(FileAccess.get_file_as_bytes(path)==disk_after_load.primary.bytes,"Second read preserves retired primary bytes"):return
 if not persisted("after-independent-load"):return
 # Only validated recovery/cache/primary may be exposed to a NEW server/client.
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"S2 starts only after recovery fully verified"):return
 var restored=await connect_scene("recovery-h2")
 if restored==null:return
 if not await ready(func():return not budget(restored).get("recovery_blocked",true) and panel(restored).visible and panel(restored).content().contains("未知时长未补计"),"New scene receives explicit cold-retirement lower-bound disclosure"):return
 if not check(budget(restored).activity=="stopped" and budget(restored).entry.budget_id==open_entry.budget_id and budget(restored).entry.saved_used_ms==open_entry.used_ms,"Recovery displays actual retained identity and saved lower bound"):return
 for key in ["enabled","can_start","can_stop","can_adjust_limit","can_reset"]:
  if not check(budget(restored).get(key)==false,"Recovery cannot enable "+key):return
 if not check(panel(restored).controls.disabled and panel(restored).controls.pressed.get_connections().is_empty(),"Locked display offers no command"):return
 lifecycle("h2-authenticated-retired")
 var retired_restored_id:int=restored.get_instance_id()
 restored.link.close();restored.music.stop();restored.effect.stop();restored.queue_free()
 if not await ready(func():return not is_instance_id_valid(retired_restored_id),"Recovered scene disposed"):return
 worlds.clear();server.stop();server.queue_free();host.queue_free()
 print("LOOT RECOVERY REMOTE UI: PASS (new-host first-loader only; no root-null/battle/storage/public admission)")
 quit(0)
