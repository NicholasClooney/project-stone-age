extends SceneTree
## Real encounter rolls, queued replay, battle capture, authority settlement,
## isolated save/reload and automation resume. No fabricated reward results.
const Backend = preload("res://server/backend.gd")
const Settings = preload("res://scripts/automation_settings.gd")
const ServerSettings = preload("res://server/server_settings.gd")
const ConditionsOff = preload("res://tests/support/conditions_off.gd")
const SAVE := "user://capture-only-test.json"
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1
func settings(backend, patch: Dictionary) -> Dictionary:
	return backend.handle({"type":"set_automation_settings","settings":patch})
func capacity(value: int) -> void:
	var file := ConfigFile.new();file.set_value("pet_storage","capacity",value)
	check(file.save(ServerSettings.path_override)==OK,"isolated authority capacity config saved")
func begin(backend) -> Dictionary:
	return backend.handle({"type":"auto_start","kind":"find_pet","map_id":100,"cell":[637,493]})
func fill_queue(automation, minimum: int = 3, species_minimum: int = 1) -> void:
	var deadline := Time.get_ticks_msec()+30000
	while (automation.showcase_queue.size()<minimum or automation._queue_templates().size()<species_minimum) and automation.hunt_running and Time.get_ticks_msec()<deadline:automation.scan_once()
	check(automation.showcase_queue.size()>=minimum,"real encounter rolls populate the capture queue")
func finish_capture(backend, reconcile: bool = true) -> void:
	var automation = backend.automation
	var deadline := Time.get_ticks_msec()+30000
	while automation.running and Time.get_ticks_msec()<deadline:automation.step()
	if reconcile:automation.flow_step()
func run() -> void:
	ServerSettings.path_override = "user://capture-only-server.cfg"
	capacity(0)
	var backend = Backend.new();backend.set_process(false);root.add_child(backend)
	backend.save_path = SAVE;backend.automation.client_attached = false
	backend.handle({"type":"grant_starter_pets"})
	backend.handle({"type":"gm_raise_level","index":-1,"target":120})
	check(backend.session.gm_set_base_stat(-1,"vitality",1000) and backend.session.gm_set_base_stat(-1,"dexterity",500),"authority creates robust capture-test player")
	backend.handle({"type":"gm_heal","index":-1})
	backend.handle({"type":"report_position","map_id":100,"cell":[637,493]})
	var automation = backend.automation
	var templates: Array = automation.usable_templates(true)
	check(templates.size()>0,"local reference encounter species are available")
	settings(backend,ConditionsOff.patch(templates))
	check(not Settings.effective(backend.session.automation_settings()).hunt.capture_only,"old mode stays the default")
	for wrong in [1,"true",{},null]:
		if wrong==null:continue # null resets an override, as for every setting.
		check(not settings(backend,{"hunt":{"capture_only":wrong}}).ok,"capture_only rejects non-boolean %s" % str(wrong))
	check(settings(backend,{"hunt":{"capture_only":true,"level_one":false,"train_after_capture":true,"showcase":false,"auto_capture":false,"total":-8,"offsets":[-2,-2,-2,-2],"fast":false,"queue":3,"stop_after":1}}).ok,"character capture-only preference saves")
	var effective: Dictionary = Settings.effective(backend.session.automation_settings()).hunt
	check(effective.level_one and effective.auto_capture and effective.showcase and not effective.train_after_capture,"server normalizes conflicting preferences to Lv1 capture-only queue")
	while backend.session.snapshot().pets.size()<backend.session.PET_CAPACITY:
		check(backend.handle({"type":"gm_grant_pet","template":templates[0],"full_grade":false}).ok,"fill carried roster with authority-issued pets")
	var roster: Array = backend.session.snapshot().pets.duplicate(true)
	check(begin(backend).ok and automation.flow_capture_only and automation.flow_showcase,"full carried roster can start real capture-only workflow")
	check(automation.run_stop_after()==0 and automation.status().flow.capture_only,"stop_after=1 is explicitly overridden and mode is published")
	fill_queue(automation,3,2)
	check(automation._queue_templates().size()>=2,"real queue contains multiple original species")
	var saved_queue: Array = automation.showcase_queue.duplicate(true)
	var saved_last: int = automation.showcase_last_template
	var queue_templates: Array = automation._queue_templates()
	var actual: Array = []
	while not automation.showcase_queue.is_empty():actual.append(int(automation._take_queued().actor.template_id))
	if queue_templates.size()>1:check(actual.slice(0,queue_templates.size())==queue_templates,"real queued hits rotate across species")
	else:check(actual.size()==saved_queue.size(),"the area's single species is consumed in queue order")
	automation.showcase_queue = saved_queue;automation.showcase_last_template = saved_last
	check(automation._queue_templates().all(func(id):return automation._species_queue(id).size()<=3),"queue bound remains per species")
	automation.flow_step()
	check(automation.flow_phase=="capture" and backend.battle_open and backend.session._pending.capture_only and backend.session._pending.capture_slots==1,"real queued roll opens authority-frozen direct-storage battle")
	var captured_actor: Dictionary = automation.flow_matched_actor.duplicate(true)
	var projected: Dictionary = Backend.GameSession.Progression.project_pet(captured_actor,120)
	check(automation.accepts_prediction(captured_actor),"original species condition gate still accepts the real match")
	# Turning the setting off during a battle must not change its destination.
	settings(backend,{"hunt":{"capture_only":false}})
	check(automation.flow_capture_only and backend.session._pending.capture_only,"current run and battle keep frozen mode when settings change")
	var count_before: int = backend.session.snapshot().pet_storage.size()
	finish_capture(backend,false)
	var cut_resume: Dictionary = automation.resume_state()
	var cut_backend = Backend.new();cut_backend.set_process(false);root.add_child(cut_backend)
	check(cut_backend.load_profile(SAVE),"restart loads a capture already settled before flow reconciliation")
	cut_backend.automation.client_attached=false
	cut_backend.automation.load_resume(JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(cut_resume)))));cut_backend.automation.try_resume()
	check(cut_backend.automation.flow_capture_only and cut_backend.automation.flow_phase=="restart" and cut_backend.automation.flow_collected_count==1 and cut_backend.session.snapshot().pet_storage.size()==count_before+1,"capture-phase resume recognizes stored UID once, without training or recapture")
	cut_backend.queue_free();await process_frame
	automation.flow_step()
	check(automation.flow_phase=="restart" and backend.session.snapshot().pet_storage.size()==count_before+1,"real capture settles directly in warehouse and restarts without training")
	if backend.session.snapshot().pet_storage.size()<=count_before:
		backend.queue_free();await process_frame;print("CAPTURE ONLY: %d failures" % failures);quit(1);return
	var caught: Dictionary = backend.session.snapshot().pet_storage.back()
	var identifier := str(caught.pet_id)
	check(backend.session.snapshot().pets==roster,"never temporarily exceeds or changes full carried roster")
	check(caught.level==1 and caught.xp==0 and not caught.get("gm_modified",false) and caught.base_stats==captured_actor.base_stats and caught.growth_seed==captured_actor.growth_seed,"new pet keeps actual newborn level, seed, stats and zero XP")
	check(automation.capture_decision(caught,"手动捕获").tags.has("capture_only"),"capture-only origin remains in log tags after manual takeover")
	check(caught.capture_only and caught.capture_only_untrained,"source and untrained protection are persistent metadata")
	check(automation.flow_collected_count==1 and automation.run_stop_after()==0,"capture-only ignores stop count even after first successful capture")
	backend._record_releases()
	var log: Dictionary = backend.capture_log.entries().back()
	check(log.level==1 and log.lv120.attack==projected.attack and log.capture_decision.tags.has("capture_only") and log.capture_decision.at=="before_inventory_join","log freezes real capture and predicted statistics before storage join")
	var after: Dictionary = backend.session.snapshot()
	check(not backend.session.apply_battle_result(backend.battle.snapshot()) and backend.session.snapshot()==after,"duplicate settlement cannot duplicate pet, reward or UID")
	automation.flow_step();automation.flow_step()
	finish_capture(backend)
	check(automation.flow_phase=="restart" and automation.flow_collected_count==2,"second genuine capture also continues despite stop_after=1")
	var second_id := str(backend.session.snapshot().pet_storage.back().pet_id)
	# Save and resume at the boundary after settlement, before next capture.
	var resume: Dictionary = automation.resume_state()
	check(backend.save(),"direct-stored pet and preference save")
	var reloaded = Backend.new();reloaded.set_process(false);root.add_child(reloaded)
	check(reloaded.load_profile(SAVE),"captured warehouse pet reloads from the real save format")
	reloaded.save_path=SAVE;reloaded.automation.client_attached=false
	reloaded.automation.load_resume(JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(resume)))));reloaded.automation.try_resume()
	check(reloaded.automation.flow_capture_only and reloaded.automation.flow_active() and reloaded.automation.flow_collected_count==2,"resume preserves frozen mode/counts even though next-run preference changed")
	var loaded: Array = reloaded.session.snapshot().pet_storage.filter(func(pet):return str(pet.pet_id)==identifier)
	check(loaded.size()==1 and loaded[0].level==1 and loaded[0].capture_only_untrained,"reload/resume retains one original protected newborn")
	reloaded.automation.stop_cycle("test");reloaded.queue_free();await process_frame
	# Ordinary trained pets continue to be tidied, protected captures do not.
	check(backend.handle({"type":"gm_grant_pet","template":int(caught.template_id),"full_grade":false}).ok,"ordinary comparison pet is authority-issued")
	var ordinary_id := str(backend.session.snapshot().pet_storage.back().pet_id)
	check(backend.session.store_pet(0) and backend.session.retrieve_pet_by_id(ordinary_id) and backend.session.level_pet_to(ordinary_id,120),"ordinary pet genuinely reaches Lv120 through progression")
	var ordinary_index: int = backend.session.snapshot().pets.map(func(pet):return str(pet.pet_id)).find(ordinary_id)
	check(backend.session.store_pet(ordinary_index),"ordinary trained pet goes to storage")
	var rule := {"tiers":0,"per_tier":0,"champions":0,"champion_stats":[],"order":["attack"],"auto":true}
	var released: Array = backend.session.apply_keep_rule(int(caught.template_id),rule)
	check(released.has(ordinary_id) and not released.has(identifier),"automatic tidy still releases ordinary Lv120 while protecting capture-only newborn")
	check(backend.session.release_pets([identifier],"自动整理").released==0,"central automatic release path also protects the source")
	for pet in backend.session._profile.pet_storage:
		if str(pet.pet_id) in [identifier,second_id]:pet.auto_hunt=true
	check(backend.session.prune_hunt_pets(int(caught.template_id),{"sum":1},[identifier,second_id])==0,"legacy reject pruning cannot release protected source even if marked auto_hunt")
	check(backend.session.release_pets([second_id]).released==1,"explicit manual release follows existing rules")
	# Capacity failure at battle preflight is atomic.
	automation.stop_cycle("test")
	settings(backend,{"hunt":{"capture_only":true}})
	capacity(backend.session.snapshot().pet_storage.size())
	var full_before: Dictionary = backend.session.snapshot()
	check(not begin(backend).ok and automation.flow_reason.contains("仓库已满"),"full warehouse pauses before opening another capture")
	check(backend.session.snapshot()==full_before and backend.session._pending.is_empty(),"capacity preflight adds no pet, reward or pending battle")
	capacity(0)
	check(begin(backend).ok,"after warehouse room is available the workflow can restart")
	fill_queue(automation,1);automation.flow_step()
	# Shrink the authority capacity during a real battle: settlement must fail
	# without profile mutation or a fake reward, and can retry after making room.
	capacity(backend.session.snapshot().pet_storage.size())
	var settlement_before: Dictionary = backend.session.snapshot()
	finish_capture(backend)
	check(automation.flow_phase=="paused" and backend.battle_open and not backend.battle_state.get("settled",false) and str(backend.battle_state.get("settlement_error","")).contains("仓库已满"),"capacity changed mid-battle pauses with an explicit unsettled result")
	check(backend.session.snapshot()==settlement_before and backend.battle_state.xp==0 and backend.battle_state.gold==0,"failed storage settlement leaves inventory and rewards atomic")
	capacity(0)
	check(backend.handle({"type":"battle_close"}).ok and backend.session.snapshot().pet_storage.size()==settlement_before.pet_storage.size()+1,"same real captured result retries once after warehouse room is available")
	check(begin(backend).ok,"workflow starts before save rollback check")
	fill_queue(automation,1);automation.flow_step()
	var save_before: Dictionary = backend.session.snapshot()
	var events_before: Array = backend.session.capture_events.duplicate(true)
	backend.save_path = "user://capture-only-missing-dir/blocked.json"
	finish_capture(backend)
	check(automation.flow_phase=="paused" and backend.battle_open and str(backend.battle_state.get("settlement_error","")).contains("保存失败"),"actual filesystem save failure pauses the captured result")
	check(backend.session.snapshot()==save_before and backend.session.capture_events==events_before and not backend.session._pending.is_empty(),"save failure rolls back UID, inventory, rewards and capture events together")
	backend.save_path = SAVE
	check(backend.handle({"type":"battle_close"}).ok and backend.session.snapshot().pet_storage.size()==save_before.pet_storage.size()+1,"save recovery settles original capture exactly once")
	# Manual training removes only the protection, never source attribution.
	var manual: Dictionary = backend.session._profile.pet_storage.filter(func(pet):return str(pet.pet_id)==identifier)[0]
	check(backend.session.retrieve_pet_by_id(identifier) and backend.session.level_pet_to(identifier,2),"player explicitly retrieves and trains the source through real progression")
	check(manual.capture_only and not manual.capture_only_untrained,"manual XP ends untrained protection but retains capture-only source")
	check(backend.session.apply_keep_rule(int(manual.template_id),rule).has(str(manual.pet_id)),"manually trained source becomes eligible for normal tidy")
	check(begin(backend).ok,"capture-only starts again before manual stop test")
	fill_queue(automation,2);automation.flow_step()
	var stopped_before: int = backend.session.snapshot().pet_storage.size()
	automation.request_stop_cycle("已手动停止")
	check(not automation.hunt_running and automation.showcase_queue.is_empty() and not automation.flow_stop_pending.is_empty(),"manual stop during capture clears queue and stops search immediately")
	finish_capture(backend);automation.flow_step()
	check(backend.session.snapshot().pet_storage.size()==stopped_before+1 and not automation.flow_active() and not automation.hunt_running and not automation.running,"manual stop finishes only current capture into warehouse and never trains or restarts")
	settings(backend,{"stat_filters":{str(captured_actor.template_id):{"threshold_mode":"absolute","conditions":{"attack":{"enabled":true,"value":3000},"sum":{"enabled":false}}}}})
	automation.flow_settings_overrides=backend.session.automation_settings()
	automation.flow_stat_filters=Settings.stat_filters(automation.flow_settings_overrides)
	check(not automation.accepts_prediction(captured_actor),"capture-only does not bypass original species attribute thresholds")
	settings(backend,{"hunt":{"capture_only":false,"level_one":true,"auto_capture":true,"train_after_capture":true,"showcase":false}})
	check(not Settings.effective(backend.session.automation_settings()).hunt.capture_only and Settings.effective(backend.session.automation_settings()).hunt.train_after_capture,"old training mode remains available after disabling capture-only")
	ServerSettings.path_override="";backend.queue_free();await process_frame
	print("CAPTURE ONLY: %d failures" % failures);quit(1 if failures else 0)
