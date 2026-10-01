extends PanelContainer
## 游戏助手: the windows this project added to the original game, in one list.
## Opened from 设置 and its shortcut (G by default, scripts/shortcuts.gd); Esc
## closes it. Each entry closes the list and opens its window. Styled like 设置
## (scripts/settings_menu.gd) and reachable with the gamepad.
const WIDTH := 520.0
const Shortcuts = preload("res://scripts/shortcuts.gd")
var world: Node
var body: VBoxContainer
var content: VBoxContainer
var grid: GridContainer
var view := "list"
var icons: Dictionary = {}

func configure(owner: Node) -> void:
	world = owner
	name = "HelperMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	custom_minimum_size = Vector2(minf(WIDTH,world.get_viewport_rect().size.x-16),0)
	add_theme_stylebox_override("panel",world.box(Color("20292f",0.97),Color("b29b65")))
	visibility_changed.connect(func():
		if visible:
			rebuild()
			_center())
	hide()

func open_menu() -> void:
	# Opens over a battle too; entries the battle does not allow are greyed.
	if world.dialogue.visible:return
	if visible:rebuild()
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show()
	world.clear_input()
	world.paused_input = true

func close_menu() -> void:
	if not visible:return
	hide()
	world.paused_input = world.battle_view.visible or world.automation_minimized()
	world.clear_input()

func relayout() -> void:
	if visible:rebuild()
	_center()

func _center() -> void:
	reset_size()
	var screen: Vector2 = world.get_viewport_rect().size
	position = ((screen-size)/2).max(Vector2(8,8))

## [node name, caption, what it does, shortcut action or "", opener].
func entries() -> Array:
	return [
		["HelperQuest","任务助手","原版任务步骤、进度和 NPC 传送；奖励由原对话确认。","",func(): world.quest_helper_menu.open_menu()],
		["HelperTraining","自动练级","原地连续遇敌、抓宠或带宠升级；五人镜像队也在这里。","",func(): world.training_helper.open_menu()],
		["HelperPetHunt","自动抓极品","按先天档位和120级属性找宠，可自动捕获、练级、存仓和按保留规则整理。","",func(): world.pet_hunt_menu.open_menu()],
		["HelperPets","宠物 · 同种比较","宠物窗口：同种比较、仓库、收藏和放生。","",func(): world.show_adventure_menu("pets")],
		["HelperEncyclopedia","宠物大全","每种宠物的原版图、成长资料、满档120级预测排名和野外出现地点；可瞬移去抓。","encyclopedia",func(): world.pet_encyclopedia.open_menu()],
		["HelperPetRecords","宠物记录","抓到和放生的记录：这一轮找宠抓到了什么，放掉了哪些、为什么、被谁比下去。","",func(): world.adventure_menu.open_pet_records("caught",-1)],
		["HelperRadio","电台","原版配乐：全部曲目、收藏、歌单、随机和单曲循环。","radio",func(): world.toggle_radio()],
		["HelperMapOverview","地图导航","按地图查看和传送。地图窗口（M）下方也可以打开。","",func(): world.dev_map_overview.open_map()],
		["HelperTravel","刷怪传送","按练级点传送到原版刷怪位置。地图窗口下方也可以打开。","",func(): world.leveling_destinations.open_menu()],
	]

func rebuild() -> void:
	view = "grid" if str(world.viewer_pref("helper_view","list"))=="grid" else "list"
	var screen: Vector2 = world.get_viewport_rect().size
	custom_minimum_size = Vector2(minf(WIDTH,maxf(280,screen.x-16)),0)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title: Label = world.text("游戏助手",20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for mode in ["list","grid"]:
		var toggle: Button = world.button("列表" if mode=="list" else "网格",func():
			world.set_viewer_pref("helper_view",mode)
			rebuild()
			_center()
			(find_child("HelperViewList" if mode=="list" else "HelperViewGrid",true,false) as Button).grab_focus())
		toggle.name = "HelperViewList" if mode=="list" else "HelperViewGrid"
		toggle.focus_mode = Control.FOCUS_ALL
		toggle.toggle_mode = true
		toggle.button_pressed = view==mode
		header.add_child(toggle)
	var close: Button = world.button("关闭 · Esc",close_menu)
	close.name = "HelperClose"
	close.focus_mode = Control.FOCUS_ALL
	header.add_child(close)
	var note: Label = world.text("本项目加入的功能，原版没有。",12)
	note.add_theme_color_override("font_color",Color("b6aa8a"))
	body.add_child(note)
	var encounters := CheckButton.new()
	encounters.name = "HelperNoRandomEncounters"
	encounters.text = "不遇敌 · 地图随机遇敌"
	encounters.tooltip_text = "按角色保存；主动刷怪、搜宠和剧情战斗照常。"
	encounters.button_pressed = bool(world.state.derived.get("no_random_encounters",false))
	encounters.toggled.connect(func(enabled: bool):
		encounters.disabled = true
		world.link.request({"type":"no_random_encounters","enabled":enabled},func(_reply: Dictionary):
			if visible:rebuild();_center()))
	body.add_child(encounters)
	var scroll := ScrollContainer.new()
	scroll.name = "HelperScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = minf(480,maxf(80,screen.y-220))
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8)
	scroll.add_child(content)
	grid = null
	if view=="grid":
		grid = GridContainer.new()
		grid.name = "HelperGrid"
		grid.columns = maxi(1,int((custom_minimum_size.x-32)/145))
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation",8)
		grid.add_theme_constant_override("v_separation",8)
		content.add_child(grid)
	for entry in entries():_entry(entry)
	var developer: Label = world.text("开发者",15)
	developer.add_theme_color_override("font_color",Color("e6c284"))
	content.add_child(developer)
	grid = null
	_entry(["HelperGM","GM 调试","调整等级、属性和体力，发放特殊宠物。","",func(): world.dev_gm_menu.open_menu()])
	var paging := HBoxContainer.new()
	body.add_child(paging)
	for forward in [false,true]:
		var page_button: Button = world.button("下一页" if forward else "上一页",func():
			scroll.scroll_vertical += int(scroll.size.y*0.8)*(1 if forward else -1))
		page_button.focus_mode = Control.FOCUS_ALL
		page_button.name = "HelperScrollNext" if forward else "HelperScrollPrevious"
		page_button.tooltip_text = "滚动助手内容；手柄 LB / RB"
		paging.add_child(page_button)
	reset_size()

func _process(_delta: float) -> void:
	if not visible:return
	var toggle = find_child("HelperNoRandomEncounters",true,false)
	if toggle is CheckButton and not toggle.disabled:
		toggle.set_pressed_no_signal(bool(world.state.derived.get("no_random_encounters",false)))
	var target: Control = world.gamepad.target
	if is_instance_valid(target) and is_ancestor_of(target):
		var scroll: ScrollContainer = find_child("HelperScroll",true,false)
		if scroll.is_ancestor_of(target):scroll.ensure_control_visible(target)

## Entries usable while a battle is on screen: the pet windows, 电台, GM (its
## 立即脱战) and a minimized automation window coming back.
func _allowed_in_battle(entry_name: String) -> bool:
	match entry_name:
		"HelperPets","HelperEncyclopedia","HelperPetRecords","HelperRadio","HelperGM":return true
		"HelperTraining":return world.training_helper.minimized
		"HelperPetHunt":return world.pet_hunt_menu.minimized
	return false

func _entry(entry: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	if is_instance_valid(grid):grid.add_child(row)
	else:content.add_child(row)
	var shortcut := ""
	if not str(entry[3]).is_empty():
		var keys: Array = world.shortcuts.get(entry[3],[]).filter(func(code): return int(code)!=0)
		if not keys.is_empty():shortcut = "  [%s]" % Shortcuts.key_name(int(keys[0]))
	var open: Button = world.button(str(entry[1])+shortcut,func():
		close_menu()
		entry[4].call())
	open.name = entry[0]
	open.focus_mode = Control.FOCUS_ALL
	open.tooltip_text = str(entry[2])+shortcut
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.custom_minimum_size = Vector2(130,100) if view=="grid" else Vector2(130,34)
	if view=="grid":
		open.text = ""
		var tile := VBoxContainer.new()
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile.offset_top = 8
		tile.offset_bottom = -8
		open.add_child(tile)
		var picture := TextureRect.new()
		picture.texture = _icon(str(entry[0]))
		picture.custom_minimum_size = Vector2(40,40)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(picture)
		var caption: Label = world.text(str(entry[1])+shortcut,13)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.size_flags_vertical = Control.SIZE_EXPAND_FILL
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(caption)
	if world.battle_view.visible and not _allowed_in_battle(str(entry[0])):
		open.disabled = true
		open.tooltip_text = "战斗结束后才能打开。\n"+open.tooltip_text
		open.modulate = Color(0.55,0.55,0.55)
	row.add_child(open)
	if view=="grid":return
	var about: Label = world.text(str(entry[2]),13)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	about.custom_minimum_size.x = maxf(100,custom_minimum_size.x-190)
	about.add_theme_color_override("font_color",Color("d8ccad"))
	row.add_child(about)

## Small purpose-specific line icons; generated once, with no asset download.
func _icon(entry_name: String) -> Texture2D:
	if icons.has(entry_name):return icons[entry_name]
	var paths := {
		"HelperQuest":"M12 6h24v36H12z M18 16h12 M18 24h12 M18 32h8 M20 6V3h8v3",
		"HelperTraining":"M8 40l16-32 16 32z M18 30h12 M24 8v14",
		"HelperPetHunt":"M8 16h6 M8 16v-6 M34 10h6v6 M40 34v6h-6 M14 40H8v-6 M16 24a8 8 0 1 0 16 0a8 8 0 1 0-16 0",
		"HelperPets":"M16 30c-8 8-2 14 8 8 10 6 16 0 8-8-6-10-10-10-16 0 M10 18a3 4 0 1 0 6 0a3 4 0 1 0-6 0 M21 12a3 4 0 1 0 6 0a3 4 0 1 0-6 0 M32 18a3 4 0 1 0 6 0a3 4 0 1 0-6 0",
		"HelperEncyclopedia":"M24 12c-6-5-12-5-18-3v28c6-2 12-2 18 3 6-5 12-5 18-3V9c-6-2-12-2-18 3v28",
		"HelperPetRecords":"M12 6h24v36H12z M18 15h12 M18 23h12 M18 31l4 4 8-8",
		"HelperRadio":"M12 20h24v20H12z M17 20L33 6 M17 28h2 M25 27h7 M25 33h7",
		"HelperMapOverview":"M6 12l12-6 12 6 12-6v30l-12 6-12-6-12 6z M18 6v30 M30 12v30",
		"HelperTravel":"M26 4L12 26h12l-2 18 16-26H26z",
		"HelperGM":"M10 10l12 12 M7 7l8 2-6 6z M22 22l18 18 M40 8l-8 2 2 6-24 24 M34 16l6-2 2-8",
	}
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48"><path d="%s" fill="none" stroke="#e6c284" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>' % paths.get(entry_name,paths.HelperQuest)
	var bitmap := Image.new()
	bitmap.load_svg_from_string(svg)
	var result := ImageTexture.create_from_image(bitmap)
	icons[entry_name] = result
	return result
