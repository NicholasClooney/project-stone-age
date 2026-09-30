extends SceneTree
## 重启后自动恢复 (hunt.resume, server/automation.gd record_shutdown and
## try_resume): a server restart is simulated by recording the shutdown and
## saving, then building a fresh backend from the save and its resume file.
## The find-pet cycle (with and without 后台搜宠) goes on with its run,
## counters and queue; the hunt continues the same run from the same roll; a
## capture cut short is fought again from the pet's own roll (or its training
## goes on when it was caught already); a training battle cut short is fought
## again; 自动练级 goes on. Nothing resumes with the setting off or when the
## character stands elsewhere. A remote device connecting after the restart
## sees the resumed cycle. Only the clock-free real core runs here: battles
## are real, no client presents them, and fast mode is off.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const Automation = preload("res://server/automation.gd")
const AutomationSettings = preload("res://scripts/automation_settings.gd")
const StatFilter = preload("res://scripts/pet_stat_filter.gd")
const SAVE := "user://hunt-resume-test.json"
const MAP := 100
const CELL := Vector2i(637,493)
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
var clock := 1000

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func base() -> String:
	return SAVE.get_basename()

func clean() -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))
	for ext in [".resume.json",".stop-log.jsonl",".release-log.jsonl",".capture-log.jsonl"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(base()+ext))

func new_backend(from_save: bool):
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	if from_save:check(backend.load_profile(SAVE),"the save loads after the restart")
	backend.save_path = SAVE
	backend.automation.client_attached = false
	backend.automation.timer_clock = func():return clock
	return backend

## The server stops (record_shutdown then save, as server_main does) and a new
## one starts from the save: load_profile, then load_resume.
func restart(old):
	old.record_shutdown()
	check(old.save(),"the save goes through at shutdown")
	old.queue_free()
	var fresh = new_backend(true)
	fresh.load_resume()
	check(not FileAccess.file_exists(base()+".resume.json"),"the resume file is used once")
	return fresh

func prepare(backend, extra: Dictionary = {}) -> void:
	backend.handle({"type":"grant_starter_pets"})
	for command in [{"type":"gm_raise_level","index":-1,"target":120},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":500},{"type":"gm_set_base_stat","index":-1,"stat":"strength","value":300},{"type":"gm_heal"}]:
		backend.handle(command)
	var hunt := {"fast":false,"total":-8,"offsets":[-2,-2,-2,-2],"showcase":true,"queue":10,"auto_capture":true,"train_after_capture":true}
	hunt.merge(extra,true)
	backend.handle({"type":"set_automation_settings","settings":{"hunt":hunt,"training":{"xp":100}}})
	backend.handle({"type":"report_position","map_id":MAP,"cell":[CELL.x,CELL.y]})

func stops() -> Array:
	var result: Array = []
	for line in FileAccess.get_file_as_string(base()+".stop-log.jsonl").split("\n",false):
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:result.append(parsed)
	return result

func last_stop() -> Dictionary:
	var all := stops()
	return all.back() if not all.is_empty() else {}

func drive(backend, until: Callable, frames: int = 3000) -> bool:
	for i in range(frames):
		if until.call():return true
		backend._process(0.25)
		clock += 250
	return bool(until.call())

func scan_until(automation, until: Callable, rolls: int = 20000) -> bool:
	for i in range(rolls):
		if until.call() or not automation.hunt_running:break
		automation.scan_once()
	return bool(until.call())

func queue_rolls(automation) -> Array:
	return automation.showcase_queue.map(func(entry):return int(entry.index))

func run() -> void:
	clean()
	await showcase_cycle()
	clean()
	await full_speed_cycle()
	clean()
	await hunt_and_training()
	clean()
	await setting_and_position()
	clean()
	await remote_device()
	clean()
	print("HUNT RESUME: %d failures" % failures)
	quit(1 if failures else 0)

# ---- 后台搜宠 cycle: queue, capture cut short, caught before, training ----
func showcase_cycle() -> void:
	var backend = new_backend(false)
	prepare(backend)
	check(bool(AutomationSettings.effective(backend.session.automation_settings()).hunt.resume),"重启后自动恢复 is on by default")
	var started: Dictionary = backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	var automation = backend.automation
	check(bool(started.ok) and automation.flow_active() and automation.flow_showcase,"a find-pet cycle with 后台搜宠 runs")
	check(scan_until(automation,func():return automation.showcase_queue.size()>=3),"hits wait in the queue")
	var run_id: String = automation.flow_run_id
	var seed_value: int = automation.hunt_run_seed
	var rolls: int = automation.hunt_rolls
	var queued := queue_rolls(automation)
	var next_troop := JSON.stringify(automation.roll_at(rolls))
	automation.flow_skipped_count = 2
	# 绝对：≥ 数值 for the blue dragon, low enough to let every queued hit stay.
	backend.handle({"type":"set_automation_settings","settings":{"stat_filters":{"92":{"threshold_mode":"absolute","conditions":{"sum":{"value":0},"attack":{"value":0}}}}}})
	check(StatFilter.absolute(automation.raw_filter_for(92)) and queue_rolls(automation)==queued,"the running cycle takes 绝对 at once; no queued hit is let go")
	clock += 90000
	var elapsed: float = automation.elapsed_seconds()
	backend.record_shutdown()
	check(FileAccess.file_exists(base()+".resume.json"),"the running cycle is written next to the save at shutdown")
	var paused := last_stop()
	check(paused.get("outcome")=="暂停" and str(paused.get("reason","")).contains("重启后"),"停止记录 says it will resume after the restart")
	backend.save();backend.queue_free()
	var fresh = new_backend(true)
	fresh.load_resume()
	automation = fresh.automation
	check(automation.position_map==MAP and automation.position_cell==CELL,"until a device reports, the character is where the cycle ran")
	automation.try_resume();automation.backend._record_releases()
	check(automation.flow_active() and automation.flow_phase=="hunt" and automation.hunt_running,"the cycle goes on after the restart")
	check(automation.flow_run_id==run_id and automation.flow_showcase and automation.flow_skipped_count==2,"with the same run and counters")
	check(automation.hunt_run_seed==seed_value and automation.hunt_rolls==rolls and JSON.stringify(automation.roll_at(rolls))==next_troop,"the hunt continues the same run from the same roll")
	check(queue_rolls(automation)==queued,"the queue is kept, best first (%s)" % str(queue_rolls(automation)))
	check(str(automation.flow_stat_filters.get(92,{}).get("threshold_mode",""))=="absolute" and int(automation.filter_for(92).conditions.sum.value)==0 and automation.survey.is_empty(),"the cycle's 属性条件 keep 绝对 over the restart")
	check(absf(automation.elapsed_seconds()-elapsed)<1.0,"the cycle's time goes on from where it was")
	var resumed := last_stop()
	check(resumed.get("outcome")=="已恢复" and str(resumed.get("reason","")).begins_with(Automation.RESUMED) and str(resumed.get("run",""))==run_id,"停止记录 says 服务器重启后已恢复")
	check(str(automation.showcase_log.back().get("text","")).begins_with(Automation.RESUMED),"and so does the info block")

	# A capture battle cut short: given up at shutdown (the save goes through),
	# fought again from the queued hit's own roll after the restart.
	check(drive(fresh,func():return automation.flow_phase=="capture" and fresh.battle_open and bool(fresh.battle.snapshot().get("active",false))),"the best queued hit's capture battle opens")
	var catching: int = int(automation.showcase_current.index)
	var slot: int = int(automation.showcase_current.slot)
	var growth: int = int(fresh.battle.snapshot().enemies[slot].growth_seed)
	var pets_before: int = fresh.session.snapshot().pets.size()
	var backend2 = fresh
	fresh = restart(backend2)
	automation = fresh.automation
	check(fresh.session.snapshot().pets.size()==pets_before and not fresh.battle_open,"the capture cut short caught nothing")
	automation.try_resume();automation.backend._record_releases()
	check(automation.flow_phase=="hunt" and int(automation.showcase_queue[0].index)==catching,"its hit goes back to the front of the queue")
	check(str(last_stop().get("reason","")).contains("放回排队"),"停止记录 says so")
	check(drive(fresh,func():return automation.flow_phase=="capture" and fresh.battle_open),"its capture battle opens again")
	# The hunt scans on meanwhile; a better hit found by then goes first and
	# this one waits its turn in the queue.
	if int(automation.showcase_current.index)==catching:
		check(int(fresh.battle.snapshot().enemies[slot].growth_seed)==growth,"replayed from its seed: the same pet")
	else:check(queue_rolls(automation).has(catching),"a better hit went first; this one still waits in the queue")

	# Caught, but the server stopped before the cycle moved on to training.
	for i in range(2000):
		if not automation.running:break
		automation.tick_battle(1.0)
	check(automation.flow_phase=="capture" and fresh.session.snapshot().pets.size()==pets_before+1,"the pet is caught just before the restart")
	fresh = restart(fresh)
	automation = fresh.automation
	automation.try_resume();automation.backend._record_releases()
	check(automation.flow_phase=="train" and automation.running and automation.training_pet_id==automation.flow_pet_id and not automation.flow_pet_id.is_empty(),"after the restart the caught pet is trained, not caught again")
	check(str(last_stop().get("reason","")).contains("已在重启前抓到"),"停止记录 says it was caught before the restart")
	var training: String = automation.flow_pet_id

	# A training battle cut short: fought again, the pet keeps its levels.
	check(drive(fresh,func():return fresh.battle_open and bool(fresh.battle.snapshot().get("active",false))),"a training battle is open")
	fresh = restart(fresh)
	automation = fresh.automation
	var level := -1
	for pet in fresh.session.snapshot().pets:
		if str(pet.pet_id)==training:level = int(pet.level)
	automation.try_resume();automation.backend._record_releases()
	check(automation.flow_phase=="train" and automation.running and automation.training_pet_id==training,"the training goes on after the restart")
	check(str(last_stop().get("reason","")).contains("从 %d 级接着练" % level),"from the level the pet has (%d)" % level)
	var pet_level := func() -> int:
		for pet in fresh.session.snapshot().pets:
			if str(pet.pet_id)==training:return int(pet.level)
		return -1
	check(drive(fresh,func():return pet_level.call()>level),"the pet gains levels again")
	fresh.queue_free()
	await process_frame

# ---- the full-speed cycle (后台搜宠 off): a capture cut short ---------------
func full_speed_cycle() -> void:
	var backend = new_backend(false)
	prepare(backend,{"showcase":false})
	backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	var automation = backend.automation
	check(automation.flow_active() and not automation.flow_showcase,"a full-speed find-pet cycle runs")
	scan_until(automation,func():return automation.flow_phase=="capture")
	check(automation.flow_phase=="capture" and backend.battle_open and not automation.flow_matched_roll.is_empty(),"a hit opens its capture battle and keeps its roll")
	var slot: int = automation.flow_matched_index
	var growth: int = int(backend.battle.snapshot().enemies[slot].growth_seed)
	var stored: int = automation.flow_stored_count
	var fresh = restart(backend)
	automation = fresh.automation
	automation.try_resume();automation.backend._record_releases()
	check(automation.flow_phase=="capture" and fresh.battle_open and automation.running,"after the restart the same capture battle opens again")
	check(automation.flow_matched_index==slot and int(fresh.battle.snapshot().enemies[slot].growth_seed)==growth,"rolled again from its seed: the same pet")
	check(str(last_stop().get("reason","")).contains("按原种子重新开战"),"停止记录 says so")
	check(drive(fresh,func():return automation.flow_stored_count>stored or automation.flow_phase in ["compare","restart","hunt"] and automation.flow_pet_id.is_empty() or not automation.flow_active()),"the cycle carries on with the pet")
	fresh.queue_free()
	await process_frame

# ---- a hunt on its own, and 自动练级 -----------------------------------------
func hunt_and_training() -> void:
	var backend = new_backend(false)
	prepare(backend,{"auto_capture":false,"train_after_capture":false,"total":8,"offsets":[2,2,2,2]})
	backend.encounter_rng.seed = 7
	backend.handle({"type":"auto_start","kind":"hunt","map_id":MAP,"cell":[CELL.x,CELL.y]})
	var automation = backend.automation
	for i in range(60):automation.scan_once()
	check(automation.hunt_running and automation.hunt_rolls==60,"a hunt on its own runs")
	var seed_value: int = automation.hunt_run_seed
	var fresh = restart(backend)
	automation = fresh.automation
	automation.try_resume();automation.backend._record_releases()
	check(automation.hunt_running and automation.hunt_run_seed==seed_value and automation.hunt_rolls==60 and not automation.flow_active(),"after the restart it goes on from roll 61 of the same run")
	check(last_stop().get("outcome")=="已恢复" and str(last_stop().get("scope"))=="hunt","停止记录 says it resumed")
	automation.stop_hunt("x")

	# 自动练级 (attack) with its counters.
	var reply: Dictionary = fresh.handle({"type":"auto_start","kind":"battle","map_id":MAP,"cell":[CELL.x,CELL.y],"settings":{"compact":false,"limit":50,"hp":1,"xp":100,"speed":8.0,"preset":"attack","level":0,"level_explicit":true}})
	check(reply.ok and automation.running,"自动练级 runs")
	check(drive(fresh,func():return automation.battles>=2 and fresh.battle_open and bool(fresh.battle.snapshot().get("active",false))),"two battles are done and a third is open")
	var battles: int = automation.battles
	var earned: int = automation.earned_xp
	fresh = restart(fresh)
	automation = fresh.automation
	automation.try_resume();automation.backend._record_releases()
	check(automation.running and automation.battles==battles and automation.earned_xp==earned and int(automation.settings.limit)==50 and str(automation.settings.preset)=="attack","自动练级 goes on after the restart with its counters and settings")
	check(automation.origin_map==MAP and automation.origin_cell==CELL,"at the same place")
	check(drive(fresh,func():return automation.battles>battles),"and fights on")
	fresh.queue_free()
	await process_frame

# ---- the setting off, and a character standing elsewhere --------------------
func setting_and_position() -> void:
	var backend = new_backend(false)
	prepare(backend,{"resume":false})
	backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	check(backend.automation.flow_active(),"a cycle runs with 重启后自动恢复 off")
	backend.record_shutdown()
	check(not FileAccess.file_exists(base()+".resume.json"),"nothing is written with the setting off")
	check(last_stop().get("outcome")=="停止" and str(last_stop().get("reason","")).contains("需要再次开始"),"停止记录 says it must be started again")
	backend.save();backend.queue_free()
	var fresh = new_backend(true)
	fresh.load_resume()
	fresh.automation.try_resume();fresh._record_releases()
	check(not fresh.automation.flow_active() and not fresh.automation.hunt_running,"nothing resumes")
	fresh.handle({"type":"set_automation_settings","settings":{"hunt":{"resume":true}}})

	fresh.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	fresh = restart(fresh)
	# A device reports another cell before the cycle could resume.
	fresh.handle({"type":"report_position","map_id":MAP,"cell":[CELL.x+2,CELL.y]})
	fresh.automation.try_resume();fresh._record_releases()
	check(not fresh.automation.flow_active() and fresh.automation.pending_resume.is_empty(),"standing elsewhere, the cycle does not resume")
	check(str(last_stop().get("reason","")).contains("不在原来的位置"),"停止记录 says why")
	fresh.queue_free()
	await process_frame

# ---- a remote device after the restart ---------------------------------------
func until(condition: Callable, seconds: float = Wait.DEADLINE) -> bool:
	return await Wait.until(self,condition,seconds)

func remote_device() -> void:
	var backend = new_backend(false)
	prepare(backend,{"rate":1})
	backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	var fresh = restart(backend)
	fresh.automation.timer_clock = Time.get_ticks_msec
	fresh.set_process(true)
	var port := 0 # any free port; the server reports the one it got
	var server = WsServer.new(fresh,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"the restarted backend listens")
	port = server.port
	check(await until(func():return fresh.automation.flow_active() and fresh.automation.hunt_running),"the cycle resumes on the server's own tick")
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = "ws://127.0.0.1:%d" % port
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	root.add_child(game)
	check(await until(func():return not game.data.is_empty() and game.link.online),"a device connects after the restart")
	check(int(game.data.map_id)==MAP and game.cell==CELL,"it stands where the cycle runs")
	check(await until(func():return game.pet_workflow.active() and (game.pet_hunt_menu.visible or game.pet_hunt_menu.minimized)),"it shows the resumed cycle in the hunt window")
	check(await until(func():return game.pet_hunt_menu.running and not game.pet_hunt_menu.stop_button.disabled and game.pet_hunt_menu.start_button.disabled),"with the window's running state")
	check(game.pet_hunt_menu.resume_after_restart.button_pressed and game.pet_hunt_menu.resume_after_restart.name=="ResumeAfterRestart","抓宠设置 shows 重启后自动恢复 on")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.link.close()
	game.music.stop();game.effect.stop();game.queue_free()
	fresh.automation.stop_request("x")
	server.queue_free()
	fresh.queue_free()
	await process_frame
