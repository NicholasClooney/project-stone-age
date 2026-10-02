extends SceneTree
## LAN profiles, phase 0 (docs/development/lan-profiles.md): one server per
## profile, so every server holds its save's lock (server/save_lock.gd), and
## every 本机极速模式 hunt on the computer shares one thread budget
## (server/fast_hunt_share.gd): equal shares among the hunts scanning now,
## rebalanced by restarting helpers from their committed rolls, and a 摸底
## that counts full-CPU seconds so it lasts 2 minutes × the number of shares.
##
## The functional core runs for real (share math, the registry files, the
## survey clock, the lock files, the automation's restart path). Only the
## shell is faked: the clock, the registry folder, which process ids are
## alive, and the helper (a stand-in script that reports progress and waits).
const Backend = preload("res://server/backend.gd")
const FastHunt = preload("res://server/fast_hunt.gd")
const FastHuntShare = preload("res://server/fast_hunt_share.gd")
const SaveLock = preload("res://server/save_lock.gd")
const ServerSettings = preload("res://server/server_settings.gd")
const PetHuntMenu = preload("res://scripts/pet_hunt_menu.gd")
const PerfMonitor = preload("res://scripts/perf_monitor.gd")
const MAP := 300
const CELL := [509,93]
var failures := 0
var now := 1000.0
var dir := ""

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func clock() -> float:
	return now

func share(name: String) -> FastHuntShare:
	return FastHuntShare.new(dir,clock,name)

func clear(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):return
	for file in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)

func run() -> void:
	dir = "user://lan-profiles-test-%d" % OS.get_process_id()
	clear(dir)
	split()
	registry()
	save_lock()
	await coordinator()
	survey_clock()
	clear(dir)
	print("LAN PROFILES: %d failures" % failures)
	quit(1 if failures else 0)

## Equal shares, the remainder to the hunts that joined first, at least one.
func split() -> void:
	var hunts := [{"id":"c","since":30.0},{"id":"a","since":10.0},{"id":"b","since":20.0}]
	var shares := FastHuntShare.split(14,hunts)
	check(shares=={"a":5,"b":5,"c":4},"14 threads among 3 hunts: 5, 5, 4, the extra ones to the longest running (%s)" % str(shares))
	check(FastHuntShare.split(14,[{"id":"a","since":1.0}])=={"a":14},"a lone hunt gets the whole budget")
	check(FastHuntShare.split(12,hunts).values()==[4,4,4],"an even budget splits evenly")
	check(FastHuntShare.split(2,hunts)=={"a":1,"b":1,"c":1},"more hunts than threads: one each, never zero")
	var sum := 0
	for value in FastHuntShare.split(11,hunts+[{"id":"d","since":40.0}]).values():sum += value
	check(sum==11,"the shares add up to the budget (%d)" % sum)
	check(FastHuntShare.split(6,[{"id":"b","since":5.0},{"id":"a","since":5.0},{"id":"c","since":9.0},{"id":"d","since":9.0}])=={"a":2,"b":2,"c":1,"d":1},"equal start times break ties by name")
	check(FastHuntShare.split(8,[]).is_empty(),"no hunts, no shares")

## The registry folder: fresh files count, stale ones are ignored, then removed.
func registry() -> void:
	var a := share("a")
	var b := share("b")
	var c := share("c")
	check(a.due() and not a.joined(),"a hunt that has not joined is due to beat")
	a.beat(14)
	check(a.joined() and a.threads==14 and a.hunters==1,"alone: 14 threads (%s)" % str(a.summary()))
	check(FileAccess.file_exists(dir.path_join("a.json")),"it keeps a file in the registry folder")
	check(not a.due(),"and is not due again within a second")
	now += 0.5
	b.beat(14)
	check(b.threads==7 and b.hunters==2,"a second hunt sees the first: 7 each (%s)" % str(b.summary()))
	now += 0.6
	check(a.due(),"a second later the first is due")
	a.beat(14)
	check(a.threads==7 and a.hunters==2,"and learns it has 7 now")
	now += 0.2
	c.beat(14)
	a.beat(14);b.beat(14)
	check([a.threads,b.threads,c.threads]==[5,5,4] and c.hunters==3,"three hunts: 5, 5, 4 (%s)" % str([a.threads,b.threads,c.threads]))
	c.leave()
	check(not c.joined() and not FileAccess.file_exists(dir.path_join("c.json")),"a hunt that stops scanning leaves the folder")
	b.beat(14)
	check(b.threads==7 and b.hunters==2,"its threads go back to the others")
	# a crashes: its file stops being refreshed.
	now += FastHuntShare.STALE_SECONDS+0.5
	b.beat(14)
	check(b.threads==14 and b.hunters==1 and FileAccess.file_exists(dir.path_join("a.json")),"a hunt silent for over %d s is ignored" % int(FastHuntShare.STALE_SECONDS))
	now += FastHuntShare.FORGET_SECONDS
	b.beat(14)
	check(not FileAccess.file_exists(dir.path_join("a.json")),"and its file is removed after %d s" % int(FastHuntShare.FORGET_SECONDS))
	FileAccess.open(dir.path_join("junk.json"),FileAccess.WRITE).store_string("{not json")
	b.beat(10)
	check(b.threads==10 and b.budget==10,"a broken file is skipped and a new budget applies at the next beat")
	b.leave()
	DirAccess.remove_absolute(dir.path_join("junk.json"))
	check(DirAccess.get_files_at(dir).is_empty(),"nothing is left behind (%s)" % str(DirAccess.get_files_at(dir)))

## One server per save.
func save_lock() -> void:
	var save := "user://lan-profiles-test-%d.json" % OS.get_process_id()
	var lock := SaveLock.lock_path(save)
	DirAccess.remove_absolute(lock)
	var alive := {101:true,202:true}
	var is_alive := func(pid: int) -> bool:return alive.get(pid,false)
	check(SaveLock.acquire(save,101,is_alive).is_empty() and SaveLock.holder_pid(save)==101,"the first server takes the lock")
	var refused := SaveLock.acquire(save,202,is_alive)
	check(not refused.is_empty() and refused.contains("101") and SaveLock.holder_pid(save)==101,"a second server is refused while the first runs: %s" % refused)
	check(SaveLock.acquire(save,101,is_alive).is_empty(),"the holder may take it again")
	SaveLock.release(save,202)
	check(FileAccess.file_exists(lock),"only the holder releases it")
	alive.erase(101)
	check(SaveLock.acquire(save,202,is_alive).is_empty() and SaveLock.holder_pid(save)==202,"a lock whose process is gone is stale and taken over")
	SaveLock.release(save,202)
	check(not FileAccess.file_exists(lock),"the holder's release removes it")
	FileAccess.open(lock,FileAccess.WRITE).store_string("garbage")
	check(SaveLock.acquire(save,303,is_alive).is_empty(),"an unreadable lock does not block")
	SaveLock.release(save,303)
	check(SaveLock.running_server(OS.get_process_id()),"this Godot process counts as a running server")
	check(not SaveLock.running_server(0) and not SaveLock.running_server(-5),"no process id is no server")

## A stand-in for the helper that reports progress and waits to be stopped.
func fake_helper() -> String:
	var path := ProjectSettings.globalize_path("user://lan-profiles-helper-%d.sh" % OS.get_process_id())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string("#!/bin/sh\necho 'progress 0 0 0 -9 0 -1 -1' > \"$2\"\nsleep 30\n")
	file.close()
	OS.execute("chmod",["+x",path])
	return path

func helper_threads(automation) -> int:
	var path: String = automation.fast_hunt.input_path
	if path.is_empty() or not FileAccess.file_exists(path):return -1
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("threads "):return int(line.split(" ")[1])
	return -1

## A backend's hunt joins the share, restarts its helper when the number of
## hunts changes (at most every 2 s, from the committed rolls) and leaves
## when it stops.
func coordinator() -> void:
	FastHunt.threads = 0
	FastHunt.helper_override = fake_helper()
	ServerSettings.threads_override = 4
	check(not ServerSettings.set_fast_hunt_threads(2).is_empty() and ServerSettings.fast_hunt_threads()==4,"--fast-threads fixes this server's budget; 线程数 cannot change it")
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	var automation = backend.automation
	automation.client_attached = false
	automation.fast_share = FastHuntShare.new(dir,clock,"me")
	var reply: Dictionary = backend.handle({"type":"auto_start","kind":"hunt","map_id":MAP,"cell":CELL,"filter":{"template":92,"level_one":true,"total":8,"offsets":[2,2,2,2],"auto_capture":false,"limit":0,"fast":true}})
	check(reply.ok,"a fast hunt starts %s" % str(reply))
	automation._hunt_process(0.016)
	check(automation.fast_hunt.running() and helper_threads(automation)==4,"alone it gets the whole budget: 4 threads (%d)" % helper_threads(automation))
	var hunt: Dictionary = automation.status().hunt
	check(int(hunt.threads_used)==4 and int(hunt.budget)==4 and int(hunt.hunters)==1 and PetHuntMenu.share_text(hunt).is_empty(),"the status shows 4 of 4, not shared")
	check(FileAccess.file_exists(dir.path_join("me.json")),"the hunt is registered")
	var first_pid: int = automation.fast_hunt.pid
	# Another profile's server starts hunting.
	var other := share("other")
	now += 0.3
	other.beat(4)
	check(other.threads==2,"the other hunt takes half (%d)" % other.threads)
	now += 1.0
	automation._hunt_process(0.016)
	check(automation.fast_share.threads==2 and automation.fast_hunt.pid==first_pid,"this hunt learns its share is 2 but waits before restarting")
	now += 1.0
	automation._hunt_process(0.016)
	check(automation.fast_hunt.pid!=first_pid or not automation.fast_hunt.running(),"2 s after its start the helper is stopped to restart")
	automation._hunt_process(0.016)
	check(automation.fast_hunt.running() and helper_threads(automation)==2 and automation.hunt_running,"and starts again with 2 threads (%d)" % helper_threads(automation))
	hunt = automation.status().hunt
	check(PetHuntMenu.share_text(hunt)==" · 线程 2/4（2 人共享）","the hunt window reads「本机极速模式%s」" % PetHuntMenu.share_text(hunt))
	var lines := PerfMonitor.lines({"fast_hunt":{"threads":2,"budget":4,"hunters":2}})
	check(lines[lines.size()-1]=="极速筛选 线程 2/4（2 人共享）","the perf panel reads「%s」" % lines[lines.size()-1])
	# Three hunters on a budget of 4: the longest running gets the extra one.
	var third := share("third")
	now += 0.2
	third.beat(4)
	now += 2.5
	automation._hunt_process(0.016)
	automation._hunt_process(0.016)
	check(helper_threads(automation)==2 and third.threads==1,"three hunts on 4 threads: this one (first) 2, the newest 1")
	other.leave();third.leave()
	now += 2.5
	automation._hunt_process(0.016)
	automation._hunt_process(0.016)
	check(helper_threads(automation)==4 and int(automation.status().hunt.hunters)==1,"when the others stop it goes back to all 4")
	backend.handle({"type":"auto","name":"stop_hunt","reason":"test"})
	check(not automation.hunt_running and not automation.fast_hunt.running() and not automation.fast_share.joined() and not FileAccess.file_exists(dir.path_join("me.json")),"stopping the hunt stops the helper and leaves the registry")
	automation.fast_hunt.stop()
	backend.queue_free()
	await process_frame
	DirAccess.remove_absolute(FastHunt.helper_override)
	FastHunt.helper_override = ""
	ServerSettings.threads_override = 0

## 摸底 counts full-CPU seconds: 1/N per wall second while N hunts share.
func survey_clock() -> void:
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	var automation = backend.automation
	var msec := [0]
	automation.survey_clock = func():return msec[0]
	automation.fast_share = FastHuntShare.new(dir,clock,"me")
	check(automation.fast_hunters()==1,"not scanning: no share")
	var other := share("other")
	now += 10.0
	other.beat(8)
	automation.fast_share.beat(8)
	check(automation.fast_hunters()==2,"two hunts share the computer")
	automation.survey = {"templates":[92],"started":0,"clock":0,"credit":0.0,"candidates":{},"runs":[]}
	automation._survey_process()
	check(automation.survey.is_empty() and not automation.surveying(92),"legacy survey state clears without delaying either profile")
	other.leave();now+=1.0;automation.fast_share.beat(8)
	check(automation.fast_hunters()==1,"remaining profile keeps the full CPU allocation")
	automation._survey_process()
	check(automation.survey.is_empty(),"a missing species never starts a new timed survey")
	automation.fast_share.leave();automation.fast_share=null
	backend.queue_free()
