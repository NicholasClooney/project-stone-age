extends "res://tests/quest_auto_loot_recovery_remote_ui_test.gd"
## UNRUN draft. Requires original E1/E2 and FINAL E3a/E3b contract/hash.
## Internal source/strong-character/seed4101 fixture; NOT public admission or RNG statistics.
## Two production scenes; retry is actual WS battle_close, NOT a UI button claim.
var battle_events:Array=[]
var source_cell:Vector2i=Vector2i(-1,-1)
func pending_difference(expected:Dictionary,actual:Dictionary)->Dictionary:
 var difference:Dictionary={}
 var keys:Array=expected.keys()
 for key in actual:
  if not keys.has(key):keys.append(key)
 for key in keys:
  if expected.has(key)!=actual.has(key) or expected.get(key)!=actual.get(key):
   difference[key]={"expected_present":expected.has(key),"actual_present":actual.has(key),"expected":expected.get(key),"actual":actual.get(key)}
 return difference
func observe(stage:String,event:Dictionary)->void:
 var record:Dictionary={"stage":stage,"event":event.duplicate(true),"run":host.quest_auto.identity.checkpoint(),"connection":host.quest_auto.connection,"client":host.quest_auto.client,"phase":host.quest_auto.phase,"timer_paused":host.quest_loot.storage_paused}
 battle_events.append(record)
 print("LOOT BATTLE OBSERVE ",JSON.stringify(record))
func source_fixture()->bool:
 host.session.OriginalEquipment.add(host.session._profile,2764)
 var map_data:Dictionary=preload("res://scripts/map_file.gd").load_map(host.quest_helper.places.file(100))
 if not check(host.quest_loot.admission_terrain_valid(map_data),"Original source terrain validated before scan"):return false
 var links:Dictionary=host.quest_helper.places.links(100)
 var selected:Vector2i=Vector2i(-1,-1)
 for y in range(341,413):
  for x in range(621,646):
   var candidate:=Vector2i(x,y)
   if host.encounter_catalog.area_at(100,candidate).get("id")!=56:continue
   if not host.quest_helper.safe(map_data,candidate,{},links):continue
   selected=candidate;break
  if selected.x>=0:break
 if not check(selected.x>=0,"Real original source area56 safe cell exists"):return false
 # Disclosed initial source location fixture so normal scene reports match it.
 # No route/arrival/protected-point proof is granted or claimed.
 source_cell=selected
 host.session.set_location(100,selected.x,selected.y)
 host.automation.position_changed(100,selected,true,"project")
 host.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(host.session._profile.player)
 host.session._profile.player.hp=host.session._profile.player.max_hp
 return check(host.save(),"Explicit source/strong-character fixture is really saved")
func run()->void:
 # DO NOT RUN before final E3 ownership/failure publication review.
 path="user://loot-battle-storage-remote.json"
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 host=Backend.new();root.add_child(host);host.set_process(false);host.save_path=path
 if not source_fixture():return
 host.event.connect(func(event):observe("backend-final",event))
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Real direct-backend S port0, not account/ProfileHub authentication"):return
 var first=await connect_scene("battle-a")
 if first==null:return
 if not check(server.clients().size()==1,"C1 is sole actual promoted WS peer"):return
 var first_peer_id:int=server.clients()[0].get_instance_id()
 var actual_client:String=first._client_id
 if not check(not actual_client.is_empty(),"C1 actual production report client ID exists"):return
 first.link.message.connect(func(event):observe("ws-a",event))
 var second=await connect_scene("battle-b")
 if second==null:return
 second.link.message.connect(func(event):observe("ws-b",event))
 if not check(server.clients().size()==2 and server.clients().any(func(peer):return peer.get_instance_id()==first_peer_id),"C2 cannot replace actual C1 transport owner"):return
 for world in worlds:
  if not await ready(func():return not world.data.is_empty() and int(world.data.map_id)==100 and world.cell==source_cell and not world.area_transition_busy and not world.moving,"Both scenes naturally finish loading original source cell"):return
  if not check(await Wait.settle(self,world),"Natural source reports complete before E1 binding"):return
 if not check(host.automation.position_map==100 and host.automation.position_cell==source_cell,"Natural dual-scene reports preserve original authority source cell"):return
 if not check(server.clients().size()==2 and server.clients().any(func(peer):return peer.get_instance_id()==first_peer_id) and first._client_id==actual_client,"Natural reports preserve captured C1 peer/client binding"):return
 var q=host.quest_auto
 q.identity.begin();q.identity.select_step(State.STEP)
 q.running=true;q.internal=true;q.detached=false;q.restored=false
 q.connection=first_peer_id;q.client=actual_client;q.phase="loot_admission";q.step=Sources.step()
 host.quest_loot.clock=func():return clock_ms
 var actual_peers:Array=[]
 for peer in server.clients():
  actual_peers.append({"instance_id":peer.get_instance_id(),"instance_id_text":str(peer.get_instance_id()),"ready_state":peer.get_ready_state(),"is_c1":peer.get_instance_id()==first_peer_id})
 var c1_now=instance_from_id(first_peer_id) if is_instance_id_valid(first_peer_id) else null
 var disk_before:String=FileAccess.get_file_as_string(path)
 var baseline_before:String=host.last_saved_payload
 print("LOOT E1 BEFORE ",JSON.stringify({"c1_peer":c1_now.get_instance_id() if is_instance_valid(c1_now) else null,"c1_peer_text":str(c1_now.get_instance_id()) if is_instance_valid(c1_now) else "retired","captured_c1":str(first_peer_id),"q_connection":q.connection,"q_connection_text":str(q.connection),"q_client":q.client,"scene_client":first._client_id,"server_clients":actual_peers,"transport_field":"_quest_connection","transport_field_value_from_current_c1":str(c1_now.get_instance_id()) if is_instance_valid(c1_now) else "retired","call_kind":"internal E1; no command or injected transport field","identity":q.identity.checkpoint(),"running":q.running,"internal":q.internal,"detached":q.detached,"restored":q.restored,"phase":q.phase,"source_step":q.step,"disk_sha256":disk_before.sha256_text(),"disk_bytes":disk_before.to_utf8_buffer().size(),"baseline_sha256":baseline_before.sha256_text(),"baseline_bytes":baseline_before.to_utf8_buffer().size(),"disk_equals_baseline":disk_before==baseline_before}))
 var admitted:Dictionary=host.quest_loot.admit_prepared_run(host) # Exactly one original call.
 var observed_entries:Dictionary=host.session._profile.get("quest_loot",{}).get("entries",{})
 var observed_entry=observed_entries.get(State.STEP)
 var disk_after:String=FileAccess.get_file_as_string(path)
 var baseline_after:String=host.last_saved_payload
 print("LOOT E1 AFTER ",JSON.stringify({"admitted":admitted,"entry_exists":observed_entries.has(State.STEP),"entry":observed_entry,"identity":q.identity.checkpoint(),"connection_text":str(q.connection),"client":q.client,"phase":q.phase,"disk_sha256":disk_after.sha256_text(),"disk_bytes":disk_after.to_utf8_buffer().size(),"baseline_sha256":baseline_after.sha256_text(),"baseline_bytes":baseline_after.to_utf8_buffer().size(),"disk_equals_baseline":disk_after==baseline_after,"disk_unchanged":disk_after==disk_before,"baseline_unchanged":baseline_after==baseline_before}))
 if not check(admitted.get("ok",false),"Real E1 durable acquire/open returns success for actual C1"):return
 if not check(observed_entry is Dictionary and observed_entry.get("open_span",false),"Successful E1 has actual durable open entry before any battle"):return
 if not persisted("battle-admitted"):return
 host.publish()
 for world in worlds:
  if not await ready(func():return budget(world).get("entry") is Dictionary and panel(world).visible,"Both real WS consumers see admitted durable entry"):return
 for world in worlds:
  if not check(await Wait.settle(self,world),"Post-admission production messages settle without position repair"):return
 if not check(q.connection==first_peer_id and q.client==actual_client and host.automation.position_map==100 and host.automation.position_cell==source_cell,"E1 and natural WS traffic preserve actual owner and source position"):return
 lifecycle("battle-admitted-real-peer")
 host.encounter_rng.seed=4101;host.encounter_catalog.pressure=50
 var attempt:Dictionary={}
 for index in range(200):
  attempt=host.quest_loot.attempt_once(host)
  if attempt.get("battle",false) or not attempt.get("ok",false):break
  clock_ms+=500
 if not check(attempt.get("battle",false) and host.battle_open and host.session._pending.has("quest_loot_receipt"),"Actual original encounter creates battle and receipt"):return
 var battle_id:String=str(host.battle.snapshot().get("battle_id",""))
 var original_battle_instance:int=host.battle.get_instance_id()
 var receipt:Dictionary=host.session._pending.quest_loot_receipt.duplicate(true)
 var pending:Dictionary=host.session._pending.duplicate(true)
 print("LOOT INITIAL PENDING ",JSON.stringify(pending))
 if not check(not battle_id.is_empty() and int(pending.group_id)==169,"Disclosed seed4101 produced expected original group169; no seed retry"):return
 if not check(host.automation.single_battle and host.automation.settings.preset=="attack" and host.automation.settings.compact,"E2 starts actual original single-battle attack/compact"):return
 var trusted:String=host.last_saved_payload
 var disk:PackedByteArray=FileAccess.get_file_as_bytes(path)
 var durable:Dictionary=ProfileCompare.validated_copy(host.session,trusted)
 if not check(durable.get("ok",false),"Whole trusted pre-settlement payload validates"):return
 if not check(DirAccess.make_dir_absolute(path+".tmp")==OK,"Only own actual atomic-writer tmp path blocked"):return
 for tick in range(100):
  if host.quest_loot.storage_paused:break
  if not host.automation.running:break
  clock_ms+=500
  host.automation.tick_battle(0.5)
 if not check(host.quest_loot.storage_paused and not host.battle_state.get("settled",true) and not host.battle.snapshot().active,"Real atomic failure reaches frozen unsettled finished battle"):return
 if not check(is_instance_id_valid(original_battle_instance) and is_instance_valid(host.battle) and host.battle.get_instance_id()==original_battle_instance and str(host.battle.snapshot().get("battle_id",""))==battle_id,"Original real battle remains readable for claims evidence"):return
 var actual_claims:Array=host.battle.drop_claims_for()
 var actual_pending:Dictionary=host.session._pending.duplicate(true)
 var expected_pending:Dictionary=pending.duplicate(true)
 expected_pending.loot_claims=actual_claims.duplicate(true) # Independent comparison only.
 print("LOOT FAILED PENDING ",JSON.stringify({"initial":pending,"actual_claims":actual_claims,"expected":expected_pending,"actual":actual_pending,"initial_difference":pending_difference(pending,actual_pending),"expected_difference":pending_difference(expected_pending,actual_pending)}))
 if not check(host.battle_open and actual_pending==expected_pending and actual_pending.get("quest_loot_receipt")==receipt,"Full failed pending equals initial copy plus only real original battle claims"):return
 if not check(host.last_saved_payload==trusted and FileAccess.get_file_as_bytes(path)==disk,"Failure preserves full trusted payload and actual primary"):return
 var paused:Dictionary=archive("battle-storage-failed")
 if paused.is_empty():return
 # E3b must confirm these actual publications; no forced publish to rescue them.
 for world in worlds:
  if not await ready(func():return budget(world).get("activity")=="storage_paused" and panel(world).content().contains("预算暂停计时"),"Actual production failure publication reaches both panels"):return
  if not check(budget(world).entry.saved_battles==durable.profile.quest_loot.entries[State.STEP].saved_battles and budget(world).entry.new_items==0,"UI retains actual saved counters during failed write"):return
 var frozen:Dictionary=host.quest_loot.cached_sample.duplicate(true)
 clock_ms+=10000
 if not check(host.quest_loot.cached_sample==frozen,"No local extrapolation or rescue sample while storage paused"):return
 if not check(DirAccess.remove_absolute(path+".tmp")==OK,"Remove only this suite's writer blocker"):return
 var ack:Dictionary={}
 first.link.request({"type":"battle_close","battle_id":battle_id},func(reply):ack.merge(reply))
 if not await ready(func():return not ack.is_empty(),"Original actual-ID WS battle_close retry replies"):return
 if not check(ack.get("ok",false) and not host.battle_open and host.session._pending.is_empty(),"Same real battle retry commits then closes"):return
 print("LOOT RETRY ACK ",JSON.stringify(ack))
 if not persisted("battle-retry-succeeded"):return
 if not check(entry().saved_battles==1 and entry().new_items==0 and not entry().open_span,"Original non-target battle counts exactly once with no fabricated drop"):return
 for world in worlds:
  if not await ready(func():return budget(world).get("entry",{}).get("saved_battles")==1 and panel(world).content().contains("已保存战数 1"),"Both actual WS panels consume committed one-battle count"):return
 # Settled/closed presentation may issue its ordinary checkpoint save.
 # Drain each real connection before final full-disk baseline; never count OS writes.
 for world in worlds:
  if not check(await Wait.settle(self,world),"Actual scene checkpoint traffic settles after successful retry"):return
 if not persisted("battle-after-scene-checkpoints"):return
 var saved:Dictionary=host.session.snapshot()
 var saved_disk:PackedByteArray=FileAccess.get_file_as_bytes(path)
 var duplicate:Dictionary={}
 first.link.request({"type":"battle_close","battle_id":battle_id},func(reply):duplicate.merge(reply))
 if not await ready(func():return not duplicate.is_empty(),"Duplicate actual-ID close gets real response"):return
 if not check(not duplicate.get("ok",true) and host.session.snapshot()==saved and FileAccess.get_file_as_bytes(path)==saved_disk,"Duplicate cannot re-award or mutate complete profile/disk"):return
 var independent=Session.new()
 if not check(independent.load_game(path) and independent.snapshot()==saved,"Independent disk reader verifies full actual battle and ledger"):return
 var final_files:Dictionary=archive("battle-storage-final")
 if final_files.is_empty():return
 var scene_ids:Array=[]
 for world in worlds:
  scene_ids.append(world.get_instance_id());world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 if not await ready(func():return scene_ids.all(func(id):return not is_instance_id_valid(id)),"Both battle scenes retired by stable IDs"):return
 worlds.clear();server.stop();server.queue_free();host.queue_free()
 print("LOOT BATTLE STORAGE REMOTE UI: PASS (internal fixed-seed ordinary driver; no target drop/public start/button-click/active-detach proof)")
 quit(0)
