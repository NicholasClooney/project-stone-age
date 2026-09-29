extends RefCounted
## Remote play and backend events for the game scene (scripts/game.gd): the
## disconnect overlay, reconnect summaries, mirroring another device's walk,
## and dispatching the backend's messages to the presentation. The game keeps
## the state; see docs/technical/game-scripts.md.
const WaitingScreen = preload("res://scripts/waiting_screen.gd")
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

func report_position() -> void:
	game.link.request({"type":"report_position","map_id":int(game.data.map_id),"cell":[game.cell.x,game.cell.y],"client":game._client_id})

## Walks (one cell) or jumps to where another device put the character, and
## loads its map when that differs. Returns true while a mirrored move runs.
func _step_follow() -> bool:
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
	var workflow_pause := str(reply.get("paused",""))
	if workflow_pause.is_empty():return
	game.last_adventure_message="找宠流程暂停："+workflow_pause
	if is_instance_valid(game.message):game.message.text=game.last_adventure_message

## Remote start: wait for the backend's first snapshot before building the map.
func _connect_remote() -> void:
	_build_link_overlay()
	game.link.connected.connect(_on_link_connected)
	game.link.disconnected.connect(_on_link_disconnected)
	game.link.connect_now()
	await game.link.connected

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
	if game.data.is_empty():
		game._link_status.text = "正在连接 MacBook 上的服务器\n%s …" % game.remote_url
	else:
		var retry: int = game.link.retry_seconds()
		game._link_status.text = "与 MacBook 上的服务器断开连接\n%s\n自动战斗和找宠会在服务器上继续。" % ("%d 秒后重试…" % retry if retry > 0 else "正在重连…")

func _on_link_connected() -> void:
	if game.data.is_empty() or not is_instance_valid(game.battle_view):return
	game._on_automation_settings()
	# Resync presentation to the backend's current battle and progress.
	if game.state.battle_open and not game.battle_view.visible and not game.training_helper.compact_active:game.present_battle_start(game.state.battle)
	elif not game.state.battle_open and game.battle_view.visible:game.present_battle_close(str(game.state.battle.get("outcome","")))
	report_position()
	game.message.text = _offline_summary()

func _on_link_disconnected() -> void:
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
	if not game.is_inside_tree() or game.data.is_empty() or not is_instance_valid(game.battle_view):return
	match str(event.type):
		"battle_started":game.present_battle_start(event.state)
		"battle_turn":game.present_battle_turn(event.state)
		"battle_closed":game.present_battle_close(str(event.outcome))
		"profile":
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
		"auto_event":_on_auto_event(event.detail)
		"rejected":
			var reason := str(event.get("reason",""))
			if not reason.is_empty():game.message.text = "未连接服务器，操作未发送。" if reason=="offline" else "服务器拒绝：%s" % reason
		"position":
			if str(event.get("client",""))!=game._client_id:
				game._follow = [int(event.map_id),Vector2i(int(event.cell[0]),int(event.cell[1]))]
				game.pending_talk = false
				game.path.clear()
				if is_instance_valid(game.travel_router) and game.travel_router.active:game.travel_router.cancel("另一台设备移动了角色。")

func _on_auto_event(detail: Dictionary) -> void:
	match str(detail.kind):
		"battle_stopped","battle_refused":
			if is_instance_valid(game.training_helper):game.training_helper.on_event(detail)
		"hunt_stopped","hunt_refused","hunt_hit":
			if is_instance_valid(game.pet_hunt_menu):game.pet_hunt_menu.on_event(detail)
		"flow_hunt","flow_paused","flow_stored","flow_compare","flow_reveal","flow_skipped":
			if is_instance_valid(game.pet_workflow):game.pet_workflow.on_event(detail)
