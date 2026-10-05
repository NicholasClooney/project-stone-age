extends "res://tests/quest_auto_loot_active_detach_remote_ui_test.gd"
## UNRUN DIAGNOSTIC: natural reconnect during original cancelled battle.
## Frozen target: natural non-job2 report must not invalidate cancellation scope.
func run()->void:
 path="user://loot-active-battle-detach.json"
 if not await prepare_bound():return
 host.encounter_rng.seed=4101;host.encounter_catalog.pressure=50
 var attempt:Dictionary={}
 for index in range(200):
  attempt=host.quest_loot.attempt_once(host)
  if attempt.get("battle",false) or not attempt.get("ok",false):break
  clock_ms+=500
 if not check(attempt.get("battle",false) and host.battle_open and host.battle.snapshot().active and host.automation.running,"Original E2 actual active single battle exists before close"):return
 var original_id:String=str(host.battle.snapshot().get("battle_id",""))
 var pending:Dictionary=host.session._pending.duplicate(true)
 if not check(int(pending.get("group_id",-1))==169 and pending.has("quest_loot_receipt"),"Fixed seed4101 creates actual non-target169 receipt"):return
 var primary:PackedByteArray=FileAccess.get_file_as_bytes(path)
 var first=worlds[0]
 host.battle_obligation={"backend":host.get_instance_id(),"session":host.session.get_instance_id(),"battle":host.battle.get_instance_id(),"automation":host.automation.get_instance_id(),"runner":host.quest_auto.get_instance_id(),"timer":host.quest_loot.get_instance_id(),"battle_id":original_id,"receipt":pending.quest_loot_receipt.duplicate(true),"token_id":host.automation.start_lifetime.get_instance_id(),"scope_id":host.automation.loot_scope.capability.get_instance_id()}
 if not check(host.battle_guard_state().values().all(func(value):return value==true),"Original owner/receipt/active scope valid before arming observer"):return
 host.guard_reports=true;host.guard_battle_scope=true
 first.link.close()
 if not await ready(func():return not server.clients().any(func(peer):return peer.get_instance_id()==initiating_peer),"Actual server removes original C1 socket before reconnect"):return
 print("LOOT BATTLE DETACHED ",JSON.stringify({"state":host.report_state(),"entry":entry().duplicate(true),"pending":host.session._pending.duplicate(true),"reports":host.report_records}))
 if not check(host.quest_auto.detached and host.quest_auto.connection==-1 and host.quest_auto.client.is_empty(),"Actual battle detach fixes revoked execution binding"):return
 if not check(host.session._pending==pending and FileAccess.get_file_as_bytes(path)==primary and entry().open_span,"Actual battle detach preserves entire receipt obligation and open disk span"):return
 if not check(host.battle_guard_state().values().all(func(value):return value==true),"Original battle obligation remains valid immediately after detach"):return
 if not check(host.automation.running and host.battle.snapshot().active and not host.quest_loot.storage_paused and not host.quest_loot.frozen,"Existing original battle remains active, not idle-closed or frozen"):return
 var archive_before:Dictionary=archive("active-battle-before-reconnect")
 if archive_before.is_empty():return
 if not await reconnected():return
 # DO NOT repair q/ignore natural reports if generic adoption invalidates scope.
 # Frozen target: observing peers must not adopt the cancelled execution.
 if not check(host.quest_auto.detached and host.quest_auto.connection==-1 and host.quest_auto.client.is_empty(),"Natural reconnect does not adopt old battle execution"):return
 if not check(not host.automation.loot_scope.is_empty() and host.automation._loot_current(host.automation.loot_scope),"Natural reconnect preserves actual original cancelled battle scope"):return
 if not check(host.battle_guard_state().values().all(func(value):return value==true),"Reconnected original battle remains active with same owner/receipt/scope"):return
 for tick in range(100):
  if not host.automation.running:break
  clock_ms+=500;host.automation.tick_battle(0.5)
  if not host.report_violation.is_empty():return
  if not check(host.original_battle_owner(),"Every original tick returns with same fixed battle and owners"):return
  if host.battle_guard_phase=="active":
   if host.battle.snapshot().active:
    if not check(host.battle_guard_state().values().all(func(value):return value==true),"Unfinished original tick retains valid receipt/scope; no next tick after failure"):return
   else:
    if not check(host.battle_state.get("settled",false) and str(host.battle_state.get("battle_id",""))==original_id and host.session._pending.is_empty() and entry().saved_battles==1 and entry().new_items==0 and not entry().open_span and not host.quest_auto.running and not host.quest_auto.owns_battle,"Same original battle durably settled before awaiting original auto close"):return
    if not persisted("battle-durable-await-close"):return
    var scope:Dictionary=host.automation.loot_scope
    if not check(not scope.is_empty() and host.automation._loot_current(scope),"Durable boundary retains original valid auto scope"):return
    host.committed_obligation={"profile":host.session.snapshot().duplicate(true),"entry":entry().duplicate(true),"token_id":host.automation.start_lifetime.get_instance_id(),"scope_id":scope.capability.get_instance_id(),"authority":scope.authority.duplicate(true)}
    host.battle_guard_phase="settled_await_close"
    print("LOOT DURABLE AWAIT CLOSE ",JSON.stringify({"tick":tick,"state":host.report_state(),"committed":host.committed_obligation}))
  if host.battle_guard_phase=="settled_await_close":
   if not check(host.battle_guard_state().values().all(func(value):return value==true),"Committed full result and original auto owner/token remain exact after each tick"):return
   if not host.automation.running and not host.battle_open:break
  # Otherwise continue only the original bounded tick driver, never manual close.
 print("LOOT BATTLE AFTER DRIVER ",JSON.stringify({"state":host.report_state(),"battle":host.battle_state.duplicate(true),"pending":host.session._pending.duplicate(true),"entry":entry().duplicate(true)}))
 if not check(not host.automation.running and not host.battle_open and host.session._pending.is_empty() and host.battle_state.get("settled",false),"One original battle settles after real detach/reconnect without rescue"):return
 if not check(str(host.battle_state.get("battle_id",""))==original_id and entry().saved_battles==1 and entry().new_items==0 and not entry().open_span and not host.quest_auto.running and not host.quest_auto.owns_battle,"Actual same battle counts once, closes span and cannot revive cancelled runner"):return
 # No await occurs between the real final tick and these complete assertions.
 # A report-induced stop sets violation above and can never reach retirement.
 if not host.report_violation.is_empty():return
 if not check(host.battle_guard_phase=="settled_await_close" and host.battle_guard_state().values().all(func(value):return value==true),"Complete retirement preserves immutable committed result and original owner"):return
 host.battle_guard_phase="retired"
 host.guard_battle_scope=false
 print("LOOT BATTLE OBSERVATION RETIRED ",JSON.stringify({"obligation":host.battle_obligation,"state":host.report_state(),"entry":entry().duplicate(true)}))
 for world in worlds:
  if not await ready(func():return budget(world).get("entry",{}).get("saved_battles")==1,"Both real consumers show one committed cancelled battle"):return
  if not check(await Wait.settle(self,world),"Natural scene checkpoint traffic settles"):return
  if not host.report_violation.is_empty():return
 if not persisted("active-battle-settled"):return
 var independent=Session.new()
 if not check(independent.load_game(path) and independent.snapshot()==host.session.snapshot(),"Independent full profile read verifies actual cancelled battle settlement"):return
 var files:Dictionary=archive("active-battle-final")
 if files.is_empty():return
 if not await dispose_scenes():return
 print("LOOT BATTLE DETACH DIAGNOSTIC: PASS (one original battle only; no target drop/account/public/scheduler continuation)")
 quit(0)
