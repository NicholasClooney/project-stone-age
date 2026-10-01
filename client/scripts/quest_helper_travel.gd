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
func _process(_delta: float) -> void:
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	if auto.get("running",false):
		world.last_adventure_message=str(auto.get("message",""))
		if not (world.link.is_local() or world.link.online) or (world.battle_view.visible and str(auto.get("phase",""))!="battle") or world.party_locked():cancel("自动任务已停止。")
		var landing:bool=str(auto.get("phase",""))=="landing"
		if not landing:auto_reported=false
		var destination:Dictionary=auto.get("target",{})
		if landing and not auto_reported and str(auto.get("client",""))==world._client_id and not destination.is_empty() and not world.area_transition_busy and not world.moving and not world.data.is_empty() and int(world.data.map_id)==int(destination.map_id) and world.cell==Vector2i(int(destination.cell[0]),int(destination.cell[1])):
			auto_reported=true
			world.report_position()
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
