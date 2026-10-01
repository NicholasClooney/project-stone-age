extends Node2D
class_name GameScene
## The game scene: owns every piece of client state (map, character, windows,
## sound, link to the backend) and wires them together. The behaviour lives in
## helpers under scripts/game/, one per area, which reach this state through
## `game.`; the forwarders at the end keep every function other scripts and
## tests call by name. See docs/technical/game-scripts.md.

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
const GameCharacter = preload("res://scripts/game/game_character.gd")
var _character
const GameMovement = preload("res://scripts/game/game_movement.gd")
var _movement
const GameInput = preload("res://scripts/game/game_input.gd")
var _input_events
const GameAreas = preload("res://scripts/game/game_areas.gd")
var _areas
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
const MapFile = preload("res://scripts/map_file.gd")
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
## 登录 (scripts/login_screen.gd) for a server hosting several profiles, and
## whether this login created the character (it then picks its look first).
var login_screen: Control
var new_character := false
## LAN phase 2: the other players on this map (scripts/remote_players.gd) and
## 一般频道 (scripts/chat_panel.gd). Both stay empty without a multi-profile
## server.
var remote_players: Node
var chat_panel: Control
## LAN phase 3: 组队 (scripts/party_panel.gd). A member follows the leader and
## cannot walk on its own (party_locked).
var party_panel: Control
var last_party_event: Dictionary = {}
## Several devices can drive one backend. This device's reports carry its id;
## another device's walk arrives as a position event and is mirrored here
## without rerunning arrival rules (encounters, map links), which the walking
## device already ran.
## Persistent UI: the root control every window hangs from. There is no
## toolbar: our own windows open from 游戏助手, 设置 and shortcuts.
var ui_root: Control
## 游戏助手 (scripts/helper_menu.gd): the list of the windows this project added.
var quest_helper_menu: PanelContainer
var quest_helper_travel: Node
var helper_menu: PanelContainer
## The 游戏助手 button on the field (the only button of ours there).
var helper_button: Button
## 后台搜宠's info block at the top left (scripts/showcase_ticker.gd).
var showcase_ticker: Control
## Battle music holds the music player through 后台搜宠's watched battles
## (scripts/game/game_audio.gd begin/end_showcase_music).
var showcase_music := false
## This device's keys, action -> [key, key] (scripts/shortcuts.gd).
var shortcuts: Dictionary = {}
var _client_id := "%x-%x" % [randi(),Time.get_ticks_usec()]
var _follow: Array = []
var _following_step := false
var _followed: Array = []
var asset_packs: Node
var gamepad: Node
## Web build: full-screen waiting room while blocking packs download.
var waiting_screen: CanvasLayer
## Web only: window.stoneAgeDev, kept so the browser callback stays alive.
var _dev_callback: JavaScriptObject
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
## 10% to 200%; a new device starts at 100% (the camera's own default).
const MIN_ZOOM := 0.1
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
## Paths of the village and wilderness music (scripts/music_tracks.gd loads them when played).
var wilderness_music := ""
var village_music := ""
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
## 宠物大全 (scripts/pet_encyclopedia_menu.gd): species grid, ranking and 瞬移去抓.
var pet_encyclopedia: Control
var dev_gm_menu: Control
var dev_map_overview: Control
## 开发者性能面板 (scripts/perf_panel.gd): built on first use, F3 by default.
var perf_panel: CanvasLayer
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
## Map art by image id, loaded when first drawn. A map change keeps only the
## tiles the next map uses (maps share many), so memory follows the current
## map instead of every map visited (game_areas.gd).
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
var navigation := preload("res://scripts/nav_grid.gd").new()
var held: Array[String] = []
var music: AudioStreamPlayer
var effect: AudioStreamPlayer
var ui_sounds: Dictionary = {}
var last_ui_sound := -1
var ui_sound_count := 0
## Device settings (viewer.cfg, see restore_device_settings): muted is the
## music switch (M), effects_on the sound effects, volume the music volume,
## effects_volume the sound effects' volume.
var muted := false
var volume := 0.55
var effects_on := true
var effects_volume := 1.0
## 设置 → 画面 (this device): 固定横屏比例, 界面大小 (percent) and 底栏常驻.
## Phones and tablets default to filling the screen, larger text and a
## pinned bottom bar (no hover on a touch screen); see game_device.gd.
var fixed_aspect := true
var ui_scale := 100.0
var taskbar_pinned := false
## 帧率上限 (this device; phones 30, computers 60) and 切到后台时继续播放
## (off: a hidden page pauses every sound so the browser can freeze it).
var max_fps := 60
var background_audio := false
## 洞穴默认音乐 (this device, on unless turned off; not the original): a cave
## without its own music markers plays the cave track instead of going on
## with the previous map's.
var cave_music := true
## Extra players that finish a sound the next one would cut off
## (scripts/game/game_audio.gd play_effect).
var effect_voices: Array[AudioStreamPlayer] = []
## Sound settings changed (M, 设置, the 音乐 window): open controls follow.
signal sound_changed
## Saved only once restore_device_settings ran, so a test that presses M or
## zooms never writes this device's real viewer.cfg.
var _device_settings_live := false
## Per-device view choices (not game state, so not in the save or backend):
## which automation windows this device keeps minimized, so a reload comes
## back the same way. Tests run without persistence and never touch the file.
const VIEWER_PREFS := "user://viewer.cfg"
var viewer_prefs_path := ""
var coordinates: Label
var message: Label
## 设置 (scripts/settings_menu.gd); help points at it for the gamepad and
## callers that pause the field while it is open.
var settings_menu: PanelContainer
var help: PanelContainer
var marker: Node2D
var marker_cell := Vector2i(-1,-1)
var character_index := 0
## characters/index.json (scripts/character_art.gd): the chooser's `choices`
## and the list of `characters`; each one's art is read when it is drawn.
var character_catalog: Dictionary = {}
const SpriteArt = preload("res://scripts/sprite_art.gd")
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const CharacterArt = preload("res://scripts/character_art.gd")
const PerfRegistry = preload("res://scripts/perf_registry.gd")
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
	_character = GameCharacter.new(self)
	_movement = GameMovement.new(self)
	_input_events = GameInput.new(self)
	_areas = GameAreas.new(self)
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
	# The desktop game's 本机极速模式 shares the computer's threads with any
	# LAN profile servers (server/fast_hunt_share.gd); tests stay alone.
	if link.is_local() and profile_persistence:backend.automation.fast_share = preload("res://server/fast_hunt_share.gd").new()
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
	# 宠物大全's thumbnails (a few MB): quietly in the background, after
	# everything the game needs to start.
	if asset_packs.enabled:asset_packs.prefetch(preload("res://scripts/pet_thumbnails.gd").atlas_packs(asset_packs))
	data = MapFile.load_map(world_catalog.file(1000))
	PerfRegistry.track_manifest("当前地图",MapFile.file_size(world_catalog.file(1000)))
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
	# A character just created on a multi-profile server picks its look first.
	if new_character:
		new_character = false
		character_selection.title_text = "新角色 · 选择外观（以后可在 设置 → 换角色 更改）"
		change_character()
	get_window().focus_exited.connect(release_keyboard_input)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(close_game)
	if "--capture-once" in OS.get_cmdline_user_args():
		capture_frame()

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
	stop_sounds()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()

const EXIT_AUDIO_MSEC := 100

## Stops the music, the effect and every spare voice still finishing a sound.
func stop_sounds() -> void:
	if is_instance_valid(music): music.stop()
	if is_instance_valid(effect): effect.stop()
	for voice in effect_voices:
		if is_instance_valid(voice): voice.stop()

func project(grid: Vector2) -> Vector2:
	return Vector2((grid.x+grid.y)*32,(grid.y-grid.x)*24)

func unproject(point: Vector2) -> Vector2:
	return Vector2(point.x/64-point.y/48,point.x/64+point.y/48)

func texture(ident: String) -> Texture2D:
	var cached: Texture2D = textures.get(ident)
	if cached==null:
		# A palette texture once tiles use them (scripts/palette_sheet.gd).
		cached = PaletteSheet.load_any("res://assets/legacy/images/"+ident+".png")
		textures[ident] = cached
		PerfRegistry.track_texture("map",ident,cached)
	return cached

## A walking frame: player characters' frames come from their sprite sheet
## (characters/sheets, docs/technical/sprite-sheets.md); map residents and
## anything not packed are single PNGs.
func character_frame(character: String, ident: int) -> Texture2D:
	var art := CharacterArt.art(character)
	if not SpriteArt.spot(art,ident).is_empty():
		var frame: Texture2D = SpriteArt.texture(art,ident)
		if frame != null or not PaletteSheet.exists("res://assets/legacy/images/%d.png" % ident):return frame
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

func _exit_tree() -> void:
	preload("res://scripts/legacy_cursor.gd").uninstall()
	if backend!=null and backend.automation.fast_share!=null:backend.automation.fast_share.leave()
	stop_sounds()
	# A stopped sound is released on the audio mixing thread. The game scene
	# goes away when the program quits (or the remote client reloads it); a
	# sound released after the engine's exit check is reported as a resource
	# still in use, which failed test suites that quit right after stopping
	# the music and freeing the game. A moment lets the mixer let go.
	OS.delay_msec(EXIT_AUDIO_MSEC)

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

func load_profile() -> bool:
	if not link.is_local():return true
	if backend.load_profile(save_path):
		session.grant_pet_care_items()
		return true
	# Never overwrite an unreadable save by autosaving a fresh profile.
	profile_persistence = false
	last_adventure_message = "存档未能读取；现以临时旅程运行，原文件保留。"
	return false

# ---- remote play and backend events (scripts/game/game_remote.gd) ----
func _server_url() -> String:return _remote._server_url()
func report_position() -> void:_remote.report_position()
func _step_follow() -> bool:return _remote._step_follow()
func _on_map_reported(reply: Dictionary) -> void:_remote._on_map_reported(reply)
func _connect_remote() -> void:await _remote._connect_remote()
func link_blocked() -> bool:return _remote.link_blocked()
func switch_profile() -> void:_remote.switch_profile()
## A 组队 member: the server moves it after the leader; its own steps, 瞬移
## and map loads are refused (the move the server sends is followed).
func party_locked() -> bool:return is_instance_valid(party_panel) and party_panel.is_member()
const PARTY_LOCKED_TEXT := "组队中由队长带路；想自己走请先离开队伍。"
## A party member's 组队自动战斗 with 快速战斗 (LAN phase 4c): its party battle
## shows as a status line, not the battle view, until it asks to watch.
func party_compact() -> bool:return is_instance_valid(party_panel) and party_panel.compact_battle()
## GM and developer tools: always on alone or on a one-profile server; on a
## multi-profile server only for its admin profiles (the backend enforces it).
func is_admin() -> bool:return bool(state.options.get("admin",true))
## The account name on a multi-profile server, "" otherwise.
func account_name() -> String:return str(state.options.get("account",""))
func _update_link_overlay() -> void:_remote._update_link_overlay()
func acknowledge_presentation() -> void:_remote.acknowledge_presentation()
func _on_backend_message(event: Dictionary) -> void:_remote._on_backend_message(event)

# ---- sound (scripts/game/game_audio.gd) ----
func exploration_music() -> AudioStream:return _audio.exploration_music()
func set_music(stream: AudioStream) -> void:_audio.set_music(stream)
func music_track(path: String) -> AudioStream:return _audio.music_track(path)
func showcase_music_active() -> bool:return _audio.showcase_music_active()
func begin_showcase_music() -> void:_audio.begin_showcase_music()
func end_showcase_music() -> void:_audio.end_showcase_music()
func setup_audio() -> void:_audio.setup_audio()
func play_battle_sound(ident: int) -> void:_audio.play_battle_sound(ident)
func play_click() -> void:_audio.play_click()
func play_ui_sound(ident: int) -> void:_audio.play_ui_sound(ident)
func toggle_mute() -> void:_audio.toggle_mute()
func set_music_volume(value: float) -> void:_audio.set_music_volume(value)
func set_effects_on(on: bool) -> void:_audio.set_effects_on(on)
func set_effects_volume(value: float) -> void:_audio.set_effects_volume(value)
func apply_sound() -> void:_audio.apply_sound()
func toggle_radio() -> void:_audio.toggle_radio()

## 开发者性能面板: an overlay that does nothing until first opened.
func toggle_perf_panel() -> void:
	if not is_instance_valid(perf_panel):
		perf_panel = preload("res://scripts/perf_panel.gd").new()
		perf_panel.configure(self)
		add_child(perf_panel)
	perf_panel.toggle()

# ---- this device's settings (scripts/game/game_device.gd) ----
func set_zoom(value: float) -> void:_device.set_zoom(value)
func maximum_zoom_out() -> void:_device.maximum_zoom_out()
func set_blink_mode(on: bool) -> void:_device.set_blink_mode(on)
func zoom_by(step: float) -> void:_device.zoom_by(step)
func _save_device(key: String, value: Variant) -> void:_device._save_device(key,value)
func set_zoom_percent(percent: float) -> void:_device.set_zoom_percent(percent)
func restore_device_settings() -> void:_device.restore_device_settings()
func playback_speed() -> float:return _device.playback_speed()
func set_battle_speed(value: float) -> void:_device.set_battle_speed(value)
func set_fixed_aspect(on: bool) -> void:_device.set_fixed_aspect(on)
func set_ui_scale(percent: float) -> void:_device.set_ui_scale(percent)
func set_taskbar_pinned(on: bool) -> void:_device.set_taskbar_pinned(on)
func touch_device() -> bool:return _device.touch_device()
func set_max_fps(value: int) -> void:_device.set_max_fps(value)
func set_background_audio(on: bool) -> void:_device.set_background_audio(on)
func set_cave_music(on: bool) -> void:_device.set_cave_music(on)
func set_palette_textures(on: bool) -> void:_device.set_palette_textures(on)
func on_page_hidden(hidden: bool) -> void:_device.on_page_hidden(hidden)
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
func battle_window_open() -> bool:return _battle.battle_window_open()

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

# ---- maps (scripts/game/game_areas.gd) ----
func area_name() -> String:return _areas.area_name()
func display_cell() -> Vector2i:return _areas.display_cell()
func build_world() -> void:_areas.build_world()
func switch_area(wilderness: bool, destination: Vector2i) -> bool:return _areas.switch_area(wilderness,destination)
func load_area_id(map_id: int, destination: Vector2i) -> bool:return _areas.load_area_id(map_id,destination)
func area_packs(map_id: int) -> Array:return _areas.area_packs(map_id)
func walk_to_exit() -> void:_areas.walk_to_exit()
func handle_arrival() -> bool:return _areas.handle_arrival()
func restore_location() -> void:_areas.restore_location()
func dev_visit(id: int) -> bool:return _areas.dev_visit(id)
func dev_go_villager() -> void:_areas.dev_go_villager()
func dev_go_adventure() -> void:_areas.dev_go_adventure()
func dev_go_shop() -> void:_areas.dev_go_shop()

# ---- input (scripts/game/game_input.gd) ----
func configure_input() -> void:_input_events.configure_input()
func load_shortcuts() -> void:_input_events.load_shortcuts()
func bind_shortcut(action: String, slot: int, key: int, swap: bool = false) -> String:return _input_events.bind_shortcut(action,slot,key,swap)
func reset_shortcuts() -> void:_input_events.reset_shortcuts()
func _input(event: InputEvent) -> void:_input_events.on_input(event)
func _unhandled_input(event: InputEvent) -> void:_input_events.on_unhandled_input(event)
func handle_world_click(point: Vector2) -> void:_input_events.handle_world_click(point)
func release_keyboard_input() -> void:_input_events.release_keyboard_input()
func clear_input() -> void:_input_events.clear_input()

# ---- walking (scripts/game/game_movement.gd) ----
func request_step(destination: Vector2i) -> bool:return _movement.request_step(destination)
func walk_to(destination: Vector2i) -> void:
	if is_instance_valid(quest_helper_travel):quest_helper_travel.cancel()
	_movement.walk_to(destination)
func walk_toward(destination: Vector2i) -> void:
	if is_instance_valid(quest_helper_travel):quest_helper_travel.cancel()
	_movement.walk_toward(destination)
func approach_npc() -> void:_movement.approach_npc()
func blink_to(destination: Vector2i) -> bool:
	if is_instance_valid(quest_helper_travel):quest_helper_travel.cancel()
	return _movement.blink_to(destination)
func reset_player() -> void:_movement.reset_player()
func _physics_process(delta: float) -> void:_movement.step_frame(delta)

# ---- the character and companions (scripts/game/game_character.gd) ----
func change_character(id: String = "") -> void:_character.change_character(id)
func refresh_companion() -> void:_character.refresh_companion()
func dev_toggle_riding() -> void:_character.dev_toggle_riding()
