extends RefCounted
## Viewer-only safety observer; all authority remains on the server.
var pending := false
var canceled := false
var pause_sent := false
var heartbeat := 0.0
var generation := 0
var status_timer := 0.0
var status_pending := false
var status: Dictionary = {}
var feedback := ""
var feedback_revision := 0

func connected(world) -> bool:
	return world.link!=null and (world.link.is_local() or world.link.online)

func blocked(world, menu) -> bool:
	if world.area_transition_busy or world.dialogue.visible:return true
	if is_instance_valid(world.classic_hud) and world.classic_hud.map_panel.visible:return true
	if is_instance_valid(world.world_travel) and is_instance_valid(world.world_travel.overlay) and world.world_travel.overlay.visible:return true
	for panel in [world.quest_helper_menu,world.settings_menu,world.leveling_destinations,world.training_helper,world.pet_hunt_menu,world.changelog_menu,world.character_selection,world.dev_gm_menu,world.dev_map_overview,world.pet_training,world.adventure_menu,world.help,world.pet_encyclopedia]:
		if is_instance_valid(panel) and panel.visible:return true
	return world.paused_input and not menu.visible and not world.battle_view.visible

func pause(world) -> void:
	canceled = true
	if pause_sent or not connected(world):return
	pause_sent = true
	world.link.request({"type":"stationary_pause","paused_input":world.paused_input,"battle_visible":world.battle_view.visible,"menu_visible":world.helper_menu.visible})

func refresh_status(world, menu) -> void:
	if status_pending or not connected(world):return
	status_pending = true
	world.link.request({"type":"stationary_keepalive"},func(reply: Dictionary):
		status_pending = false
		if not is_instance_valid(menu):return
		var fresh: Dictionary = reply.get("stationary",{})
		if fresh==status:return
		status = fresh
		if menu.visible:menu.rebuild();menu._center())

func opened(world, menu) -> void:
	generation += 1
	feedback = ""
	if pending or bool(world.state.derived.get("stationary",{}).get("running",false)):pause(world)
	status_timer = 1.0
	refresh_status(world,menu)

func toggle(world, menu, enabled: bool) -> void:
	if pending:return
	pending = true;canceled = false;pause_sent = false;feedback = ""
	var request_generation := generation
	world.link.request({"type":"stationary_encounters","enabled":enabled},func(reply: Dictionary):
		pending = false
		if not is_instance_valid(menu):return
		if reply.get("ok",false) and enabled:
			if canceled or request_generation!=generation or not menu.visible or blocked(world,menu) or not connected(world):
				pause_sent = false;pause(world)
			else:
				heartbeat = 0.0
				menu.close_menu()
		else:
			feedback = str(reply.get("reason",""))
			if not feedback.is_empty():feedback_revision += 1
			if menu.visible:menu.rebuild();menu._center())
	if menu.visible:menu.rebuild();menu._center()

func tick(world, menu, delta: float) -> void:
	if world.link==null:return
	if menu.visible:
		status_timer -= delta
		if status_timer<=0:
			status_timer = 1.0
			refresh_status(world,menu)
	var active: bool = bool(world.state.derived.get("stationary",{}).get("running",false))
	if not connected(world):
		if pending:canceled = true
		return
	if pending and (not menu.visible or blocked(world,menu)):pause(world)
	if not active:
		if not pending:pause_sent = false
		return
	if blocked(world,menu) or (menu.visible and not pending):pause(world);return
	if pause_sent:return
	heartbeat -= delta
	if heartbeat<=0:
		heartbeat = 1.0
		world.link.request({"type":"stationary_keepalive"})
