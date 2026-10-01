extends SceneTree
## No toolbar: 设置 (Esc, 系统, H), 游戏助手 (G) and their entries, the zoom
## slider, M for the map, the 快捷键 page (rebinding, conflicts, swapping,
## clearing, defaults), the 电台 window's sound controls, 五人镜像队 in
## 自动练级, and this device's settings saved and restored (only once they are
## restored, so tests never write the real viewer.cfg).
const PREFS := "user://settings-menu-test.cfg"
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
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
	check(game.get("dev_bar")==null,"there is no toolbar")
	for gone in ["DevMapOverview","DevTrainingTravel","DevTraining","DevPetHunt","DevMusic","DevSettings","DevRiding","DevGM","DevEncounter","DevBlinkMode","DevCloneSquad","DevHelp","DevCharacter","ExploreOutside","MaxOut","DevRadio"]:
		check(game.find_child(gone,true,false)==null,"%s is not on the game screen" % gone)
	# The one button of ours on the field: 游戏助手, below the classic icons.
	var ours: Array = game.ui_root.get_children().filter(func(node): return node is Button and node.visible)
	check(ours.size()==1 and ours[0]==game.helper_button and game.helper_button.text=="游戏助手 [G]","the only button of ours on the field is 游戏助手 [G]")
	game.helper_button.pressed.emit()
	await process_frame
	check(game.helper_menu.visible,"the field button opens 游戏助手")
	game.helper_menu.close_menu()
	await process_frame

	# Nothing is saved before the device settings are restored.
	game.toggle_mute()
	check(game.muted and not _saved("music_on"),"switching music before restore writes no device setting")
	game.toggle_mute()
	game.restore_device_settings()

	# R no longer sends the player back to the village square (Cmd+R, the
	# browser's reload, reached the game as R).
	check(not game.shortcuts.has("reset") and not InputMap.has_action("reset"),"there is no 回到村中广场 shortcut")
	var stood: Vector2i = game.cell
	game.cell += Vector2i(1,0)
	var moved: Vector2i = game.cell
	key(KEY_R)
	await process_frame
	check(game.cell==moved,"R leaves the player where they are")
	game.cell = stood
	# Esc with no window open opens 设置.
	key(KEY_ESCAPE)
	await process_frame
	var menu = game.settings_menu
	check(menu.visible and game.paused_input and game.help==menu,"Esc with nothing open opens 设置 and pauses walking")
	for control in ["SettingsZoom","SettingsZoomValue","SettingsSound","SettingsEffects","SettingsVolume","SettingsEffectsVolume","SettingsRadio","SettingsHelper","SettingsCharacter","SettingsBlinkMode","SettingsFreeSpirits","SettingsSave","Changelog","SettingsHelp","SettingsKeys","SettingsDeveloper"]:
		check(menu.find_child(control,true,false)!=null,"设置 has %s" % control)
	check(menu.find_child("SettingsGM",true,false)==null,"开发者 starts collapsed")
	(menu.find_child("SettingsDeveloper",true,false) as Button).pressed.emit()
	await process_frame
	var gm: Button = menu.find_child("SettingsGM",true,false)
	check(gm!=null,"expanding 开发者 shows GM 调试")
	gm.pressed.emit()
	await process_frame
	check(game.dev_gm_menu.visible and not menu.visible,"GM 调试 opens from 开发者")
	key(KEY_ESCAPE)
	await process_frame
	check(not game.dev_gm_menu.visible and not menu.visible,"Esc closes the top window first and does not open 设置 then")

	# Sound, zoom and 瞬移 are saved as they change.
	menu.open_menu()
	await process_frame
	(menu.find_child("SettingsVolume",true,false) as HSlider).value = 0.3
	(menu.find_child("SettingsEffectsVolume",true,false) as HSlider).value = 0.5
	check(is_equal_approx(game.effects_volume,0.5) and is_equal_approx(game.effect.volume_db,-10.0+linear_to_db(0.5)) and _saved("effects_volume"),"音效音量 sets the effects player and is saved on this device")
	(menu.find_child("SettingsEffects",true,false) as CheckBox).button_pressed = false
	(menu.find_child("SettingsBlinkMode",true,false) as CheckBox).button_pressed = true
	(menu.find_child("SettingsSound",true,false) as CheckBox).button_pressed = false
	(menu.find_child("SettingsZoom",true,false) as HSlider).value = 35
	var zoom: float = game.camera.zoom.x
	check(is_equal_approx(game.volume,0.3) and not game.effects_on and game.dev_blink_mode and game.muted and is_equal_approx(zoom,0.35),"设置 changes volume, effects, music, 瞬移 and zoom")
	check(is_equal_approx(game.effect.volume_db,-80.0) and is_equal_approx(game.music.volume_db,-80.0),"the players follow the new sound settings")
	# 调色板贴图: on by default; off draws the old RGBA textures at once.
	var palette_box: CheckBox = menu.find_child("SettingsPaletteTextures",true,false)
	check(palette_box!=null and palette_box.button_pressed and PaletteSheet.user_on and _drawn_palette(game),"调色板贴图 starts on and the player is drawn from a palette sheet")
	palette_box.button_pressed = false
	check(not PaletteSheet.user_on and _saved("palette_textures") and not _drawn_palette(game) and game.player.sprite.material==null,"turning it off saves it on this device and the player's next frame is RGBA again")
	palette_box.button_pressed = true
	check(PaletteSheet.user_on and _drawn_palette(game),"turning it on draws the palette sheet again")
	palette_box.button_pressed = false
	check(_saved("zoom") and _saved("music_on"),"the zoom and the music switch are saved on this device")
	# 画面 on a desktop: fixed aspect, 100% interface, the bar on hover.
	check(game.fixed_aspect and is_equal_approx(game.ui_scale,100.0) and not game.taskbar_pinned and game.get_window().content_scale_aspect==Window.CONTENT_SCALE_ASPECT_KEEP and is_equal_approx(game.get_window().content_scale_factor,1.0),"a desktop keeps the fixed aspect, 100% and the hover bar by default")
	var ui_scale: HSlider = menu.find_child("SettingsUiScale",true,false)
	ui_scale.value = 150
	check(is_equal_approx(game.ui_scale,100.0),"dragging 界面大小 does not rescale yet")
	ui_scale.drag_ended.emit(true)
	check(is_equal_approx(game.ui_scale,150.0) and is_equal_approx(game.get_window().content_scale_factor,1.5) and _saved("ui_scale"),"letting go applies 150% and saves it")
	await process_frame
	await process_frame
	var screen: Vector2 = game.get_viewport_rect().size
	check(menu.position.distance_to(((screen-menu.size)/2).max(Vector2(8,8)))<1.0,"设置 is centred again on the rescaled screen (%s, screen %s)" % [str(menu.position),str(screen)])
	check(is_equal_approx(game.classic_hud.bar.size.x,game.classic_hud.size.x),"the bottom bar still spans the screen")
	var box: Control = game.dialogue.get_node("OriginalDialogue")
	check(box.position.x >= 8 and box.position.x+384*box.scale.x <= screen.x-8 and box.position.y+192*box.scale.y <= screen.y,"the NPC dialogue box fits the rescaled screen (%s x%.2f on %s)" % [str(box.position),box.scale.x,str(screen)])
	var narrow := Vector2(420,900)
	game.dialogue.size = narrow
	game._ui.place_dialogue(box)
	check(box.scale.x < game.classic_hud.SCALE and is_equal_approx(box.position.x+384*box.scale.x/2,narrow.x/2) and box.position.x >= 15,"on a narrow phone screen it shrinks to fit and stays centred")
	game.dialogue.size = screen
	game._ui.place_dialogue(box)
	(menu.find_child("SettingsFixedAspect",true,false) as CheckBox).button_pressed = false
	check(game.get_window().content_scale_aspect==Window.CONTENT_SCALE_ASPECT_EXPAND and _saved("fixed_aspect"),"unticking 固定横屏比例 lets the view fill the screen")
	(menu.find_child("SettingsTaskbarPinned",true,false) as CheckBox).button_pressed = true
	await process_frame
	await process_frame
	check(game.taskbar_pinned and game.classic_hud.taskbar.visible and _saved("taskbar_pinned"),"底栏常驻 shows the task buttons without hovering")
	(menu.find_child("SettingsTaskbarPinned",true,false) as CheckBox).button_pressed = false
	(menu.find_child("SettingsFixedAspect",true,false) as CheckBox).button_pressed = true
	ui_scale.value = 100
	ui_scale.drag_ended.emit(true)
	check(game.get_window().content_scale_aspect==Window.CONTENT_SCALE_ASPECT_KEEP and is_equal_approx(game.get_window().content_scale_factor,1.0),"and back to the desktop view")
	# 帧率上限: a desktop is uncapped by default; 30 caps the engine.
	check(game.max_fps==60 and Engine.max_fps==0,"a desktop has no frame cap by default")
	(menu.find_child("SettingsMaxFps",true,false) as HSlider).value = 30
	check(Engine.max_fps==30 and _saved("max_fps"),"帧率上限 30 caps the engine and is saved")
	# A hidden page pauses the sound unless 切到后台时继续播放 is on.
	var player := AudioStreamPlayer.new()
	player.stream = AudioStreamGenerator.new()
	game.add_child(player)
	player.play()
	game.on_page_hidden(true)
	check(player.stream_paused and Engine.max_fps==5,"a hidden page pauses playing sounds and draws at 5 fps")
	game.on_page_hidden(false)
	check(not player.stream_paused and Engine.max_fps==30,"showing it again resumes them and the cap")
	(menu.find_child("SettingsBackgroundAudio",true,false) as CheckBox).button_pressed = true
	game.on_page_hidden(true)
	check(not player.stream_paused and game.background_audio and _saved("background_audio"),"with 切到后台时继续播放 the sound plays on")
	game.on_page_hidden(false)
	(menu.find_child("SettingsBackgroundAudio",true,false) as CheckBox).button_pressed = false
	(menu.find_child("SettingsMaxFps",true,false) as HSlider).value = 60
	check(Engine.max_fps==0,"60 is no cap again")
	player.queue_free()
	menu.close_menu()

	# M opens the map, not the music switch.
	key(KEY_M)
	await process_frame
	check(game.classic_hud.map_panel.visible and game.muted,"M opens the map window and leaves the music as it was")
	key(KEY_ESCAPE)
	await process_frame
	check(not game.classic_hud.map_panel.visible and not menu.visible,"Esc closes the map without opening 设置")

	# H opens 操作说明, H again closes it.
	key(KEY_H)
	await process_frame
	var help_text: Label = menu.find_child("SettingsHelpText",true,false)
	check(menu.visible and menu.page=="help" and help_text!=null and help_text.text.contains("游戏助手") and help_text.text.contains("快捷键") and not help_text.text.contains("工具栏"),"H opens 操作说明 describing 游戏助手 and 快捷键, no toolbar")
	key(KEY_H)
	await process_frame
	check(not menu.visible and not game.paused_input,"H again closes it and walking resumes")

	# 系统 on the classic taskbar opens 设置.
	game.classic_hud.task_buttons[6].pressed.emit()
	await process_frame
	check(menu.visible,"系统 opens 设置")
	game.classic_hud.task_buttons[6].pressed.emit()
	await process_frame
	check(not menu.visible,"系统 again closes it")

	# 游戏助手: G, and from 设置; every entry opens its window.
	var helper = game.helper_menu
	key(KEY_G)
	await process_frame
	check(helper.visible and game.paused_input,"G opens 游戏助手")
	var opened := {"HelperTraining":func():return game.training_helper.visible,"HelperPetHunt":func():return game.pet_hunt_menu.visible,"HelperPets":func():return game.adventure_menu.visible,"HelperPetRecords":func():return game.adventure_menu.visible and game.adventure_menu.pet_records_open,"HelperRadio":func():return game.radio_panel.visible,"HelperMapOverview":func():return game.dev_map_overview.visible,"HelperTravel":func():return game.leveling_destinations.visible,"HelperGM":func():return game.dev_gm_menu.visible}
	for entry in opened:
		helper.open_menu()
		await process_frame
		var open: Button = helper.find_child(entry,true,false)
		check(open!=null,"游戏助手 lists %s" % entry)
		if open==null:continue
		open.pressed.emit()
		await process_frame
		check(not helper.visible and opened[entry].call(),"%s opens its window" % entry)
		for node in [game.training_helper,game.pet_hunt_menu,game.dev_map_overview,game.leveling_destinations,game.dev_gm_menu]:
			if node.visible:
				if node==game.dev_map_overview:node.close_map()
				else:node.close_menu()
		if game.adventure_menu.visible:game.close_adventure_menu()
		if game.radio_panel.visible:game.radio_panel.close_panel()
		await process_frame
	check(not game.paused_input,"walking resumes after the windows close")
	menu.open_menu()
	await process_frame
	(menu.find_child("SettingsHelper",true,false) as Button).pressed.emit()
	await process_frame
	check(helper.visible and not menu.visible,"设置 opens 游戏助手")
	check(game.gamepad.panel()==helper and not game.gamepad.candidates(helper).is_empty(),"the gamepad reaches 游戏助手's buttons")
	key(KEY_ESCAPE)
	await process_frame
	check(not helper.visible and not menu.visible,"Esc closes 游戏助手")

	# 电台 from 设置: the music switch and volume live there too.
	menu.open_menu()
	await process_frame
	(menu.find_child("SettingsRadio",true,false) as Button).pressed.emit()
	await process_frame
	var panel = game.radio_panel
	var music_on: CheckBox = panel.find_child("RadioMusicOn",true,false)
	var slider: HSlider = panel.find_child("RadioVolume",true,false)
	check(panel.visible and not menu.visible and music_on!=null and slider!=null and not music_on.button_pressed and is_equal_approx(slider.value,0.3),"设置's 电台 opens the radio with the music switch and volume")
	music_on.button_pressed = true
	slider.value = 0.8
	check(not game.muted and is_equal_approx(game.volume,0.8),"the 电台 window changes them")
	key(KEY_ESCAPE)
	await process_frame
	check(not panel.visible and not menu.visible,"Esc closes the radio window before opening 设置")

	# 快捷键: rebind, conflicts, swap, clear, defaults.
	menu.open_menu("keys")
	await process_frame
	check(menu.page=="keys" and menu.find_child("Shortcut_map_0",true,false).text=="M","快捷键 lists the map on M")
	(menu.find_child("Shortcut_map_0",true,false) as Button).pressed.emit()
	await process_frame
	key(KEY_K)
	await process_frame
	check(game.shortcuts.map[0]==KEY_K and InputMap.action_get_events("map").any(func(e): return e is InputEventKey and e.physical_keycode==KEY_K),"a slot takes the next key and the InputMap follows")
	check(not game.classic_hud.map_panel.visible and menu.visible,"the captured key does nothing else")
	(menu.find_child("Shortcut_map_0",true,false) as Button).pressed.emit()
	await process_frame
	key(KEY_G)
	await process_frame
	check(game.shortcuts.map[0]==KEY_K and menu.find_child("ShortcutConflict",true,false)!=null,"a key another action uses is refused with a conflict")
	(menu.find_child("ShortcutSwap",true,false) as Button).pressed.emit()
	await process_frame
	check(game.shortcuts.map[0]==KEY_G and game.shortcuts.helper[0]==KEY_K,"交换 swaps the two keys")
	(menu.find_child("Shortcut_radio_0",true,false) as Button).pressed.emit()
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	check(menu.visible and game.shortcuts.radio[0]==0,"Esc cancels a capture and keeps the window open")
	(menu.find_child("Shortcut_radio_0",true,false) as Button).pressed.emit()
	await process_frame
	key(KEY_F6)
	await process_frame
	check(game.shortcuts.radio[0]==KEY_F6,"an empty slot takes a free key")
	(menu.find_child("Shortcut_wave_0",true,false) as Button).pressed.emit()
	await process_frame
	key(KEY_BACKSPACE)
	await process_frame
	check(game.shortcuts.wave[0]==0,"退格键 clears a slot")
	check(_saved("shortcuts"),"changed keys are saved on this device")
	menu.close_menu()
	await process_frame
	key(KEY_F6)
	await process_frame
	check(game.radio_panel.visible,"the new radio key opens the radio")
	game.radio_panel.close_panel()

	# 五人镜像队 in 自动练级.
	var clone: CheckBox = game.training_helper.panel.find_child("CloneSquadToggle",true,false)
	check(clone!=null,"自动练级 holds the 五人镜像队 switch")
	clone.button_pressed = true
	check(game.session.clone_squad_enabled,"which turns the clone squad on")
	clone.button_pressed = false
	check(not game.session.clone_squad_enabled,"and off")

	# A new session on this device gets the saved settings and keys back.
	await close_game(game)
	var again = await make_game()
	check(is_equal_approx(again.volume,0.55) and again.effects_on and not again.dev_blink_mode and again.shortcuts.map[0]==KEY_M and is_equal_approx(again.camera.zoom.x,1.0),"a test game keeps the defaults (100% zoom) until it restores")
	again.restore_device_settings()
	check(is_equal_approx(again.effects_volume,0.5),"restoring brings back the effects volume")
	check(not PaletteSheet.user_on and not _drawn_palette(again),"restoring brings back 调色板贴图 off")
	again.set_palette_textures(true)
	check(is_equal_approx(again.volume,0.8) and not again.muted and not again.effects_on and again.dev_blink_mode and is_equal_approx(again.camera.zoom.x,zoom),"restoring brings back volume, music, effects, 瞬移 and zoom")
	check(again.shortcuts.map[0]==KEY_G and again.shortcuts.helper[0]==KEY_K and again.shortcuts.radio[0]==KEY_F6 and again.shortcuts.wave[0]==0,"and the keys")
	check(InputMap.action_get_events("helper").any(func(e): return e is InputEventKey and e.physical_keycode==KEY_K),"applied to the InputMap at startup")
	again.settings_menu.open_menu("keys")
	await process_frame
	(again.settings_menu.find_child("ShortcutReset",true,false) as Button).pressed.emit()
	await process_frame
	check(again.shortcuts==preload("res://scripts/shortcuts.gd").defaults() and not _has_overrides(),"恢复默认 brings back every default key")
	await close_game(again)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	await create_timer(0.3).timeout
	print("SETTINGS MENU: %d failures" % failures)
	quit(1 if failures else 0)

## Whether the player's sprite shows a palette sheet with its material, after
## drawing its current frame again.
func _drawn_palette(game) -> bool:
	game.player.current_image = -1
	game.player._process(0.0)
	var texture: Texture2D = game.player.sprite.texture
	return PaletteSheet.is_palette(texture) and game.player.sprite.material==PaletteSheet.material_of(texture)

func _has_overrides() -> bool:
	var config := ConfigFile.new()
	if config.load(PREFS)!=OK:return false
	return not (config.get_value("view","shortcuts",{}) as Dictionary).is_empty()

func _saved(key_name: String) -> bool:
	var config := ConfigFile.new()
	if config.load(PREFS)!=OK:return false
	return config.has_section_key("view",key_name)
