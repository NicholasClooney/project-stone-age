extends Node
## One server, many profiles (LAN phase 1, docs/development/lan-profiles.md):
## every character in the accounts file (server/accounts.gd) gets its own
## Backend, with its own save, save lock, automation, battle, pet logs,
## restart-resume file and fast hunt share, all in this one process. A
## connection logs into one profile (name + PIN, or a remembered device
## token) and from then on its commands go to that profile's backend and it
## receives only that profile's events. Several devices may log into the
## same profile and drive it together, as with a lone server.
##
## Backends open on their first login and then stay open, so automation goes
## on with nobody connected. A profile whose run was written down at the last
## shutdown (<save>.resume.json) opens at start, so every profile's hunt,
## find-pet cycle or 自动练级 resumes after a restart without a login.
##
## The transport (server/ws_server.gd) calls handle() with an opaque
## connection id and delivers `outgoing`; tests call them directly.
signal outgoing(connection: int, message: Dictionary)

const Backend = preload("res://server/backend.gd")
const Accounts = preload("res://server/accounts.gd")
const SaveLock = preload("res://server/save_lock.gd")
const SaveBackups = preload("res://server/save_backups.gd")
const FastHuntShare = preload("res://server/fast_hunt_share.gd")
const Presence = preload("res://server/presence.gd")

var accounts
## id -> Backend, for every profile opened since the server started.
var backends: Dictionary = {}
## Registry folder for 本机极速模式 shares (server/fast_hunt_share.gd); every
## profile is its own participant. "" gives backends no share (tests).
var share_dir := FastHuntShare.DEFAULT_DIR
## False keeps backends from ticking on their own (tests drive them).
var tick := true
## Dated copies of each save when it opens (server/save_backups.gd).
var backups := true
## Why start() failed.
var last_error := ""
## connection -> {id, token}
var _connections: Dictionary = {}
## LAN phase 2: who stands where, and 一般频道 chat (server/presence.gd).
var presence = Presence.new()
## Milliseconds for presence ticks and the chat rate limit (tests fake it).
var presence_clock: Callable = Time.get_ticks_msec
var _stopped := false

func _init(accounts_path: String = "", fake_clock: Callable = Callable()) -> void:
	accounts = Accounts.new(accounts_path,fake_clock)

## Reads the accounts and opens every profile with a run to resume. False
## (last_error says why) when the accounts file cannot be used.
func start() -> bool:
	if not accounts.load_file():
		last_error = accounts.last_error
		return false
	for entry in accounts.profiles():
		if FileAccess.file_exists(resume_file(accounts.save_path(entry))):
			var error := open_profile(str(entry.id))
			if error.is_empty():print("[%s] 重启后自动恢复：已打开存档。" % entry.name)
			else:printerr("[%s] %s" % [entry.name,error])
	return true

## The backend's restart-resume file for a save (backend.gd _resume_file).
static func resume_file(save_path: String) -> String:
	return save_path.get_basename()+".resume.json"

## Opens a profile's backend if it is not open yet; "" or why it cannot.
func open_profile(id: String) -> String:
	if backends.has(id):return ""
	var entry: Dictionary = accounts.by_id(id)
	if entry.is_empty():return "没有这个角色。"
	var path: String = accounts.save_path(entry)
	var refused := SaveLock.acquire(path)
	if not refused.is_empty():return refused
	if backups:SaveBackups.backup(path)
	var backend = Backend.new()
	backend.name = "Profile_"+id
	backend.admin = bool(entry.admin)
	backend.account_name = str(entry.name)
	add_child(backend)
	if not tick:backend.set_process(false)
	backend.automation.client_attached = false
	if not share_dir.is_empty():backend.automation.fast_share = FastHuntShare.new(share_dir)
	if FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"):
		if not backend.load_profile(path):
			backend.free()
			SaveLock.release(path)
			return "存档 %s 无法读取；为免覆盖，暂不能登录这个角色。" % ProjectSettings.globalize_path(path)
	backend.save_path = path
	backend.keep_resume_current = true
	backend.save()
	backend.load_resume()
	backend.event.connect(_on_backend_event.bind(id))
	backends[id] = backend
	return ""

## The profile a connection is logged into, "" when none.
func profile_of(connection: int) -> String:
	return str(_connections.get(connection,{}).get("id",""))

func backend_of(connection: int):
	return backends.get(profile_of(connection))

## Connections logged into `id`.
func connections_of(id: String) -> Array:
	var result: Array = []
	for connection in _connections:
		if str(_connections[connection].id)==id:result.append(connection)
	return result

## One command from a connection. Before a login only hello, login,
## create_profile and ping are accepted.
func handle(connection: int, command: Dictionary) -> Dictionary:
	var type := str(command.get("type",""))
	var reply: Dictionary
	match type:
		"ping":reply = {"ok":true}
		"hello":reply = _hello(connection,command)
		"login":reply = _login(connection,command)
		"create_profile":reply = _create(connection,command)
		"logout":reply = _logout(connection)
		"profiles":reply = {"ok":true,"profiles":_listing(),"allow_create":accounts.allow_create()}
		"say":reply = _say(connection,command)
		_:
			var backend = backend_of(connection)
			if backend==null:reply = {"ok":false,"reason":"请先登录。","login_required":true}
			else:return backend.handle(command)
	reply.seq = command.get("seq",0)
	reply.type = "ack" if reply.get("ok",false) else "rejected"
	reply.v = Backend.PROTOCOL
	return reply

## A connection closed.
func disconnect_connection(connection: int) -> void:
	var id := profile_of(connection)
	_connections.erase(connection)
	presence.forget(connection)
	_attach(id)

func _hello(connection: int, command: Dictionary) -> Dictionary:
	if int(command.get("protocol",Backend.PROTOCOL))!=Backend.PROTOCOL:return {"ok":false,"reason":"protocol %d required" % Backend.PROTOCOL}
	accounts.reload_if_changed()
	var login = command.get("login",{})
	var reason := ""
	if login is Dictionary and not str(login.get("token","")).is_empty():
		var checked: Dictionary = accounts.verify_token(str(login.get("name","")),str(login.token))
		if checked.ok:return _enter(connection,checked.entry,str(login.token))
		reason = str(checked.reason)
	var reply := {"ok":true,"login_required":true,"profiles":_listing(),"allow_create":accounts.allow_create()}
	if not reason.is_empty():reply.reason = reason
	return reply

func _login(connection: int, command: Dictionary) -> Dictionary:
	accounts.reload_if_changed()
	var checked: Dictionary = accounts.verify_pin(str(command.get("name","")),str(command.get("pin","")))
	if not checked.ok:return checked
	return _enter(connection,checked.entry,accounts.issue_token(str(checked.entry.id)))

func _create(connection: int, command: Dictionary) -> Dictionary:
	accounts.reload_if_changed()
	var created: Dictionary = accounts.create(str(command.get("name","")),str(command.get("pin","")))
	if not created.ok:return created
	print("[%s] 新角色已创建%s。" % [created.entry.name,"（管理员）" if created.entry.admin else ""])
	var reply := _enter(connection,created.entry,accounts.issue_token(str(created.entry.id)))
	reply.created = true
	return reply

## Forgets this device's token and leaves the profile; the connection stays
## open at the profile picker.
func _logout(connection: int) -> Dictionary:
	var id := profile_of(connection)
	if id.is_empty():return {"ok":true}
	accounts.revoke_token(id,str(_connections[connection].get("token","")))
	disconnect_connection(connection)
	return {"ok":true,"profiles":_listing(),"allow_create":accounts.allow_create()}

func _enter(connection: int, entry: Dictionary, token: String) -> Dictionary:
	var id := str(entry.id)
	var error := open_profile(id)
	if not error.is_empty():return {"ok":false,"reason":error}
	var backend = backends[id]
	# The admin flag may have changed in the file since the backend opened.
	if backend.admin!=bool(entry.admin):
		backend.admin = bool(entry.admin)
		backend.publish()
	var previous := profile_of(connection)
	_connections[connection] = {"id":id,"token":token}
	presence.forget(connection)
	if previous!=id:_attach(previous)
	_attach(id)
	return {"ok":true,"snapshot":backend.full_snapshot(),"account":{"name":str(entry.name),"admin":bool(entry.admin)},"token":token}

## Paced automation waits for a device only while one of this profile's
## devices is connected.
func _attach(id: String) -> void:
	if backends.has(id):backends[id].automation.client_attached = not connections_of(id).is_empty()

func _listing() -> Array:
	var result: Array = []
	for entry in accounts.profiles():
		result.append({"name":str(entry.name),"admin":bool(entry.admin),"online":not connections_of(str(entry.id)).is_empty()})
	return result

func _on_backend_event(message: Dictionary, id: String) -> void:
	for connection in connections_of(id):outgoing.emit(connection,message)

## Runs before the backends each frame (they are its children): the
## automation frame budget is divided among the profiles using it now.
func _process(_delta: float) -> void:
	share_budget()
	if tick:presence_tick()

## Every open profile as server/presence.gd reads it.
func presence_profiles() -> Array:
	var result: Array = []
	for id in backends:
		var profile: Dictionary = backends[id].presence_state()
		profile.id = id
		profile.connections = connections_of(id)
		result.append(profile)
	return result

## Sends each device what changed among the players on its map (at most every
## Presence.TICK_MSEC; `force` for tests). Returns how many messages went out.
func presence_tick(force: bool = false) -> int:
	var news: Array = presence.tick(int(presence_clock.call()),presence_profiles(),force)
	for item in news:outgoing.emit(item[0],item[1])
	return news.size()

## 一般频道: one line to every device on the speaker's map.
func _say(connection: int, command: Dictionary) -> Dictionary:
	var id := profile_of(connection)
	if id.is_empty() or not backends.has(id):return {"ok":false,"reason":"请先登录。","login_required":true}
	var profiles := presence_profiles()
	var speaker: Dictionary = {}
	for profile in profiles:
		if str(profile.id)==id:speaker = profile
	var said: Dictionary = presence.say(int(presence_clock.call()),speaker,profiles,str(command.get("text","")))
	for item in said.deliveries:outgoing.emit(item[0],item[1])
	if said.reply.ok:print("[%s] 一般频道：%s" % [speaker.name,said.reply.text])
	return said.reply

## Every backend's budget_share: how many backends spend a frame budget now.
func share_budget() -> int:
	var busy := 0
	for backend in backends.values():
		if backend.automation.busy():busy += 1
	for backend in backends.values():backend.automation.budget_share = maxi(1,busy)
	return busy

## A graceful stop: every profile records its run, saves, writes its resume
## file, stops its helper, leaves the thread share and releases its lock.
func shut_down() -> void:
	if _stopped:return
	_stopped = true
	for id in backends:
		var backend = backends[id]
		backend.shut_down()
		backend.automation.fast_hunt.stop()
		if backend.automation.fast_share!=null:backend.automation.fast_share.leave()
		SaveLock.release(backend.save_path)
	_connections.clear()
