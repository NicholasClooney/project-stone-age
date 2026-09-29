extends PanelContainer
## 设置: zoom, sound, character, 瞬移, saving, 更新日志 and 操作说明, plus a
## collapsed 开发者 section with GM 调试. Opened by the toolbar's 设置, the
## classic taskbar's 系统 and H (on 操作说明); Esc closes it. It pauses the
## field like the old Help panel it replaces, so it is game.help too (the
## gamepad's Start and panel lookup use that). Every choice here is this
## device's own (viewer.cfg), see game.gd's device settings.
const WIDTH := 560.0
var world: Node
var page := "main"
var developer_open := false
var body: VBoxContainer

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

## Shows the window on page "main" or "help" (操作说明).
func open_menu(start_page: String = "main") -> void:
	page = start_page
	if visible:rebuild()
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show()
	world.clear_input()
	world.paused_input = true

func close_menu() -> void:
	if not visible:return
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
	var title: Label = world.text("操作说明" if page=="help" else "设置",20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if page=="help":
		var back: Button = world.button("返回设置",func(): page = "main";rebuild();_center())
		back.name = "SettingsBack"
		header.add_child(back)
	var close: Button = world.button("关闭 · Esc",close_menu)
	close.name = "SettingsClose"
	header.add_child(close)
	if page=="help":_help_page()
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
	# 画面
	var view := _section("画面")
	for entry in [["−","ZoomMinus",func(): world.zoom_by(-world.ZOOM_STEP)],["+","ZoomPlus",func(): world.zoom_by(world.ZOOM_STEP)],["拉到最远","MaxOut",world.zoom_farthest]]:
		var control: Button = world.button(entry[0],func(): entry[2].call();_sync_zoom())
		control.name = entry[1]
		view.add_child(control)
	var zoom_label: Label = world.text("",14)
	zoom_label.name = "SettingsZoomValue"
	view.add_child(zoom_label)
	# 声音
	var sound := _section("声音")
	sound.add_child(_check("音乐 [M]","SettingsSound",not world.muted,func(on: bool):
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
	# 角色 and 移动
	var character := _section("角色")
	var choose: Button = world.button("换角色 [Tab]",func(): close_menu();world.change_character())
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
	var help: Button = world.button("操作说明 [H]",func(): page = "help";rebuild();_center())
	help.name = "SettingsHelp"
	about.add_child(help)
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

## Follows sound changes made elsewhere (M, the 音乐 window, another page).
func _sync_sound() -> void:
	if not visible:return
	var sound := find_child("SettingsSound",true,false) as CheckBox
	if sound:sound.set_pressed_no_signal(not world.muted)
	var effects := find_child("SettingsEffects",true,false) as CheckBox
	if effects:effects.set_pressed_no_signal(world.effects_on)
	var slider := find_child("SettingsVolume",true,false) as HSlider
	if slider:slider.set_value_no_signal(world.volume)

const HELP := """移动
  点击地面寻路，或用 WASD / 方向键行走。
  鼠标滚轮或「设置 → 画面」缩放。R 回到村中广场，E 挥手，X 坐下 / 站起。

快捷键
  M 音乐开关　Ctrl+M 地图窗口　Tab 换角色　H 操作说明　Esc 关闭窗口

工具栏
  地图导航：按地图查看和传送。
  刷怪传送：按练级点传送到原版刷怪位置。
  自动练级：原地连续遇敌、抓宠或带宠升级；五人镜像队也在这里。
  自动抓极品：按先天档位和120级属性找宠，本机极速模式用所有 CPU 核心扫描；可自动捕获、练级、存仓。
  音乐：原版配乐电台、收藏和歌单，以及音乐开关和音量。
  设置：画面、声音（音乐、音效、音量）、角色、瞬移、存档、更新日志和本说明；开发者区有 GM 调试。

底部菜单（鼠标移到屏幕底部出现）
  状态、宠物（同种比较、仓库、放生）、道具、系统（打开设置）。

其他
  旅程自动保存。音量、音乐开关、音效、缩放和瞬移模式由每台设备各自记住。"""

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
