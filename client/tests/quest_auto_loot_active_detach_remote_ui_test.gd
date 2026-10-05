extends "res://tests/quest_auto_loot_battle_storage_remote_ui_test.gd"
## UNRUN DIAGNOSTIC: real E1 idle detach, no attempt; frozen stop/no-adoption target.
## Target: idle close stops old execution; natural reports never revive it.
class ReportObservedBackend:
 extends "res://server/backend.gd"
 var report_records:Array=[]
 var observer_server:WeakRef
 var guard_reports:=false
 var guard_battle_scope:=false
 var report_violation:String=""
 func report_state()->Dictionary:
  var q=quest_auto
  var scope:Dictionary=automation.loot_scope
  return {"identity":q.identity.checkpoint().duplicate(true),"quest_id":q.quest_id,"connection":str(q.connection),"client":q.client,"running":q.running,"owns_battle":q.owns_battle,"internal":q.internal,"detached":q.detached,"restored":q.restored,"phase":q.phase,"step":q.step.duplicate(true),"scope_present":not scope.is_empty(),"scope_valid":automation._loot_current(scope) if not scope.is_empty() else false,"scope_authority":scope.get("authority",{}).duplicate(true),"auto_running":automation.running,"battle_open":battle_open,"battle_id":str(battle.snapshot().get("battle_id","")),"pending_receipt":session._pending.get("quest_loot_receipt",{}).duplicate(true),"ready_frame_present":not quest_loot.ready_frame.is_empty(),"close_pending_present":not quest_loot.close_pending.is_empty(),"timer_anchor":quest_loot.anchor_ms,"timer_frozen":quest_loot.frozen,"storage_paused":quest_loot.storage_paused,"backend_id":str(get_instance_id()),"session_id":str(session.get_instance_id()),"map_id":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y]}
 func _cmd_report_position(command:Dictionary)->Dictionary:
  var before:Dictionary=report_state()
  var observed:Dictionary=command.duplicate(true)
  var transport:Dictionary={"available":false,"incoming_member":false,"members":[]}
  var current_server=observer_server.get_ref() if observer_server!=null else null
  if is_instance_valid(current_server):
   transport.available=true
   transport.backend_matches=is_same(current_server.backend,self)
   for peer in current_server.clients():
    transport.members.append({"peer":str(peer.get_instance_id()),"state":peer.get_ready_state()})
    if peer.get_instance_id()==command.get("_quest_connection",-1):transport.incoming_member=true
  var reply:Dictionary=super._cmd_report_position(command) # Exactly once; unchanged production consumer.
  var record:Dictionary={"transport":transport,"command":observed,"injected_peer_text":str(observed.get("_quest_connection",-1)),"before":before,"after":report_state(),"reply":reply.duplicate(true)}
  report_records.append(record);print("LOOT ACTUAL REPORT ",JSON.stringify(record))
  if guard_reports:
   var different:bool=int(observed.get("map_id",-1))!=int(before.map_id) or observed.get("cell",[])!=before.cell
   if different:report_violation="Natural report changed actual source map/cell"
   elif guard_battle_scope and before.scope_present and not record.after.scope_valid:report_violation="Natural report invalidated original cancelled battle scope"
   elif guard_battle_scope and before.auto_running and not record.after.auto_running:report_violation="Natural same-cell report stopped retained original battle"
   if not report_violation.is_empty():
    print("FAIL ",report_violation);get_tree().quit(1)
  return reply
func ready(condition:Callable,note:String)->bool:
 var reached:bool=await Wait.until(self,func():return not host.report_violation.is_empty() or condition.call())
 if not host.report_violation.is_empty():return false # Observer already logged and quit; no next action.
 return check(reached,note)
var initiating_peer:int=-1
var initiating_client:String=""
func prepare_bound()->bool:
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 host=ReportObservedBackend.new();root.add_child(host);host.set_process(false);host.save_path=path
 if not source_fixture():return false
 host.event.connect(func(event):observe("backend-final",event))
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 host.observer_server=weakref(server)
 if not check(server.start()==OK,"Detach direct-backend transport starts on actual port0"):return false
 var first=await connect_scene("detach-a")
 if first==null:return false
 if not check(server.clients().size()==1,"Original C1 is sole promoted peer"):return false
 initiating_peer=server.clients()[0].get_instance_id();initiating_client=first._client_id
 first.link.message.connect(func(event):observe("ws-a",event))
 var second=await connect_scene("detach-b")
 if second==null:return false
 second.link.message.connect(func(event):observe("ws-b",event))
 for world in worlds:
  if not await ready(func():return not world.data.is_empty() and int(world.data.map_id)==100 and world.cell==source_cell and not world.area_transition_busy and not world.moving,"Natural scene loads actual ordinary source initial fixture"):return false
  if not check(await Wait.settle(self,world),"Natural initial reports settle before E1"):return false
  if not host.report_violation.is_empty():return false
 if not check(server.clients().size()==2 and server.clients().any(func(peer):return peer.get_instance_id()==initiating_peer) and first._client_id==initiating_client,"Actual initial C1 transport/client retained"):return false
 if not check(host.automation.position_map==100 and host.automation.position_cell==source_cell,"Both natural reports preserve actual source cell"):return false
 var q=host.quest_auto
 q.identity.begin();q.identity.select_step(State.STEP)
 q.running=true;q.internal=true;q.detached=false;q.restored=false
 q.connection=initiating_peer;q.client=initiating_client;q.phase="loot_admission";q.step=Sources.step()
 host.quest_loot.clock=func():return clock_ms
 var admitted:Dictionary=host.quest_loot.admit_prepared_run(host)
 print("LOOT DETACH ADMISSION ",JSON.stringify({"peer":str(initiating_peer),"client":initiating_client,"reply":admitted,"state":host.report_state()}))
 if not check(admitted.get("ok",false),"Real peer-bound E1 admission succeeds once"):return false
 if not check(entry().open_span and host.quest_loot.anchor_ms==clock_ms,"Real durable entry and active timer exist before disconnect"):return false
 if not persisted("detach-admitted"):return false
 host.publish() # Initial admission publication only; no rescue after disconnect.
 for world in worlds:
  if not await ready(func():return budget(world).get("entry") is Dictionary and panel(world).visible,"Both production consumers see admitted entry"):return false
  if not check(await Wait.settle(self,world),"Initial admission consumer roundtrip"):return false
  if not host.report_violation.is_empty():return false
 return check(q.connection==initiating_peer and q.client==initiating_client,"E1 and initial consumer reports keep actual initiating binding")
func reconnected()->bool:
 var first=worlds[0]
 first.link.connect_now()
 if not await ready(func():return first.link.online,"C1 production link authenticates a genuinely new socket"):return false
 for world in worlds:
  if not check(await Wait.settle(self,world),"Natural reconnect/report traffic roundtrip without forced report"):return false
  if not host.report_violation.is_empty():return false
 print("LOOT AFTER NATURAL RECONNECT ",JSON.stringify({"state":host.report_state(),"reports":host.report_records}))
 return check(server.clients().size()==2 and not server.clients().any(func(peer):return peer.get_instance_id()==initiating_peer),"Retired C1 peer is absent from actual new two-client membership")
func dispose_scenes()->bool:
 var ids:Array=[]
 for world in worlds:
  ids.append(world.get_instance_id());world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 if not await ready(func():return ids.all(func(id):return not is_instance_id_valid(id)),"Detach scenes retire using stable IDs"):return false
 worlds.clear();server.stop();server.queue_free();host.queue_free()
 return true
func run()->void:
 path="user://loot-active-idle-detach.json"
 if not await prepare_bound():return
 var initial:Dictionary=entry().duplicate(true)
 var old_owner:Dictionary={"backend":host.get_instance_id(),"session":host.session.get_instance_id(),"runner":host.quest_auto.get_instance_id(),"identity_object":host.quest_auto.identity.get_instance_id(),"identity":host.quest_auto.identity.checkpoint().duplicate(true)}
 var first=worlds[0]
 clock_ms=1750 # No sample call: E3a must take the exact close sample itself.
 host.guard_reports=true
 first.link.close()
 if not await ready(func():return not server.clients().any(func(peer):return peer.get_instance_id()==initiating_peer) and not entry().open_span,"Real CLOSED initiating peer triggers actual durable idle close"):return
 print("LOOT IDLE DETACHED ",JSON.stringify({"state":host.report_state(),"entry":entry().duplicate(true),"reports":host.report_records}))
 var stopped_files:Dictionary=archive("idle-detach-target-before-assert")
 if stopped_files.is_empty():return
 if not check(host.get_instance_id()==old_owner.backend and host.session.get_instance_id()==old_owner.session and host.quest_auto.get_instance_id()==old_owner.runner and host.quest_auto.identity.get_instance_id()==old_owner.identity_object and host.quest_auto.identity.checkpoint()==old_owner.identity,"Observed close still belongs to fixture original owner and identity, not a successor"):return
 if not check(entry().used_ms==750 and entry().budget_id==initial.budget_id and entry().generation==initial.generation and entry().revision==initial.revision+1 and entry().saved_battles==0 and entry().new_items==0,"E3a persists exact750 idle cutoff and same budget history"):return
 if not check(host.session._pending.is_empty() and not host.battle_open and host.quest_loot.anchor_ms<0,"Idle disconnect retires active span without creating battle"):return
 if not persisted("idle-detach-closed"):return
 var closed:Dictionary=entry().duplicate(true)
 var independent=Session.new()
 if not check(independent.load_game(path) and independent.snapshot()==host.session.snapshot(),"Independent full disk proves actual idle close"):return
 if not check(not host.quest_auto.running and not host.quest_auto.owns_battle and host.quest_auto.detached and host.quest_auto.connection==-1 and host.quest_auto.client.is_empty() and host.quest_loot.ready_frame.is_empty(),"Successful idle detach stops old execution with revoked binding and attempt permission"):return
 if not await ready(func():return panel(first).content().contains("连接状态已过期") and budget(worlds[1]).get("entry",{}).get("saved_used_ms")==750,"Closed C1 marks stale and live C2 consumes actual saved cutoff"):return
 var files:Dictionary=archive("idle-detach-before-reconnect")
 if files.is_empty():return
 if not await reconnected():return
 for world in worlds:
  if not await ready(func():return budget(world).get("entry",{}).get("saved_used_ms")==750 and panel(world).content().contains("本步已用 750 ms"),"Both real clients show same closed history after natural reconnect"):return
 if not check(not host.quest_auto.running and not host.quest_auto.owns_battle and host.quest_auto.detached and host.quest_auto.connection==-1 and host.quest_auto.client.is_empty() and host.quest_loot.ready_frame.is_empty(),"Natural reconnect observes history without adopting old idle execution"):return
 if not check(entry()==closed and host.quest_loot.anchor_ms<0 and not host.battle_open and host.session._pending.is_empty(),"Natural reconnect cannot reopen span, reset history or manufacture attempt"):return
 if not persisted("idle-detach-after-reconnect"):return
 if not check(FileAccess.get_file_as_bytes(path)==files.primary.bytes,"Actual reconnect preserves closed primary bytes"):return
 # No new span or implicit execution revival is authorized.
 if not await dispose_scenes():return
 print("LOOT IDLE DETACH DIAGNOSTIC: PASS (idle stopped history target only; no battle/scheduler coverage)")
 quit(0)
