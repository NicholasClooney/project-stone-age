extends RefCounted
## This device's own choices for the game scene (scripts/game.gd), kept in
## viewer.cfg rather than the save or the backend: zoom, sound switches,
## 瞬移模式, battle playback speed and window states. The values stay on the
## game (game.volume, game.dev_blink_mode, game.viewer_prefs_path and so on);
## see docs/technical/game-scripts.md.
var game: GameScene
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const SheetFrames = preload("res://scripts/sheet_frames.gd")

func _init(owner: GameScene) -> void:
	game = owner

func set_zoom(value: float) -> void:
	game.camera.zoom = Vector2.ONE*clampf(value,GameScene.MIN_ZOOM,GameScene.MAX_ZOOM)

func maximum_zoom_out() -> void:
	set_zoom(GameScene.MIN_ZOOM)

func set_blink_mode(on: bool) -> void:
	game.dev_blink_mode = on
	_save_device("blink_mode",on)

## Zoom the player chose (wheel, keys, 设置, gamepad), remembered on this device.
func zoom_by(step: float) -> void:
	set_zoom(game.camera.zoom.x+step)
	_save_device("zoom",game.camera.zoom.x)

func _save_device(key: String, value: Variant) -> void:
	if game._device_settings_live:set_viewer_pref(key,value)

## The 设置 → 画面 slider (10 to 200), remembered on this device.
func set_zoom_percent(percent: float) -> void:
	set_zoom(percent/100.0)
	_save_device("zoom",game.camera.zoom.x)

## This device's sound, zoom and 瞬移 choices (viewer.cfg). Restored for real
## play (a save or a remote backend); tests keep the defaults unless they call it.
func restore_device_settings() -> void:
	game._device_settings_live = true
	game.volume = clampf(float(viewer_pref("volume",game.volume)),0.0,1.0)
	game.muted = not bool(viewer_pref("music_on",not game.muted))
	game.effects_on = bool(viewer_pref("effects_on",game.effects_on))
	game.effects_volume = clampf(float(viewer_pref("effects_volume",game.effects_volume)),0.0,1.0)
	game.dev_blink_mode = bool(viewer_pref("blink_mode",game.dev_blink_mode))
	var touch := touch_device()
	game.fixed_aspect = bool(viewer_pref("fixed_aspect",not touch))
	game.ui_scale = clampf(float(viewer_pref("ui_scale",200.0 if touch else 100.0)),UI_SCALE_MIN,UI_SCALE_MAX)
	game.taskbar_pinned = bool(viewer_pref("taskbar_pinned",touch))
	game.max_fps = clampi(int(viewer_pref("max_fps",30 if touch else 60)),FPS_MIN,FPS_MAX)
	game.background_audio = bool(viewer_pref("background_audio",false))
	game.cave_music = bool(viewer_pref("cave_music",true))
	set_palette_textures(bool(viewer_pref("palette_textures",true)))
	apply_view()
	watch_page_visibility()
	if not game.get_viewport().size_changed.is_connected(_on_screen_resized):
		game.get_viewport().size_changed.connect(_on_screen_resized)
	var zoom = viewer_pref("zoom",0.0)
	if (zoom is float or zoom is int) and float(zoom)>0.0:set_zoom(float(zoom))
	game.load_shortcuts()
	game.apply_sound()

const UI_SCALE_MIN := 50.0
const UI_SCALE_MAX := 300.0

## A phone or tablet (the native mobile builds, or the web page on one).
func touch_device() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

## 固定横屏比例 keeps the designed 1280×800 frame (bars around it on another
## shape); off, the view grows to fill the screen and the HUD follows the
## edges. 界面大小 scales every 2D element; windows are not re-laid out for
## very large sizes yet (the player tries what fits).
func apply_view() -> void:
	var window := game.get_window()
	if window==null:return
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP if game.fixed_aspect else Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_factor = game.ui_scale/100.0
	if not _page_hidden:Engine.max_fps = engine_fps()
	relayout_windows.call_deferred()

func set_fixed_aspect(on: bool) -> void:
	game.fixed_aspect = on
	_save_device("fixed_aspect",on)
	apply_view()

func set_ui_scale(percent: float) -> void:
	game.ui_scale = clampf(percent,UI_SCALE_MIN,UI_SCALE_MAX)
	_save_device("ui_scale",game.ui_scale)
	apply_view()

func _on_screen_resized() -> void:
	relayout_windows.call_deferred()

## After the screen's size changes (界面大小, 固定横屏比例, a phone turned or
## a browser resized) every open window goes back to where it opens: 设置
## centred again and so on. A window opts in with relayout().
func relayout_windows() -> void:
	if not game.is_inside_tree():return
	for node in game.get_tree().root.find_children("*","Control",true,false):
		if node.has_method("relayout") and node.is_visible_in_tree():node.relayout()

const FPS_MIN := 15
const FPS_MAX := 60
## Frames per second while the page is hidden but still running (its sound
## plays on): nothing is seen, so drawing is only kept alive.
const HIDDEN_FPS := 5

## The engine's cap: 60 means no cap of ours (the display's refresh rules).
func engine_fps() -> int:
	return 0 if game.max_fps>=FPS_MAX else game.max_fps

## 帧率上限: fewer frames, less battery; the original animates at far less.
func set_max_fps(value: int) -> void:
	game.max_fps = clampi(value,FPS_MIN,FPS_MAX)
	_save_device("max_fps",game.max_fps)
	apply_view()

func set_cave_music(on: bool) -> void:
	game.cave_music = on
	_save_device("cave_music",on)
	# The current map's music follows at once.
	if not game.data.is_empty() and not game.battle_view.visible:game.set_music(game.exploration_music())

## 调色板贴图: sprite sheets as 256-colour textures (a quarter of the video
## memory) or RGBA as before. Sheets load again the next time they are drawn,
## so the change shows as soon as each sprite moves to its next frame.
func set_palette_textures(on: bool) -> void:
	_save_device("palette_textures",on)
	if PaletteSheet.user_on == on:return
	PaletteSheet.user_on = on
	SheetFrames.flush()
	for loader in [preload("res://scripts/battle_art.gd"),preload("res://scripts/riding.gd"),preload("res://scripts/character_art.gd")]:
		if loader._cache != null:loader._cache.forget_frames()

func set_background_audio(on: bool) -> void:
	game.background_audio = on
	_save_device("background_audio",on)

var _page_hidden := false
var _paused_players: Array = []
var _visibility_callback: JavaScriptObject

## On the web, follow the page's visibility (another tab, another app, the
## screen locked). A page that plays sound is kept running by the browser, so
## a hidden page pauses every sound unless 切到后台时继续播放 is on.
func watch_page_visibility() -> void:
	if not OS.has_feature("web") or _visibility_callback!=null:return
	var document = JavaScriptBridge.get_interface("document")
	if document==null:return
	_visibility_callback = JavaScriptBridge.create_callback(func(_args):on_page_hidden(bool(document.hidden)))
	document.addEventListener("visibilitychange",_visibility_callback)

func on_page_hidden(hidden: bool) -> void:
	if hidden==_page_hidden:return
	_page_hidden = hidden
	if hidden:
		Engine.max_fps = HIDDEN_FPS
		if not game.background_audio:
			for player in game.get_tree().root.find_children("*","AudioStreamPlayer",true,false):
				if player.playing and not player.stream_paused:
					player.stream_paused = true
					_paused_players.append(player)
	else:
		Engine.max_fps = engine_fps()
		for player in _paused_players:
			if is_instance_valid(player):player.stream_paused = false
		_paused_players.clear()

func set_taskbar_pinned(on: bool) -> void:
	game.taskbar_pinned = on
	_save_device("taskbar_pinned",on)

## Battle playback speed chosen on this device (1× until one is applied).
func playback_speed() -> float:
	if game.battle_speed<0:game.battle_speed = float(viewer_pref("battle_speed",0.0))
	return game.battle_speed if game.battle_speed>0 else 1.0

func set_battle_speed(value: float) -> void:
	game.battle_speed = value
	if is_instance_valid(game.battle_view):game.battle_view.playback_speed = value
	set_viewer_pref("battle_speed",value)

func _viewer_prefs_file() -> String:
	if not game.viewer_prefs_path.is_empty():return game.viewer_prefs_path
	return GameScene.VIEWER_PREFS if game.profile_persistence else ""

func viewer_pref(key: String, fallback: Variant = false) -> Variant:
	var file := _viewer_prefs_file()
	if file.is_empty():return fallback
	var config := ConfigFile.new()
	if config.load(file)!=OK:return fallback
	return config.get_value("view",key,fallback)

func set_viewer_pref(key: String, value: Variant) -> void:
	var file := _viewer_prefs_file()
	if file.is_empty():return
	var config := ConfigFile.new()
	config.load(file)
	if config.has_section_key("view",key) and config.get_value("view",key)==value:return
	config.set_value("view",key,value)
	config.save(file)
