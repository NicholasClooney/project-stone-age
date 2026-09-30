extends SceneTree
## LAN profiles, phase 0 (docs/development/lan-profiles.md): one server per
## profile, so every server holds its save's lock (server/save_lock.gd). The
## lock files are real; only which process ids are alive is faked.
const SaveLock = preload("res://server/save_lock.gd")
const ServerSettings = preload("res://server/server_settings.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func run() -> void:
	save_lock()
	fast_threads()
	print("LAN PROFILES: %d failures" % failures)
	quit(1 if failures else 0)

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

## --fast-threads fixes one server's 线程数.
func fast_threads() -> void:
	ServerSettings.threads_override = 4
	check(not ServerSettings.set_fast_hunt_threads(2).is_empty() and ServerSettings.fast_hunt_threads()==4,"--fast-threads fixes this server's 线程数; the setting cannot change it")
	ServerSettings.threads_override = 0
