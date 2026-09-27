extends Node2D

const LegacyActor = preload("res://scripts/legacy_actor.gd")
const GameSession = preload("res://server/game_session.gd")
const AdventureMenu = preload("res://scripts/adventure_menu.gd")
const PetFollower = preload("res://scripts/pet_follower.gd")
const BattleSession = preload("res://server/battle_session.gd")
const BattleView = preload("res://scripts/battle_view.gd")
const WorldCatalog = preload("res://scripts/world_catalog.gd")
var world_catalog = WorldCatalog.new()
var travel_router: Node
var world_travel: Node
var props: Node
var random_encounters := true
var last_encounter_error := ""
var encounter_catalog = preload("res://server/encounter_catalog.gd").new()
var encounter_rng := RandomNumberGenerator.new()
var arrival_lock := Vector2i(-1,-1)
const LegacyGround = preload("res://scripts/legacy_ground.gd")
const SPAWN := Vector2i(80,90)
const STEP_TIME := 0.19
const MIN_ZOOM := 0.4
const MAX_ZOOM := 2.0
const ZOOM_STEP := 0.1
const SCREEN_DIRECTIONS := [Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1)]
var terrain: Node2D
var ui_layer: CanvasLayer
var battle_view: Control
var battle_session = BattleSession.new()
var field_steps := 0
var battle_sounds: Dictionary = {}
var wilderness_music: AudioStream
var village_music: AudioStream
var area_music: AudioStream
var session = GameSession.new()
var changelog_menu: Control
var training_settings: Dictionary = {}
var training_helper: Control
var pet_workflow: Node
var pet_hunt_menu: Control
var dev_gm_menu: Control
var dev_map_overview: Control
var pet_training: Control
var adventure_menu: Control
var profile_persistence := true
var area_transition_busy := false
var dev_blink_mode := false
var travel_landing: RefCounted
var leveling_destinations: Control
var clone_button: Button
var map_transition: CanvasLayer
var save_path := "user://single-player.json"
var pet_follower: Node2D
var pet_trail: Array[Vector2i] = []
var adventure_hint: Label
var encounter_serial := 0
var save_elapsed := 0.0
var mvp_manifest: Dictionary = {}
var last_adventure_message := ""
var last_saved_payload := ""
var boss_button: Button
var data: Dictionary
var textures: Dictionary = {}
var player: Node2D
var actors: Node2D
var camera: Camera2D
var logical_position := Vector2(SPAWN)
var cell := SPAWN
var from_cell := SPAWN
var target_cell := SPAWN
var moving := false
var step_progress := 0.0
var path: Array[Vector2i] = []
var navigation := AStarGrid2D.new()
var held: Array[String] = []
var music: AudioStreamPlayer
var effect: AudioStreamPlayer
var ui_sounds: Dictionary = {}
var last_ui_sound := -1
var ui_sound_count := 0
var muted := false
var volume := 0.55
var coordinates: Label
var message: Label
var mute_button: Button
var help: PanelContainer
var marker: Node2D
var marker_cell := Vector2i(-1,-1)
var character_index := 0
var character_catalog: Dictionary = {}
var character_selection: Control
var paused_input := false
var load_error := ""
var classic_hud: Control
var npc_data: Dictionary = {}
var npc: Node2D
var npc_sprite: Sprite2D
var npc_cell := Vector2i(-1,-1)
var pending_talk := false
var dialogue: Control
var dialogue_name: Label
var dialogue_text: Label

func _ready() -> void:
	encounter_rng.randomize()
	preload("res://scripts/legacy_cursor.gd").install()
	marker = preload("res://scripts/legacy_grid_cursor.gd").new()
	marker.world = self
	add_child(marker)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	configure_input()
	if "--script" in OS.get_cmdline_args():profile_persistence = false
	if FileAccess.file_exists("res://assets/legacy/mvp/manifest.json"):
		mvp_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/mvp/manifest.json"))
	if profile_persistence and (FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak")):
		load_profile()
	if not FileAccess.file_exists("res://assets/legacy/samgir.json") or not FileAccess.file_exists("res://assets/legacy/ui/manifest.json") or world_catalog.maps.is_empty():
		load_error = "Original client assets have not been imported.\nSee README.md → Import original resources."
		var error_label := Label.new()
		error_label.text = load_error
		error_label.position = Vector2(50,100)
		add_child(error_label)
		return
	data = JSON.parse_string(FileAccess.get_file_as_string(world_catalog.file(1000)))
	build_world()
	setup_audio()
	map_transition = preload("res://scripts/classic_map_transition.gd").new()
	add_child(map_transition)
	build_ui()
	travel_router = preload("res://scripts/travel_router.gd").new()
	travel_router.configure(self)
	add_child(travel_router)
	if profile_persistence:
		restore_location()
		if FileAccess.file_exists("res://assets/legacy/pets/catalog.json") and session.claim_default_companions():
			checkpoint()
			message.text = "伙伴已加入：蓝人龙、金虎、红暴龙。打开宠物菜单查看。"
	refresh_companion()
	get_window().focus_exited.connect(release_keyboard_input)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(close_game)
	if "--capture-once" in OS.get_cmdline_user_args():
		capture_frame()


func area_name() -> String:
	return str(data.get("name","萨姆吉尔村"))

func display_cell() -> Vector2i:
	var origin: Array = data.get("origin",[0,0])
	return cell+Vector2i(int(origin[0]),int(origin[1]))

func build_world() -> void:
	var map_image_ids: Array = data.images.keys()
	if character_catalog.is_empty() and FileAccess.file_exists("res://assets/legacy/characters/catalog.json"):
		character_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/characters/catalog.json"))
	if not character_catalog.is_empty():
		data.characters.merge(character_catalog.characters,true)
		data.images.merge(character_catalog.images,true)
	for ident in map_image_ids:
		textures[ident] = load("res://assets/legacy/images/"+ident+".png")
	terrain = LegacyGround.new()
	terrain.world = self
	for entry in data.ground:
		terrain.ground[int(entry[1])*int(data.width)+int(entry[0])] = str(int(entry[2]))
	add_child(terrain)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	actors.z_index = 1
	add_child(actors)
	player = LegacyActor.new()
	player.world = self
	player.character_id = str(session.snapshot().get("character_id","100000"))
	if not data.characters.has(player.character_id):player.character_id = "100000"
	player.position = project(logical_position)
	actors.add_child(player)
	camera = Camera2D.new()
	camera.position = Vector2(0,-25)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10
	player.add_child(camera)
	navigation.clear()
	navigation.region = Rect2i(0,0,int(data.width),int(data.height))
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	navigation.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	navigation.update()
	for y in range(int(data.height)):
		for x in range(int(data.width)):
			navigation.set_point_solid(Vector2i(x,y),not is_walkable(Vector2i(x,y)))
	props = preload("res://scripts/legacy_props.gd").new()
	props.world = self
	actors.add_child(props)
	if int(data.map_id) in [1000,1002]:
		setup_npc()
	pet_trail.assign([cell,cell])
	pet_follower = null

func switch_area(wilderness: bool, destination: Vector2i) -> bool:
	return load_area_id(100 if wilderness else 1000,destination+Vector2i(592,448) if wilderness and world_catalog.maps.has("100") else destination)

func load_area_id(map_id: int, destination: Vector2i) -> bool:
	var file := world_catalog.file(map_id)
	if not FileAccess.file_exists(file):
		message.text = "Import the wilderness assets first; see README.md."
		return false
	var next_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not next_data is Dictionary:
		return false
	var width := int(next_data.width)
	var height := int(next_data.height)
	if destination.x<0 or destination.y<0 or destination.x>=width or destination.y>=height or int(next_data.blocked[destination.y*width+destination.x])!=0:
		return false
	if is_instance_valid(training_helper):training_helper.release_clone_override()
	var workflow_pause := ""
	if is_instance_valid(pet_workflow):workflow_pause=pet_workflow.prepare_scene_reload()
	var previous_zoom: Vector2 = camera.zoom
	clear_input()
	for node in [terrain,actors,ui_layer]:
		remove_child(node)
		node.queue_free()
	data = next_data
	textures.clear()
	world_travel = null
	npc_data.clear()
	npc_cell = Vector2i(-1,-1)
	npc = null
	npc_sprite = null
	cell = destination
	arrival_lock = destination
	from_cell = destination
	target_cell = destination
	logical_position = Vector2(destination)
	moving = false
	paused_input = false
	marker_cell = Vector2i(-1,-1)
	field_steps = 0
	build_world()
	camera.zoom = previous_zoom
	build_ui()
	if not workflow_pause.is_empty():
		pet_workflow.phase="paused"
		pet_workflow.reason=workflow_pause
		last_adventure_message="找宠流程暂停："+workflow_pause
		message.text=last_adventure_message
	camera.reset_smoothing()
	area_music = exploration_music()
	set_music(area_music)
	queue_redraw()
	refresh_companion()
	checkpoint()
	return true

func transition_area(map_id: int, destination: Vector2i) -> bool:
	if area_transition_busy:return false
	area_transition_busy = true
	paused_input = true
	clear_input()
	_run_area_transition(map_id,destination)
	return true

func _run_area_transition(map_id: int, destination: Vector2i) -> void:
	await map_transition.transition(func():
		var changed := load_area_id(map_id,destination)
		paused_input = true
		return changed)
	area_transition_busy = false
	paused_input = false
	clear_input()

func walk_to_exit() -> void:
	if paused_input:
		return
	var links: Dictionary = world_catalog.links(int(data.map_id))
	var closest := Vector2i(-1,-1)
	var distance := INF
	for point in links:
		var link: Dictionary = links[point]
		if int(data.map_id) in [1000,2000,3000,4000] and not world_catalog.field(int(link.to_map)):continue
		if cell.distance_squared_to(point)<distance:
			closest=point;distance=cell.distance_squared_to(point)
	if closest.x>=0:walk_to(closest)

func handle_arrival() -> bool:
	pet_trail.append(cell)
	while pet_trail.size()>3:pet_trail.pop_front()
	if cell==arrival_lock:return false
	arrival_lock = Vector2i(-1,-1)
	var links: Dictionary = world_catalog.links(int(data.map_id))
	if links.has(cell):
		var link: Dictionary = links[cell]
		return transition_area(int(link.to_map),Vector2i(int(link.target[0]),int(link.target[1])))
	if world_catalog.field(int(data.map_id)) and random_encounters:
		field_steps += 1
		if encounter_catalog.step(int(data.map_id),cell,encounter_rng):
			return begin_wild_battle()
	return false

func begin_battle(boss: bool = false, enemy_count: int = 0) -> bool:
	if moving or paused_input or not world_catalog.field(int(data.map_id)) or battle_view==null:
		return false
	if not FileAccess.file_exists("res://assets/legacy/battle/manifest.json"):
		message.text = "Import original battle assets first; see README.md."
		return false
	var species := ["wooli","wooli_wooli","woolistan"]
	var config: Dictionary = session.start_battle_config("woolistan" if boss else species[encounter_serial%3],boss,1 if boss else (enemy_count if enemy_count > 0 else 1 + encounter_serial % 3))
	return open_battle_config(config)

func begin_wild_battle() -> bool:
	last_encounter_error=""
	if moving or paused_input or area_transition_busy or battle_view==null or battle_view.visible:return false
	if not world_catalog.field(int(data.map_id)):return false
	var troop: Dictionary = encounter_catalog.roll(int(data.map_id),cell,encounter_rng)
	if troop.is_empty():
		last_encounter_error="data"
		message.text = "这里没有可用的普通野外遇敌。" if encounter_catalog.last_error.is_empty() else "此区域的原版遇敌数据或条件尚未完整支持，暂时跳过。"
		return false
	if not battle_view.can_render_troop(troop.enemies):
		last_encounter_error="art"
		message.text = "本次敌群的原版动画缺失或损坏，已跳过；未替换敌人。"
		return false
	var opened := open_battle_config(session.start_wild_battle_config(troop))
	if opened:
		encounter_catalog.pressure = int(encounter_catalog.area_at(int(data.map_id),cell).get("probability_min",0))
	return opened

func open_battle_config(config: Dictionary) -> bool:
	if config.is_empty():return false
	if is_instance_valid(travel_router):travel_router.cancel("战斗中断了自动寻路，请重新选择目的地。")
	clear_input()
	paused_input = true
	player.set_action(3)
	help.hide()
	classic_hud.map_panel.hide()
	encounter_serial += 1
	battle_session=preload("res://server/squad_battle_session.gd").new() if not config.get("allies",[]).is_empty() else BattleSession.new()
	battle_session.rng_seed = 42+encounter_serial
	var state: Dictionary = battle_session.start_battle(config)
	if is_instance_valid(training_helper) and training_helper.compact_active:
		return true
	battle_view.open_battle(state)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/battle/manifest.json"))
	set_music(load("res://assets/legacy/battle/"+str(manifest.audio.bgm)))
	play_battle_sound(215)
	return true

func battle_action(action: String) -> void:
	if not battle_view.visible and not (is_instance_valid(training_helper) and training_helper.compact_active):
		return
	var before: Dictionary = session.snapshot()
	var target: int = int(battle_view.get("player_target"))
	battle_session.set_pet_target(int(battle_view.get("pet_target")))
	var skill_id: int = int(battle_view.get("selected_pet_skill"))
	if skill_id > 0 and battle_session.snapshot().pet_command == "skill":
		battle_session.set_pet_skill(skill_id)
	var state: Dictionary = battle_session.developer_escape() if action=="developer_escape" else battle_session.submit_action(action,target,int(battle_view.get("switch_pet_index")))
	if not bool(state.active) and session.apply_battle_result(state):
		if is_instance_valid(training_helper) and training_helper.running:training_helper.record_result(state)
		if state.outcome in ["win","captured"] and int(state.get("xp",0)) > 0:
			state.events.append("获得经验 %d，石币 %d。" % [int(state.get("xp",0)),int(state.get("gold",0))])
			var after: Dictionary = session.snapshot()
			state.result_summary = [{"name":"你","xp":int(state.get("xp",0)),"level_up":int(after.player.level)>int(before.player.level)}]
			var pet_rewards: Array = state.get("pet_reward_xp",[])
			for pet_index in range(mini(before.pets.size(),pet_rewards.size())):
				if int(pet_rewards[pet_index])<=0: continue
				state.result_summary.append({"name":str(after.pets[pet_index].name),"xp":int(pet_rewards[pet_index]),"level_up":int(after.pets[pet_index].level)>int(before.pets[pet_index].level)})
			if int(after.player.level)>int(before.player.level):
				state.events.append("升级！%d 级，体力恢复。状态窗口可分配 %d 点。" % [int(after.player.level),int(after.player.get("stat_points",0))])
			if int(after.active_pet)>=0 and int(after.active_pet) < before.pets.size():
				var index: int = after.active_pet
				if int(after.pets[index].level)>int(before.pets[index].level):
					state.events.append("%s 成长到 %d 级！" % [after.pets[index].name,after.pets[index].level])
					if int(after.pets[index].level) == 2:
						state.events.append("可以向饲育员学习伙伴技能。")
		elif state.outcome=="captured":
			state.events.append("伙伴已加入宠物栏，可为它取名并选择出战。")
		checkpoint()
	if is_instance_valid(training_helper) and training_helper.compact_active:return
	battle_view.show_state(state)
	play_ui_sound(217 if ui_sounds.has(217) else 201)

func return_from_battle() -> void:
	var compact_battle: bool=is_instance_valid(training_helper) and training_helper.compact_active
	if (not battle_view.visible and not compact_battle) or battle_session.snapshot().active or (not compact_battle and battle_view.is_animating()):
		return
	var outcome: String = battle_session.snapshot().outcome
	if compact_battle:training_helper.compact_active=false
	battle_view.close_battle()
	clear_input()
	paused_input = false
	field_steps = 0
	if outcome!="defeat":set_music(exploration_music())
	play_ui_sound(203)
	if outcome=="defeat":
		switch_area(false,SPAWN)
	refresh_companion()
	checkpoint()

func capture_frame() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").path_join("../artifacts")
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join("samgir-original.png"))

func close_game() -> void:
	checkpoint()
	clear_input()
	paused_input = true
	music.stop()
	effect.stop()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()

func configure_input() -> void:
	var bindings := {"north":[KEY_W,KEY_UP],"south":[KEY_S,KEY_DOWN],"west":[KEY_A,KEY_LEFT],"east":[KEY_D,KEY_RIGHT],"mute":[KEY_M],"reset":[KEY_R],"character":[KEY_TAB],"sit":[KEY_X],"wave":[KEY_E],"help":[KEY_H]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action,event)

func project(grid: Vector2) -> Vector2:
	return Vector2((grid.x+grid.y)*32,(grid.y-grid.x)*24)

func unproject(point: Vector2) -> Vector2:
	return Vector2(point.x/64-point.y/48,point.x/64+point.y/48)

func is_walkable(point: Vector2i) -> bool:
	if point.x<0 or point.y<0 or point.x>=int(data.width) or point.y>=int(data.height):
		return false
	return point != npc_cell and not (is_instance_valid(world_travel) and world_travel.blocks(point)) and int(data.blocked[point.y*int(data.width)+point.x])==0

func can_step(origin: Vector2i, destination: Vector2i) -> bool:
	var d := destination-origin
	if abs(d.x)>1 or abs(d.y)>1 or d==Vector2i.ZERO or not is_walkable(destination):
		return false
	if d.x != 0 and d.y != 0:
		return is_walkable(origin+Vector2i(d.x,0)) and is_walkable(origin+Vector2i(0,d.y))
	return true

func request_step(destination: Vector2i) -> bool:
	if moving or not can_step(cell,destination):
		return false
	var d := destination-cell
	# Legacy moveAddTbl: direction 0 is south, 4 north; increments turn clockwise.
	player.facing = (SCREEN_DIRECTIONS.find(d)+4)%8
	from_cell = cell
	target_cell = destination
	step_progress = 0
	moving = true
	player.set_action(4)
	return true

func _input(event: InputEvent) -> void:
	if data.is_empty():
		return
	for action in ["north","south","west","east"]:
		if event.is_action_pressed(action) and not event.is_echo() and not paused_input:
			if is_instance_valid(travel_router):travel_router.cancel("手动移动取消了自动寻路。")
			pending_talk = false
			held.erase(action)
			held.append(action)
			path.clear()
		elif event.is_action_released(action):
			held.erase(action)

func _unhandled_input(event: InputEvent) -> void:
	for modal in [leveling_destinations]:
		if is_instance_valid(modal) and modal.visible:
			if event.is_action_pressed("ui_cancel"):modal.close_menu()
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(training_helper) and training_helper.visible:
		if event.is_action_pressed("ui_cancel"):training_helper.close_menu()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(pet_hunt_menu) and pet_hunt_menu.visible:
		if event.is_action_pressed("ui_cancel"):pet_hunt_menu.close_menu()
		get_viewport().set_input_as_handled()
		return
	if data.is_empty():
		return
	if is_instance_valid(changelog_menu) and changelog_menu.visible:
		if event.is_action_pressed("ui_cancel"):changelog_menu.close_menu()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(character_selection) and character_selection.visible:
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(dev_gm_menu) and dev_gm_menu.visible:
		if event.is_action_pressed("ui_cancel"):dev_gm_menu.close_menu()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(dev_map_overview) and dev_map_overview.visible:
		if event.is_action_pressed("ui_cancel"):dev_map_overview.close_map()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(pet_training) and pet_training.visible:
		if event.is_action_pressed("ui_cancel"):pet_training.close_training()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(world_travel) and world_travel.overlay.visible:
		if event.is_action_pressed("ui_cancel"):world_travel._close()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(adventure_menu) and adventure_menu.visible:
		if event.is_action_pressed("ui_cancel"):close_adventure_menu()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(battle_view) and battle_view.visible:
		if event.is_action_pressed("mute"):
			toggle_mute()
		elif event.is_action_pressed("ui_accept") and not battle_session.snapshot().active:
			return_from_battle()
		get_viewport().set_input_as_handled()
		return
	if dialogue.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			close_dialogue()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode==KEY_M:
		classic_hud.toggle_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and classic_hud.map_panel.visible:
		classic_hud.toggle_map()
		return
	if event.is_action_pressed("mute"):
		toggle_mute()
	elif event.is_action_pressed("help") or event.is_action_pressed("ui_cancel"):
		help.visible = not help.visible if event.is_action_pressed("help") else false
		paused_input = help.visible
		clear_input()
	elif event.is_action_pressed("reset"):
		reset_player()
	elif event.is_action_pressed("character"):
		change_character()
	elif event.is_action_pressed("sit") and not moving:
		player.set_action(3 if player.action==5 else 5)
	elif event.is_action_pressed("wave") and not moving:
		player.set_action(6)
	elif event is InputEventMouseButton and event.pressed and not paused_input:
		if event.button_index == MOUSE_BUTTON_LEFT:
			handle_world_click(get_global_transform_with_canvas().affine_inverse()*event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(camera.zoom.x+ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(camera.zoom.x-ZOOM_STEP)

func walk_to(destination: Vector2i) -> void:
	if is_instance_valid(travel_router):travel_router.cancel("新的移动目标取消了跨地图路线。")
	pending_talk = false
	if not is_walkable(destination):
		message.text = "That spot is blocked. Choose a path or clearing."
		return
	var start := target_cell if moving else cell
	path = navigation.get_id_path(start,destination)
	if not path.is_empty():
		path.pop_front()
		marker_cell = destination
		message.text = "Walking to (%d, %d)" % [destination.x,destination.y]
	else:
		message.text = "No walkable route to that spot."
	queue_redraw()

func _physics_process(delta: float) -> void:
	if area_transition_busy:return
	if data.is_empty():
		return
	if moving:
		var d := target_cell-from_cell
		var distance_scale := sqrt(2.0) if d.x != 0 and d.y != 0 else 1.0
		step_progress = minf(1,step_progress+delta/(STEP_TIME*distance_scale))
		logical_position = Vector2(from_cell).lerp(Vector2(target_cell),step_progress)
		player.position = project(logical_position)
		if step_progress>=1:
			cell = target_cell
			moving = false
			if handle_arrival():
				return
	if not moving:
		var destination := cell
		if not paused_input and not held.is_empty():
			var d := Vector2i.ZERO
			for action in held:
				match action:
					"north": d += Vector2i(1,-1)
					"south": d += Vector2i(-1,1)
					"east": d += Vector2i(1,1)
					"west": d += Vector2i(-1,-1)
			destination += Vector2i(signi(d.x),signi(d.y))
		elif not paused_input and not path.is_empty():
			destination = path.pop_front()
		if destination != cell:
			if not request_step(destination):
				path.clear()
				player.set_action(3)
		elif player.action == 4:
			player.set_action(3)
			marker_cell = Vector2i(-1,-1)
			queue_redraw()
	if pending_talk and not moving and path.is_empty():
		pending_talk = false
		if in_talk_range(cell):
			open_dialogue()
	if player.action == 6 and player.elapsed>1.1:
		player.set_action(3)
	save_elapsed += delta
	if profile_persistence and save_elapsed>=5.0 and not moving and not battle_session.snapshot().active:
		checkpoint()
	if is_instance_valid(clone_button):clone_button.disabled=paused_input or area_transition_busy
	update_adventure_hint()
	coordinates.text = "%s  ·  %d, %d" % [area_name(),display_cell().x,display_cell().y]

func release_keyboard_input() -> void:
	# Focus changes release held keys; an intentional click route keeps running.
	held.clear()

func dev_visit(id: int) -> bool:
	if is_instance_valid(travel_router):travel_router.cancel("开发传送取消了自动寻路。")
	if paused_input or area_transition_busy or battle_view.visible:return false
	var info: Dictionary = world_catalog.info(id)
	if info.is_empty():return false
	var spawn: Array = info.spawn
	return load_area_id(id,Vector2i(int(spawn[0]),int(spawn[1])))

func dev_go_villager() -> void:
	if paused_input or area_transition_busy:return
	if load_area_id(1000,Vector2i(92,72)):approach_npc()

func dev_go_adventure() -> void:
	if paused_input or area_transition_busy:return
	if int(data.map_id)==1000:switch_area(true,Vector2i(45,45))
	else:load_area_id(1000,SPAWN)

func dev_go_shop() -> void:
	if paused_input or area_transition_busy:return
	if load_area_id(1002,Vector2i(16,15)):approach_npc()

func blink_to(destination: Vector2i) -> bool:
	if paused_input or area_transition_busy or battle_session.snapshot().active:return false
	if not Rect2i(0,0,int(data.width),int(data.height)).has_point(destination):return false
	var landing:=Vector2i(-1,-1)
	for radius in range(9):
		for y in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				if maxi(absi(x),absi(y))!=radius:continue
				var candidate:=destination+Vector2i(x,y)
				if is_walkable(candidate) and (radius==0 or not world_catalog.links(int(data.map_id)).has(candidate)):
					landing=candidate;break
			if landing.x>=0:break
		if landing.x>=0:break
	if landing.x<0:return false
	if is_instance_valid(travel_router):travel_router.cancel("点击瞬移停止了自动寻路。")
	clear_input();moving=false
	cell=landing;from_cell=landing;target_cell=landing;logical_position=Vector2(landing);step_progress=0
	player.position=project(logical_position);player.set_action(3)
	marker_cell=landing;camera.reset_smoothing();refresh_companion();checkpoint();queue_redraw()
	if world_catalog.links(int(data.map_id)).has(landing):
		arrival_lock=Vector2i(-1,-1);handle_arrival()
	return true

func dev_encounter() -> void:
	if paused_input or area_transition_busy or battle_view.visible:return
	# Force a source-backed local encounter; move to Samgir wilderness only from a safe map.
	if moving:
		moving = false
		logical_position = Vector2(cell)
		player.position = project(logical_position)
	clear_input()
	if not world_catalog.field(int(data.map_id)):
		if not switch_area(true,Vector2i(45,45)):return
	begin_wild_battle()

func clear_input() -> void:
	if is_instance_valid(world_travel):world_travel.pending = -1
	pending_talk = false
	held.clear()
	path.clear()

func reset_player() -> void:
	if is_instance_valid(battle_view) and battle_view.visible:
		return
	if int(data.map_id)!=1000:
		switch_area(false,SPAWN)
		return
	if dialogue.visible:
		close_dialogue()
	clear_input()
	moving = false
	cell = SPAWN
	target_cell = SPAWN
	logical_position = Vector2(SPAWN)
	player.position = project(logical_position)
	player.set_action(3)
	camera.reset_smoothing()
	message.text = "Back at the village square."

func change_character(id: String = "") -> void:
	if battle_view.visible or area_transition_busy:return
	if id.is_empty():
		character_selection.open_menu()
		return
	if not data.characters.has(id) or not session.set_character(id):return
	player.character_id = id
	refresh_riding()
	player.current_image = -1
	player.elapsed = 0.0
	message.text = "Original character %s" % id
	play_click()
	checkpoint()

func set_zoom(value: float) -> void:
	camera.zoom = Vector2.ONE*clampf(value,MIN_ZOOM,MAX_ZOOM)

func maximum_zoom_out() -> void:
	set_zoom(MIN_ZOOM)

func exploration_music() -> AudioStream:
	var info: Dictionary = world_catalog.info(int(data.map_id))
	if info.get("music") is String and not str(info.music).is_empty():
		var path := "res://assets/legacy/"+str(info.music)
		if ResourceLoader.exists(path):return load(path)
	if str(info.get("kind",""))=="interior" and area_music!=null:return area_music
	return wilderness_music if int(data.map_id)==100 and wilderness_music!=null else village_music

func set_music(stream: AudioStream) -> void:
	if music.stream==stream and music.playing:return
	music.stop()
	music.stream = stream
	if stream is AudioStreamWAV:
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length()*stream.mix_rate)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.play()

func setup_audio() -> void:
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/legacy/sabgm_t0.wav")
	music.stream.loop_begin = 0
	music.stream.loop_end = int(music.stream.get_length()*music.stream.mix_rate)
	music.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	village_music = music.stream
	if mvp_manifest.get("audio",{}).has("wilderness"):
		wilderness_music = load("res://assets/legacy/mvp/"+str(mvp_manifest.audio.wilderness))
	music.volume_db = linear_to_db(volume)
	add_child(music)
	music.play()
	effect = AudioStreamPlayer.new()
	for entry in [[201,"sas_01.wav"],[202,"sas_02.wav"],[203,"sas_03.wav"]]:
		ui_sounds[entry[0]] = load("res://assets/legacy/"+entry[1])
	if FileAccess.file_exists("res://assets/legacy/battle/manifest.json"):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/battle/manifest.json"))
		for ident in manifest.get("frame_sounds",{}):
			battle_sounds[int(ident)] = load("res://assets/legacy/battle/"+str(manifest.frame_sounds[ident]))
		if manifest.audio.has("battle_cancel"):
			ui_sounds[217] = load("res://assets/legacy/battle/"+str(manifest.audio.battle_cancel))
	if ui_sounds.has(217):battle_sounds[217] = ui_sounds[217]
	if mvp_manifest.get("audio",{}).has("menu_denied"):
		battle_sounds[220] = load("res://assets/legacy/mvp/"+str(mvp_manifest.audio.menu_denied))
	if mvp_manifest.get("audio",{}).has("battle_enter"):
		battle_sounds[215] = load("res://assets/legacy/mvp/"+str(mvp_manifest.audio.battle_enter))
	effect.stream = ui_sounds[201]
	effect.volume_db = -10
	add_child(effect)

func play_battle_sound(ident: int) -> void:
	if not battle_sounds.has(ident):
		var path := str(preload("res://scripts/riding.gd").manifest().get("frame_sounds",{}).get(str(ident),""))
		if not path.is_empty(): battle_sounds[ident] = load("res://assets/legacy/riding/"+path)
	if ui_sounds.has(ident):
		play_ui_sound(ident)
		return
	if muted or not battle_sounds.has(ident):
		return
	effect.stream = battle_sounds[ident]
	effect.play()

func play_click() -> void:
	play_ui_sound(201)

func play_ui_sound(ident: int) -> void:
	if muted:
		return
	last_ui_sound = ident
	ui_sound_count += 1
	effect.stream = ui_sounds[ident]
	effect.play()

func toggle_mute() -> void:
	muted = not muted
	music.volume_db = -80 if muted else linear_to_db(maxf(volume,0.0001))
	effect.volume_db = -80 if muted else -10
	mute_button.text = "Music: off  [M]" if muted else "Music: on  [M]"

func _exit_tree() -> void:
	preload("res://scripts/legacy_cursor.gd").uninstall()
	if is_instance_valid(music): music.stop()
	if is_instance_valid(effect): effect.stop()

func box(color: Color, border: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(2)
	result.set_corner_radius_all(3)
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 7
	result.content_margin_bottom = 7
	return result

func text(value: String, size: int = 15) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	label.add_theme_color_override("font_color",Color("f8edc7"))
	return label

func button(value: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = value
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size",13)
	b.add_theme_stylebox_override("normal",box(Color("574431"),Color("9d8354")))
	b.add_theme_stylebox_override("hover",box(Color("775b3c"),Color("e6c284")))
	b.pressed.connect(callback)
	return b

func build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	var font: Font = load("res://assets/fonts/NotoSansSC.ttf")
	var readable_font := FontVariation.new()
	readable_font.base_font = font
	readable_font.variation_opentype = {2003265652:450.0} # OpenType wght axis tag.
	ui_theme.default_font = readable_font
	root.theme = ui_theme
	ui_layer.add_child(root)
	coordinates = text("")
	message = text("")
	root.add_child(coordinates)
	root.add_child(message)
	coordinates.hide()
	message.hide()
	classic_hud = preload("res://scripts/classic_hud.gd").new()
	classic_hud.world = self
	root.add_child(classic_hud)
	boss_button = null
	var dev := HFlowContainer.new()
	dev.size.x = get_viewport_rect().size.x-24
	dev.position = Vector2(12,85)
	dev.add_theme_constant_override("separation",5)
	root.add_child(dev)
	dev.add_child(text("DEV",12))
	var zoom_minus := button("−",func(): set_zoom(camera.zoom.x-ZOOM_STEP))
	zoom_minus.name = "ZoomMinus"
	dev.add_child(zoom_minus)
	var zoom_plus := button("+",func(): set_zoom(camera.zoom.x+ZOOM_STEP))
	zoom_plus.name = "ZoomPlus"
	dev.add_child(zoom_plus)
	var max_out := button("Max out",maximum_zoom_out)
	max_out.name = "MaxOut"
	dev.add_child(max_out)
	character_selection = preload("res://scripts/character_selection.gd").new()
	character_selection.configure(self)
	root.add_child(character_selection)
	var choose_character := button("角色",change_character)
	choose_character.name = "DevCharacter"
	dev.add_child(choose_character)
	var riding_menu := MenuButton.new()
	riding_menu.name = "DevRiding"
	riding_menu.text = "骑乘 ▾"
	riding_menu.flat = false
	riding_menu.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	riding_menu.get_popup().add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	riding_menu.get_popup().add_item("骑乘金虎 / 下骑",0)
	riding_menu.get_popup().add_item("选择金虎骑手造型（100010）",1)
	riding_menu.get_popup().id_pressed.connect(func(id: int):
		if id == 0: dev_toggle_riding()
		elif not paused_input and not moving: change_character("100010"))
	dev.add_child(riding_menu)
	travel_landing=preload("res://scripts/travel_landing.gd").new()
	travel_landing.configure(self)
	leveling_destinations=preload("res://scripts/leveling_destinations.gd").new()
	leveling_destinations.configure(self);root.add_child(leveling_destinations)
	var training_travel:=button("刷怪传送",leveling_destinations.open_menu)
	training_travel.name="DevTrainingTravel";dev.add_child(training_travel)
	var overview_button := button("地图导航",func(): dev_map_overview.open_map())
	overview_button.name = "DevMapOverview"
	dev.add_child(overview_button)
	var gm_button := button("GM 调试",func(): dev_gm_menu.open_menu())
	gm_button.name="DevGM"
	gm_button.z_index=190
	dev.add_child(gm_button)
	var teleport := button("瞬移模式",func(): pass)
	teleport.name = "DevBlinkMode"
	teleport.toggle_mode = true
	teleport.button_pressed = dev_blink_mode
	teleport.toggled.connect(func(enabled: bool): dev_blink_mode=enabled)
	teleport.tooltip_text = "开启后点击当前地图即可瞬移；障碍旁寻找可站立位置，关闭后恢复点击寻路"
	dev.add_child(teleport)
	clone_button=button("五人镜像队",func():pass)
	clone_button.name="DevCloneSquad";clone_button.toggle_mode=true
	clone_button.button_pressed=session.clone_squad_enabled
	clone_button.tooltip_text="复制当前出战宠与骑乘状态，本体优先，四组人宠自动跟随目标；经验仍归本体和真实宠物。下一场生效。"
	clone_button.toggled.connect(func(enabled):
		if not paused_input and not battle_session.snapshot().active:set_clone_squad_enabled(enabled)
		else:clone_button.set_pressed_no_signal(session.clone_squad_enabled))
	dev.add_child(clone_button)
	var encounter := button("立即遇敌",dev_encounter)
	encounter.name = "DevEncounter"
	dev.add_child(encounter)
	pet_hunt_menu = preload("res://scripts/pet_hunt_menu.gd").new()
	pet_hunt_menu.configure(self)
	root.add_child(pet_hunt_menu)
	training_helper = preload("res://scripts/training_helper.gd").new()
	training_helper.configure(self)
	root.add_child(training_helper)
	pet_workflow = preload("res://scripts/pet_workflow.gd").new()
	pet_workflow.configure(self)
	root.add_child(pet_workflow)
	var training := button("自动练级",training_helper.open_menu)
	training.name="DevTraining"
	dev.add_child(training)
	var hunt := button("自动抓极品",pet_hunt_menu.open_menu)
	hunt.name = "DevPetHunt"
	dev.add_child(hunt)
	if int(data.map_id)==1000:
		dev.add_child(button("Villager",dev_go_villager))
	var exit_button := button("村外探险" if int(data.map_id)==1000 else "返回村庄",dev_go_adventure)
	exit_button.name = "ExploreOutside"
	dev.add_child(exit_button)
	if int(data.map_id)==1000:
		dev.add_child(button("道具店",dev_go_shop))
	if int(data.map_id)==100:
		boss_button = button("挑战强敌",func():
			if session.can_fight_boss():begin_battle(true))
		boss_button.tooltip_text = "接受委托、战胜三个对手并捕获伙伴后开放"
		dev.add_child(boss_button)
	mute_button = button("Music: on  [M]",toggle_mute)
	mute_button.text = "Music: off  [M]" if muted else "Music: on  [M]"
	dev.add_child(mute_button)
	changelog_menu = preload("res://scripts/changelog_menu.gd").new()
	changelog_menu.configure(self)
	root.add_child(changelog_menu)
	var changes := button("更新日志 "+str(changelog_menu.history.get("version","v0.0.0")),changelog_menu.open_menu)
	changes.name = "Changelog"
	dev.add_child(changes)
	var help_button := button("Help [H]",func():
		if not dialogue.visible:
			help.visible = not help.visible
			paused_input = help.visible
			clear_input())
	help_button.name = "DevHelp"
	dev.add_child(help_button)
	help = PanelContainer.new()
	help.position = Vector2(310,200)
	help.size = Vector2(660,330)
	help.add_theme_stylebox_override("panel",box(Color("303b2e"),Color("c3a26d")))
	root.add_child(help)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",14)
	help.add_child(content)
	content.add_child(text("Welcome back to 萨姆吉尔",25))
	content.add_child(text("Click a walkable tile to find a path, or use WASD / arrow keys.\nE: wave   X: sit / stand   Tab: choose original character\nMouse wheel or + / −: zoom   M: mute   R: return to square\n\nOriginal 2.5-era map and client assets, rendered in Godot.\nClick 村外探险 to leave through the west exit.\nWild encounters follow original regional enemy and level tables.\nClick the villager to approach and talk. Enter / Esc closes dialogue.",17))
	content.add_child(text("Music volume",14))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = volume
	slider.value_changed.connect(func(value: float): volume = value; music.volume_db = -80 if muted else linear_to_db(maxf(volume,0.0001)))
	content.add_child(slider)
	content.add_child(button("Back to the village",func(): help.hide(); paused_input = false; clear_input()))
	help.hide()
	build_dialogue(root)
	adventure_menu = AdventureMenu.new()
	adventure_menu.configure(self)
	root.add_child(adventure_menu)
	pet_training = preload("res://scripts/pet_training.gd").new()
	pet_training.configure(self)
	root.add_child(pet_training)
	dev_map_overview = preload("res://scripts/dev_map_overview.gd").new()
	dev_map_overview.configure(self)
	root.add_child(dev_map_overview)
	dev_gm_menu=preload("res://scripts/dev_gm_menu.gd").new()
	dev_gm_menu.configure(self)
	root.add_child(dev_gm_menu)
	adventure_hint = text("",14)
	adventure_hint.position = Vector2(18,132)
	dev.resized.connect(func():
		if is_instance_valid(adventure_hint):adventure_hint.position.y=dev.position.y+dev.size.y+8)
	adventure_hint.add_theme_color_override("font_shadow_color",Color.BLACK)
	adventure_hint.add_theme_constant_override("shadow_offset_x",1)
	adventure_hint.add_theme_constant_override("shadow_offset_y",1)
	adventure_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(adventure_hint)
	battle_view = BattleView.new()
	root.add_child(battle_view)
	battle_view.configure(self)
	battle_view.playback_speed=float(training_settings.get("speed",1.0))
	battle_view.action_requested.connect(battle_action)
	battle_view.return_requested.connect(return_from_battle)
	battle_view.sound_requested.connect(play_battle_sound)
	battle_view.capture_music_requested.connect(func(celebrating: bool):
		set_music(load("res://assets/legacy/battle/audio/sabgm_s0.wav") if celebrating else load("res://assets/legacy/battle/audio/sabgm_b0.wav")))
	battle_view.pet_command_requested.connect(func(command: String):
		if command == "skill": battle_session.set_pet_skill(int(battle_view.get("selected_pet_skill")))
		else: battle_session.set_pet_command(command))
	world_travel = preload("res://scripts/world_travel.gd").new()
	actors.add_child(world_travel)
	var residents: Array = []
	for entry in world_catalog.residents:
		if int(entry.map_id)==int(data.map_id) and Vector2i(entry.cell[0],entry.cell[1])!=npc_cell:residents.append(entry)
	world_travel.setup(self,root,residents)


func setup_npc() -> void:
	if int(data.map_id)==1002 and not mvp_manifest.is_empty():
		npc_data = mvp_manifest.merchant.duplicate(true)
	elif not FileAccess.file_exists("res://assets/legacy/samgir-npc.json"):
		return
	else:
		npc_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/samgir-npc.json"))
	npc_cell = Vector2i(npc_data.cell[0],npc_data.cell[1])
	navigation.set_point_solid(npc_cell,true)
	npc = Node2D.new()
	npc.position = project(Vector2(npc_cell))
	actors.add_child(npc)
	npc_sprite = Sprite2D.new()
	npc_sprite.texture = load("res://assets/legacy/mvp/"+str(npc_data.path)) if int(data.map_id)==1002 else load("res://assets/legacy/samgir-villager.png")
	npc_sprite.centered = false
	npc_sprite.position = Vector2(npc_data.offset[0],npc_data.offset[1])
	npc.add_child(npc_sprite)
	var label := text(npc_data.name,14)
	label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	label.position = Vector2(-28,-94)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	npc.add_child(label)

func handle_world_click(point: Vector2) -> void:
	if paused_input:
		return
	if dev_blink_mode:
		blink_to(Vector2i(unproject(point).round()));return
	if is_instance_valid(travel_router):travel_router.cancel("手动点击取消了自动寻路。")
	if is_instance_valid(world_travel) and world_travel.handle_click(point):return
	if is_instance_valid(npc_sprite) and npc_sprite.get_rect().has_point(npc_sprite.to_local(point)):
		approach_npc()
	else:
		var destination := Vector2i(unproject(point).round())
		if is_walkable(destination):walk_to(destination)
		else:walk_toward(destination)

func walk_toward(destination: Vector2i) -> void:
	# Original map.cpp getRouteMap advances toward even a blocked/outside click.
	# Keep collision authoritative; walking across a doorway still triggers its warp.
	pending_talk = false
	path.clear()
	var start := target_cell if moving else cell
	var cursor := start
	var direction := Vector2(destination-start)
	var steps := maxi(absi(destination.x-start.x),absi(destination.y-start.y))
	if steps==0:return
	for i in range(1,mini(steps,int(data.width)+int(data.height))+1):
		var next := start+Vector2i((direction*float(i)/float(steps)).round())
		if next==cursor:continue
		if not can_step(cursor,next):break
		path.append(next)
		cursor=next
	marker_cell = cursor if not path.is_empty() else Vector2i(-1,-1)
	queue_redraw()

func in_talk_range(point: Vector2i) -> bool:
	var delta := (point-npc_cell).abs()
	# Cardinal neighbours avoid talking diagonally through blocked corners.
	return (point==Vector2i(16,15)) if int(data.map_id)==1002 else delta.x+delta.y == 1

func approach_npc() -> void:
	if paused_input:
		return
	if npc_data.is_empty():
		message.text = "The villager has not been imported. See README.md."
		return
	clear_input()
	var start := target_cell if moving else cell
	var best: Array[Vector2i] = []
	var approaches := [Vector2i(-2,0)] if int(data.map_id)==1002 else [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
	for offset in approaches:
		var destination: Vector2i = npc_cell+offset
		if not is_walkable(destination):
			continue
		var candidate := navigation.get_id_path(start,destination)
		if not candidate.is_empty() and (best.is_empty() or candidate.size()<best.size()):
			best = candidate
	if best.is_empty():
		message.text = "There is no clear path to the villager."
		return
	best.pop_front()
	path = best
	pending_talk = true
	message.text = "正在走向 %s…" % str(npc_data.name)

func open_dialogue() -> void:
	if moving or not in_talk_range(cell):
		return
	if int(data.map_id)==1002:
		show_adventure_menu("shop")
		return
	clear_input()
	paused_input = true
	player.set_action(3)
	player.facing = (SCREEN_DIRECTIONS.find(npc_cell-cell)+4)%8
	dialogue_name.text = npc_data.name
	dialogue_text.text = npc_data.text
	dialogue.show()
	play_ui_sound(202)

func close_dialogue() -> void:
	if not dialogue.visible:
		return
	play_ui_sound(203)
	dialogue.hide()
	paused_input = help.visible
	clear_input()
	message.text = "Click the villager to talk again, or keep exploring."

func build_dialogue(root: Control) -> void:
	dialogue = Control.new()
	dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dialogue)
	var panel := Control.new()
	panel.name = "OriginalDialogue"
	panel.size = Vector2(384,192)
	panel.scale = Vector2.ONE*classic_hud.SCALE
	panel.position = Vector2((1280-384*classic_hud.SCALE)/2,450)
	dialogue.add_child(panel)
	# WindowDisp composes a stone frame from the original 64×48 tiles.
	for y in range(4):
		for x in range(6):
			var row := 0 if y==0 else (2 if y==3 else 1)
			var column := 0 if x==0 else (2 if x==5 else 1)
			classic_hud.picture(panel,26001+row*3+column,Vector2(x*64,y*48))
	dialogue_name = text("",15)
	dialogue_name.position = Vector2(18,15)
	dialogue_name.add_theme_color_override("font_color",Color.YELLOW)
	dialogue_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dialogue_name)
	dialogue_text = text("",15)
	dialogue_text.position = Vector2(18,45)
	dialogue_text.size = Vector2(348,90)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.add_theme_color_override("font_color",Color.WHITE)
	dialogue_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dialogue_text)
	var button_art: Texture2D = classic_hud.art[26091]
	var close_button: TextureButton = classic_hud.icon(panel,26091,26091,Vector2((384-button_art.get_width())/2.0,156),"确定 · Enter / Esc")
	close_button.name = "ConfirmDialogue"
	close_button.pressed.connect(close_dialogue)
	var quest_choice := Button.new()
	quest_choice.text = "村外的伙伴 / 休息"
	quest_choice.position = Vector2(105,112)
	quest_choice.size = Vector2(190,30)
	quest_choice.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	quest_choice.add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	quest_choice.pressed.connect(func(): close_dialogue(); show_adventure_menu("quest"))
	panel.add_child(quest_choice)
	dialogue.hide()


func restore_location() -> void:
	var location: Dictionary = session.snapshot().location
	var point := Vector2i(int(location.x),int(location.y))
	if int(location.map_id)==100 and not world_catalog.maps.has("100"):point -= Vector2i(592,448)
	if not load_area_id(int(location.map_id),point):
		load_area_id(1000,SPAWN)

func checkpoint() -> bool:
	if battle_session.snapshot().active:return false
	var point := display_cell()
	if ((is_instance_valid(battle_view) and battle_view.visible) or (is_instance_valid(training_helper) and training_helper.compact_active)) and battle_session.snapshot().outcome=="defeat":
		session.set_location(1000,SPAWN.x,SPAWN.y)
	else:
		session.set_location(int(data.map_id),point.x,point.y)
	save_elapsed = 0
	if not profile_persistence:return true
	var payload := JSON.stringify(session.snapshot())
	if payload==last_saved_payload:return true
	var success: bool = session.save_game(save_path)
	if success:last_saved_payload = payload
	if not success:last_adventure_message = "保存失败，请检查存储空间。"
	return success

func refresh_companion() -> void:
	refresh_riding()
	if is_instance_valid(pet_follower):
		pet_follower.queue_free()
	pet_follower = null
	var profile: Dictionary = session.snapshot()
	if int(profile.active_pet)<0 or not FileAccess.file_exists("res://assets/legacy/battle/manifest.json"):return
	var pet: Dictionary = profile.pets[int(profile.active_pet)]
	if int(pet.hp)<=0:return
	pet_follower = PetFollower.new()
	pet_follower.world = self
	pet_follower.position = player.position
	actors.add_child(pet_follower)
	pet_follower.select_pet(str(int(pet.sprite)),str(pet.name))

func update_adventure_hint() -> void:
	if not is_instance_valid(adventure_hint):return
	adventure_hint.visible = not battle_view.visible and not adventure_menu.visible and not dialogue.visible
	var profile: Dictionary = session.snapshot()
	var q: Dictionary = profile.quest
	if is_instance_valid(boss_button):boss_button.disabled = not session.can_fight_boss()
	var objective := "找村民聊聊，准备你的第一次冒险。"
	if q.claimed:objective = "委托完成！继续培养与收集你的伙伴。"
	elif session.can_fight_boss():objective = "准备好后，在村外点击 DEV「挑战强敌」。"
	elif q.boss_defeated:objective = "回到村民身边领取报酬。"
	elif q.accepted:objective = "村外的伙伴：胜利 %d/3 · 捕获伙伴 %d/1" % [mini(3,int(q.wins)),mini(1,profile.pets.size())]
	adventure_hint.text = "Lv.%d  体力 %d/%d  石币 %d   %s" % [profile.player.level,profile.player.hp,profile.player.max_hp,profile.player.gold,objective]
	if not last_adventure_message.is_empty():adventure_hint.text += "\n"+last_adventure_message

func show_adventure_menu(kind: String) -> void:
	if is_instance_valid(character_selection) and character_selection.visible:return
	if is_instance_valid(changelog_menu) and changelog_menu.visible:return
	if is_instance_valid(dev_gm_menu) and dev_gm_menu.visible:return
	if is_instance_valid(dev_map_overview) and dev_map_overview.visible:return
	if is_instance_valid(pet_training) and pet_training.visible:return
	if is_instance_valid(world_travel) and world_travel.overlay.visible:return
	if adventure_menu.visible and adventure_menu.kind == kind:
		close_adventure_menu()
		return
	if battle_view.visible and kind!="system":
		play_battle_sound(220)
		return
	if moving or dialogue.visible or help.visible:return
	if kind=="shop" and (int(data.map_id)!=1002 or not in_talk_range(cell)):return
	if kind=="quest" and (int(data.map_id)!=1000 or not in_talk_range(cell)):return
	clear_input()
	paused_input = true
	classic_hud.map_panel.hide()
	adventure_menu.open_menu(kind)
	play_ui_sound(202)

func close_adventure_menu() -> void:
	adventure_menu.hide()
	paused_input = battle_view.visible
	clear_input()
	refresh_companion()
	checkpoint()
	play_ui_sound(203)

func perform_adventure_action(action: String, value: Variant = null) -> void:
	if not adventure_menu.visible or (battle_view.visible and action!="mute"):return
	var success := false
	var note := ""
	var at_shop := int(data.map_id)==1002 and in_talk_range(cell)
	var at_villager := int(data.map_id)==1000 and in_talk_range(cell)
	match action:
		"pet_preview":
			adventure_menu.selected_pet = int(value)
			adventure_menu.refresh()
			return
		"buy_potion":success = at_shop and session.buy_item("potion")
		"buy_club":success = at_shop and session.buy_item("club")
		"buy_mirror_charm":success = at_shop and session.buy_item("mirror_charm")
		"sell_potion":success = at_shop and session.sell_item("potion")
		"sell_club":success = at_shop and session.sell_item("club")
		"sell_mirror_charm":success = at_shop and session.sell_item("mirror_charm")
		"use_potion":success = session.use_item("potion")
		"equip":success = session.equip_item("club")
		"equip_mirror":success = session.equip_item("mirror_charm")
		"allocate_stat":success = session.allocate_stat(str(value),adventure_menu.allocation_amount)
		"distribute_stats":
			var selected: Array=[]
			for key in ["vitality","strength","toughness","dexterity"]:
				if key in adventure_menu.allocation_stats:selected.append(key)
			success=session.distribute_stats(selected)
		"select_pet":success = session.select_pet(int(value))
		"rename_pet":success = session.rename_pet(int(value),adventure_menu.name_edit.text)
		"accept_quest":success = at_villager and session.accept_quest()
		"claim_quest":success = at_villager and session.claim_quest()
		"heal":success = at_villager and session.heal()
		"save":success = checkpoint()
		"mute":toggle_mute(); success = true
	if success:
		checkpoint()
		note = "已完成。"
		if action=="claim_quest":note = "委托完成！获得石币、经验与回复药。"
		elif action=="heal":note = "你与伙伴恢复了体力。"
		elif action=="accept_quest":note = "委托已接受，出发去村外吧！"
	else:note = "现在无法这样做，请检查条件、石币或数量。"
	adventure_menu.refresh(note)
	play_ui_sound(201)

func load_profile() -> bool:
	if session.load_game(save_path):return true
	# Never overwrite an unreadable save by autosaving a fresh profile.
	profile_persistence = false
	last_adventure_message = "存档未能读取；现以临时旅程运行，原文件保留。"
	return false

func refresh_riding() -> void:
	if not is_instance_valid(player): return
	var profile: Dictionary = session.snapshot()
	var index := int(profile.get("ride_pet",-1))
	var composite := -1
	if index >= 0 and index < profile.pets.size():
		composite = preload("res://scripts/riding.gd").composite(str(profile.get("character_id","100000")),int(profile.pets[index].sprite))
	player.mounted_character_id = str(composite) if composite >= 0 else ""

func dev_toggle_riding() -> void:
	if paused_input or moving or area_transition_busy or not session.has_method("mount_pet"): return
	var profile: Dictionary = session.snapshot()
	if int(profile.get("ride_pet",-1)) >= 0:
		session.mount_pet(-1)
		message.text = "下骑。"
	else:
		var index := -1
		for i in range(profile.pets.size()):
			if int(profile.pets[i].sprite) == 100330:
				index = i
				break
		if index < 0:
			message.text = "先领取测试伙伴，再骑乘金虎。"
			return
		var selected_as_fighter := int(profile.active_pet) == index
		var candidate: Dictionary = profile.duplicate(true)
		if selected_as_fighter: candidate.active_pet = -1
		var reason := preload("res://scripts/riding.gd").can_mount(candidate,index)
		if not reason.is_empty():
			message.text = reason
			refresh_companion()
			return
		if selected_as_fighter: session.select_pet(-1)
		if not session.mount_pet(index): return
		message.text = "骑乘金虎。"
	refresh_companion()
	play_click()
	checkpoint()

func set_clone_squad_enabled(enabled:bool)->void:
	session.clone_squad_enabled=enabled
	if is_instance_valid(clone_button):clone_button.set_pressed_no_signal(enabled)
