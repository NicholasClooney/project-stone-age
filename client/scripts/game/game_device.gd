extends RefCounted
## This device's own choices for the game scene (scripts/game.gd), kept in
## viewer.cfg rather than the save or the backend: zoom, sound switches,
## 瞬移模式, battle playback speed and window states. The values stay on the
## game (game.volume, game.dev_blink_mode, game.viewer_prefs_path and so on);
## see docs/technical/game-scripts.md.
var game: GameScene

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
	apply_view()
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

func set_fixed_aspect(on: bool) -> void:
	game.fixed_aspect = on
	_save_device("fixed_aspect",on)
	apply_view()

func set_ui_scale(percent: float) -> void:
	game.ui_scale = clampf(percent,UI_SCALE_MIN,UI_SCALE_MAX)
	_save_device("ui_scale",game.ui_scale)
	apply_view()

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
