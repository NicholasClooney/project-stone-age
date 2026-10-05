extends Node
const AutoPolicy=preload("res://scripts/quest_auto_policy.gd")
## Client journey only: downloads, server-authorized visit, then original dialogue.
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
func configure(owner: Node) -> void:world=owner
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
		# Render one cached authoritative projection; never interpret old seconds.
		var view=preload("res://scripts/quest_auto_loot_view.gd").new()
		view.replace_snapshot(auto,true)
		if not world.link.is_local() and not world.link.online:view.disconnected()
		message+="\n"+"\n".join(view.lines())
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
