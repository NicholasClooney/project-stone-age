extends PanelContainer
## 设置 (the classic 系统 menu): zoom, sound and 电台, 游戏助手, character,
## 瞬移, saving, 快捷键, 更新日志 and 操作说明, plus a collapsed 开发者
## section with GM 调试. Opened by Esc with no other window open, the classic
## taskbar's 系统 and H (on 操作说明); Esc closes it. It pauses the
## field like the old Help panel it replaces, so it is game.help too (the
## gamepad's Start and panel lookup use that). Every choice here is this
## device's own (viewer.cfg), see game.gd's device settings.
const WIDTH := 560.0
const Shortcuts = preload("res://scripts/shortcuts.gd")
var world: Node
## "main", "help" (操作说明) or "keys" (快捷键).
var page := "main"
var developer_open := false
var body: VBoxContainer
## 快捷键: the [action, slot] waiting for a key, and a refused key's conflict.
var capturing: Array = []
var conflict: Dictionary = {}

func configure(owner: Node) -> void:
	world = owner
	name = "SettingsMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	custom_minimum_size = Vector2(WIDTH,0)
	add_theme_stylebox_override("panel",world.box(Color("20292f",0.97),Color("b29b65")))
	visibility_changed.connect(func():
		if visible:
			rebuild()
			_center())
	world.sound_changed.connect(_sync_sound)
	hide()

## Shows the window on page "main", "help" (操作说明) or "keys" (快捷键).
func open_menu(start_page: String = "main") -> void:
	page = start_page
	capturing = []
	conflict = {}
	if visible:rebuild()
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show()
	world.clear_input()
	world.paused_input = true

func close_menu() -> void:
	if not visible:return
	capturing = []
	conflict = {}
	hide()
	# A battle keeps the field paused; so does a minimized automation window.
	world.paused_input = world.battle_view.visible or world.automation_minimized()
	world.clear_input()

func _center() -> void:
	reset_size()
	var screen: Vector2 = world.get_viewport_rect().size
	position = ((screen-size)/2).max(Vector2(8,8))

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title: Label = world.text({"help":"操作说明","keys":"快捷键"}.get(page,"设置"),20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if page!="main":
		var back: Button = world.button("返回设置",func(): page = "main";rebuild();_center())
		back.name = "SettingsBack"
		header.add_child(back)
	var close: Button = world.button("关闭 · Esc",close_menu)
	close.name = "SettingsClose"
	header.add_child(close)
	if page=="help":_help_page()
	elif page=="keys":_keys_page()
	else:_main_page()
	reset_size()

func _section(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	var label: Label = world.text(caption,15)
	label.custom_minimum_size.x = 56
	label.add_theme_color_override("font_color",Color("e6c284"))
	row.add_child(label)
	body.add_child(row)
	return row

func _check(caption: String, node_name: String, pressed: bool, toggled: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.name = node_name
	box.text = caption
	box.focus_mode = Control.FOCUS_NONE
	box.add_theme_font_size_override("font_size",14)
	box.button_pressed = pressed
	box.toggled.connect(toggled)
	return box

func _main_page() -> void:
	# 画面: 10% to 200%, a new device starts at 100%.
	var view := _section("画面")
	view.add_child(world.text("缩放",14))
	var zoom := HSlider.new()
	zoom.name = "SettingsZoom"
	zoom.min_value = world.MIN_ZOOM*100
	zoom.max_value = world.MAX_ZOOM*100
	zoom.step = 5
	zoom.custom_minimum_size = Vector2(260,24)
	zoom.focus_mode = Control.FOCUS_NONE
	zoom.value = world.camera.zoom.x*100
	zoom.value_changed.connect(func(value: float):
		world.set_zoom_percent(value)
		_sync_zoom())
	view.add_child(zoom)
	var zoom_label: Label = world.text("",14)
	zoom_label.name = "SettingsZoomValue"
	view.add_child(zoom_label)
	# 声音
	var sound := _section("声音")
	sound.add_child(_check("音乐","SettingsSound",not world.muted,func(on: bool):
		if on==world.muted:world.toggle_mute()))
	sound.add_child(_check("音效","SettingsEffects",world.effects_on,world.set_effects_on))
	var volume_row := _section("")
	volume_row.add_child(world.text("音乐音量",14))
	var slider := HSlider.new()
	slider.name = "SettingsVolume"
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(240,24)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value = world.volume
	slider.value_changed.connect(world.set_music_volume)
	volume_row.add_child(slider)
	var effects_row := _section("")
	effects_row.add_child(world.text("音效音量",14))
	var effects_slider := HSlider.new()
	effects_slider.name = "SettingsEffectsVolume"
	effects_slider.min_value = 0
	effects_slider.max_value = 1
	effects_slider.step = 0.05
	effects_slider.custom_minimum_size = Vector2(240,24)
	effects_slider.focus_mode = Control.FOCUS_NONE
	effects_slider.value = world.effects_volume
	effects_slider.value_changed.connect(world.set_effects_volume)
	effects_row.add_child(effects_slider)
	var radio: Button = world.button("电台",func(): close_menu();world.toggle_radio())
	radio.name = "SettingsRadio"
	radio.tooltip_text = "原版配乐电台、收藏、歌单、随机和单曲循环"
	volume_row.add_child(radio)
	# 游戏助手: the windows this project added.
	var helper := _section("助手")
	var helper_open: Button = world.button("游戏助手 [%s]" % _key_of("helper"),func(): close_menu();world.helper_menu.open_menu())
	helper_open.name = "SettingsHelper"
	helper_open.tooltip_text = "自动练级、自动抓极品、电台、地图导航、刷怪传送等"
	helper.add_child(helper_open)
	# 角色 and 移动
	var character := _section("角色")
	var choose: Button = world.button("换角色 [%s]" % _key_of("character"),func(): close_menu();world.change_character())
	choose.name = "SettingsCharacter"
	character.add_child(choose)
	var movement := _section("移动")
	var blink := _check("瞬移模式","SettingsBlinkMode",world.dev_blink_mode,world.set_blink_mode)
	blink.tooltip_text = "开启后点击当前地图即可瞬移；障碍旁寻找可站立位置，关闭后恢复点击寻路"
	movement.add_child(blink)
	# 存档
	var saving := _section("存档")
	saving.add_child(world.text("旅程会自动保存。" if world.profile_persistence else "临时旅程：存档未启用。",14))
	var save: Button = world.button("保存旅程",func():
		world.checkpoint()
		world.message.text = "旅程已保存。")
	save.name = "SettingsSave"
	save.disabled = not world.profile_persistence or world.battle_view.visible
	saving.add_child(save)
	# 关于
	var about := _section("关于")
	var changes: Button = world.button("更新日志 "+str(world.changelog_menu.history.get("version","v0.0.0")),func(): close_menu();world.changelog_menu.open_menu())
	changes.name = "Changelog"
	about.add_child(changes)
	var help: Button = world.button("操作说明 [%s]" % _key_of("help"),func(): page = "help";rebuild();_center())
	help.name = "SettingsHelp"
	about.add_child(help)
	var keys: Button = world.button("快捷键",func(): page = "keys";capturing = [];conflict = {};rebuild();_center())
	keys.name = "SettingsKeys"
	about.add_child(keys)
	# 开发者 (collapsed)
	var developer := _section("")
	var fold: Button = world.button(("▼ " if developer_open else "▶ ")+"开发者",func(): developer_open = not developer_open;rebuild();_center())
	fold.name = "SettingsDeveloper"
	developer.add_child(fold)
	if developer_open:
		var tools := _section("")
		var gm: Button = world.button("GM 调试",func(): close_menu();world.dev_gm_menu.open_menu())
		gm.name = "SettingsGM"
		gm.tooltip_text = "调整等级、属性和体力，发放特殊宠物（开发者功能）"
		tools.add_child(gm)
	_sync_zoom()

func _sync_zoom() -> void:
	var label := find_child("SettingsZoomValue",true,false)
	if label:label.text = "%d%%" % roundi(world.camera.zoom.x*100)
	var slider := find_child("SettingsZoom",true,false) as HSlider
	if slider:slider.set_value_no_signal(world.camera.zoom.x*100)

## The first key of an action, for button captions.
func _key_of(action: String) -> String:
	for code in world.shortcuts.get(action,[]):
		if int(code)!=0:return Shortcuts.key_name(int(code))
	return "无"

# ---- 快捷键 ----------------------------------------------------------------

## Every action with its two key slots. Click a slot, then press a key: Esc
## cancels, Backspace clears the slot. A key another action uses asks to swap.
func _keys_page() -> void:
	var note: Label = world.text("点一个按键格再按新键；Esc 取消，退格键清空。Esc 始终关闭窗口并打开设置，不能改。",12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = WIDTH-24
	note.add_theme_color_override("font_color",Color("b6aa8a"))
	body.add_child(note)
	if not conflict.is_empty():
		var row := HBoxContainer.new()
		row.name = "ShortcutConflict"
		row.add_theme_constant_override("separation",8)
		body.add_child(row)
		var text: Label = world.text("%s 已用于「%s」。" % [Shortcuts.key_name(int(conflict.key)),Shortcuts.caption(str(conflict.holder))],14)
		text.add_theme_color_override("font_color",Color("ffd98a"))
		row.add_child(text)
		var swap: Button = world.button("交换",func():
			world.bind_shortcut(str(conflict.action),int(conflict.slot),int(conflict.key),true)
			conflict = {};rebuild())
		swap.name = "ShortcutSwap"
		row.add_child(swap)
		var cancel: Button = world.button("取消",func(): conflict = {};rebuild())
		cancel.name = "ShortcutCancel"
		row.add_child(cancel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH-24,380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation",4)
	scroll.add_child(list)
	for entry in Shortcuts.ACTIONS:
		var action: String = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		list.add_child(row)
		var caption: Label = world.text(entry[1],14)
		caption.custom_minimum_size.x = 200
		row.add_child(caption)
		for slot in range(Shortcuts.SLOTS):
			var waiting: bool = capturing==[action,slot]
			var code: int = int(world.shortcuts.get(action,[0,0])[slot])
			var key: Button = world.button("按下新键…" if waiting else Shortcuts.key_name(code),func():
				capturing = [action,slot];conflict = {};rebuild())
			key.name = "Shortcut_%s_%d" % [action,slot]
			key.custom_minimum_size.x = 130
			if waiting:key.add_theme_color_override("font_color",Color("ffd98a"))
			row.add_child(key)
	var reset: Button = world.button("恢复默认",func():
		world.reset_shortcuts();capturing = [];conflict = {};rebuild())
	reset.name = "ShortcutReset"
	body.add_child(reset)

## While a slot waits for a key, every key goes here first (before movement,
## M, Esc and the rest), so the game does not act on it.
func _input(event: InputEvent) -> void:
	if not visible or capturing.is_empty() or not event is InputEventKey or not event.pressed or event.echo:return
	get_viewport().set_input_as_handled()
	var action: String = capturing[0]
	var slot: int = capturing[1]
	capturing = []
	var code: int = event.physical_keycode if event.physical_keycode!=0 else event.keycode
	if code==KEY_ESCAPE:
		rebuild();return
	if code==KEY_BACKSPACE:code = 0
	var holder: String = world.bind_shortcut(action,slot,code)
	if not holder.is_empty():conflict = {"action":action,"slot":slot,"key":code,"holder":holder}
	rebuild()

## Follows sound changes made elsewhere (M, the 音乐 window, another page).
func _sync_sound() -> void:
	if not visible:return
	var sound := find_child("SettingsSound",true,false) as CheckBox
	if sound:sound.set_pressed_no_signal(not world.muted)
	var effects := find_child("SettingsEffects",true,false) as CheckBox
	if effects:effects.set_pressed_no_signal(world.effects_on)
	var slider := find_child("SettingsVolume",true,false) as HSlider
	if slider:slider.set_value_no_signal(world.volume)
	var effects_slider := find_child("SettingsEffectsVolume",true,false) as HSlider
	if effects_slider:effects_slider.set_value_no_signal(world.effects_volume)

const HELP := """移动
  点击地面寻路，或用 WASD / 方向键行走。
  鼠标滚轮、+ / − 或「设置 → 画面」的滑杆缩放（10% 到 200%）。
  R 回到村中广场，E 挥手，X 坐下 / 站起。

快捷键（默认，可在「设置 → 快捷键」修改）
  M 地图窗口　G 游戏助手　Tab 换角色　H 操作说明
  Esc 关闭最上面的窗口；没有窗口时打开设置

游戏助手（G、画面左上的「游戏助手」按钮，或「设置 → 助手」）
  自动练级：原地连续遇敌、抓宠或带宠升级；五人镜像队也在这里。
  自动抓极品：按先天档位和120级属性找宠，本机极速模式用所有 CPU 核心扫描；可自动捕获、练级、存仓，按保留规则整理。
    展示模式（默认开）：找到一只先亮出预测的120级属性，再以正常速度播放捕获和几场练级战斗；后台继续找，最多排队10只。
  宠物 · 同种比较：同种比较、仓库、收藏和放生。
  电台：原版配乐、收藏、歌单、随机和单曲循环。
  地图导航：按地图查看和传送。
  刷怪传送：按练级点传送到原版刷怪位置。
  开发者：GM 调试（等级、属性、体力、发放特殊宠物）。

地图窗口（M）
  下方有「地图导航」和「刷怪传送」。

底部菜单（鼠标移到屏幕底部出现）
  地图、状态、宠物（同种比较、仓库、放生）、道具、系统（打开设置）。

其他
  旅程自动保存。音量、音乐开关、音效、缩放、瞬移模式和快捷键由每台设备各自记住。"""

func _help_page() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH-24,420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var text: Label = world.text(HELP,14)
	text.name = "SettingsHelpText"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = WIDTH-40
	scroll.add_child(text)
