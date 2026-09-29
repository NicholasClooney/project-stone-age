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
const GameMenus = preload("res://scripts/game/game_menus.gd")
var _menus
const GameUi = preload("res://scripts/game/game_ui.gd")
var _ui
const GameStartup = preload("res://scripts/game/game_startup.gd")
var _startup
const GameBattle = preload("res://scripts/game/game_battle.gd")
var _battle
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
	_menus = GameMenus.new(self)
	_ui = GameUi.new(self)
	_startup = GameStartup.new(self)
	_battle = GameBattle.new(self)
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


var _dev_callback: JavaScriptObject


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

# ---- battles (scripts/game/game_battle.gd) ----
func begin_battle(boss: bool = false, enemy_count: int = 0) -> bool:return _battle.begin_battle(boss,enemy_count)
func begin_wild_battle() -> bool:return _battle.begin_wild_battle()
func _on_encounter_reply(reply: Dictionary) -> void:_battle._on_encounter_reply(reply)
func open_battle_config(config: Dictionary) -> bool:return _battle.open_battle_config(config)
func present_battle_start(battle_state: Dictionary) -> bool:return _battle.present_battle_start(battle_state)
func battle_action(action: String) -> void:_battle.battle_action(action)
func present_battle_turn(battle_state: Dictionary) -> void:_battle.present_battle_turn(battle_state)
func return_from_battle() -> void:_battle.return_from_battle()
func present_battle_close(outcome: String) -> void:_battle.present_battle_close(outcome)
func dev_encounter() -> void:_battle.dev_encounter()

# ---- startup and web downloads (scripts/game/game_startup.gd) ----
func await_packs(packs: Array, label: String) -> bool:return await _startup.await_packs(packs,label)
func pet_packs() -> Array:return _startup.pet_packs()
func _asset_pack_url() -> String:return _startup._asset_pack_url()
func _download_core() -> bool:return await _startup._download_core()
func _download_start_area() -> bool:return await _startup._download_start_area()
func _build_waiting_screen() -> void:_startup._build_waiting_screen()
func _show_startup_error(text_value: String) -> void:_startup._show_startup_error(text_value)

# ---- building the interface (scripts/game/game_ui.gd) ----
func box(color: Color, border: Color) -> StyleBoxFlat:return _ui.box(color,border)
func text(value: String, size: int = 15) -> Label:return _ui.text(value,size)
func button(value: String, callback: Callable) -> Button:return _ui.button(value,callback)
func build_ui() -> void:_ui.build_ui()
func refresh_map_ui() -> void:_ui.refresh_map_ui()
func _panel_open() -> bool:return _ui._panel_open()
func update_adventure_hint() -> void:_ui.update_adventure_hint()

# ---- NPC and adventure menus (scripts/game/game_menus.gd) ----
func setup_npc() -> void:_menus.setup_npc()
func in_talk_range(point: Vector2i) -> bool:return _menus.in_talk_range(point)
func open_dialogue() -> void:_menus.open_dialogue()
func close_dialogue() -> void:_menus.close_dialogue()
func show_adventure_menu(kind: String) -> void:_menus.show_adventure_menu(kind)
func close_adventure_menu() -> void:_menus.close_adventure_menu()
func perform_adventure_action(action: String, value: Variant = null) -> void:_menus.perform_adventure_action(action,value)
