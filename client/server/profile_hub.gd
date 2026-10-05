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
const Party = preload("res://server/party.gd")
const PartyBattles = preload("res://server/party_battles.gd")
const AutomationSettings = preload("res://scripts/automation_settings.gd")

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
# Short operation tokens only; frames/owners are never stored here.
var _connection_calls: Dictionary = {}
## LAN phase 2: who stands where, and 一般频道 chat (server/presence.gd).
var presence = Presence.new()
## Milliseconds for presence ticks and the chat rate limit (tests fake it).
var presence_clock: Callable = Time.get_ticks_msec
## LAN phase 3: 组队 on the map (server/party.gd).
var party = Party.new()
## LAN phase 4a: the parties' shared battles (server/party_battles.gd), and
## the milliseconds their turn timers run on (tests fake it).
var party_battles = PartyBattles.new(self)
var battle_clock: Callable = Time.get_ticks_msec
## connection -> the last `party` event it was sent (JSON), so only changes go out.
var _party_sent: Dictionary = {}
var _party_tick_msec := -100000
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
	backend.party_battle_hook = party_battles.open.bind(id)
	backend.stationary_party_member = party.in_party.bind(id)
	backend.party_guard = _party_guard.bind(id)
	backend.training_reward_context = party_battles.training_context.bind(id)
	backend.training_borrow_preview = party_battles.training_preview.bind(id)
	backend.quest_visit_guard = _quest_visit_guard.bind(id)
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
		"turn":reply = _turn(connection,command)
		"party_switch","party_share_exp","party_join","party_leave","party_kick","party_disband":reply = _party_command(connection,type,command)
		_:
			var backend = backend_of(connection)
			if backend==null:reply = {"ok":false,"reason":"请先登录。","login_required":true}
			else:
				var id := profile_of(connection)
				reply = _party_refusal(connection,id,type,command)
				if reply.is_empty():
					var leading: bool = type=="report_position" and party.is_leader(id)
					var before := [backend.automation.position_map,backend.automation.position_cell]
					var trusted:=command.duplicate(true)
					trusted["_quest_connection"]=connection
					trusted.erase("_fee_binding")
					if type in ["permit_shop_open","permit_shop_choose","permit_shop_cancel","quest_close"]:trusted["_fee_binding"]=backend._fee_bindings.get(connection)
					var result: Dictionary = backend.handle(trusted)
					if leading and bool(result.get("ok",false)):_party_follow(id,before)
					return result
	reply.seq = command.get("seq",0)
	reply.type = "ack" if reply.get("ok",false) else "rejected"
	reply.v = Backend.PROTOCOL
	return reply

# Connection-map retirement guards. No PIN/token policy or account schema change.
func _connection_call(connection:int)->Dictionary:
	var call=RefCounted.new()
	_connection_calls[connection]=call
	var record:Dictionary=_connections.get(connection,{})
	var id:String=str(record.get("id",""))
	var owner=backends.get(id)
	return {"connection":connection,"call":call,"accounts":accounts,"present":_connections.has(connection),"record":record,"value":record.duplicate(true),"owner_id":id,"owner":owner,"session":owner.session if owner!=null else null,"path":owner.save_path if owner!=null else "","binding":owner._fee_bindings.get(connection) if owner!=null else null}
func _connection_current(f:Dictionary)->bool:
	var c:int=f.connection
	if _connection_calls.get(c)!=f.call or accounts!=f.accounts or _connections.has(c)!=f.present:return false
	if f.present and (not is_same(_connections[c],f.record) or _connections[c]!=f.value):return false
	if f.owner!=null:
		if not is_instance_valid(f.owner) or backends.get(f.owner_id)!=f.owner or f.owner.session!=f.session or f.owner.save_path!=f.path or f.owner._fee_bindings.get(c)!=f.binding:return false
	if f.has("previous_owner") and f.previous_owner!=null:
		if not is_instance_valid(f.previous_owner) or backends.get(f.previous_id)!=f.previous_owner or f.previous_owner.session!=f.previous_session or f.previous_owner.save_path!=f.previous_path:return false
	if f.has("target"):
		if not is_instance_valid(f.target) or backends.get(f.target_id)!=f.target or f.target.session!=f.target_session or f.target.save_path!=f.target_path:return false
	return true
func _connection_done(f:Dictionary)->void:
	if _connection_calls.get(f.connection)==f.call:_connection_calls.erase(f.connection)
func _connection_superseded(f:Dictionary)->Dictionary:
	_connection_done(f)
	return {"ok":false,"reason":"连接操作已被后续操作替代。","stale":true}
func _retire_fee(f:Dictionary)->bool:
	if not _connection_current(f):return false
	if f.owner!=null:
		f.owner.fee_detach(f.connection) # base has no emit/Callable/save
		f.binding=null # expected result, never adopt whatever is now current
	return _connection_current(f)
## A connection closed. Nested enter owns a different call and cannot be erased.
func disconnect_connection(connection:int)->void:
	var f:Dictionary=_connection_call(connection)
	if _retire_fee(f):_disconnect_owned(f)
	_connection_done(f)
func _disconnect_owned(f:Dictionary)->bool:
	if not _connection_current(f):return false
	if f.owner!=null:
		f.owner.quest_auto.detach(f.owner,f.connection)
		if not _connection_current(f):return false
	_connections.erase(f.connection)
	f.present=false
	presence.forget(f.connection)
	if not _connection_current(f):return false
	_party_sent.erase(f.connection)
	_attach(f.owner_id)
	if not _connection_current(f):return false
	_party_gone(f.owner_id)
	return _connection_current(f)

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
func _logout(connection:int)->Dictionary:
	var f:Dictionary=_connection_call(connection)
	var id:String=f.owner_id
	var old_token:String=str(f.value.get("token",""))
	if id.is_empty():
		_connection_done(f)
		return {"ok":true}
	if not _retire_fee(f):return _connection_superseded(f)
	if f.owner.quest_auto.connection==connection or f.owner.quest_auto.detached:
		f.owner.quest_auto.stop(f.owner,"已退出角色。")
		if not _connection_current(f):return _connection_superseded(f)
	# Never read a possibly replaced _connections entry after a callback.
	f.accounts.revoke_token(id,old_token)
	if not _connection_current(f):return _connection_superseded(f)
	if not _disconnect_owned(f):return _connection_superseded(f)
	var listing:Array=_listing()
	if not _connection_current(f):return _connection_superseded(f)
	_connection_done(f)
	return {"ok":true,"profiles":listing,"allow_create":accounts.allow_create()}

func _enter(connection:int,entry:Dictionary,token:String)->Dictionary:
	var f:Dictionary=_connection_call(connection)
	var id:String=str(entry.id)
	var wanted_admin:bool=bool(entry.admin)
	var error:String=open_profile(id)
	if not _connection_current(f):return _connection_superseded(f)
	if not error.is_empty():
		_connection_done(f)
		return {"ok":false,"reason":error}
	var backend=backends[id]
	f.target=backend;f.target_id=id;f.target_session=backend.session;f.target_path=backend.save_path
	if not _retire_fee(f):return _connection_superseded(f)
	if backend.admin!=wanted_admin:
		backend.admin=wanted_admin
		backend.publish()
		if not _connection_current(f):return _connection_superseded(f)
	var previous:String=f.owner_id
	f.previous_id=previous;f.previous_owner=f.owner;f.previous_session=f.session;f.previous_path=f.path
	# Install only this call's intended record, with no callback between check/install.
	var installed:Dictionary={"id":id,"token":token}
	_connections[connection]=installed
	f.present=true;f.record=installed;f.value=installed.duplicate(true)
	f.owner_id=id;f.owner=backend;f.session=f.target_session;f.path=f.target_path
	f.binding=backend.fee_attach(connection) # base no callback; verify exact returned epoch
	if not _connection_current(f):return _connection_superseded(f)
	presence.forget(connection)
	if not _connection_current(f):return _connection_superseded(f)
	_party_sent.erase(connection)
	if previous!=id:
		var old_backend=f.previous_owner
		if old_backend!=null and old_backend.quest_auto.connection==connection:
			old_backend.quest_auto.stop(old_backend,"发起设备已切换角色。")
			if not _connection_current(f):return _connection_superseded(f)
		_attach(previous)
		if not _connection_current(f):return _connection_superseded(f)
		_party_gone(previous)
		if not _connection_current(f):return _connection_superseded(f)
	_attach(id)
	if not _connection_current(f):return _connection_superseded(f)
	var snapshot:Dictionary=backend.full_snapshot()
	if not _connection_current(f):return _connection_superseded(f)
	_connection_done(f)
	return {"ok":true,"snapshot":snapshot,"account":{"name":str(entry.name),"admin":wanted_admin},"token":token}

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
	if tick:
		party_battles.tick()
		presence_tick()

## Every open profile as server/presence.gd reads it.
func presence_profiles() -> Array:
	var result: Array = []
	for id in backends:
		var profile: Dictionary = backends[id].presence_state()
		profile.id = id
		profile.connections = connections_of(id)
		profile.party = party.leader_of(id)
		result.append(profile)
	return result

## Sends each device what changed among the players on its map (at most every
## Presence.TICK_MSEC; `force` for tests), and its party view when that
## changed. Returns how many presence messages went out.
func presence_tick(force: bool = false) -> int:
	var profiles := presence_profiles()
	var news: Array = presence.tick(int(presence_clock.call()),profiles,force)
	for item in news:outgoing.emit(item[0],item[1])
	var now := int(presence_clock.call())
	if force or now-_party_tick_msec>=Presence.TICK_MSEC:
		_party_tick_msec = now
		party_tick(profiles)
	return news.size()

# ---- 组队 (LAN phase 3, server/party.gd) ------------------------------------

## Each logged-in device's `party` event, sent when its view changed (the 组队
## switch, the members, the leader's battle). Returns how many went out.
func party_tick(profiles: Array = []) -> int:
	if profiles.is_empty():profiles = presence_profiles()
	var by_id := {}
	for profile in profiles:by_id[str(profile.id)] = profile
	var sent := 0
	for connection in _connections:
		var id := profile_of(connection)
		var view: Dictionary = party.view(id,by_id)
		if backends.has(id) and party.in_party(id):backends[id].quest_auto.stop(backends[id],"组队变化停止了自动任务。")
		var key := JSON.stringify(view)
		if _party_sent.get(connection,"")==key:continue
		_party_sent[connection] = key
		view.type = "party"
		view.v = 1
		view.me = id
		outgoing.emit(connection,view)
		sent += 1
	return sent

## Commands a party refuses, or answers itself; {} lets the backend handle it.
## Members follow the leader: their own walking reports are ignored (the
## device is told where the server has them), they meet no enemies and start
## no battles. Only the leader starts automation, and only 自动练级 (LAN
## phase 4c, _auto_refusal).
func _party_refusal(connection: int, id: String, type: String, command: Dictionary) -> Dictionary:
	if not party.in_party(id):return {}
	# A leader who escaped from the party's battle waits for the others
	# before walking on or meeting enemies (LAN phase 4a).
	var waiting: bool = party.is_leader(id) and party_battles.party_busy(id) and not party_battles.in_battle(id)
	if type=="auto_start":
		var why := _auto_refusal(id,command)
		if why.is_empty() and waiting:why = "队友还在战斗中，请等他们结束。"
		if not why.is_empty():return {"ok":false,"reason":why}
		return {}
	if not party.is_member(id) and not waiting:return {}
	match type:
		"report_position":
			var automation = backends[id].automation
			var cell: Array = command.get("cell",[0,0])
			var here := Vector2i(int(cell[0]),int(cell[1]))
			if automation.position_map>=0 and (int(command.get("map_id",-1))!=automation.position_map or here!=automation.position_cell):
				outgoing.emit(connection,{"type":"position","v":Backend.PROTOCOL,"map_id":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y],"client":"party"})
			return {"ok":true,"paused":"","party":true}
		"field_step":return {"ok":true,"hit":false,"battle":false,"party":true}
		"wild_encounter","begin_battle","open_battle":return {"ok":false,"reason":"队友还在战斗中，请等他们结束。" if waiting else "组队时只有队长会遇敌；队员跟着队长走。"}
	return {}

# ---- automation in a party (LAN phase 4c) -------------------------------------

const REFUSE_HUNT := "组队中不能使用自动抓宠、找宠和后台搜宠：它们要停下来比较、放生和存仓库，跟不上队伍。请先离开队伍。"

## Why `id`, in a party, cannot start this automation; "" when it may. The
## leader may run 自动练级 with the 普通攻击 preset: every troop it meets is a
## party battle. Members follow and fight with 组队自动战斗 instead; capture,
## hunts and the find-pet cycle are refused for everyone.
func _auto_refusal(id: String, command: Dictionary) -> String:
	var kind := str(command.get("kind",""))
	if kind in ["hunt","find_pet","capture_battle"]:return REFUSE_HUNT
	if kind=="pet_train":return "组队中不能带宠升级（它要单独的镜像助战），请先离开队伍。"
	if party.is_member(id):return "队员跟着队长走，不能自己开始自动练级；想自动出招，请在队伍列表打开「自动战斗」。"
	if kind!="battle":return "组队中不能使用这项自动功能，请先离开队伍。"
	var preset := str(backends[id].automation.profile_settings().preset)
	var given = command.get("settings",{})
	if given is Dictionary and given.has("preset"):preset = str(given.preset)
	if command.has("capture_target") or preset!="attack":return "组队中的自动练级只能用「普通攻击」预设；抓宠和带宠升级请先离开队伍。"
	return ""

## A member's 组队自动战斗 preset for its party battle slot, {} when off:
## {hp: its own 停机线}. PartyBattleSession._auto_command plays it.
func party_auto(id: String) -> Dictionary:
	var backend = backends.get(id)
	if backend==null:return {}
	var overrides: Dictionary = backend.session._profile.get("automation_settings",{})
	var own = overrides.get("party",{})
	if not (own is Dictionary and bool(own.get("auto",false))):return {}
	var training = overrides.get("training",{})
	var line := int(training.get("hp",AutomationSettings.defaults().training.hp)) if training is Dictionary else int(AutomationSettings.defaults().training.hp)
	var spirit := bool(training.get("spirit",AutomationSettings.defaults().training.get("spirit",true))) if training is Dictionary else bool(AutomationSettings.defaults().training.get("spirit",true))
	var side := int(training.get("side_heal",AutomationSettings.defaults().training.get("side_heal",50))) if training is Dictionary else int(AutomationSettings.defaults().training.get("side_heal",50))
	return {"hp":line,"spirit":spirit,"side":side}

## Backend.party_guard of a party leader's 自动练级, before each new troop,
## for the leader and every member at their own 停机线 (the leader's run's,
## each member's own): the 恢复护符 heals their carried pets (it is never
## used up), and a player at the line casts their worn field 精灵 (治愈,
## 滋润; their own 用精灵补血 switch) while the 气力 lasts, then drinks
## 回复药 until above it. The
## party keeps going; only someone healing cannot lift (no 回复药 left, no
## 恢复护符, a fallen pet) stops the run, saying who and why.
func _quest_visit_guard(id: String) -> String:
	return "组队时请先离开队伍再使用任务旅行。" if party.in_party(id) else ""

func _party_guard(leader: String) -> String:
	if not party.is_leader(leader):return ""
	for id in party.members(leader):
		var backend = backends.get(id)
		if backend==null or not backend.session._pending.is_empty():continue
		var session = backend.session
		var changed: bool = session.heal_carried_pets()
		var line := int(backend.automation.settings.hp) if id==leader else int(backend.automation.profile_settings().hp)
		var player: Dictionary = session._profile.player
		# 用精灵补血 (each player's own switch): a field 精灵 before 回复药.
		var own: Dictionary = backend.automation.settings if id==leader else backend.automation.profile_settings()
		if bool(own.get("spirit",true)) and session.spirit_heal_to_line(line,[int(session._profile.active_pet),int(session._profile.get("ride_pet",-1))]):changed = true
		while int(player.hp)*100<=int(player.max_hp)*line and session.use_item("potion"):changed = true
		if changed:
			backend.save()
			backend.publish()
		var why: String = backend.automation.profile_health_reason() if id==leader else backend.automation.profile_health_reason(line)
		if why.is_empty():continue
		if why=="玩家体力达到停机线":why += "，回复药已用完"
		else:why += "，恢复护符不能救起倒下的宠物" if int(session._profile.inventory.get("healing_charm",0))>0 else "，没有恢复护符"
		return why if id==leader else "队友%s：%s" % [_name(id),why]
	return ""

## Stops the 自动练级 of `leader` (when it runs) because its party changed.
func _stop_party_run(leader: String, reason: String) -> void:
	var backend = backends.get(leader)
	if backend==null or not backend.automation.running:return
	backend.automation.stop(reason)
	backend.automation.log_line("[自动练级] "+reason)

## The leader moved: every member steps after it, or goes where it warped.
func _party_follow(leader: String, before: Array) -> void:
	var automation = backends[leader].automation
	var positions := {}
	for member in party.members(leader).slice(1):
		if backends.has(member):positions[member] = [backends[member].automation.position_map,backends[member].automation.position_cell]
	var evidence:Dictionary={"leader_from_map":int(before[0]),"leader_from_cell":[before[1].x,before[1].y],"leader_to_map":automation.position_map,"leader_to_cell":[automation.position_cell.x,automation.position_cell.y]}
	for move in party.follow(leader,int(before[0]),before[1],automation.position_map,automation.position_cell,positions):
		if backends.has(move[0]):backends[move[0]].report_party_position({"type":"report_position","map_id":move[1],"cell":[move[2].x,move[2].y],"map_changed":move[3],"client":"party"},evidence)

func _party_command(connection: int, type: String, command: Dictionary) -> Dictionary:
	var id := profile_of(connection)
	if id.is_empty() or not backends.has(id):return {"ok":false,"reason":"请先登录。","login_required":true}
	var result: Dictionary
	match type:
		"party_switch":
			party.set_accept(id,bool(command.get("on",false)))
			result = {"ok":true,"accept":party.accepts(id)}
		"party_share_exp":
			result = party.set_share(id,bool(command.get("on",true)))
			if result.ok:
				for member in party.members(id):_system(member,"队长%s了队伍共享经验。" % ("打开" if result.share_exp else "关闭"))
		"party_join":
			result = party.join(id,int(command.get("facing",4)),presence_profiles(),str(command.get("target","")))
			if result.ok:
				var name := _name(id)
				print("[%s] 加入 %s 的队伍。" % [name,_name(result.leader)])
				for member in result.members:
					_system(member,"加入团队！" if member==id else "%s 加入团队！" % name)
		"party_leave":result = _party_left(id,party.leave(id),"")
		"party_disband":result = _party_left(id,party.disband(id),"")
		"party_kick":
			var target := str(command.get("id",""))
			result = _party_left(target,party.kick(id,target),"kick")
	party_tick()
	return result

## Tells the players concerned, as the original's yellow system lines.
func _party_left(id: String, result: Dictionary, why: String) -> Dictionary:
	if not result.ok:return result
	var name := _name(id)
	# The leader's 自动练级 was fighting for this party (LAN phase 4c).
	var leader := str(result.leader)
	if bool(result.disbanded) and leader==id:_stop_party_run(leader,"队伍已解散，自动练级已停止。")
	elif why=="kick":_stop_party_run(leader,"踢出了%s，自动练级已停止。" % name)
	else:_stop_party_run(leader,"%s离开了队伍，自动练级已停止。" % name)
	if bool(result.disbanded) and str(result.leader)==id:
		print("[%s] 解散了队伍。" % name)
		for member in result.left:_system(member,"团队已解散！")
		return result
	print("[%s] %s队伍。" % [name,"被踢出" if why=="kick" else "离开"])
	_system(id,"被队长踢出队伍。" if why=="kick" else "脱离团队！")
	for member in result.members+(result.left.filter(func(other):return other!=id)):
		_system(member,"%s %s" % [name,"被踢出队伍。" if why=="kick" else "脱离团队！"])
	return result

## A profile with no device left (disconnect, logout, another login) leaves
## its party; a leader's party disbands (CHAR_DischargeParty at logout).
func _party_gone(id: String) -> void:
	if id.is_empty() or not party.in_party(id) or not connections_of(id).is_empty():return
	# A leader's 自动练级 needs its leader at the table (LAN phase 4c).
	if party.is_leader(id):_stop_party_run(id,"队长已离线，自动练级已停止。")
	# In a party battle it is auto-played, and leaves once the battle ends.
	if party_battles.lost_devices(id):return
	_party_left(id,party.leave(id),"")
	party_tick()

func _system(id: String, text: String) -> void:
	for connection in connections_of(id):outgoing.emit(connection,{"type":"chat","v":1,"channel":"系统","id":"","name":"","text":text,"mine":false})

func _name(id: String) -> String:
	return str(backends[id].account_name) if backends.has(id) else id

## 一般频道: one line to every device on the speaker's map.
## 右键转向: the character turns in place; presence shows it to the others.
func _turn(connection: int, command: Dictionary) -> Dictionary:
	var id := profile_of(connection)
	if id.is_empty() or not backends.has(id):return {"ok":false,"reason":"请先登录。","login_required":true}
	var facing := int(command.get("facing",-1))
	if facing<0 or facing>7:return {"ok":false,"reason":"方向不对。"}
	presence.turn(id,facing)
	return {"ok":true}

func _say(connection: int, command: Dictionary) -> Dictionary:
	var id := profile_of(connection)
	if id.is_empty() or not backends.has(id):return {"ok":false,"reason":"请先登录。","login_required":true}
	var profiles := presence_profiles()
	var speaker: Dictionary = {}
	for profile in profiles:
		if str(profile.id)==id:speaker = profile
	var to_party := str(command.get("channel",""))=="队伍"
	if to_party and not party.in_party(id):return {"ok":false,"reason":"还没有队伍，队伍频道没人听。"}
	var said: Dictionary = presence.say(int(presence_clock.call()),speaker,profiles,str(command.get("text","")),party.members(id) if to_party else [])
	for item in said.deliveries:outgoing.emit(item[0],item[1])
	if said.reply.ok:print("[%s] %s：%s" % [speaker.name,"队伍频道" if to_party else "一般频道",said.reply.text])
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
