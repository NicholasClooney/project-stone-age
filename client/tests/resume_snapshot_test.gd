extends SceneTree
## 重启后自动恢复 without a clean shutdown (backend.gd keep_resume_file): the
## standalone server keeps <save>.resume.json current while a run goes on, so
## a killed server (TERM or kill -9 skip _finalize) resumes from it. Checked
## with a fake clock: the file is written at once when the run moves on (the
## queue, a capture, training), else every 10 s; always whole (temp + rename);
## the save is written first, so the file never names a pet the save lacks;
## it is removed when the run stops. The shutdown request
## (server/shutdown_request.gd) is looked at once a second and used once; the
## graceful stop (backend.shut_down) records the pause, saves and writes it.
const Backend = preload("res://server/backend.gd")
const Automation = preload("res://server/automation.gd")
const ShutdownRequest = preload("res://server/shutdown_request.gd")
const SAVE := "user://resume-snapshot-test.json"
const MAP := 100
const CELL := Vector2i(637,493)
var failures := 0
var clock := 1000

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func base() -> String:
	return SAVE.get_basename()

func resume_file() -> String:
	return base()+".resume.json"

func clean() -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))
	for ext in [".resume.json",".resume.json.tmp",".stop-log.jsonl",".release-log.jsonl",".capture-log.jsonl",".shutdown"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(base()+ext))

func new_backend(from_save: bool):
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	if from_save:check(backend.load_profile(SAVE),"the save loads after the restart")
	backend.save_path = SAVE
	backend.keep_resume_current = true
	backend.resume_clock = func():return clock
	backend.automation.client_attached = false
	backend.automation.timer_clock = func():return clock
	return backend

func prepare(backend, extra: Dictionary = {}) -> void:
	backend.handle({"type":"grant_starter_pets"})
	for command in [{"type":"gm_raise_level","index":-1,"target":120},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":500},{"type":"gm_set_base_stat","index":-1,"stat":"strength","value":300},{"type":"gm_heal"}]:
		backend.handle(command)
	var hunt := {"fast":false,"total":-8,"offsets":[-2,-2,-2,-2],"showcase":true,"queue":10,"auto_capture":true,"train_after_capture":true}
	hunt.merge(extra,true)
	backend.handle({"type":"set_automation_settings","settings":{"hunt":hunt,"training":{"xp":100}}})
	backend.handle({"type":"report_position","map_id":MAP,"cell":[CELL.x,CELL.y]})

## One server tick (the fake clock moves on by `msec`).
func tick(backend, msec: int = 250) -> void:
	clock += msec
	backend._process(float(msec)/1000.0)

func read_resume() -> Dictionary:
	if not FileAccess.file_exists(resume_file()):return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(resume_file()))
	var state = JSON.to_native(parsed) if parsed!=null else null
	return state if state is Dictionary else {}

func saved_pet_ids() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	var ids: Array = []
	if parsed is Dictionary:
		for pet in parsed.get("pets",[]):ids.append(str(pet.get("pet_id","")))
	return ids

func stops() -> Array:
	var result: Array = []
	for line in FileAccess.get_file_as_string(base()+".stop-log.jsonl").split("\n",false):
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:result.append(parsed)
	return result

func last_stop() -> Dictionary:
	var all := stops()
	return all.back() if not all.is_empty() else {}

func queue_rolls(automation) -> Array:
	return automation.showcase_queue.map(func(entry):return int(entry.index))

## A kill -9: no record_shutdown, no save; a new backend starts from whatever
## the files say.
func kill_and_restart(old):
	old.set_process(false)
	old.keep_resume_current = false
	old.queue_free()
	var fresh = new_backend(true)
	fresh.load_resume()
	fresh.automation.try_resume();fresh._record_releases()
	return fresh

func run() -> void:
	clean()
	await cadence()
	clean()
	await capture_and_kill()
	clean()
	await stop_removes()
	clean()
	await shutdown_request()
	clean()
	print("RESUME SNAPSHOT: %d failures" % failures)
	quit(1 if failures else 0)

# ---- cadence and atomicity ------------------------------------------------
const STRICT := {"auto_capture":false,"train_after_capture":false,"total":8,"offsets":[2,2,2,2],"rate":3}

func cadence() -> void:
	var backend = new_backend(false)
	prepare(backend,STRICT)
	backend.encounter_rng.seed = 7
	var automation = backend.automation
	tick(backend)
	check(not FileAccess.file_exists(resume_file()),"nothing is written while nothing runs")
	backend.handle({"type":"auto_start","kind":"hunt","map_id":MAP,"cell":[CELL.x,CELL.y]})
	check(automation.hunt_running,"a hunt runs")
	tick(backend)
	var state := read_resume()
	check(str(state.get("kind",""))=="hunt" and int(state.map_id)==MAP and state.cell==[CELL.x,CELL.y],"the hunt is written down as soon as it starts")
	check(not FileAccess.file_exists(resume_file()+".tmp"),"through a temporary file that is renamed over it")
	check(FileAccess.file_exists(SAVE),"the save is written with it")
	var writes: int = backend.resume_writes
	# Only the roll counter grows while it scans.
	for i in range(9):tick(backend,1000)
	check(automation.hunt_running and automation.hunt_rolls>0,"it scans (%d rolls)" % automation.hunt_rolls)
	check(backend.resume_writes==writes,"rolls alone do not rewrite it within 10 s (%d writes)" % (backend.resume_writes-writes))
	tick(backend,1000)
	var rolls: int = automation.hunt_rolls
	check(backend.resume_writes==writes+1 and int(read_resume().hunt.rolls)==rolls,"after 10 s it is written again with the rolls so far (%d)" % int(read_resume().get("hunt",{}).get("rolls",-1)))
	backend.queue_free()
	await process_frame

	# 后台搜宠: a new hit in the queue is written at once.
	clean()
	backend = new_backend(false)
	prepare(backend)
	automation = backend.automation
	backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	automation.auto_tick = false
	tick(backend)
	check(str(read_resume().get("kind",""))=="flow","a find-pet cycle is written down as soon as it starts")
	var queue := queue_rolls(automation)
	for i in range(20000):
		if queue_rolls(automation)!=queue or not automation.hunt_running:break
		automation.scan_once()
	check(queue_rolls(automation)!=queue,"a hit joins the queue")
	writes = backend.resume_writes
	tick(backend,10)
	check(backend.resume_writes==writes+1,"the queue change is written at once")
	var queued: Array = read_resume().get("flow",{}).get("showcase_queue",[]).map(func(entry):return int(entry.index))
	check(queued==queue_rolls(automation),"with the queue as it is (%s)" % str(queued))
	writes = backend.resume_writes
	tick(backend,10);tick(backend,10)
	check(backend.resume_writes==writes,"an unchanged run is not rewritten every tick")
	backend.queue_free()
	await process_frame

# ---- a capture and training between writes, then kill -9 ------------------
func drive(backend, until: Callable, frames: int = 4000, each: Callable = Callable()) -> bool:
	for i in range(frames):
		if until.call():return true
		tick(backend)
		if each.is_valid():each.call()
	return bool(until.call())

func capture_and_kill() -> void:
	var backend = new_backend(false)
	prepare(backend)
	var automation = backend.automation
	backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	check(drive(backend,func():return automation.flow_phase=="capture" and backend.battle_open),"the cycle opens a capture battle")
	check(str(read_resume().get("flow",{}).get("flow_phase",""))=="capture","the capture is written at once")
	var run_id: String = automation.flow_run_id
	# kill -9 with the capture battle open: fought again from its seed.
	var catching: int = int(automation.showcase_current.index)
	var fresh = kill_and_restart(backend)
	automation = fresh.automation
	check(automation.flow_active() and automation.flow_run_id==run_id,"after kill -9 the same cycle resumes")
	check(last_stop().get("outcome")=="已恢复","停止记录 says it resumed")
	check(automation.flow_phase=="hunt" and not automation.showcase_queue.is_empty() and int(automation.showcase_queue[0].index)==catching,"the capture open at the kill goes back to the front of the queue")
	check(drive(fresh,func():return automation.flow_phase=="capture" and fresh.battle_open) and (int(automation.showcase_current.index)==catching or queue_rolls(automation).has(catching)),"capturing goes on, the hit fought again in its turn")
	# The capture settles and training begins; each step is saved first.
	var consistent := [true]
	var named := func():
		var flow: Dictionary = read_resume().get("flow",{})
		var pet := str(flow.get("flow_pet_id",""))
		if str(flow.get("flow_phase",""))=="train" and not pet.is_empty() and not saved_pet_ids().has(pet):consistent[0] = false
	check(drive(fresh,func():return automation.flow_phase=="train" and automation.running and fresh.battle_open,4000,named),"the pet is caught and its training battles begin")
	check(consistent[0],"the file never names a training pet the save lacks")
	var training: String = automation.flow_pet_id
	check(str(read_resume().get("flow",{}).get("flow_pet_id",""))==training and saved_pet_ids().has(training),"the training pet is written down, and it is in the save")
	var rolls: int = automation.hunt_rolls
	# kill -9 in the middle of a training battle.
	fresh = kill_and_restart(fresh)
	automation = fresh.automation
	check(automation.flow_active() and automation.flow_run_id==run_id and automation.flow_phase=="train" and automation.training_pet_id==training,"after kill -9 the cycle resumes training the same pet (phase %s)" % automation.flow_phase)
	check(automation.hunt_rolls<=rolls,"the hunt goes on from the last written roll (%d <= %d)" % [automation.hunt_rolls,rolls])
	fresh.queue_free()
	await process_frame

# ---- the file goes when the run stops ------------------------------------
func stop_removes() -> void:
	var backend = new_backend(false)
	prepare(backend,STRICT)
	backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	tick(backend)
	check(FileAccess.file_exists(resume_file()),"a running cycle has its file")
	backend.handle({"type":"auto","name":"stop_flow","now":true})
	tick(backend,10)
	check(not FileAccess.file_exists(resume_file()),"a manual stop removes it")
	backend.handle({"type":"auto_start","kind":"hunt","map_id":MAP,"cell":[CELL.x,CELL.y]})
	tick(backend)
	check(str(read_resume().get("kind",""))=="hunt","a hunt on its own is written down")
	backend.handle({"type":"report_position","map_id":MAP,"cell":[CELL.x+2,CELL.y],"map_changed":true})
	tick(backend,10)
	check(not backend.automation.hunt_running and not FileAccess.file_exists(resume_file()),"a position change stops it and removes the file")
	backend.handle({"type":"report_position","map_id":MAP,"cell":[CELL.x,CELL.y]})
	backend.handle({"type":"set_automation_settings","settings":{"hunt":{"resume":false}}})
	backend.handle({"type":"auto_start","kind":"hunt","map_id":MAP,"cell":[CELL.x,CELL.y]})
	tick(backend)
	check(backend.automation.hunt_running and not FileAccess.file_exists(resume_file()),"with 重启后自动恢复 off nothing is written")
	backend.queue_free()
	await process_frame

# ---- the shutdown request and the graceful stop ---------------------------
func shutdown_request() -> void:
	var path := base()+".shutdown"
	var request = ShutdownRequest.new(path)
	request.clock = func():return clock
	check(not request.poll(),"no request, no stop")
	FileAccess.open(path,FileAccess.WRITE).close()
	clock += 500
	check(not request.poll(),"looked at no more than once a second")
	clock += 500
	check(request.poll() and not FileAccess.file_exists(path),"a request is seen within a second and removed")
	clock += 1000
	check(not request.poll(),"and used once")
	FileAccess.open(path,FileAccess.WRITE).close()
	var fresh_request = ShutdownRequest.new(path)
	fresh_request.clear()
	check(not FileAccess.file_exists(path),"a request left from before a start is cleared")

	var backend = new_backend(false)
	prepare(backend)
	backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	tick(backend)
	for i in range(30):backend.automation.scan_once()
	var rolls: int = backend.automation.hunt_rolls
	backend.shut_down()
	check(not backend.keep_resume_current and not backend.is_processing(),"the graceful stop halts the backend")
	check(last_stop().get("outcome")=="暂停" and str(last_stop().get("reason","")).contains("重启后"),"停止记录 says 暂停")
	check(int(read_resume().get("hunt",{}).get("rolls",-1))==rolls,"the final file has every roll (%d)" % rolls)
	var fresh = kill_and_restart(backend)
	check(fresh.automation.flow_active() and fresh.automation.hunt_rolls==rolls,"and the cycle resumes from it")
	fresh.queue_free()
	await process_frame
