extends RefCounted
## Walking in the game scene (scripts/game.gd): single steps, routes to a
## clicked cell or toward a blocked one, walking up to the villager, 瞬移,
## resetting to the square, and the per-frame step that moves the character
## along its route. The game keeps its _physics_process callback and the
## position state; see docs/technical/game-scripts.md.
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

func request_step(destination: Vector2i) -> bool:
	if game.moving or not game.can_step(game.cell,destination):
		return false
	if game.party_locked():
		game.message.text = GameScene.PARTY_LOCKED_TEXT
		return false
	var d := destination-game.cell
	# Legacy moveAddTbl: direction 0 is south, 4 north; increments turn clockwise.
	game.player.facing = (GameScene.SCREEN_DIRECTIONS.find(d)+4)%8
	game.from_cell = game.cell
	game.target_cell = destination
	game.step_progress = 0
	game.moving = true
	game._followed = []
	game._follow = []
	game.player.set_action(4)
	return true

func walk_to(destination: Vector2i) -> void:
	if is_instance_valid(game.travel_router):game.travel_router.cancel("新的移动目标取消了跨地图路线。")
	game.pending_talk = false
	if not game.is_walkable(destination):
		game.message.text = "That spot is blocked. Choose a path or clearing."
		return
	var start := game.target_cell if game.moving else game.cell
	game.path = game.navigation.get_id_path(start,destination)
	if not game.path.is_empty():
		game.path.pop_front()
		game.marker_cell = destination
		game.message.text = "Walking to (%d, %d)" % [destination.x,destination.y]
	else:
		game.message.text = "No walkable route to that spot."
	game.queue_redraw()

func walk_toward(destination: Vector2i) -> void:
	# Original map.cpp getRouteMap advances toward even a blocked/outside click.
	# Keep collision authoritative; walking across a doorway still triggers its warp.
	game.pending_talk = false
	game.path.clear()
	var start := game.target_cell if game.moving else game.cell
	var cursor := start
	var direction := Vector2(destination-start)
	var steps := maxi(absi(destination.x-start.x),absi(destination.y-start.y))
	if steps==0:return
	for i in range(1,mini(steps,int(game.data.width)+int(game.data.height))+1):
		var next := start+Vector2i((direction*float(i)/float(steps)).round())
		if next==cursor:continue
		if not game.can_step(cursor,next):break
		game.path.append(next)
		cursor=next
	game.marker_cell = cursor if not game.path.is_empty() else Vector2i(-1,-1)
	game.queue_redraw()

func approach_npc() -> void:
	if game.paused_input:
		return
	if game.npc_data.is_empty():
		game.message.text = "The villager has not been imported. See README.md."
		return
	game.clear_input()
	var start := game.target_cell if game.moving else game.cell
	var best: Array[Vector2i] = []
	var approaches := [Vector2i(-2,0)] if int(game.data.map_id)==1002 else [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
	for offset in approaches:
		var destination: Vector2i = game.npc_cell+offset
		if not game.is_walkable(destination):
			continue
		var candidate := game.navigation.get_id_path(start,destination)
		if not candidate.is_empty() and (best.is_empty() or candidate.size()<best.size()):
			best = candidate
	if best.is_empty():
		game.message.text = "There is no clear path to the villager."
		return
	best.pop_front()
	game.path = best
	game.pending_talk = true
	game.message.text = "正在走向 %s…" % str(game.npc_data.name)

func blink_to(destination: Vector2i) -> bool:
	if game.paused_input or game.area_transition_busy or game.battle_session.snapshot().active:return false
	if game.party_locked():
		game.message.text = GameScene.PARTY_LOCKED_TEXT
		return false
	if not Rect2i(0,0,int(game.data.width),int(game.data.height)).has_point(destination):return false
	var landing:=Vector2i(-1,-1)
	for radius in range(9):
		for y in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				if maxi(absi(x),absi(y))!=radius:continue
				var candidate:=destination+Vector2i(x,y)
				if game.is_walkable(candidate) and (radius==0 or not game.world_catalog.links(int(game.data.map_id)).has(candidate)):
					landing=candidate;break
			if landing.x>=0:break
		if landing.x>=0:break
	if landing.x<0:return false
	if is_instance_valid(game.travel_router):game.travel_router.cancel("点击瞬移停止了自动寻路。")
	game.clear_input();game.moving=false
	game.cell=landing;game.from_cell=landing;game.target_cell=landing;game.logical_position=Vector2(landing);game.step_progress=0
	game.report_position()
	game.player.position=game.project(game.logical_position);game.player.set_action(3)
	game.marker_cell=landing;game.camera.reset_smoothing();game.refresh_companion();game.checkpoint();game.queue_redraw()
	if game.world_catalog.links(int(game.data.map_id)).has(landing):
		game.arrival_lock=Vector2i(-1,-1);game.handle_arrival()
	return true

func reset_player() -> void:
	if is_instance_valid(game.battle_view) and game.battle_view.visible:
		return
	if int(game.data.map_id)!=1000:
		game.switch_area(false,GameScene.SPAWN)
		return
	if game.dialogue.visible:
		game.close_dialogue()
	game.clear_input()
	game.moving = false
	game.cell = GameScene.SPAWN
	game.report_position()
	game.target_cell = GameScene.SPAWN
	game.logical_position = Vector2(GameScene.SPAWN)
	game.player.position = game.project(game.logical_position)
	game.player.set_action(3)
	game.camera.reset_smoothing()
	game.message.text = "Back at the village square."

func step_frame(delta: float) -> void:
	if not game.link.is_local():
		game.link.poll(delta)
		game._update_link_overlay()
		if game.link_blocked():return
	if game.area_transition_busy:return
	if game.data.is_empty():
		return
	if not game._settings_dirty.is_empty() and Time.get_ticks_msec()-game._settings_dirty_msec>=GameScene.SETTINGS_SEND_MSEC:game.flush_automation_settings()
	if game._ui_stale and not game._ui_refresh_held():
		game._ui_refreshed_msec = Time.get_ticks_msec()
		game._ui_stale = game.refresh_open_panels()
	if game.moving:
		var d := game.target_cell-game.from_cell
		var distance_scale := sqrt(2.0) if d.x != 0 and d.y != 0 else 1.0
		game.step_progress = minf(1,game.step_progress+delta/(GameScene.STEP_TIME*distance_scale))
		game.logical_position = Vector2(game.from_cell).lerp(Vector2(game.target_cell),game.step_progress)
		game.player.position = game.project(game.logical_position)
		if game.step_progress>=1:
			game.cell = game.target_cell
			game.moving = false
			if game._following_step:
				game._following_step = false
				game.pet_trail.append(game.cell)
				while game.pet_trail.size()>3:game.pet_trail.pop_front()
			elif game.handle_arrival():
				return
	if not game.moving and not (game.held.is_empty() and game.path.is_empty() and game._step_follow()):
		var destination := game.cell
		if not game.paused_input and not game.held.is_empty():
			var d := Vector2i.ZERO
			for action in game.held:
				match action:
					"north": d += Vector2i(1,-1)
					"south": d += Vector2i(-1,1)
					"east": d += Vector2i(1,1)
					"west": d += Vector2i(-1,-1)
			destination += Vector2i(signi(d.x),signi(d.y))
		elif not game.paused_input and not game.path.is_empty():
			destination = game.path.pop_front()
		if destination != game.cell:
			if not request_step(destination):
				game.path.clear()
				game.player.set_action(3)
		elif game.player.action == 4:
			game.player.set_action(3)
			game.marker_cell = Vector2i(-1,-1)
			game.queue_redraw()
	if game.pending_talk and not game.moving and game.path.is_empty():
		game.pending_talk = false
		if game.in_talk_range(game.cell):
			game.open_dialogue()
	if game.player.action == 6 and game.player.elapsed>1.1:
		game.player.set_action(3)
	game.save_elapsed += delta
	if game.profile_persistence and game.save_elapsed>=5.0 and not game.moving and not game.battle_session.snapshot().active:
		game.checkpoint()
	if is_instance_valid(game.clone_button):game.clone_button.disabled=game.paused_input or game.area_transition_busy
	game.acknowledge_presentation()
	game.update_adventure_hint()
	game.coordinates.text = "%s  ·  %d, %d" % [game.area_name(),game.display_cell().x,game.display_cell().y]
