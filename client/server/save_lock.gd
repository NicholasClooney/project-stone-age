extends RefCounted
## One server per save: server_main.gd takes `<save>.lock` (JSON with its
## process id) before it loads the save and removes it on exit, and refuses to
## start while another running server holds it. A lock whose process is gone
## (a crash, a reboot) is stale and taken over. See
## docs/development/lan-profiles.md.

static func lock_path(save_path: String) -> String:
	return save_path+".lock"

## Takes the lock for `pid`. "" on success, else why not (in Chinese, for the
## log). `alive` answers whether a process id is a running server; tests fake
## it.
static func acquire(save_path: String, pid: int = OS.get_process_id(), alive: Callable = running_server) -> String:
	var path := lock_path(save_path)
	var holder := holder_pid(save_path)
	if holder > 0 and holder!=pid and alive.call(holder):
		return "存档 %s 正被另一个服务器（进程 %d）使用，拒绝同时打开。先停止那个服务器；如果它已经不在运行，删除 %s。" % [ProjectSettings.globalize_path(save_path),holder,ProjectSettings.globalize_path(path)]
	var folder := path.get_base_dir()
	if not folder.is_empty():DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:return "无法写入存档锁 %s。" % ProjectSettings.globalize_path(path)
	file.store_string(JSON.stringify({"pid":pid,"since":int(Time.get_unix_time_from_system()),"save":ProjectSettings.globalize_path(save_path)}))
	file.close()
	return ""

## Removes the lock if `pid` holds it.
static func release(save_path: String, pid: int = OS.get_process_id()) -> void:
	if holder_pid(save_path)==pid:DirAccess.remove_absolute(lock_path(save_path))

## The process id written in the lock, 0 when there is none or it is unreadable.
static func holder_pid(save_path: String) -> int:
	var path := lock_path(save_path)
	if not FileAccess.file_exists(path):return 0
	var json := JSON.new()
	var data = json.data if json.parse(FileAccess.get_file_as_string(path))==OK else null
	return int(data.get("pid",0)) if data is Dictionary else 0

## Whether `pid` is a running Godot process (a server or the game). Godot's
## own OS.is_process_running only knows its child processes, so this asks ps;
## a reused pid of another program does not count. Windows asks tasklist.
static func running_server(pid: int) -> bool:
	var output: Array = []
	if pid > 0 and OS.get_name()=="Windows":
		if OS.execute("tasklist",["/FI","PID eq %d" % pid,"/FO","CSV","/NH"],output)!=0:return false
		return not output.is_empty() and str(output[0]).to_lower().contains("godot")
	if pid <= 0 or not OS.get_name() in ["macOS","Linux","FreeBSD"]:return false
	if OS.execute("ps",["-p",str(pid),"-o","comm="],output)!=0:return false
	return not output.is_empty() and str(output[0]).to_lower().contains("godot")
