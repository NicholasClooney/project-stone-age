extends RefCounted
## Remote play and backend events for the game scene (scripts/game.gd): the
## disconnect overlay, reconnect summaries, mirroring another device's walk,
## and dispatching the backend's messages to the presentation. The game keeps
## the state; see docs/technical/game-scripts.md.
const WaitingScreen = preload("res://scripts/waiting_screen.gd")
const LoginScreen = preload("res://scripts/login_screen.gd")
const QUEST_RECEIPT_FIELDS=["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq"]
class LogoutReply extends RefCounted:
	var owner_ref:WeakRef
	var game_ref:WeakRef
	var link_ref:WeakRef
	var peer_ref:WeakRef
	var lifecycle:int
	var generation:int
	var delivered:=false
	static func deliver(reply:Dictionary,guard:LogoutReply)->void:
		if guard.delivered:return
		guard.delivered=true
		var target=guard.owner_ref.get_ref()
		var scene=guard.game_ref.get_ref()
		var link=guard.link_ref.get_ref()
		var peer=guard.peer_ref.get_ref()
		if not is_instance_valid(target) or not is_instance_valid(scene) or not is_instance_valid(link) or not is_instance_valid(peer):return
		if target.game!=scene or target.logout_generation!=guard.generation or scene.link!=link:return
		if link._lifecycle!=guard.lifecycle or link._peer!=peer:return
		if bool(reply.get("stale",false)):return
		if not bool(reply.get("ok",false)):
			if is_instance_valid(scene.message):scene.message.text=str(reply.get("reason","切换角色未完成。"))
			return
		target._remember_login()
		if not is_instance_valid(scene) or scene.link!=link or link._lifecycle!=guard.lifecycle or link._peer!=peer or target.logout_generation!=guard.generation:return
		if scene.is_inside_tree():scene.get_tree().reload_current_scene()

var logout_generation:=0
var quest_prefix:Array=[]
var quest_prefix_id:=""
var quest_prefix_count:=0
var quest_follow_interval:=0.0
var quest_position_epoch:=0
var quest_handshake_pending:=false
var quest_handshake_sent:=false
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

## Remote backend address: an explicit override, then --server=ws://host:port,
## then on the web the page's ?server= parameter or the page host's port 8781.
func _server_url() -> String:
	if not GameScene.server_url_override.is_empty():return GameScene.server_url_override
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):return argument.trim_prefix("--server=")
	if OS.has_feature("web"):
		var chosen = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''",true)
		if chosen is String and not chosen.is_empty():return chosen
		var host = JavaScriptBridge.eval("window.location.hostname",true)
		var secure = JavaScriptBridge.eval("window.location.protocol==='https:'",true)
		return "%s://%s:8781" % ["wss" if secure else "ws",str(host) if host is String and not str(host).is_empty() else "localhost"]
	return ""

func report_position() -> bool:
	if game.data.is_empty() or game.area_transition_busy or game.moving or not quest_prefix.is_empty():return false
	if not game.link.is_local() and not game.link.online:return false
	var command:Dictionary={"type":"report_position","map_id":int(game.data.map_id),"cell":[game.cell.x,game.cell.y],"client":game._client_id}
	var auto:Dictionary=game.state.derived.get("quest_auto",{})
	var receipt:Dictionary=game.get_meta("quest_position_receipt",{})
	if auto.get("running",false) and (auto.get("detached",false) or quest_handshake_pending):
		if quest_handshake_sent:return false
		var authority:Dictionary=game.state.automation.get("position",{})
		if authority.get("map_id",-1)!=command.map_id or authority.get("cell",[])!=command.cell:return false
		# Transport reconnection is an untagged authority-cell handshake. Never
		# copy a prior socket's seq/segment into it, even at the same location.
		clear_quest_receipt()
		quest_handshake_pending=false
		quest_handshake_sent=true
	elif not receipt.is_empty() and receipt.get("map_id",-1)==command.map_id and receipt.get("cell",[])==command.cell and game._followed==[command.map_id,game.cell]:
		if not quest_receipt_current(receipt,auto):return false
		command.quest_position_seq=receipt.seq
		for field in QUEST_RECEIPT_FIELDS:
			if receipt.has(field):command[field]=receipt[field]
	elif auto.get("running",false) and auto.has("motion"):
		# A new client must receive this move's packet; snapshot identity is not
		# a replacement capability for an old animation or missing packet.
		return false
	game.link.request(command)
	return true

func clear_quest_receipt()->void:
	quest_prefix=[];quest_prefix_id="";quest_prefix_count=0;quest_follow_interval=0.0
	quest_position_epoch+=1
	game.set_meta("quest_position_receipt",{})

func quest_receipt_current(receipt:Dictionary,auto:Dictionary)->bool:
	if not receipt.has("quest_run_id"):return true # old A server, seq only
	if not auto.get("running",false) or (auto.get("detached",false) and not quest_handshake_sent):return false
	if str(auto.get("run_id",""))!=str(receipt.quest_run_id):return false
	var revision:=int(auto.get("revision",-1))
	if revision>int(receipt.quest_revision):return false
	if revision==int(receipt.quest_revision) and str(auto.get("step_id",""))!=str(receipt.quest_step_id):return false
	return str(auto.get("phase","")) not in ["battle","waiting_reward","waiting_boss","manual","done"]

func accept_quest_position(event:Dictionary)->bool:
	var auto:Dictionary=game.state.derived.get("quest_auto",{})
	if not quest_receipt_current(event,auto):return false
	var previous:Dictionary=game.get_meta("quest_position_receipt",{})
	if previous.get("quest_run_id","")==event.get("quest_run_id","") and int(previous.get("seq",-1))>=int(event.quest_position_seq):return false
	var receipt:Dictionary=event.duplicate(true)
	receipt.seq=event.quest_position_seq
	if previous.get("quest_segment_id","")!=event.get("quest_segment_id","") or previous.get("quest_revision",-1)!=event.get("quest_revision",-1):quest_position_epoch+=1
	queue_committed_prefix(receipt,previous)
	game.set_meta("quest_position_receipt",receipt)
	if is_instance_valid(game.quest_helper_travel):game.quest_helper_travel.auto_reported=false
	return true

## Keep only cells already committed by the server. A later prefix extends
## this queue; it cannot replace the remaining bends with a straight shortcut.
func queue_committed_prefix(receipt:Dictionary,previous:Dictionary)->void:
	var segment:Dictionary=receipt.get("quest_segment",{})
	if segment.get("kind","")!="public_stride":
		quest_prefix=[];quest_prefix_id="";quest_prefix_count=0;quest_follow_interval=0.0
		return
	var cells:Array=segment.get("cells",[])
	var id:String=str(receipt.quest_segment_id)
	if id!=quest_prefix_id:
		# Another device may acknowledge faster than this observer can render.
		# Preserve already committed bends across contiguous segments as well.
		var continuous:bool=previous.get("quest_run_id")==receipt.get("quest_run_id") and previous.get("quest_revision")==receipt.get("quest_revision") and previous.get("quest_step_id")==receipt.get("quest_step_id") and previous.get("map_id")==segment.get("from_map") and previous.get("cell")==segment.get("from_cell")
		if not continuous:quest_prefix=[]
		quest_prefix_count=0;quest_prefix_id=id
		if not continuous and not game.moving:
			# A newly connected observer can already be on a committed prefix cell.
			for index in range(cells.size()):
				if int(game.data.get("map_id",-1))==int(cells[index].map_id) and game.cell==Vector2i(int(cells[index].cell[0]),int(cells[index].cell[1])):quest_prefix_count=index+1
		# A cold observer starts at the confirmed origin before drawing the bend.
		if int(game.data.get("map_id",-1))!=int(segment.from_map):
			quest_prefix.append([int(segment.from_map),Vector2i(int(segment.from_cell[0]),int(segment.from_cell[1]))])
	for index in range(quest_prefix_count,cells.size()):
		var point:Dictionary=cells[index]
		quest_prefix.append([int(point.map_id),Vector2i(int(point.cell[0]),int(point.cell[1]))])
	quest_prefix_count=cells.size()
	quest_follow_interval=maxf(0.01,float(segment.get("interval_seconds",GameScene.STEP_TIME)))

func follow_interval()->float:
	return quest_follow_interval if quest_follow_interval>0.0 else GameScene.STEP_TIME

func sync_quest_receipt()->void:
	if not game.state.derived.get("quest_auto",{}).get("detached",false):quest_handshake_sent=false
	var receipt:Dictionary=game.get_meta("quest_position_receipt",{})
	if receipt.is_empty():return
	var auto:Dictionary=game.state.derived.get("quest_auto",{})
	if quest_receipt_current(receipt,auto) and (not auto.has("motion") or not auto.motion.is_empty()):return
	clear_quest_receipt()
	game._follow=[]
	if game._following_step:
		game._following_step=false
		game.moving=false
		game.logical_position=Vector2(game.cell)
		game.player.position=game.project(game.logical_position)
	# Resync only to the confirmed authority cell, never the cancelled tail.
	var authority:Dictionary=game.state.automation.get("position",{})
	if auto.get("running",false) and not authority.is_empty():game._follow=[int(authority.map_id),Vector2i(int(authority.cell[0]),int(authority.cell[1]))]

## Walks (one cell) or jumps to where another device put the character, and
## loads its map when that differs. Returns true while a mirrored move runs.
func _step_follow() -> bool:
	if not quest_prefix.is_empty():
		while not quest_prefix.is_empty() and quest_prefix.front()==[int(game.data.map_id),game.cell]:quest_prefix.pop_front()
		game._follow=[] if quest_prefix.is_empty() else quest_prefix.front().duplicate()
	if game._follow.is_empty() or game.area_transition_busy or game.battle_view.visible:return false
	var map_id: int = game._follow[0]
	var target: Vector2i = game._follow[1]
	game._followed = [map_id,target]
	if map_id!=int(game.data.map_id):
		game._follow = []
		game.load_area_id(map_id,target)
		return true
	if target==game.cell:
		game._follow = []
		return false
	var d := target-game.cell
	if maxi(absi(d.x),absi(d.y))==1:
		game.player.facing = (GameScene.SCREEN_DIRECTIONS.find(d)+4)%8
		game.from_cell = game.cell
		game.target_cell = target
		game.step_progress = 0
		game.moving = true
		game._following_step = true
		game.player.set_action(4)
	else:
		game._follow = []
		game.cell = target;game.from_cell = target;game.target_cell = target;game.logical_position = Vector2(target)
		game.player.position = game.project(game.logical_position);game.player.set_action(3)
		game.camera.reset_smoothing();game.refresh_companion();game.queue_redraw()
	return true

func _on_map_reported(reply: Dictionary) -> void:
	if not reply.get("ok",false) and is_instance_valid(game.message):game.message.text=str(reply.get("reason","移动未获服务器确认。"))
	var workflow_pause := str(reply.get("paused",""))
	if workflow_pause.is_empty():return
	game.last_adventure_message="找宠流程暂停："+workflow_pause
	if is_instance_valid(game.message):game.message.text=game.last_adventure_message

## Remote start: wait for the backend's first snapshot before building the map.
func _connect_remote() -> void:
	_build_link_overlay()
	_restore_login()
	game.link.login_needed.connect(_on_login_needed)
	game.link.connected.connect(_on_link_connected)
	game.link.disconnected.connect(_on_link_disconnected)
	game.link.connect_now()
	await game.link.connected

# ---- 登录 (a server hosting several profiles) ----------------------------

## This device's remembered login for this server: viewer.cfg `logins`, server
## address -> {name, token}.
func _restore_login() -> void:
	var saved = game.viewer_pref("logins",{})
	var login = saved.get(game.remote_url,{}) if saved is Dictionary else {}
	if login is Dictionary:
		game.link.login_name = str(login.get("name",""))
		game.link.login_token = str(login.get("token",""))

func _remember_login() -> void:
	var saved = game.viewer_pref("logins",{})
	var logins: Dictionary = saved.duplicate() if saved is Dictionary else {}
	var wanted := {"name":str(game.link.login_name),"token":str(game.link.login_token)}
	if game.link.login_token.is_empty():logins.erase(game.remote_url)
	elif logins.get(game.remote_url,{})==wanted:return
	else:logins[game.remote_url] = wanted
	game.set_viewer_pref("logins",logins)

func _on_login_needed(info: Dictionary) -> void:
	if not is_instance_valid(game.login_screen):return
	game.login_screen.open(info)
	_update_link_overlay()

## 切换角色: forget this device's login and start over at the picker.
func switch_profile() -> void:
	if game.link.is_local():return
	var original=game.link
	var lifecycle:int=original._lifecycle
	var peer=weakref(original._peer) if is_instance_valid(original._peer) else null
	if is_instance_valid(game.world_travel):game.world_travel.permit_logout_begin()
	if not is_instance_valid(game) or game.link!=original or original._lifecycle!=lifecycle:return
	if peer==null or not is_instance_valid(peer.get_ref()) or original._peer!=peer.get_ref():return
	logout_generation+=1
	var receiver:=LogoutReply.new()
	receiver.owner_ref=weakref(self);receiver.game_ref=weakref(game)
	receiver.link_ref=weakref(original);receiver.peer_ref=peer
	receiver.lifecycle=lifecycle;receiver.generation=logout_generation
	original.logout(LogoutReply.deliver.bind(receiver))

func _build_link_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 150
	game.add_child(layer)
	# Before the first snapshot the notice sits on the waiting screen's art,
	# dimmed like the rest of the overlay, on every build that has it.
	if ResourceLoader.exists(WaitingScreen.IMAGE):
		game._link_backdrop = ColorRect.new()
		game._link_backdrop.color = WaitingScreen.BACKDROP
		game._link_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game._link_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var art := TextureRect.new()
		art.texture = load(WaitingScreen.IMAGE)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		game._link_backdrop.add_child(art)
		layer.add_child(game._link_backdrop)
	game.link_overlay = ColorRect.new()
	game.link_overlay.color = Color(0,0,0,0.72)
	game.link_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.link_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(game.link_overlay)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation",16)
	game.link_overlay.add_child(column)
	game._link_status = game.text("",20)
	game._link_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(game._link_status)
	game.login_screen = LoginScreen.new()
	game.login_screen.name = "LoginScreen"
	game.login_screen.configure(game,game.link)
	game.link_overlay.add_child(game.login_screen)
	_update_link_overlay()

## True while the backend is unreachable; the overlay then owns all input.
func link_blocked() -> bool:
	return is_instance_valid(game.link_overlay) and game.link_overlay.visible

func _update_link_overlay() -> void:
	if not is_instance_valid(game.link_overlay):return
	var blocked: bool = not game.link.online
	if blocked!=game.link_overlay.visible:
		game.link_overlay.visible = blocked
		if blocked:
			game.clear_input()
			game.path.clear()
	if is_instance_valid(game._link_backdrop):
		game._link_backdrop.visible = blocked and game.data.is_empty()
		game.link_overlay.color.a = 0.45 if game._link_backdrop.visible else 0.72
	if not blocked:return
	if is_instance_valid(game.login_screen) and game.login_screen.visible and bool(game.link.get("awaiting_login")):
		game._link_status.text = ""
	elif game.data.is_empty():
		game._link_status.text = "正在连接 MacBook 上的服务器\n%s …" % game.remote_url
	else:
		var retry: int = game.link.retry_seconds()
		game._link_status.text = "与 MacBook 上的服务器断开连接\n%s\n自动战斗和找宠会在服务器上继续。" % ("%d 秒后重试…" % retry if retry > 0 else "正在重连…")

func _on_link_connected() -> void:
	quest_handshake_sent=false
	clear_quest_receipt()
	quest_handshake_pending=game.state.derived.get("quest_auto",{}).get("running",false)
	if is_instance_valid(game.login_screen):
		game.login_screen.hide()
		if bool(game.login_screen.last_login.get("created",false)):game.new_character = true
		game.login_screen.last_login = {}
	if not game.link.account.is_empty():_remember_login()
	if game.data.is_empty() or not is_instance_valid(game.battle_view):return
	game._on_automation_settings()
	# Resync presentation to the backend's current battle and progress.
	if game.state.battle_open and not game.battle_view.visible and not game.training_helper.compact_active and not game.party_compact():game.present_battle_start(game.state.battle)
	elif not game.state.battle_open and game.battle_view.visible:game.present_battle_close(str(game.state.battle.get("outcome","")))
	if game.state.derived.get("quest_auto",{}).get("running",false):
		# Reconnect follows authority before reporting, never the stale local cell.
		var current:Dictionary=game.state.automation.get("position",{})
		if not current.is_empty():game._follow=[int(current.map_id),Vector2i(int(current.cell[0]),int(current.cell[1]))]
		game.quest_helper_travel.auto_reported=false
	else:report_position()
	# Windows show the backend's automation as it is now: after a server
	# restart a resumed run (重启后自动恢复) is running again.
	for node in [game.training_helper,game.pet_hunt_menu,game.pet_workflow]:
		if is_instance_valid(node):node.on_status(game.state.automation)
	game.resume_automation_view()
	game.message.text = _offline_summary()

func _on_link_disconnected() -> void:
	quest_handshake_sent=false
	clear_quest_receipt()
	game._follow=[]
	game._followed=[]
	if game._following_step:
		game._following_step=false
		game.moving=false
		game.logical_position=Vector2(game.cell)
		if is_instance_valid(game.player):game.player.position=game.project(game.logical_position)
	quest_handshake_pending=true
	# The server sends everyone on the map again after the reconnect.
	if is_instance_valid(game.remote_players):game.remote_players.reset()
	if is_instance_valid(game.party_panel):game.party_panel.reset()
	game._offline_profile = game.state.full_profile()
	game._offline_battles = int(game.state.automation.get("battles",0))
	if is_instance_valid(game.message):game.message.text = "与服务器的连接中断，正在重连…"

func _offline_summary() -> String:
	if game._offline_profile.is_empty():return "已重新连接服务器。"
	var now: Dictionary = game.state.full_profile()
	var parts: PackedStringArray = ["已重新连接"]
	var battles := int(game.state.automation.get("battles",0))-game._offline_battles
	if battles > 0:parts.append("离线期间自动战斗 %d 场" % battles)
	if int(now.player.level)!=int(game._offline_profile.player.level):parts.append("等级 %d → %d" % [game._offline_profile.player.level,now.player.level])
	var caught: int = now.pets.size()+now.get("pet_storage",[]).size()-game._offline_profile.pets.size()-game._offline_profile.get("pet_storage",[]).size()
	if caught > 0:parts.append("新伙伴 %d 只" % caught)
	game._offline_profile = {}
	return " · ".join(parts)

## Paced automation waits until this client has finished animating a turn.
func acknowledge_presentation() -> void:
	if not bool(game.state.automation.get("running",false)) or not is_instance_valid(game.battle_view) or not game.battle_view.visible or game.battle_view.is_animating():return
	var key := "%s:%d" % [str(game.state.battle.get("battle_id","")),int(game.state.battle.get("turn",0))]
	if key==game._presented_key:return
	game._presented_key = key
	game.link.request({"type":"presented","battle_id":str(game.state.battle.get("battle_id","")),"turn":int(game.state.battle.get("turn",0))})

func _on_backend_message(event: Dictionary) -> void:
	# LAN phase 2: other players and 一般频道, even before the map is built.
	if str(event.get("type","")) in ["presence","chat"]:
		if is_instance_valid(game.remote_players):game.remote_players.on_event(event)
		if is_instance_valid(game.chat_panel):game.chat_panel.on_event(event)
		return
	# LAN phase 3: 组队.
	if str(event.get("type",""))=="party":
		# Kept for a panel built later (the first view can arrive before the map).
		game.last_party_event = event
		if is_instance_valid(game.party_panel):game.party_panel.on_event(event)
		return
	if not game.is_inside_tree() or game.data.is_empty() or not is_instance_valid(game.battle_view):return
	match str(event.type):
		"battle_started":game.present_battle_start(event.state)
		"battle_turn":game.present_battle_turn(event.state)
		# A party battle's turn still waits: who has sent, the turn timer.
		"battle_state":
			if game.battle_view.visible and event.state.has("party"):game.battle_view.update_party(event.state)
		"battle_closed":game.present_battle_close(str(event.outcome))
		"profile":
			sync_quest_receipt()
			if is_instance_valid(game.clone_button):game.clone_button.set_pressed_no_signal(bool(game.state.options.get("clone_squad",false)))
			game._mark_ui_stale()
			game._on_automation_settings()
			if is_instance_valid(game.radio):game.radio.on_profile()
		"pet_storage":
			game._mark_ui_stale()
		"pet_log_changed":
			if is_instance_valid(game.adventure_menu):game.adventure_menu.pet_log_changed()
		"auto_status":
			for node in [game.training_helper,game.pet_hunt_menu,game.pet_workflow]:
				if is_instance_valid(node):node.on_status(event.status)
			if is_instance_valid(game.adventure_menu):game.adventure_menu.hunt_status_changed(event.status)
		"auto_event":_on_auto_event(event.detail)
		"rejected":
			var reason := str(event.get("reason",""))
			if not reason.is_empty():game.message.text = "未连接服务器，操作未发送。" if reason=="offline" else "服务器拒绝：%s" % reason
		"quest_result":
			game.last_adventure_message=str(event.get("text",""))
			game.message.text=game.last_adventure_message
		"position":
			if event.has("quest_position_seq"):
				if not accept_quest_position(event):return
			else:clear_quest_receipt()
			if str(event.get("client",""))!=game._client_id:
				game._follow = quest_prefix.front().duplicate() if not quest_prefix.is_empty() else [int(event.map_id),Vector2i(int(event.cell[0]),int(event.cell[1]))]
				game.pending_talk = false
				game.path.clear()
				# "party": the server moved this 组队 member after its leader.
				if is_instance_valid(game.travel_router) and game.travel_router.active:game.travel_router.cancel("跟随队长移动。" if str(event.get("client",""))=="party" else "另一台设备移动了角色。")

func _on_auto_event(detail: Dictionary) -> void:
	match str(detail.kind):
		"battle_stopped","battle_refused":
			if is_instance_valid(game.training_helper):game.training_helper.on_event(detail)
		"hunt_stopped","hunt_refused","hunt_hit":
			if is_instance_valid(game.pet_hunt_menu):game.pet_hunt_menu.on_event(detail)
		"flow_hunt","flow_paused","flow_stored","flow_compare","flow_reveal","flow_skipped":
			if is_instance_valid(game.pet_workflow):game.pet_workflow.on_event(detail)
