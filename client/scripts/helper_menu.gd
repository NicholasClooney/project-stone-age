extends PanelContainer
## 游戏助手: the windows this project added to the original game, in one list.
## Opened from 设置 and its shortcut (G by default, scripts/shortcuts.gd); Esc
## closes it. Each entry closes the list and opens its window. Styled like 设置
## (scripts/settings_menu.gd) and reachable with the gamepad.
const WIDTH := 520.0
const Shortcuts = preload("res://scripts/shortcuts.gd")
var world: Node
var body: VBoxContainer

func configure(owner: Node) -> void:
	world = owner
	name = "HelperMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	custom_minimum_size = Vector2(WIDTH,0)
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
	_center()

func _center() -> void:
	reset_size()
	var screen: Vector2 = world.get_viewport_rect().size
	position = ((screen-size)/2).max(Vector2(8,8))

## [node name, caption, what it does, shortcut action or "", opener].
func entries() -> Array:
	return [
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
	var close: Button = world.button("关闭 · Esc",close_menu)
	close.name = "HelperClose"
	header.add_child(close)
	var note: Label = world.text("本项目加入的功能，原版没有。",12)
	note.add_theme_color_override("font_color",Color("b6aa8a"))
	body.add_child(note)
	for entry in entries():_entry(entry)
	var developer: Label = world.text("开发者",15)
	developer.add_theme_color_override("font_color",Color("e6c284"))
	body.add_child(developer)
	_entry(["HelperGM","GM 调试","调整等级、属性和体力，发放特殊宠物。","",func(): world.dev_gm_menu.open_menu()])
	reset_size()

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
	body.add_child(row)
	var shortcut := ""
	if not str(entry[3]).is_empty():
		var keys: Array = world.shortcuts.get(entry[3],[]).filter(func(code): return int(code)!=0)
		if not keys.is_empty():shortcut = "  [%s]" % Shortcuts.key_name(int(keys[0]))
	var open: Button = world.button(str(entry[1])+shortcut,func():
		close_menu()
		entry[4].call())
	open.name = entry[0]
	open.custom_minimum_size = Vector2(150,34)
	if world.battle_view.visible and not _allowed_in_battle(str(entry[0])):
		open.disabled = true
		open.tooltip_text = "战斗结束后才能打开。"
	row.add_child(open)
	var about: Label = world.text(str(entry[2]),13)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	about.custom_minimum_size.x = WIDTH-190
	about.add_theme_color_override("font_color",Color("d8ccad"))
	row.add_child(about)
