extends Node2D
class_name GameScene

const LegacyActor = preload("res://scripts/legacy_actor.gd")
const Backend = preload("res://server/backend.gd")
const LocalLink = preload("res://network/local_link.gd")
const WsLink = preload("res://network/ws_link.gd")
const EncounterCatalog = preload("res://server/encounter_catalog.gd")
const AssetPacks = preload("res://scripts/asset_packs.gd")
const WaitingScreen = preload("res://scripts/waiting_screen.gd")
const TroopArt = preload("res://server/troop_art.gd")
## Behaviour split out of this script (see docs/technical/game-scripts.md);
## each helper is created first in _init and reaches the state through `game.`.
const GamePanels = preload("res://scripts/game/game_panels.gd")
var _panels
const GameAutomation = preload("res://scripts/game/game_automation.gd")
var _automation
const GameDevice = preload("res://scripts/game/game_device.gd")
var _device
const GameAudio = preload("res://scripts/game/game_audio.gd")
var _audio
const GameRemote = preload("res://scripts/game/game_remote.gd")
var _remote

## Resolves when AssetPacks finishes one ensure() call.
class PackWaiter extends RefCounted:
	signal done
	var finished := false
	var ok := false
	func finish(result: bool) -> void:
		ok = result
		finished = true
		done.emit()
const ClientState = preload("res://network/client_state.gd")
const SessionClient = preload("res://network/session_client.gd")
const BattleClient = preload("res://network/battle_client.gd")
const AdventureMenu = preload("res://scripts/adventure_menu.gd")
const PetFollower = preload("res://scripts/pet_follower.gd")
const BattleView = preload("res://scripts/battle_view.gd")
const WorldCatalog = preload("res://scripts/world_catalog.gd")
const Riding = preload("res://scripts/riding.gd")
var world_catalog = WorldCatalog.new()
var travel_router: Node
var world_travel: Node
var props: Node
var random_encounters := true
var last_encounter_error := ""
## Authority lives behind the link. In-process these expose its encounter
## content and RNG to developer tools and tests; a remote client reads the same
## content from its own copy and never rolls.
var _content_catalog
var encounter_catalog:
	get:
		if link.is_local():return link.backend.encounter_catalog
		if _content_catalog==null:_content_catalog = EncounterCatalog.new()
		return _content_catalog
var encounter_rng: RandomNumberGenerator:
	get:return link.backend.encounter_rng if link.is_local() else null
## Set before instantiating to play against a remote backend (tests, tools).
static var server_url_override := ""
var remote_url := ""
var _offline_profile: Dictionary = {}
var _offline_battles := 0
## Remote play: covers the game and blocks input whenever the backend is unreachable.
var link_overlay: Control
var _link_backdrop: Control
var _link_status: Label
## Several devices can drive one backend. This device's reports carry its id;
## another device's walk arrives as a position event and is mirrored here
## without rerunning arrival rules (encounters, map links), which the walking
## device already ran.
## Persistent UI: the root control and DEV bar, and the DEV buttons that only
## exist on some maps (replaced by refresh_map_ui on every map change).
var ui_root: Control
var dev_bar: HFlowContainer
var _client_id := "%x-%x" % [randi(),Time.get_ticks_usec()]
var _follow: Array = []
var _following_step := false
var _followed: Array = []
var asset_packs: Node
var gamepad: Node
## Web build: full-screen waiting room while blocking packs download.
var waiting_screen: CanvasLayer
var arrival_lock := Vector2i(-1,-1)
var _presented_key := ""
var _ui_stale := false
## When a key was last pressed in a text field; see _typing_in.
var _last_typing_msec := -100000
const TYPING_GRACE_MSEC := 2000
## Redraws while automation runs are spaced out so a panel's buttons survive a click.
const UI_REFRESH_MSEC := 400
var _ui_refreshed_msec := -100000
var _companion_key: Array = []
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
var backend
var link
var state
var session
var battle_session
var field_steps := 0
var battle_sounds: Dictionary = {}
var wilderness_music: AudioStream
var village_music: AudioStream
var area_music: AudioStream
var changelog_menu: Control
## Automation settings belong to the character profile (automation_settings,
## owned by the backend); windows read them through automation_settings().
const AutomationSettings = preload("res://scripts/automation_settings.gd")
## This device's battle playback speed (viewer.cfg); 0 until the player applies one.
var battle_speed := -1.0
## Automation windows with control changes not yet sent to the backend.
var _settings_dirty: Array = []
var _settings_dirty_msec := 0
const SETTINGS_SEND_MSEC := 500
var _automation_settings_json := ""
var training_helper: Control
var pet_workflow: Node
var pet_hunt_menu: Control
var dev_gm_menu: Control
var dev_map_overview: Control
var pet_training: Control
## 电台 (scripts/radio.gd) and its window; the radio plays through `music`.
var radio: Node
var radio_panel: Control
## Web only: keeps sound alive across system audio interruptions (web_audio.gd).
var web_audio: Node
var adventure_menu: Control
var profile_persistence := true:
	set(value):
		profile_persistence = value
		_sync_persistence()
var area_transition_busy := false
var dev_blink_mode := false
var travel_landing: RefCounted
var leveling_destinations: Control
var clone_button: Button
var map_transition: CanvasLayer
var save_path := "user://single-player.json":
	set(value):
		save_path = value
		_sync_persistence()
var pet_follower: Node2D
var pet_trail: Array[Vector2i] = []
var adventure_hint: Label
var save_elapsed := 0.0
var mvp_manifest: Dictionary = {}
var last_adventure_message := ""
var data: Dictionary
## Map art by image id, loaded when first drawn and kept across map changes
## (maps share most tiles). Cleared on a map change once it grows past
## TEXTURE_CACHE_LIMIT, so memory stays bounded on the web client.
var textures: Dictionary = {}
const TEXTURE_CACHE_LIMIT := 4000
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
## Device settings (viewer.cfg, see restore_device_settings): muted is the
## music switch (M), effects_on the sound effects, volume the music volume.
var muted := false
var volume := 0.55
var effects_on := true
## Sound settings changed (M, 设置, the 音乐 window): open controls follow.
signal sound_changed
var coordinates: Label
var message: Label
## 设置 (scripts/settings_menu.gd); help points at it for the gamepad and
## callers that pause the field while it is open.
var settings_menu: PanelContainer
var help: PanelContainer
var marker: Node2D
var marker_cell := Vector2i(-1,-1)
var character_index := 0
var character_catalog: Dictionary = {}
const SheetFrames = preload("res://scripts/sheet_frames.gd")
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

func _init() -> void:
	_panels = GamePanels.new(self)
	_automation = GameAutomation.new(self)
	_device = GameDevice.new(self)
	_audio = GameAudio.new(self)
	_remote = GameRemote.new(self)
	remote_url = _server_url()
	state = ClientState.new()
	if remote_url.is_empty():
		backend = Backend.new()
		# Owned from construction so a game freed before entering the tree frees it too.
		add_child(backend)
		# In-process, the game's frame loop drives automation through its controls.
		# (set_process(false) would not stick: Godot re-enables _process on ready.)
		backend.automation.auto_tick = false
		link = LocalLink.new(backend)
	else:
		link = WsLink.new(remote_url)
	link.message.connect(state.apply)
	session = SessionClient.new(link,state)
	battle_session = BattleClient.new(link,state)
	if link.is_local():state.apply(link.request({"type":"hello","protocol":Backend.PROTOCOL}).snapshot)
	link.message.connect(_on_backend_message)

func _sync_persistence() -> void:
	if backend!=null:backend.save_path = save_path if profile_persistence else ""

## Resync after a test or tool changed authority internals directly.
func sync_state() -> void:
	state.apply(link.request({"type":"snapshot"}).snapshot)

func _ready() -> void:
	_sync_persistence()
	preload("res://scripts/legacy_cursor.gd").install()
	marker = preload("res://scripts/legacy_grid_cursor.gd").new()
	marker.world = self
	add_child(marker)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	configure_input()
	if "--script" in OS.get_cmdline_args():profile_persistence = false
	gamepad = preload("res://scripts/gamepad.gd").new()
	gamepad.configure(self)
	add_child(gamepad)
	asset_packs = AssetPacks.new()
	add_child(asset_packs)
	var pack_url := _asset_pack_url()
	if not pack_url.is_empty():
		asset_packs.configure(pack_url)
		_build_waiting_screen()
		if not await _download_core():
			_show_startup_error("素材索引或核心包下载失败，请检查与 MacBook 的连接后刷新页面。")
			return
	if FileAccess.file_exists("res://assets/legacy/mvp/manifest.json"):
		mvp_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/mvp/manifest.json"))
	if link.is_local() and profile_persistence and (FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak")):
		load_profile()
	if not FileAccess.file_exists("res://assets/legacy/samgir.json") or not FileAccess.file_exists("res://assets/legacy/ui/manifest.json") or world_catalog.maps.is_empty():
		load_error = "Original client assets have not been imported.\nSee README.md → Import original resources."
		var error_label := Label.new()
		error_label.text = load_error
		error_label.position = Vector2(50,100)
		add_child(error_label)
		return
	if not link.is_local():
		if is_instance_valid(waiting_screen):waiting_screen.hold("正在连接服务器…")
		await _connect_remote()
	if asset_packs.enabled and not await _download_start_area():
		_show_startup_error("起始地图素材下载失败，请检查与 MacBook 的连接后刷新页面。")
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
	if profile_persistence or not link.is_local():
		restore_location()
		if FileAccess.file_exists("res://assets/legacy/pets/catalog.json") and session.claim_default_companions():
			checkpoint()
			message.text = "伙伴已加入：蓝人龙、金虎、红暴龙。打开宠物菜单查看。"
	refresh_companion()
	report_position()
	# A remote backend may already be mid-battle (another device, or a reload).
	if state.battle_open and not bool(state.automation.get("compact",false)):present_battle_start(state.battle)
	resume_automation_view()
	# This device's radio, if it was left on (tests without a save keep scene music).
	if profile_persistence or not link.is_local():
		radio.restore()
		restore_device_settings()
	if is_instance_valid(waiting_screen):
		waiting_screen.release()
		waiting_screen.enter_game()
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
	if character_catalog.is_empty() and FileAccess.file_exists("res://assets/legacy/characters/catalog.json"):
		character_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/characters/catalog.json"))
	if not character_catalog.is_empty():
		data.characters.merge(character_catalog.characters,true)
		data.images.merge(character_catalog.images,true)
	terrain = LegacyGround.new()
	terrain.world = self
	terrain.fill(data.ground,int(data.width),int(data.height))
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
	# While the map is built nothing else blocks a cell (the resident and the
	# travel overlay are placed afterwards), so only the map's own flags count.
	var width := int(data.width)
	var blocked: Array = data.blocked
	for index in range(blocked.size()):
		if blocked[index]!=0:navigation.set_point_solid(Vector2i(index%width,index/width))
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
	var needed := area_packs(map_id)
	if not asset_packs.is_ready(needed):
		_load_area_after_download(map_id,destination,needed)
		return true
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
	var previous_zoom: Vector2 = camera.zoom
	clear_input()
	# Residents and their dialogue belong to the old map.
	if dialogue.visible:close_dialogue()
	if is_instance_valid(world_travel) and is_instance_valid(world_travel.overlay):world_travel.overlay.queue_free()
	for node in [terrain,actors]:
		remove_child(node)
		node.queue_free()
	data = next_data
	if textures.size() > TEXTURE_CACHE_LIMIT:textures.clear()
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
	paused_input = _panel_open() or automation_minimized()
	marker_cell = Vector2i(-1,-1)
	field_steps = 0
	build_world()
	camera.zoom = previous_zoom
	refresh_map_ui()
	if [int(data.map_id),cell]!=_followed:link.request({"type":"report_position","map_id":int(data.map_id),"cell":[cell.x,cell.y],"map_changed":true,"client":_client_id},_on_map_reported)
	camera.reset_smoothing()
	area_music = exploration_music()
	set_music(area_music)
	queue_redraw()
	refresh_companion()
	checkpoint()
	for link_info in world_catalog.links(map_id).values():asset_packs.prefetch(area_packs(int(link_info.to_map)))
	return true

## Packs a map needs: its data, tiles, residents and music.
func area_packs(map_id: int) -> Array:
	var packs: Array = asset_packs.map_packs(map_id).duplicate()
	var music_path := str(world_catalog.info(map_id).get("music",""))
	if not music_path.is_empty():packs.append(asset_packs.file_pack("res://assets/legacy/"+music_path))
	return packs

func _load_area_after_download(map_id: int, destination: Vector2i, needed: Array) -> void:
	clear_input()
	paused_input = true
	var ok := await await_packs(needed,"地图 %s" % str(world_catalog.info(map_id).get("name",map_id)))
	paused_input = false
	if ok:load_area_id(map_id,destination)
	elif is_instance_valid(message):message.text = "地图素材下载失败，请稍后再试。"

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
	report_position()
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
		var can_battle := not moving and not paused_input and not area_transition_busy and is_instance_valid(battle_view) and not battle_view.visible
		last_encounter_error=""
		return bool(link.request({"type":"field_step","map_id":int(data.map_id),"cell":[cell.x,cell.y],"encounter":can_battle},_on_encounter_reply).get("battle",false))
	return false

func begin_battle(boss: bool = false, enemy_count: int = 0) -> bool:
	if moving or paused_input or not world_catalog.field(int(data.map_id)) or battle_view==null:
		return false
	if not FileAccess.file_exists("res://assets/legacy/battle/manifest.json"):
		message.text = "Import original battle assets first; see README.md."
		return false
	var reply: Dictionary = link.request({"type":"begin_battle","boss":boss,"enemy_count":enemy_count})
	return bool(reply.ok) or bool(reply.get("pending",false))

func begin_wild_battle() -> bool:
	last_encounter_error=""
	if moving or paused_input or area_transition_busy or battle_view==null or battle_view.visible:return false
	if not world_catalog.field(int(data.map_id)):return false
	var reply: Dictionary = link.request({"type":"wild_encounter","map_id":int(data.map_id),"cell":[cell.x,cell.y]},_on_encounter_reply)
	return bool(reply.ok) or bool(reply.get("pending",false))

func _on_encounter_reply(reply: Dictionary) -> void:
	var skipped := str(reply.get("skipped",""))
	if skipped.is_empty():return
	last_encounter_error=skipped
	if skipped=="data":
		message.text = "这里没有可用的普通野外遇敌。" if str(reply.reason).is_empty() else "此区域的原版遇敌数据或条件尚未完整支持，暂时跳过。"
	elif skipped=="art":
		message.text = "本次敌群的原版动画缺失或损坏，已跳过；未替换敌人。"

func open_battle_config(config: Dictionary) -> bool:
	if config.is_empty():return false
	var reply: Dictionary = link.request({"type":"open_battle","config":config})
	return bool(reply.ok) or bool(reply.get("pending",false))

## Presentation for a battle the backend has just opened.
func present_battle_start(battle_state: Dictionary) -> bool:
	if asset_packs.enabled and not (is_instance_valid(training_helper) and training_helper.compact_active):
		var needed := battle_packs(battle_state)
		if not asset_packs.is_ready(needed):
			clear_input()
			paused_input = true
			var battle_id := str(battle_state.get("battle_id",""))
			asset_packs.ensure(needed,func(ok: bool):
				if ok and state.battle_open and str(state.battle.get("battle_id",""))==battle_id and not battle_view.visible:present_battle_start(state.battle)
				elif not ok and is_instance_valid(message):message.text = "战斗素材下载失败，战斗仍在进行；稍后重试。","战斗素材")
			return true
	if is_instance_valid(travel_router):travel_router.cancel("战斗中断了自动寻路，请重新选择目的地。")
	clear_input()
	paused_input = true
	player.set_action(3)
	help.hide()
	classic_hud.map_panel.hide()
	if is_instance_valid(training_helper) and training_helper.compact_active:
		return true
	# Pets or storage opened beside minimized automation give way to its battle.
	if adventure_menu.visible:adventure_menu.hide()
	battle_view.open_battle(battle_state)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/battle/manifest.json"))
	set_music(load("res://assets/legacy/battle/"+str(manifest.audio.bgm)))
	play_battle_sound(215)
	return true

func battle_action(action: String) -> void:
	if not battle_view.visible and not (is_instance_valid(training_helper) and training_helper.compact_active):
		return
	var target: int = int(battle_view.get("player_target"))
	battle_session.set_pet_target(int(battle_view.get("pet_target")))
	var skill_id: int = int(battle_view.get("selected_pet_skill"))
	if skill_id > 0 and battle_session.snapshot().pet_command == "skill":
		battle_session.set_pet_skill(skill_id)
	if action=="developer_escape":battle_session.developer_escape()
	else:battle_session.submit_action(action,target,int(battle_view.get("switch_pet_index")))

## Presentation for one resolved turn, from the player or a backend runner.
func present_battle_turn(battle_state: Dictionary) -> void:
	if battle_state.get("settled",false):checkpoint()
	if is_instance_valid(training_helper) and training_helper.compact_active:return
	if not is_instance_valid(battle_view) or not battle_view.visible:return
	battle_view.show_state(battle_state)
	play_ui_sound(217 if ui_sounds.has(217) else 201)

func return_from_battle() -> void:
	var compact_battle: bool=is_instance_valid(training_helper) and training_helper.compact_active
	if (not battle_view.visible and not compact_battle) or battle_session.snapshot().active or (not compact_battle and battle_view.is_animating()):
		return
	link.request({"type":"battle_close"})

## Presentation after the backend closed a battle.
func present_battle_close(outcome: String) -> void:
	battle_view.close_battle()
	clear_input()
	paused_input = automation_minimized()
	field_steps = 0
	if outcome!="defeat":set_music(exploration_music())
	play_ui_sound(203)
	if outcome=="defeat":
		switch_area(false,SPAWN)
	refresh_companion()
	checkpoint()
	# A running automation keeps the map locked between its battles.
	if bool(state.automation.get("running",false)):paused_input = true

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

func texture(ident: String) -> Texture2D:
	var cached: Texture2D = textures.get(ident)
	if cached==null:
		cached = load("res://assets/legacy/images/"+ident+".png")
		textures[ident] = cached
	return cached

## A walking frame: player characters' frames come from their sprite sheet
## (characters/sheets, docs/technical/sprite-sheets.md); map residents and
## anything not packed are single PNGs.
func character_frame(character: String, ident: int) -> Texture2D:
	var sheets: Dictionary = character_catalog.get("sheets",{})
	if sheets.get(character,{}).get("frames",{}).has(str(ident)):
		var frame: Texture2D = SheetFrames.texture("res://assets/legacy/characters/",sheets,character,ident)
		if frame != null or not ResourceLoader.exists("res://assets/legacy/images/%d.png" % ident):return frame
	return texture(str(ident))

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
	_followed = []
	_follow = []
	player.set_action(4)
	return true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and get_viewport().gui_get_focus_owner() is LineEdit:
		_last_typing_msec = Time.get_ticks_msec()
	if event.is_action_pressed("ui_cancel") and is_instance_valid(pet_workflow) and pet_workflow.phase=="restart":
		pet_workflow.stop_cycle("已手动停止");get_viewport().set_input_as_handled();return
	if data.is_empty():
		return
	if link_blocked():
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:get_viewport().set_input_as_handled()
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
	elif event.is_action_pressed("help"):
		if settings_menu.visible and settings_menu.page=="help":settings_menu.close_menu()
		elif not dialogue.visible:settings_menu.open_menu("help")
	elif event.is_action_pressed("ui_cancel"):
		settings_menu.close_menu()
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
			zoom_by(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(-ZOOM_STEP)

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
	if not link.is_local():
		link.poll(delta)
		_update_link_overlay()
		if link_blocked():return
	if area_transition_busy:return
	if data.is_empty():
		return
	if not _settings_dirty.is_empty() and Time.get_ticks_msec()-_settings_dirty_msec>=SETTINGS_SEND_MSEC:flush_automation_settings()
	if _ui_stale and not _ui_refresh_held():
		_ui_refreshed_msec = Time.get_ticks_msec()
		_ui_stale = refresh_open_panels()
	if moving:
		var d := target_cell-from_cell
		var distance_scale := sqrt(2.0) if d.x != 0 and d.y != 0 else 1.0
		step_progress = minf(1,step_progress+delta/(STEP_TIME*distance_scale))
		logical_position = Vector2(from_cell).lerp(Vector2(target_cell),step_progress)
		player.position = project(logical_position)
		if step_progress>=1:
			cell = target_cell
			moving = false
			if _following_step:
				_following_step = false
				pet_trail.append(cell)
				while pet_trail.size()>3:pet_trail.pop_front()
			elif handle_arrival():
				return
	if not moving and not (held.is_empty() and path.is_empty() and _step_follow()):
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
	acknowledge_presentation()
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
	report_position()
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
	report_position()
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
	if not asset_packs.is_ready([asset_packs.character_pack(id)]):
		asset_packs.ensure([asset_packs.character_pack(id)],func(ok: bool):if ok:change_character(id),"角色")
		return
	if not data.characters.has(id) or not session.set_character(id):return
	player.character_id = id
	refresh_riding()
	player.current_image = -1
	player.elapsed = 0.0
	message.text = "Original character %s" % id
	play_click()
	checkpoint()

## Saved only once restore_device_settings ran, so a test that presses M or
## zooms never writes this device's real viewer.cfg.
var _device_settings_live := false

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

## Built once. A map change keeps every panel (and what it shows) and only
## refreshes the parts that belong to the map: see refresh_map_ui().
func build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	var root := Control.new()
	ui_root = root
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
	var dev := HFlowContainer.new()
	dev_bar = dev
	dev.size.x = get_viewport_rect().size.x-24
	dev.position = Vector2(12,85)
	dev.add_theme_constant_override("separation",5)
	root.add_child(dev)
	character_selection = preload("res://scripts/character_selection.gd").new()
	character_selection.configure(self)
	root.add_child(character_selection)
	travel_landing=preload("res://scripts/travel_landing.gd").new()
	travel_landing.configure(self)
	leveling_destinations=preload("res://scripts/leveling_destinations.gd").new()
	leveling_destinations.configure(self);root.add_child(leveling_destinations)
	var overview_button := button("地图导航",func(): dev_map_overview.open_map())
	overview_button.name = "DevMapOverview"
	overview_button.tooltip_text = "按地图查看和传送"
	dev.add_child(overview_button)
	var training_travel:=button("刷怪传送",leveling_destinations.open_menu)
	training_travel.name="DevTrainingTravel";training_travel.tooltip_text="按练级点传送到原版刷怪位置";dev.add_child(training_travel)
	pet_hunt_menu = preload("res://scripts/pet_hunt_menu.gd").new()
	pet_hunt_menu.configure(self)
	root.add_child(pet_hunt_menu)
	training_helper = preload("res://scripts/training_helper.gd").new()
	training_helper.configure(self)
	root.add_child(training_helper)
	# 五人镜像队 lives in the 自动练级 window beside its other battle options.
	clone_button=CheckBox.new()
	clone_button.name="CloneSquadToggle";clone_button.text="五人镜像队"
	clone_button.focus_mode=Control.FOCUS_NONE
	clone_button.position=Vector2(560,164)
	clone_button.button_pressed=session.clone_squad_enabled
	clone_button.tooltip_text="复制当前出战宠与骑乘状态，本体优先，四组人宠自动跟随目标；经验仍归本体和真实宠物。下一场生效。"
	clone_button.toggled.connect(func(enabled):
		if not battle_session.snapshot().active and not area_transition_busy:set_clone_squad_enabled(enabled)
		else:clone_button.set_pressed_no_signal(session.clone_squad_enabled))
	training_helper.panel.add_child(clone_button)
	pet_workflow = preload("res://scripts/pet_workflow.gd").new()
	pet_workflow.configure(self)
	root.add_child(pet_workflow)
	var training := button("自动练级",training_helper.open_menu)
	training.name="DevTraining"
	dev.add_child(training)
	var hunt := button("自动抓极品",pet_hunt_menu.open_menu)
	hunt.name = "DevPetHunt"
	dev.add_child(hunt)
	radio = preload("res://scripts/radio.gd").new()
	radio.name = "Radio"
	add_child(radio)
	radio.configure(self)
	web_audio = preload("res://scripts/web_audio.gd").new()
	web_audio.name = "WebAudio"
	add_child(web_audio)
	web_audio.configure(self)
	radio_panel = preload("res://scripts/radio_panel.gd").new()
	root.add_child(radio_panel)
	radio_panel.configure(self,radio)
	var music_button := button("音乐",func():
		if radio_panel.visible:radio_panel.close_panel()
		else:radio_panel.open_panel())
	music_button.name = "DevMusic"
	music_button.tooltip_text = "原版配乐电台、收藏和歌单，声音开关和音乐音量"
	dev.add_child(music_button)
	changelog_menu = preload("res://scripts/changelog_menu.gd").new()
	changelog_menu.configure(self)
	root.add_child(changelog_menu)
	settings_menu = preload("res://scripts/settings_menu.gd").new()
	root.add_child(settings_menu)
	settings_menu.configure(self)
	help = settings_menu
	var settings_button := button("设置",func():
		if settings_menu.visible:settings_menu.close_menu()
		elif not dialogue.visible:settings_menu.open_menu())
	settings_button.name = "DevSettings"
	settings_button.tooltip_text = "画面、声音、角色、瞬移、存档、更新日志和操作说明"
	dev.add_child(settings_button)
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
	battle_view.playback_speed=playback_speed()
	battle_view.action_requested.connect(battle_action)
	battle_view.return_requested.connect(return_from_battle)
	battle_view.sound_requested.connect(play_battle_sound)
	battle_view.capture_music_requested.connect(func(celebrating: bool):
		set_music(load("res://assets/legacy/battle/audio/sabgm_s0.wav") if celebrating else load("res://assets/legacy/battle/audio/sabgm_b0.wav")))
	battle_view.pet_command_requested.connect(func(command: String):
		if command == "skill": battle_session.set_pet_skill(int(battle_view.get("selected_pet_skill")))
		else: battle_session.set_pet_command(command))
	refresh_map_ui()

## The map-specific parts of the UI: the residents with their travel
## dialogue, and the HUD's map window.
func refresh_map_ui() -> void:
	world_travel = preload("res://scripts/world_travel.gd").new()
	actors.add_child(world_travel)
	var residents: Array = []
	for entry in world_catalog.residents:
		if int(entry.map_id)==int(data.map_id) and Vector2i(entry.cell[0],entry.cell[1])!=npc_cell:residents.append(entry)
	world_travel.setup(self,ui_root,residents)
	if is_instance_valid(classic_hud) and classic_hud.is_node_ready():classic_hud.refresh_map()

## Whether a panel that stops walking is open; a map change keeps panels open.
## A minimized automation window is hidden, so it does not count; see
## automation_minimized() for how it still holds the character in place.
func _panel_open() -> bool:
	for node in [leveling_destinations,training_helper,pet_hunt_menu,changelog_menu,character_selection,dev_gm_menu,dev_map_overview,pet_training,adventure_menu,help]:
		if is_instance_valid(node) and node.visible:return true
	return false

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

## Places the character at startup: where a running backend already has it
## (another device or automation may have moved it since the last save),
## else the saved location. Arriving there is not travel, so it is not
## reported as a map change, which would stop running automation.
func restore_location() -> void:
	var location: Dictionary = session.snapshot().location
	var map_id := int(location.map_id)
	var point := Vector2i(int(location.x),int(location.y))
	if map_id==100 and not world_catalog.maps.has("100"):point -= Vector2i(592,448)
	var live: Dictionary = state.automation.get("position",{})
	if not link.is_local() and int(live.get("map_id",-1))>=0:
		map_id = int(live.map_id)
		point = Vector2i(int(live.cell[0]),int(live.cell[1]))
	_followed = [map_id,point]
	if not load_area_id(map_id,point):
		load_area_id(1000,SPAWN)

## Per-device view choices (not game state, so not in the save or backend):
## which automation windows this device keeps minimized, so a reload comes
## back the same way. Tests run without persistence and never touch the file.
const VIEWER_PREFS := "user://viewer.cfg"
var viewer_prefs_path := ""

# Copies the on-disk save beside itself before an irreversible change; returns
# the backup path or "" when there is no save file.
func backup_save(tag: String) -> String:
	if not FileAccess.file_exists(save_path):return ""
	var now:=Time.get_datetime_dict_from_system()
	var stamp:="%04d%02d%02d-%02d%02d%02d"%[now.year,now.month,now.day,now.hour,now.minute,now.second]
	var target:="%s.before-%s-%s.json"%[save_path.get_basename(),tag,stamp]
	var serial:=1
	while FileAccess.file_exists(target):
		serial+=1;target="%s.before-%s-%s-%d.json"%[save_path.get_basename(),tag,stamp,serial]
	return target if DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),ProjectSettings.globalize_path(target))==OK else ""

func release_pets(ids: Array) -> Dictionary:
	var backup:=backup_save("release") if profile_persistence else ""
	var result: Dictionary=session.release_pets(ids)
	result.backup=backup
	if int(result.released)>0:refresh_companion();checkpoint()
	return result

func checkpoint() -> bool:
	if battle_session.snapshot().active:return false
	var point := display_cell()
	save_elapsed = 0
	var reply: Dictionary = link.request({"type":"checkpoint","map_id":int(data.map_id),"x":point.x,"y":point.y},func(result: Dictionary):
		if str(result.get("reason",""))=="save_failed":last_adventure_message = "保存失败，请检查存储空间。")
	return bool(reply.ok) or bool(reply.get("pending",false))

func refresh_companion() -> void:
	var profile_now: Dictionary = session.snapshot()
	var wanted: Array = []
	if int(profile_now.active_pet)>=0 and int(profile_now.active_pet)<profile_now.pets.size():wanted.append(asset_packs.sprite_pack(profile_now.pets[int(profile_now.active_pet)].sprite))
	if not asset_packs.is_ready(wanted):
		asset_packs.ensure(wanted,func(ok: bool):if ok and is_instance_valid(player):refresh_companion())
		return
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
	var objective := "找村民聊聊，准备你的第一次冒险。"
	if q.claimed:objective = "委托完成！继续培养与收集你的伙伴。"
	elif session.can_fight_boss():objective = "准备好后，在村外点击 DEV「挑战强敌」。"
	elif q.boss_defeated:objective = "回到村民身边领取报酬。"
	elif q.accepted:objective = "村外的伙伴：胜利 %d/3 · 捕获伙伴 %d/1" % [mini(3,int(q.wins)),mini(1,profile.pets.size())]
	adventure_hint.text = "Lv.%d  体力 %d/%d  石币 %d   %s" % [profile.player.level,profile.player.hp,profile.player.max_hp,profile.player.gold,objective]
	if not last_adventure_message.is_empty():adventure_hint.text += "\n"+last_adventure_message

func show_adventure_menu(kind: String) -> void:
	# The old 系统 page is 设置 now (settings_menu.gd).
	if kind=="system":
		if settings_menu.visible:settings_menu.close_menu()
		else:settings_menu.open_menu()
		return
	if is_instance_valid(character_selection) and character_selection.visible:return
	if is_instance_valid(changelog_menu) and changelog_menu.visible:return
	if is_instance_valid(dev_gm_menu) and dev_gm_menu.visible:return
	if is_instance_valid(dev_map_overview) and dev_map_overview.visible:return
	if is_instance_valid(pet_training) and pet_training.visible:return
	if is_instance_valid(world_travel) and world_travel.overlay.visible:return
	if adventure_menu.visible and adventure_menu.kind == kind:
		close_adventure_menu()
		return
	if battle_view.visible:
		play_battle_sound(220)
		return
	if moving or dialogue.visible or help.visible:return
	if kind=="shop" and (int(data.map_id)!=1002 or not in_talk_range(cell)):return
	if kind=="pets":
		var portraits := pet_packs()
		if not asset_packs.is_ready(portraits):
			asset_packs.ensure(portraits,func(ok: bool):if ok:show_adventure_menu(kind),"宠物图像")
			return
	if kind=="quest" and (int(data.map_id)!=1000 or not in_talk_range(cell)):return
	clear_input()
	paused_input = true
	classic_hud.map_panel.hide()
	adventure_menu.open_menu(kind)
	play_ui_sound(202)

func close_adventure_menu() -> void:
	adventure_menu.hide()
	release_input()
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
		"heal_pets":success = session.heal_carried_pets()
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
	if not link.is_local():return true
	if backend.load_profile(save_path):
		session.grant_pet_care_items()
		return true
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
	if composite >= 0 and not asset_packs.is_ready([asset_packs.riding_pack(composite)]):
		asset_packs.ensure([asset_packs.riding_pack(composite)],func(ok: bool):if ok:refresh_riding())
		return
	player.mounted_character_id = str(composite) if composite >= 0 else ""

## DEV: dismount, or ride the pet selected in the pet window, else the first
## carried pet this character can ride (a battling pet goes to standby first).
func dev_toggle_riding() -> void:
	if paused_input or moving or area_transition_busy or not session.has_method("mount_pet"): return
	var profile: Dictionary = session.snapshot()
	if int(profile.get("ride_pet",-1)) >= 0:
		session.mount_pet(-1)
		message.text = "下骑。"
	else:
		var order: Array = []
		if is_instance_valid(adventure_menu) and adventure_menu.selected_pet >= 0 and adventure_menu.selected_pet < profile.pets.size():
			order.append(adventure_menu.selected_pet)
		for i in range(profile.pets.size()):
			if not order.has(i):order.append(i)
		var index := -1
		var first_reason := ""
		for i in order:
			var candidate: Dictionary = profile.duplicate(true)
			if int(candidate.active_pet) == i: candidate.active_pet = -1
			var reason: String = Riding.can_mount(candidate,i)
			if reason.is_empty():
				index = i
				break
			if first_reason.is_empty() and Riding.composite(str(profile.get("character_id","100000")),int(profile.pets[i].sprite)) >= 0:
				first_reason = str(profile.pets[i].name)+"："+reason
		if index < 0:
			message.text = first_reason if not first_reason.is_empty() else "没有此造型可骑乘的伙伴。可骑乘：%s。" % "、".join(PackedStringArray(Riding.rideable_pets(str(profile.get("character_id","100000"))).map(func(sprite): return Riding.pet_name(sprite))))
			refresh_companion()
			return
		if int(profile.active_pet) == index: session.select_pet(-1)
		if not session.mount_pet(index):
			message.text = session.last_error
			return
		message.text = "骑乘%s。" % str(profile.pets[index].name)
	refresh_companion()
	play_click()
	checkpoint()

## Battle art packs for one battle state; also fixes its background choice.
func battle_packs(battle_state: Dictionary) -> Array:
	var art: Dictionary = battle_view.required_art(battle_state)
	var packs: Array = []
	for ident in art.sprites:packs.append(asset_packs.sprite_pack(ident))
	for ident in art.riding:packs.append(asset_packs.riding_pack(ident))
	for path in art.files:packs.append(asset_packs.file_pack(path))
	return packs

## Sprite packs for every carried and stored pet, for portraits and previews.
func pet_packs() -> Array:
	var packs: Array = []
	var profile_now: Dictionary = session.snapshot()
	for pet in profile_now.pets+profile_now.get("pet_storage",[]):
		var pack: String = asset_packs.sprite_pack(pet.get("sprite",""))
		if not packs.has(pack):packs.append(pack)
	return packs

func await_packs(packs: Array, label: String) -> bool:
	var waiter := PackWaiter.new()
	asset_packs.ensure(packs,waiter.finish,label)
	if not waiter.finished:await waiter.done
	return waiter.ok

## Pack base URL: --asset-packs=URL, the page's ?packs= parameter, or the
## packs/ folder next to a web build's page. Empty when assets ship locally.
func _asset_pack_url() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--asset-packs="):return argument.trim_prefix("--asset-packs=")
	if not OS.has_feature("web"):return ""
	var chosen = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('packs') || ''",true)
	if chosen is String and not chosen.is_empty():return chosen
	var page = JavaScriptBridge.eval("window.location.href.split('?')[0].replace(/[^/]*$/,'')",true)
	return str(page)+"packs/"

func _download_core() -> bool:
	var waiter := PackWaiter.new()
	waiting_screen.hold("正在读取素材索引…")
	asset_packs.load_index(waiter.finish)
	if not waiter.finished:await waiter.done
	if not waiter.ok:return false
	# The waiting screen's own image and music come first, in a tiny pack.
	if await await_packs(["loading"],"等待画面"):waiting_screen.load_art()
	waiting_screen.hold("正在准备素材…")
	if not await await_packs(["core","music-sabgm_t0"],"核心素材"):return false
	# setup_audio() loads every track the MVP manifest names at startup.
	var startup_music: Array = []
	var mvp = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/mvp/manifest.json"))
	if mvp is Dictionary:
		for track in mvp.get("audio",{}).values():startup_music.append(asset_packs.file_pack("res://assets/legacy/mvp/"+str(track)))
	if not await await_packs(startup_music,"音乐"):return false
	# Catalogs read at construction must see the mounted core pack.
	world_catalog = WorldCatalog.new()
	TroopArt.pack_index = asset_packs.index.get("sprites",{})
	return true

func _download_start_area() -> bool:
	var profile_now: Dictionary = session.snapshot()
	var packs: Array = area_packs(1000)
	for pack in area_packs(int(profile_now.get("location",{}).get("map_id",1000))):
		if not packs.has(pack):packs.append(pack)
	packs.append(asset_packs.character_pack(profile_now.get("character_id","100000")))
	waiting_screen.hold("正在准备起始地图…")
	return await await_packs(packs,"起始地图")

## Web only: window.stoneAge mirrors map, cell, connection and pack state
## once a second, for Safari's Web Inspector on another device.
func _publish_web_status() -> void:
	var status := {"map":int(data.get("map_id",-1)),"cell":[cell.x,cell.y],"online":bool(link.get("online")) if not link.is_local() else true,
		"battle":bool(is_instance_valid(battle_view) and battle_view.visible),"mounted":asset_packs._mounted.size(),"pending":asset_packs._queued.size()+asset_packs._active.size(),"downloading":asset_packs._active.values(),"queued":asset_packs._queued,"waiters":asset_packs._waiters.size(),"waiting_screen":is_instance_valid(waiting_screen) and waiting_screen.visible,
		"message":str(message.text) if is_instance_valid(message) else ""}
	JavaScriptBridge.eval("window.stoneAge = %s" % JSON.stringify(status))

var _dev_callback: JavaScriptObject

## Web only: window.stoneAgeDev(name) runs the same actions as the on-screen DEV
## buttons, so a browser session can be driven from the console.
func _install_web_dev_hook() -> void:
	_dev_callback = JavaScriptBridge.create_callback(_on_web_dev)
	JavaScriptBridge.get_interface("window").stoneAgeDev = _dev_callback

func _on_web_dev(arguments: Array) -> void:
	var action: String = str(arguments[0]) if not arguments.is_empty() else ""
	match action:
		"explore":dev_go_adventure()
		"encounter":dev_encounter()
		"village":load_area_id(1000,SPAWN)
		"escape":battle_action("developer_escape")
		"return":return_from_battle()
		"pets":show_adventure_menu("pets")

func _build_waiting_screen() -> void:
	if OS.has_feature("web"):
		_install_web_dev_hook()
		var status_timer := Timer.new()
		status_timer.wait_time = 1.0
		status_timer.autostart = true
		status_timer.timeout.connect(_publish_web_status)
		add_child(status_timer)
	waiting_screen = WaitingScreen.new()
	add_child(waiting_screen)
	waiting_screen.configure(asset_packs,func():return music,func():return -80.0 if muted else linear_to_db(maxf(volume,0.0001)))

func _show_startup_error(text_value: String) -> void:
	if is_instance_valid(waiting_screen):
		waiting_screen.fail(text_value)
		return
	var label := text(text_value,20)
	label.position = Vector2(50,100)
	add_child(label)

# ---- remote play and backend events (scripts/game/game_remote.gd) ----
func _server_url() -> String:return _remote._server_url()
func report_position() -> void:_remote.report_position()
func _step_follow() -> bool:return _remote._step_follow()
func _on_map_reported(reply: Dictionary) -> void:_remote._on_map_reported(reply)
func _connect_remote() -> void:await _remote._connect_remote()
func link_blocked() -> bool:return _remote.link_blocked()
func _update_link_overlay() -> void:_remote._update_link_overlay()
func acknowledge_presentation() -> void:_remote.acknowledge_presentation()
func _on_backend_message(event: Dictionary) -> void:_remote._on_backend_message(event)

# ---- sound (scripts/game/game_audio.gd) ----
func exploration_music() -> AudioStream:return _audio.exploration_music()
func set_music(stream: AudioStream) -> void:_audio.set_music(stream)
func setup_audio() -> void:_audio.setup_audio()
func play_battle_sound(ident: int) -> void:_audio.play_battle_sound(ident)
func play_click() -> void:_audio.play_click()
func play_ui_sound(ident: int) -> void:_audio.play_ui_sound(ident)
func toggle_mute() -> void:_audio.toggle_mute()
func set_music_volume(value: float) -> void:_audio.set_music_volume(value)
func set_effects_on(on: bool) -> void:_audio.set_effects_on(on)
func apply_sound() -> void:_audio.apply_sound()

# ---- this device's settings (scripts/game/game_device.gd) ----
func set_zoom(value: float) -> void:_device.set_zoom(value)
func maximum_zoom_out() -> void:_device.maximum_zoom_out()
func set_blink_mode(on: bool) -> void:_device.set_blink_mode(on)
func zoom_by(step: float) -> void:_device.zoom_by(step)
func _save_device(key: String, value: Variant) -> void:_device._save_device(key,value)
func zoom_farthest() -> void:_device.zoom_farthest()
func restore_device_settings() -> void:_device.restore_device_settings()
func playback_speed() -> float:return _device.playback_speed()
func set_battle_speed(value: float) -> void:_device.set_battle_speed(value)
func viewer_pref(key: String, fallback: Variant = false) -> Variant:return _device.viewer_pref(key,fallback)
func set_viewer_pref(key: String, value: Variant) -> void:_device.set_viewer_pref(key,value)

# ---- automation windows (scripts/game/game_automation.gd) ----
func resume_automation_view() -> void:_automation.resume_automation_view()
func automation_overrides() -> Dictionary:return _automation.automation_overrides()
func automation_settings() -> Dictionary:return _automation.automation_settings()
func stat_filter(template_id: int) -> Dictionary:return _automation.stat_filter(template_id)
func mark_settings_dirty(window: Node) -> void:_automation.mark_settings_dirty(window)
func flush_automation_settings() -> void:_automation.flush_automation_settings()
func _on_automation_settings() -> void:_automation._on_automation_settings()
func _automation_running() -> bool:return _automation._automation_running()
func automation_minimized() -> bool:return _automation.automation_minimized()
func set_clone_squad_enabled(enabled:bool)->void:_automation.set_clone_squad_enabled(enabled)

# ---- panel redraws (scripts/game/game_panels.gd) ----
func refresh_open_panels() -> bool:return _panels.refresh_open_panels()
func _mark_ui_stale() -> void:_panels._mark_ui_stale()
func _ui_refresh_held() -> bool:return _panels._ui_refresh_held()
func release_input() -> void:_panels.release_input()
func rebuild_keeping_scroll(panel: Control) -> void:_panels.rebuild_keeping_scroll(panel)
func capture_scroll(root: Node) -> Array[Vector2i]:return _panels.capture_scroll(root)
func restore_scroll(root: Node, before: Array[Vector2i]) -> void:_panels.restore_scroll(root,before)
func _scroll_areas(root: Node) -> Array[ScrollContainer]:return _panels._scroll_areas(root)
func _typing_in(panel: Control) -> bool:return _panels._typing_in(panel)
