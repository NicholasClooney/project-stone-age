extends Node
const AutoPolicy=preload("res://scripts/quest_auto_policy.gd")
## Client journey only: downloads, server-authorized visit, then original dialogue.
class LootStartReply extends RefCounted:
	## The link retains this receiver until the exact reply arrives. Keep only
	## weak owners so a closed/replaced scene cannot be kept alive by a request.
	var travel_ref:WeakRef
	var world_ref:WeakRef
	var link_ref:WeakRef
	var peer_ref:WeakRef
	var generation:int
	var lifecycle:int
	var logout_generation:int
	var local_link:=false
	var snapshot_request:=false
	var delivered:=false
	static func deliver(reply:Dictionary,guard:LootStartReply)->void:
		if guard.delivered:return
		guard.delivered=true
		var travel=guard.travel_ref.get_ref()
		var game=guard.world_ref.get_ref()
		var link=guard.link_ref.get_ref()
		if not is_instance_valid(travel) or not is_instance_valid(game):return
		if travel.world!=game or travel.loot_start_generation!=guard.generation:return
		if not is_instance_valid(link) or game.link!=link:
			travel._retire_loot_reply(guard,"连接或场景已变化；等待新的服务端状态，不会自动重试。")
			return
		if travel._current_logout_generation()!=guard.logout_generation:
			travel._retire_loot_reply(guard,"角色会话已变化；等待新的服务端状态，不会自动重试。")
			return
		if not guard.local_link:
			var peer=guard.peer_ref.get_ref() if guard.peer_ref!=null else null
			if not is_instance_valid(peer) or link.get("_peer")!=peer or int(link.get("_lifecycle"))!=guard.lifecycle:
				travel._retire_loot_reply(guard,"连接代际已变化；等待新的服务端状态，不会自动重试。")
				return
		if guard.snapshot_request:travel._finish_public_loot_snapshot(reply,guard)
		else:travel._finish_public_loot_start(reply,guard)

var world: Node
var generation:=0
var active:=false
var phase:=""
var target: Dictionary={}
var report_ok:=false
var own_load:=false
var own_route:=false
var auto_requested:=false
var auto_reported:=false
var loot_start_generation:=0
var loot_start_pending:=false
var loot_snapshot_pending:=false
var loot_start_waiting_snapshot:=false
var loot_start_waiting_state_event:=0
var loot_start_state_event_generation:=0
var loot_start_request_state_event:=0
var loot_start_logout_generation:=-1
var loot_start_confirmation_run:Dictionary={}
var loot_start_confirmation_budget:Dictionary={}
var loot_start_confirmation_logout_generation:=-1
var loot_snapshot_apply_generation:=-1
var loot_start_feedback:=""
func configure(owner: Node) -> void:
	world=owner
	if world.state.changed.is_connected(_on_loot_state_changed)==false:world.state.changed.connect(_on_loot_state_changed)
	if world.link.has_signal("disconnected") and not world.link.disconnected.is_connected(_on_loot_link_changed):world.link.disconnected.connect(_on_loot_link_changed)
	if world.link.has_signal("connected") and not world.link.connected.is_connected(_on_loot_link_changed):world.link.connected.connect(_on_loot_link_changed)

func _current_logout_generation()->int:
	var remote=world.get("_remote") if is_instance_valid(world) else null
	if not is_instance_valid(remote):return -1
	var value=remote.get("logout_generation")
	return int(value) if value is int else -1

func public_loot_ui_state()->Dictionary:
	var auto_value=world.state.derived.get("quest_auto",{})
	var budget_value=auto_value.get("budget",null) if auto_value is Dictionary else null
	var can_value=budget_value.get("can_start",null) if budget_value is Dictionary else null
	var reason_value=budget_value.get("reason","") if budget_value is Dictionary else ""
	return {
		"visible":world.state.quest_loot_enabled(),
		"can_start":can_value is bool and can_value,
		"reason":reason_value if reason_value is String else "",
		"link_ready":world.link.is_local() or world.link.online,
		"pending":loot_start_pending or loot_snapshot_pending,
		"waiting_snapshot":loot_start_waiting_snapshot,
		"feedback":loot_start_feedback
	}

func _on_loot_state_changed(kind:String)->void:
	if kind not in ["profile","snapshot"]:return
	loot_start_state_event_generation+=1
	# Defer all synchronous profile/snapshot reconciliation until the snapshot
	# callback revalidates owner, link and operation after the full signal stack.
	if loot_snapshot_apply_generation>=0:return
	_reconcile_loot_start_state_event()

func _reconcile_loot_start_state_event()->void:
	if loot_start_waiting_snapshot and loot_start_state_event_generation>loot_start_waiting_state_event:
		if not loot_start_confirmation_run.is_empty():
			if _current_logout_generation()!=loot_start_confirmation_logout_generation:
				_clear_loot_start_confirmation()
				loot_start_waiting_snapshot=false
				loot_snapshot_pending=false
				loot_start_feedback="角色会话已变化；当前页面不再等待旧启动回执。"
			elif _public_loot_start_reflected(loot_start_confirmation_run,loot_start_confirmation_budget):
				_clear_loot_start_confirmation()
				loot_start_waiting_snapshot=false
				loot_snapshot_pending=false
				loot_start_feedback="服务器状态已确认此启动请求；当前运行状态与后续资格以最新投影为准。"
			else:
				# A later unrelated profile is not proof that this start is visible.
				# Retire the snapshot request too, so its late callback cannot rewind it.
				loot_start_waiting_state_event=loot_start_state_event_generation
				loot_snapshot_pending=false
		else:
			loot_start_waiting_snapshot=false
			loot_snapshot_pending=false
			loot_start_feedback=""

func _on_loot_link_changed()->void:
	if loot_start_pending:_retire_public_loot_start(loot_start_generation,"连接已变化；等待新的服务端状态，不会自动重试。")
	if loot_snapshot_pending:_retire_public_loot_snapshot(loot_start_generation,"连接已变化；等待重新连接后的服务端状态，不会自动重试。")

func _retire_loot_reply(guard:LootStartReply,reason:String)->void:
	if guard.snapshot_request:_retire_public_loot_snapshot(guard.generation,reason)
	else:_retire_public_loot_start(guard.generation,reason)

func _retire_public_loot_start(expected_generation:int,reason:String)->void:
	if expected_generation!=loot_start_generation or not loot_start_pending:return
	loot_start_pending=false
	loot_start_waiting_snapshot=loot_start_state_event_generation<=loot_start_request_state_event
	loot_start_waiting_state_event=loot_start_state_event_generation
	loot_start_feedback=reason

func _retire_public_loot_snapshot(expected_generation:int,reason:String)->void:
	if expected_generation!=loot_start_generation or not loot_snapshot_pending:return
	loot_snapshot_pending=false
	loot_start_waiting_snapshot=true
	loot_start_waiting_state_event=loot_start_state_event_generation
	loot_start_feedback=reason

func start_public_loot()->bool:
	var eligibility:=public_loot_ui_state()
	if not eligibility.visible or not eligibility.can_start or not eligibility.link_ready or loot_start_pending or loot_start_waiting_snapshot:return false
	loot_start_generation+=1
	loot_start_pending=true
	loot_start_waiting_snapshot=false
	_clear_loot_start_confirmation()
	loot_start_request_state_event=loot_start_state_event_generation
	loot_start_logout_generation=_current_logout_generation()
	loot_start_feedback="正在等待服务器确认启动状态。"
	var link=world.link
	var guard:=LootStartReply.new()
	guard.travel_ref=weakref(self);guard.world_ref=weakref(world);guard.link_ref=weakref(link)
	guard.generation=loot_start_generation;guard.logout_generation=loot_start_logout_generation
	guard.local_link=link.is_local()
	if not guard.local_link:
		var peer=link.get("_peer")
		if not is_instance_valid(peer):
			_retire_public_loot_start(loot_start_generation,"当前连接不可用；等待新的服务端状态，不会自动重试。")
			return false
		guard.peer_ref=weakref(peer)
		guard.lifecycle=int(link.get("_lifecycle"))
	var immediate:Dictionary=link.request({"type":"quest_loot_start"},LootStartReply.deliver.bind(guard))
	if not immediate.get("pending",false) and not guard.delivered:LootStartReply.deliver(immediate,guard)
	return true

static func _exact_keys(value:Dictionary,expected:Array)->bool:
	if value.size()!=expected.size():return false
	for key in expected:
		if not value.has(key):return false
	return true

static func _opaque_id(value:Variant)->bool:
	return value is String and value.length()==32 and value.is_valid_hex_number()

static func _valid_run_identity(value:Variant)->bool:
	if not value is Dictionary or not _exact_keys(value,["run_id","step_id","revision"]):return false
	return _opaque_id(value.get("run_id")) and value.get("step_id")=="jewels:hunt:2760" and value.get("revision") is int and int(value.revision)>=0

static func _valid_budget_identity(value:Variant)->bool:
	if not value is Dictionary or not _exact_keys(value,["budget_id","generation","revision"]):return false
	return _opaque_id(value.get("budget_id")) and value.get("generation") is int and int(value.generation)>=0 and value.get("revision") is int and int(value.revision)>=0

func _clear_loot_start_confirmation()->void:
	loot_start_confirmation_run={}
	loot_start_confirmation_budget={}
	loot_start_confirmation_logout_generation=-1

func _public_loot_start_reflected(run_identity:Dictionary,budget_identity:Dictionary)->bool:
	var auto_value=world.state.derived.get("quest_auto",{})
	if not auto_value is Dictionary or not auto_value.get("running",null) is bool:return false
	var run_projection:Dictionary={"run_id":auto_value.get("run_id",null),"step_id":auto_value.get("step_id",null),"revision":auto_value.get("revision",null)}
	if not _valid_run_identity(run_projection):return false
	if run_projection.run_id!=run_identity.run_id or run_projection.step_id!=run_identity.step_id or int(run_projection.revision)<int(run_identity.revision):return false
	var budget_value=auto_value.get("budget",null)
	if not budget_value is Dictionary or not budget_value.get("can_start",null) is bool:return false
	var entry=budget_value.get("entry",null)
	if not entry is Dictionary:return false
	var budget_projection:Dictionary={"budget_id":entry.get("budget_id",null),"generation":entry.get("generation",null),"revision":entry.get("revision",null)}
	if not _valid_budget_identity(budget_projection):return false
	if budget_projection.budget_id!=budget_identity.budget_id or budget_projection.generation!=budget_identity.generation or int(budget_projection.revision)<int(budget_identity.revision):return false
	# A still-running run must continue to block another start. A stopped
	# successor is authoritative too: its current can_start/reason decides the
	# next action, including a recovery lock, without reviving the old ACK.
	if auto_value.running and budget_value.can_start:return false
	return true

func _wait_for_public_loot_snapshot()->bool:
	# A profile event racing the reply is not necessarily the resolution for
	# this command. Keep the control closed until an ordinary snapshot or a
	# later authoritative profile/snapshot event settles the uncertainty.
	loot_start_waiting_snapshot=true
	loot_start_waiting_state_event=loot_start_state_event_generation
	return true

func _request_public_loot_snapshot(source_guard:LootStartReply)->void:
	if not loot_start_waiting_snapshot or loot_snapshot_pending:return
	var link=source_guard.link_ref.get_ref()
	var game=source_guard.world_ref.get_ref()
	if not is_instance_valid(link) or not is_instance_valid(game) or world.link!=link:
		loot_start_feedback="无法确认预算状态；等待重新连接，不会自动重试。"
		return
	var guard:=LootStartReply.new()
	guard.travel_ref=source_guard.travel_ref;guard.world_ref=source_guard.world_ref;guard.link_ref=source_guard.link_ref;guard.peer_ref=source_guard.peer_ref
	guard.generation=source_guard.generation;guard.lifecycle=source_guard.lifecycle;guard.logout_generation=source_guard.logout_generation
	guard.local_link=source_guard.local_link;guard.snapshot_request=true
	loot_snapshot_pending=true
	var immediate:Dictionary=link.request({"type":"snapshot"},LootStartReply.deliver.bind(guard))
	if not immediate.get("pending",false) and not guard.delivered:LootStartReply.deliver(immediate,guard)

func _finish_public_loot_snapshot(reply:Dictionary,guard:LootStartReply)->void:
	if guard.generation!=loot_start_generation or not loot_snapshot_pending:return
	var sequence=reply.get("seq",null)
	var ok=reply.get("ok",null)
	var snapshot=reply.get("snapshot",null)
	if reply.get("type",null)!="ack" or not sequence is int or int(sequence)<=0 or not ok is bool or not ok or not snapshot is Dictionary or snapshot.get("type",null)!="snapshot" or not snapshot.get("rev",null) is int or not snapshot.get("profile",null) is Dictionary or not snapshot.get("derived",null) is Dictionary or not snapshot.get("options",null) is Dictionary or not snapshot.get("battle",null) is Dictionary or not snapshot.get("battle_open",null) is bool or not snapshot.get("automation",null) is Dictionary:
		loot_snapshot_pending=false
		loot_start_waiting_snapshot=true
		loot_start_waiting_state_event=loot_start_state_event_generation
		loot_start_feedback=str(reply.get("reason","无法读取新的服务端状态；不会自动重试。"))
		return
	var event:Dictionary=snapshot.duplicate(true)
	# ClientState.apply emits `changed` synchronously. A listener can dispose or
	# replace this scene, its travel helper, state, link or login before apply
	# returns, so retain only weak ownership across that reentrant boundary.
	var travel_ref=guard.travel_ref
	var game_ref=guard.world_ref
	var link_ref=guard.link_ref
	var peer_ref=guard.peer_ref
	var expected_generation:=guard.generation
	var expected_lifecycle:=guard.lifecycle
	var expected_logout_generation:=guard.logout_generation
	var local_link:=guard.local_link
	var game=game_ref.get_ref() if game_ref!=null else null
	if not is_instance_valid(game) or not is_instance_valid(game.state):return
	var state=game.state
	var state_ref=weakref(state)
	var had_confirmation:=not loot_start_confirmation_run.is_empty()
	loot_snapshot_apply_generation=expected_generation
	state.apply(event)
	var travel=travel_ref.get_ref() if travel_ref!=null else null
	game=game_ref.get_ref() if game_ref!=null else null
	var link=link_ref.get_ref() if link_ref!=null else null
	state=state_ref.get_ref() if state_ref!=null else null
	if not is_instance_valid(travel):return
	if not is_instance_valid(game):
		if travel.loot_snapshot_apply_generation==expected_generation:travel.loot_snapshot_apply_generation=-1
		return
	if travel.world!=game or game.get("quest_helper_travel")!=travel:
		if travel.loot_snapshot_apply_generation==expected_generation:travel.loot_snapshot_apply_generation=-1
		return
	if travel.loot_start_generation!=expected_generation:
		if travel.loot_snapshot_apply_generation==expected_generation:travel.loot_snapshot_apply_generation=-1
		return
	if not is_instance_valid(link) or not is_instance_valid(state) or game.get("state")!=state or game.get("link")!=link:
		if travel.loot_snapshot_apply_generation==expected_generation:travel.loot_snapshot_apply_generation=-1
		travel.loot_snapshot_pending=false
		travel.loot_start_waiting_snapshot=true
		travel.loot_start_waiting_state_event=travel.loot_start_state_event_generation
		return
	if travel._current_logout_generation()!=expected_logout_generation:
		travel.loot_snapshot_apply_generation=-1
		travel._retire_public_loot_snapshot(expected_generation,"角色会话已变化；等待新的服务端状态，不会自动重试。")
		return
	if not local_link:
		var peer=peer_ref.get_ref() if peer_ref!=null else null
		if not is_instance_valid(peer) or link.get("_peer")!=peer or int(link.get("_lifecycle"))!=expected_lifecycle:
			travel.loot_snapshot_apply_generation=-1
			travel._retire_public_loot_snapshot(expected_generation,"连接代际已变化；等待新的服务端状态，不会自动重试。")
			return
	travel.loot_snapshot_apply_generation=-1
	travel._reconcile_loot_start_state_event()
	# Preserve any synchronous state-handler decision. This callback may only
	# retire its own request after revalidating that the operation still owns it.
	if not travel.loot_start_waiting_snapshot:
		travel.loot_snapshot_pending=false
		if not had_confirmation:travel.loot_start_feedback="服务端状态已刷新；开始资格以当前预算为准。"
	else:
		travel.loot_snapshot_pending=false
		travel.loot_start_waiting_state_event=travel.loot_start_state_event_generation
		travel.loot_start_feedback="服务端状态已刷新；仍等待与启动回执一致的状态，不会自动重试。"

func _finish_public_loot_start(reply:Dictionary,guard:LootStartReply)->void:
	loot_start_pending=false
	var kind=reply.get("type",null)
	var sequence=reply.get("seq",null)
	var ok=reply.get("ok",null)
	var persisted=reply.get("persisted",null)
	if not kind is String or kind not in ["ack","rejected"] or not sequence is int or int(sequence)<=0 or not ok is bool or not persisted is bool:
		var needs_snapshot_envelope:=_wait_for_public_loot_snapshot()
		loot_start_feedback="服务器回复格式无效；等待新的服务端状态，不会自动重试。"
		if needs_snapshot_envelope:_request_public_loot_snapshot(guard)
		return
	if not ok:
		if kind!="rejected":
			var needs_snapshot_rejected_kind:=_wait_for_public_loot_snapshot()
			loot_start_feedback="服务器拒绝回复格式无效；等待新的服务端状态，不会自动重试。"
			if needs_snapshot_rejected_kind:_request_public_loot_snapshot(guard)
			return
		if persisted:
			var needs_snapshot_persisted:=_wait_for_public_loot_snapshot()
			var persisted_reason_value=reply.get("reason","")
			var persisted_reason:String=persisted_reason_value if persisted_reason_value is String else ""
			loot_start_feedback="预算可能已持久化，但启动未获确认；等待服务端状态，不会自动重试。 "+persisted_reason
			if needs_snapshot_persisted:_request_public_loot_snapshot(guard)
		else:
			loot_start_waiting_snapshot=false
			var rejected_reason_value=reply.get("reason",null)
			loot_start_feedback=rejected_reason_value if rejected_reason_value is String else "限时刷物未能启动。"
		return
	if kind!="ack" or not persisted or not _valid_run_identity(reply.get("run_identity",null)) or not _valid_budget_identity(reply.get("budget_identity",null)):
		var needs_snapshot_identity:=_wait_for_public_loot_snapshot()
		loot_start_feedback="启动回复缺少有效的持久化身份；等待新的服务端状态，不会自动重试。"
		if needs_snapshot_identity:_request_public_loot_snapshot(guard)
		return
	loot_start_confirmation_run=reply.run_identity.duplicate(true)
	loot_start_confirmation_budget=reply.budget_identity.duplicate(true)
	loot_start_confirmation_logout_generation=guard.logout_generation
	if _public_loot_start_reflected(loot_start_confirmation_run,loot_start_confirmation_budget):
		_clear_loot_start_confirmation()
		loot_start_waiting_snapshot=false
		loot_start_feedback="服务端已确认持久化；当前运行状态与后续资格以服务端状态为准。"
	else:
		loot_start_waiting_snapshot=true
		loot_start_waiting_state_event=loot_start_state_event_generation
		loot_start_feedback="服务端已确认持久化并启动；正在等待匹配的服务端状态，不会重复开始。"
		_request_public_loot_snapshot(guard)

func auto_status() -> String:
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	if auto_pending():return "正在准备任务地图…"
	if str(auto.get("phase",""))=="manual":
		return str(auto.get("pause_reason","")) if not str(auto.get("pause_reason","")).is_empty() else str(auto.get("message",""))
	var message:=str(auto.get("message",""))
	if auto.get("budget",{}).get("finish_current_battle",false):
		message="仅结算当前场，不再开始下一场 · "+message
	elif auto.get("detached",false):
		if auto.get("running",false):return "等待设备确认当前位置 · "+message
		if auto.get("budget",{}).get("recovery_blocked",false):message="任务已停止，预算恢复锁定 · "+message
		elif auto.get("budget",{}).get("entry",null) is Dictionary:message="任务已停止，保留预算历史 · "+message
		else:message="任务已停止 · "+message
	if not str(auto.get("mode_notice","")).is_empty():message+="\n"+str(auto.mode_notice)
	var budget:Dictionary=auto.get("budget",{})
	if not budget.is_empty():
		if world.state.quest_loot_enabled():
			# Render one cached authoritative projection; never interpret old seconds.
			var view=preload("res://scripts/quest_auto_loot_view.gd").new()
			view.replace_snapshot(auto,true)
			if not world.link.is_local() and not world.link.online:view.disconnected()
			message+="\n"+"\n".join(view.lines())
		elif budget.get("recovery_blocked",false)==true:
			# Keep an actual recovery lock visible while its controls and ordinary
			# budget panel stay closed until the server enables the feature.
			var reason:=str(budget.get("reason",""))
			message+="\n刷物预算恢复锁定（只读警告）"+("："+reason if not reason.is_empty() else "。")
	return message
func auto_heading()->String:
	match str(world.state.derived.get("quest_auto",{}).get("phase","")):
		"waiting_reward":return "等待选择奖励 · 成功后自动继续"
		"waiting_boss":return "等待手动 Boss 战 · 胜利后按继续"
		"manual":return "已停止 · 待手动处理"
	return auto_mode()
func continue_auto(expected:Dictionary)->void:
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	for key in ["run_id","step_id","revision"]:
		if auto.get(key)!=expected.get(key):return
	if str(auto.get("phase",""))!="waiting_boss" or not auto.get("can_continue",false) or not (world.link.is_local() or world.link.online):return
	world.link.request({"type":"quest_auto_continue","quest_run_id":str(auto.get("run_id","")),"quest_step_id":str(auto.get("step_id","")),"quest_revision":int(auto.get("revision",-1)),"client":world._client_id},func(reply:Dictionary):
		if not reply.get("ok",false):world.last_adventure_message=str(reply.get("reason","当前任务无法继续。")))
func auto_mode() -> String:
	if auto_pending():return "自动任务准备中"
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	if auto.has("effective_mode"):
		var actual:=str(auto.effective_mode)
		var desired:=str(auto.get("settings",{}).get("mode","A"))
		var title:String={"A":"连续原路自动推进 · 实际 A","B":"公开入口直达 · 实际 B（项目改动）","C":"原路分段快移 · 实际 C（项目改动；单位时间遇敌更多）"}.get(actual,"未知执行模式")
		if desired!=actual:title+=" · 设置意图 %s 尚未生效"%desired
		return title
	return "连续原路自动推进" if world.state.derived.get("quest_auto",{}).get("strict_walk",false) else "自动任务 · 便利导航模式"
func auto_pending() -> bool:
	return active and phase in ["auto_download","auto_request"]
func cancel_navigation() -> void:
	# A panel owns presentation only; preserve pending and server-owned automation.
	if active and not auto_pending():cancel()
func cancel(reason: String="") -> void:
	if auto_requested or world.state.derived.get("quest_auto",{}).get("running",false):
		world.link.request({"type":"quest_auto_stop","client":world._client_id})
	auto_requested=false
	generation+=1
	if active and phase in ["walking","approaching"]:
		world.travel_router.cancel(reason)
		world.path.clear()
		if is_instance_valid(world.world_travel):world.world_travel.pending=-1
	active=false
	phase=""
	if not reason.is_empty():
		world.message.text=reason
		world.last_adventure_message=reason
func valid(ticket: int) -> bool:
	return ticket==generation and active and (world.link.is_local() or world.link.online) and not world.battle_view.visible and not world.party_locked()
func published_step(quest_id: int, step_id: String) -> Dictionary:
	for quest in world.state.derived.get("quest_helper",{}).get("quests",[]):
		if int(quest.id)!=quest_id:continue
		for step in quest.get("steps",[]):
			if str(step.id)==step_id:return step
	return {}
func visit(step: Dictionary, mode: String) -> void:
	cancel()
	world.travel_router.cancel()
	active=true
	phase="download"
	world.last_adventure_message="任务导航：正在准备地图；Esc 停止。"
	var ticket:=generation
	target=step.duplicate(true)
	target.mode=mode
	var needed: Array=world._areas.area_packs(int(step.map_id))
	var ready: bool=await world.await_packs(needed,"任务地图")
	if not valid(ticket):return
	if not ready:cancel("地图素材下载失败，请稍后再试。");return
	var current:=published_step(int(step.quest_id),str(step.id))
	if current.is_empty() or int(current.map_id)!=int(step.map_id):cancel("任务目标已变化，请重新选择步骤。");return
	target=current.duplicate(true)
	target.mode=mode
	phase="request"
	world.link.request({"type":"quest_visit","quest_id":int(step.quest_id),"step_id":str(step.id),"mode":mode,"client":world._client_id},func(reply: Dictionary):_visited(reply,ticket))
func _visited(reply: Dictionary, ticket: int) -> void:
	if not valid(ticket):return
	if not reply.get("ok",false):cancel(str(reply.get("reason","无法前往任务 NPC。")));return
	var destination: Dictionary=reply.get("target",{})
	if destination.is_empty():cancel("任务传送没有返回落点。");return
	var current:=published_step(int(target.quest_id),str(target.id))
	if not current.is_empty() and str(current.get("npc_id",""))==str(destination.get("npc_id","")):target.cell=current.cell.duplicate()
	var needed: Array=world._areas.area_packs(int(destination.map_id))
	if not world.asset_packs.is_ready(needed):
		phase="download"
		var ready: bool=await world.await_packs(needed,"任务地图")
		if not valid(ticket):return
		if not ready:cancel("地图素材下载失败，请稍后再试。");return
	target.map_id=int(destination.map_id)
	target.npc_id=str(destination.get("npc_id",target.get("npc_id","")))
	if str(target.npc_id).is_empty():target.cell=destination.cell.duplicate()
	phase="landing"
	report_ok=false
	own_load=true
	var loaded: bool=world.load_area_id(int(destination.map_id),Vector2i(int(destination.cell[0]),int(destination.cell[1])))
	own_load=false
	if not loaded:cancel("任务地图无法加载。");return
	if not valid(ticket):return
func map_reported(reply: Dictionary, ticket: int) -> void:
	if ticket!=generation or not active or phase!="landing":return
	if not reply.get("ok",false):cancel(str(reply.get("reason","地图位置未获确认。")))
	else:report_ok=true
func map_loading() -> void:
	if active and not own_load:cancel("切换地图停止了任务导航。")
func start_auto(quest_id: int) -> void:
	cancel()
	world.travel_router.cancel()
	active=true
	phase="auto_download"
	var ticket:=generation
	var needed:Array=[]
	for map_id in AutoPolicy.JOB_MAPS.get(quest_id,[]):
		for pack in world._areas.area_packs(map_id):
			if not pack in needed:needed.append(pack)
	var ready:bool=await world.await_packs(needed,"自动任务地图")
	if not valid(ticket):return
	if not ready:cancel("地图素材下载失败，请稍后再试。");return
	phase="auto_request"
	auto_requested=true
	world.link.request({"type":"quest_auto_start","quest_id":quest_id,"client":world._client_id},func(reply:Dictionary):
		if ticket!=generation:return
		active=false
		phase=""
		if not reply.get("ok",false):
			auto_requested=false
			world.last_adventure_message=str(reply.get("reason","自动任务无法开始。")))
static func is_service_battle(auto:Dictionary)->bool:
	if str(auto.get("phase",""))=="battle":return true
	if str(auto.get("phase",""))!="loot_battle" or str(auto.get("step_id",""))!="jewels:hunt:2760":return false
	var budget=auto.get("budget",null)
	if not budget is Dictionary:return false
	var entry=budget.get("entry",null)
	return entry is Dictionary and str(entry.get("step_id",""))==str(auto.step_id)
func _process(_delta: float) -> void:
	if loot_start_pending and _current_logout_generation()!=loot_start_logout_generation:
		_retire_public_loot_start(loot_start_generation,"角色会话已变化；等待新的服务端状态，不会自动重试。")
	if loot_start_waiting_snapshot and loot_start_confirmation_run.is_empty() and loot_start_state_event_generation>loot_start_waiting_state_event:
		loot_start_waiting_snapshot=false
		loot_start_feedback=""
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	if auto.get("running",false):
		world.last_adventure_message=auto_status()
		if (world.link.is_local() or world.link.online) and ((world.battle_view.visible and not auto.get("strict_walk",false) and not is_service_battle(auto)) or world.party_locked()):cancel("自动任务已停止。")
		var receipt:Dictionary=world.get_meta("quest_position_receipt",{})
		var landing:bool=str(auto.get("phase","")) in ["landing","segment_landing"] or bool(receipt.get("quest_ack_required",false)) or auto.get("detached",false)
		if not landing:auto_reported=false
		var destination:Dictionary=world.state.automation.get("position",{}) if auto.get("detached",false) else auto.get("target",{})
		if landing and not auto_reported and (str(auto.get("client",""))==world._client_id or auto.get("detached",false)) and not destination.is_empty() and not world.area_transition_busy and not world.moving and not world.data.is_empty() and int(world.data.map_id)==int(destination.map_id) and world.cell==Vector2i(int(destination.cell[0]),int(destination.cell[1])):
			auto_reported=world._remote.report_position()
	else:
		auto_reported=false
		if phase!="auto_request":auto_requested=false
	if not active:return
	if not (world.link.is_local() or world.link.online) or world.battle_view.visible or world.party_locked():cancel("任务导航已停止。");return
	if phase=="landing" and report_ok and not world.area_transition_busy:
		if target.mode=="near":
			active=false
			phase=""
			world.last_adventure_message="已抵达任务地点。"
			return
		var point:=Vector2i(int(target.cell[0]),int(target.cell[1]))
		own_route=true
		var started: bool=world.travel_router.request(int(target.map_id),point)
		own_route=false
		if not started:cancel(world.travel_router.last_error);return
		phase="walking"
		world.last_adventure_message="任务导航：正在走向目标；Esc 停止。"
	elif phase=="walking" and not world.travel_router.active:
		if not world.travel_router.last_error.is_empty():cancel(world.travel_router.last_error);return
		if str(target.get("npc_id","" )).is_empty():
			active=false
			phase=""
			world.last_adventure_message="已抵达任务地点。"
			return
		# Map changes destroy travel/dialogue; resolve the current instance now.
		var travel=world.world_travel
		for index in range(travel.entries.size()):
			if str(travel.entries[index].get("id",""))==str(target.npc_id):
				phase="approaching"
				travel.approach(index)
				return
		cancel("当前地图找不到任务 NPC。")
	elif phase=="approaching" and world.world_travel.pending<0:
		active=false
		phase=""

func open_auto_reward()->void:
	if not (world.link.is_local() or world.link.online) or world.battle_view.visible:return
	if not is_instance_valid(world.world_travel):return
	world.world_travel.quest_dialogue.open_auto(world.state.derived.get("quest_auto",{}))
