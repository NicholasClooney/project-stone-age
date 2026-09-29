extends SceneTree
## 设置 and the tidied toolbar: the window's controls, H and 系统, the collapsed
## 开发者 section, the 音乐 window's sound controls, 五人镜像队 in 自动练级, and
## this device's settings saved and restored (only once they are restored, so
## tests that press M never write the real viewer.cfg).
const PREFS := "user://settings-menu-test.cfg"
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event,true)

func make_game():
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	game.viewer_prefs_path = PREFS
	root.add_child(game)
	await process_frame
	await process_frame
	return game

func close_game(game) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game = await make_game()
	var names: Array = []
	for node in game.dev_bar.get_children():names.append(str(node.name))
	check(names==["DevMapOverview","DevTrainingTravel","DevTraining","DevPetHunt","DevMusic","DevSettings"],"the toolbar holds 地图导航, 刷怪传送, 自动练级, 自动抓极品, 音乐 and 设置")
	for gone in ["DevRiding","DevGM","DevEncounter","DevBlinkMode","DevCloneSquad","DevHelp","DevCharacter","ExploreOutside","MaxOut","DevRadio"]:
		check(game.dev_bar.find_child(gone,true,false)==null,"%s is no longer on the toolbar" % gone)

	# Nothing is saved before the device settings are restored.
	game.toggle_mute()
	check(game.muted and not _saved("music_on"),"pressing M before restore writes no device setting")
	game.toggle_mute()
	game.restore_device_settings()

	# 设置 window.
	game.dev_bar.get_node("DevSettings").pressed.emit()
	await process_frame
	var menu = game.settings_menu
	check(menu.visible and game.paused_input and game.help==menu,"设置 opens from the toolbar and pauses walking")
	for control in ["ZoomMinus","ZoomPlus","MaxOut","SettingsSound","SettingsEffects","SettingsVolume","SettingsCharacter","SettingsBlinkMode","SettingsSave","Changelog","SettingsHelp","SettingsDeveloper"]:
		check(menu.find_child(control,true,false)!=null,"设置 has %s" % control)
	check(menu.find_child("SettingsGM",true,false)==null,"开发者 starts collapsed")
	(menu.find_child("SettingsDeveloper",true,false) as Button).pressed.emit()
	await process_frame
	var gm: Button = menu.find_child("SettingsGM",true,false)
	check(gm!=null,"expanding 开发者 shows GM 调试")
	gm.pressed.emit()
	await process_frame
	check(game.dev_gm_menu.visible and not menu.visible,"GM 调试 opens from 开发者")
	game.dev_gm_menu.close_menu()
	await process_frame

	# Sound, zoom and 瞬移 are saved as they change.
	menu.open_menu()
	await process_frame
	(menu.find_child("SettingsVolume",true,false) as HSlider).value = 0.3
	(menu.find_child("SettingsEffects",true,false) as CheckBox).button_pressed = false
	(menu.find_child("SettingsBlinkMode",true,false) as CheckBox).button_pressed = true
	game.set_zoom(1.0)
	(menu.find_child("ZoomPlus",true,false) as Button).pressed.emit()
	var zoom: float = game.camera.zoom.x
	check(is_equal_approx(game.volume,0.3) and not game.effects_on and game.dev_blink_mode and zoom>1.0,"设置 changes volume, effects, 瞬移 and zoom")
	check(is_equal_approx(game.effect.volume_db,-80.0) and is_equal_approx(game.music.volume_db,linear_to_db(0.3)),"the players follow the new sound settings")
	menu.close_menu()
	key(KEY_M)
	await process_frame
	check(game.muted and is_equal_approx(game.music.volume_db,-80.0),"M switches the music off")
	menu.open_menu()
	await process_frame
	check(not (menu.find_child("SettingsSound",true,false) as CheckBox).button_pressed,"设置's music switch shows M's change")
	menu.close_menu()

	# H opens 操作说明, H again closes it; Esc closes 设置.
	key(KEY_H)
	await process_frame
	var help_text: Label = menu.find_child("SettingsHelpText",true,false)
	check(menu.visible and menu.page=="help" and help_text!=null and help_text.text.contains("刷怪传送") and help_text.text.contains("自动抓极品"),"H opens 操作说明 describing the current windows")
	key(KEY_H)
	await process_frame
	check(not menu.visible and not game.paused_input,"H again closes it and walking resumes")
	menu.open_menu()
	key(KEY_ESCAPE)
	await process_frame
	check(not menu.visible,"Esc closes 设置")

	# 系统 on the classic taskbar opens 设置.
	game.classic_hud.task_buttons[6].pressed.emit()
	await process_frame
	check(menu.visible,"系统 opens 设置")
	game.classic_hud.task_buttons[6].pressed.emit()
	await process_frame
	check(not menu.visible,"系统 again closes it")

	# 音乐 window: the same switch and volume.
	game.dev_bar.get_node("DevMusic").pressed.emit()
	await process_frame
	var panel = game.radio_panel
	var music_on: CheckBox = panel.find_child("RadioMusicOn",true,false)
	var slider: HSlider = panel.find_child("RadioVolume",true,false)
	check(panel.visible and music_on!=null and slider!=null and not music_on.button_pressed and is_equal_approx(slider.value,0.3),"音乐 shows the music switch and volume")
	music_on.button_pressed = true
	slider.value = 0.8
	check(not game.muted and is_equal_approx(game.volume,0.8),"the 音乐 window changes them")
	key(KEY_M)
	await process_frame
	check(not music_on.button_pressed,"and follows M while open")
	key(KEY_M)
	await process_frame
	panel.close_panel()

	# 五人镜像队 in 自动练级.
	var clone: CheckBox = game.training_helper.panel.find_child("CloneSquadToggle",true,false)
	check(clone!=null,"自动练级 holds the 五人镜像队 switch")
	clone.button_pressed = true
	check(game.session.clone_squad_enabled,"which turns the clone squad on")
	clone.button_pressed = false
	check(not game.session.clone_squad_enabled,"and off")

	# A new session on this device gets the saved settings back.
	await close_game(game)
	var again = await make_game()
	check(is_equal_approx(again.volume,0.55) and again.effects_on and not again.dev_blink_mode,"a test game keeps the defaults until it restores")
	again.restore_device_settings()
	check(is_equal_approx(again.volume,0.8) and not again.muted and not again.effects_on and again.dev_blink_mode and is_equal_approx(again.camera.zoom.x,zoom),"restoring brings back volume, music, effects, 瞬移 and zoom")
	check(is_equal_approx(again.music.volume_db,linear_to_db(0.8)) and is_equal_approx(again.effect.volume_db,-80.0),"and applies them to the players")
	await close_game(again)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	await create_timer(0.3).timeout
	print("SETTINGS MENU: %d failures" % failures)
	quit(1 if failures else 0)

func _saved(key_name: String) -> bool:
	var config := ConfigFile.new()
	if config.load(PREFS)!=OK:return false
	return config.has_section_key("view",key_name)
