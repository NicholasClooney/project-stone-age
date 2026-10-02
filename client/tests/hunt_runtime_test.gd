extends SceneTree
## Real original rolls, seeded prediction, queue replay and battle settlement.
const Backend=preload("res://server/backend.gd")
const Settings=preload("res://scripts/automation_settings.gd")
const Filter=preload("res://scripts/pet_stat_filter.gd")
const Fast=preload("res://server/fast_hunt.gd")
const Progression=preload("res://server/progression.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func create_backend():
	var backend=Backend.new();root.add_child(backend);backend.set_process(false);backend.automation.client_attached=false
	backend.save_path="user://hunt-runtime.json"
	backend.handle({"type":"grant_starter_pets"})
	backend.handle({"type":"gm_raise_level","index":-1,"target":120})
	backend.session.gm_set_base_stat(-1,"vitality",1000);backend.session.gm_set_base_stat(-1,"dexterity",500)
	backend.handle({"type":"gm_heal","index":-1})
	backend.handle({"type":"report_position","map_id":100,"cell":[637,493]})
	return backend
func configure(backend,background:bool,show:bool,battle:bool,only:bool=false)->bool:
	return backend.handle({"type":"set_automation_settings","settings":{"hunt":{"background_search":background,"show_battles":show,"battle_training":battle,"capture_only":only,"total":-8,"offsets":[-2,-2,-2,-2],"fast":false,"stop_after":0},"training":{"borrow_troops":false,"select_troops":false,"xp":100}}}).ok
func queue(backend)->bool:
	var deadline:=Time.get_ticks_msec()+30000
	while backend.automation.showcase_queue.is_empty() and backend.automation.hunt_running and Time.get_ticks_msec()<deadline:backend.automation.scan_once()
	return not backend.automation.showcase_queue.is_empty()
func run()->void:
	var old:=Settings.sanitize({"hunt":{"showcase":false}})
	var migrated:Dictionary=Settings.effective(old).hunt
	check(not migrated.background_search and not migrated.show_battles and not migrated.battle_training,"old showcase=false safely preserves search, display and quick-training choices")
	var explicit:Dictionary=Settings.effective({"hunt":{"showcase":false,"background_search":true,"battle_training":true}}).hunt
	check(explicit.background_search and explicit.battle_training and not explicit.show_battles,"new choices independently override the legacy setting")
	for key in ["background_search","show_battles","battle_training"]:
		check(not Settings.apply_patch({}, {"hunt":{key:1}}).ok,"strict boolean authority: "+key)
	for background in [false,true]:
		for shown in [false,true]:
			var backend=create_backend();var auto=backend.automation
			check(configure(backend,background,shown,false),"save independent mode combination")
			check(backend.handle({"type":"auto_start","kind":"find_pet","map_id":100,"cell":[637,493]}).ok,"start real original hunt")
			check(queue(backend),"first qualifying candidate enters queue without waiting for survey")
			check(auto.survey.is_empty() and auto.survey_picks.is_empty(),"no survey phase or timer")
			var entry:Dictionary=auto.showcase_queue[0].duplicate(true)
			var species:=int(entry.actor.template_id)
			check(not auto.species_maxima(species).is_empty(),"queued candidate immediately establishes relative baseline")
			auto.flow_step()
			check(auto.flow_phase=="capture" and auto.running and auto.compact_active==not shown and auto.showcase_show_battle==shown,"queue replay starts genuine capture with independently selected presentation")
			var rolls:int=auto.hunt_rolls
			auto._hunt_process(0.1)
			check(auto.hunt_running and (auto.hunt_rolls>rolls if background else auto.hunt_rolls==rolls),"background off pauses cursor without stopping queue; on continues ordinary search")
			# A real file checkpoint persists all three frozen choices.
			var resume:Dictionary=auto.resume_state()
			check(resume.flow.flow_background_search==background and resume.flow.flow_show_battles==shown and not resume.flow.flow_battle_training,"restart intent contains independent operating choices")
			backend.record_shutdown();check(backend.save(),"real profile and resume file saved at capture checkpoint")
			backend.queue_free();await process_frame
			backend=Backend.new();root.add_child(backend);backend.set_process(false);backend.automation.client_attached=false
			check(backend.load_profile("user://hunt-runtime.json"),"real profile reload succeeds")
			backend.save_path="user://hunt-runtime.json";backend.load_resume();auto=backend.automation;auto.try_resume()
			check(auto.flow_background_search==background and auto.flow_show_battles==shown and not auto.flow_battle_training,"file restart preserves independent frozen choices")
			var restored_queue:Array=auto.showcase_queue.duplicate(true)
			auto.flow_step()
			var replayed:Array=restored_queue.filter(func(candidate):return candidate.actor.growth_seed==auto.flow_matched_actor.get("growth_seed",-1))
			check(auto.flow_phase=="capture" and replayed.size()==1,"restart replays exact saved queued candidate after current priority checks")
			if replayed.size()==1:entry=replayed[0]
			var deadline:=Time.get_ticks_msec()+30000
			while auto.running and Time.get_ticks_msec()<deadline:auto.step()
			auto.flow_step()
			check(auto.flow_phase in ["restart","compare"] and auto.flow_collected_count==1,"real captured pet completes quick cultivation and counts once")
			var found:Dictionary={}
			for pet in backend.session.snapshot().pets+backend.session.snapshot().pet_storage:
				if str(pet.pet_id)==auto.flow_pet_id:found=pet
			check(not found.is_empty() and int(found.level)==120 and found.growth_seed==entry.actor.growth_seed and int(found.attack)==int(entry.prediction.attack),"quick cultivation preserves actual captured UID/seed and exact Lv120 prediction")
			auto.stop_cycle("test done");backend.queue_free();await process_frame
	# Real-battle training may be compact without becoming instant cultivation.
	var backend=create_backend();var auto=backend.automation
	check(configure(backend,false,false,true),"choose real training without visible battle")
	check(backend.handle({"type":"auto_start","kind":"find_pet","map_id":100,"cell":[637,493]}).ok and queue(backend),"real training run has queued candidate")
	auto.flow_step()
	var deadline:=Time.get_ticks_msec()+30000
	while auto.running and Time.get_ticks_msec()<deadline:auto.step()
	auto.flow_step()
	check(auto.flow_phase=="train" and auto.running and auto.settings.compact and auto.training_pet_level==120 and int(auto._flow_pet().level)<120,"hidden real training remains actual battles, not direct level assignment")
	var before:int=auto.hunt_rolls
	auto._hunt_process(0.1)
	check(auto.hunt_rolls==before and auto.hunt_running,"no-background training pauses scans and retains run")
	auto.stop_cycle("test done");backend.queue_free();await process_frame
	print("HUNT RUNTIME: %d failures"%failures);quit(1 if failures else 0)
