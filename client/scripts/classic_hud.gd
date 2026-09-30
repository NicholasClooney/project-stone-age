extends Control
const SCALE := 1.25
const Highlight = preload("res://scripts/legacy_ui_highlight.gd")
const PerfRegistry = preload("res://scripts/perf_registry.gd")
var world: Node2D
var art: Dictionary = {}
var map_panel: Control
var map_coordinates: Label
var map_south_coordinates: Label
var status: Label
var hover_label := ""
var taskbar: Control
var bar: TextureRect
var reveal := 0.0
var task_buttons: Array[TextureButton] = []
var right_panel: Control
var map_name: Label
var map_view: Control
var dragging := false
var drag_offset := Vector2.ZERO
var pointer_position := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/ui/manifest.json"))
	for ident in manifest.images:
		art[int(ident)] = load("res://assets/legacy/ui/%s.png" % ident)
		PerfRegistry.track_texture("ui",ident,art[int(ident)])
	var left := Control.new()
	left.scale = Vector2.ONE*SCALE
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	picture(left,26236,Vector2.ZERO)
	var names := ["游戏设定","交换名片","加入队伍","交易","家族"]
	var ids := [26101,26103,26105,26234,26237]
	for i in range(ids.size()):
		var item := icon(left,ids[i],ids[i]+1,Vector2(3+i*33,3),names[i])
		# LAN phase 3 (scripts/party_panel.gd): 游戏设定 holds the 组队 switch,
		# 加入队伍 joins the player in front or leaves the party.
		if i==0:
			item.name = "GameSettingsButton"
			item.pressed.connect(func():if is_instance_valid(world.party_panel):world.party_panel.toggle_settings())
		elif i==2:
			item.name = "PartyButton"
			item.pressed.connect(func():if is_instance_valid(world.party_panel):world.party_panel.press_party_button())
			item.mouse_entered.connect(func():if is_instance_valid(world.party_panel):hover_label = world.party_panel.button_caption())
	right_panel = Control.new()
	right_panel.scale = Vector2.ONE*SCALE
	right_panel.size = Vector2(164,63)
	right_panel.clip_contents = true
	right_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right_panel)
	# Original center anchor + ADRN offset: y = 21 - 16 = 5.
	# Two adjacent time-strip frames fill the aperture continuously.
	picture(right_panel,26119,Vector2(72,5))
	picture(right_panel,26120,Vector2(136,5))
	picture(right_panel,26260,Vector2.ZERO)
	icon(right_panel,26111,26112,Vector2(4,4),"加入战斗")
	icon(right_panel,26113,26114,Vector2(35,4),"决斗")
	icon(right_panel,26249,26248,Vector2(66,4),"帮助")
	icon(right_panel,26115,26116,Vector2(106,42),"动作")
	bar = picture(self,26012,Vector2.ZERO)
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	status = world.text("",15)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(status)
	taskbar = Control.new()
	taskbar.scale = Vector2.ONE*SCALE
	taskbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(taskbar)
	var labels := ["地图  M","状态","宠物","道具","邮件","相簿","系统"]
	for i in range(7):
		var item := icon(taskbar,26150+i*2,26151+i*2,Vector2(i*92,0),labels[i])
		task_buttons.append(item)
		if i==0:
			item.pressed.connect(toggle_map)
		elif i==6:
			# 系统 opens 设置 (zoom, sound, character, saving, 操作说明).
			item.pressed.connect(func():
				if world.settings_menu.visible:world.settings_menu.close_menu()
				else:world.settings_menu.open_menu())
		elif i in [1,2,3]:
			var kind: String = {1:"status",2:"pets",3:"inventory"}[i]
			item.pressed.connect(func(): world.show_adventure_menu(kind))
	# Original bottom bar remains above battle presentation; top field HUD does not.
	var bottom_layer := CanvasLayer.new()
	bottom_layer.layer = 20
	add_child(bottom_layer)
	var bottom_root := Control.new()
	bottom_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_layer.add_child(bottom_root)
	for control in [bar,status,taskbar]:control.reparent(bottom_root)
	build_map()
	resized.connect(layout)
	layout()

func picture(parent: Node, ident: int, point: Vector2) -> TextureRect:
	var result := TextureRect.new()
	result.texture = art[ident]
	result.position = point
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func icon(parent: Node, normal: int, pressed: int, point: Vector2, caption: String) -> TextureButton:
	var result := TextureButton.new()
	result.texture_normal = art[normal]
	result.texture_pressed = art[pressed]
	result.texture_hover = art[normal]
	result.position = point
	result.focus_mode = Control.FOCUS_NONE
	result.tooltip_text = caption
	result.mouse_entered.connect(func(): hover_label = caption)
	result.mouse_exited.connect(func(): hover_label = "")
	parent.add_child(result)
	Highlight.attach(result,Rect2(Vector2(-2,-2),result.texture_normal.get_size()+Vector2(4,4)))
	return result

func layout() -> void:
	right_panel.position = Vector2(size.x-164*SCALE,0)
	bar.position = Vector2(0,size.y-24*SCALE)
	bar.size = Vector2(size.x,24*SCALE)
	status.position = Vector2(0,size.y-25)
	status.size = Vector2(size.x,24)
	map_panel.position = Vector2(size.x-248*SCALE-8,90)

func _process(delta: float) -> void:
	var pointer := pointer_position
	var at_bottom := pointer.y>=size.y-30*SCALE and pointer.y<=size.y
	reveal = move_toward(reveal,1.0 if at_bottom and not world.dialogue.visible and not (is_instance_valid(world.world_travel) and world.world_travel.overlay.visible) else 0.0,delta*6)
	taskbar.position = Vector2((size.x-640*SCALE)/2,size.y-24*SCALE*reveal)
	taskbar.visible = reveal>0
	status.visible = reveal<0.05
	status.text = hover_label if not hover_label.is_empty() else "一般频道                     %s (%d) 坐标 (%d, %d)                     玩家模式 0" % [world.area_name(),int(world.data.map_id),world.display_cell().x,world.display_cell().y]
	map_coordinates.text = str(world.display_cell().x)
	map_south_coordinates.text = str(world.display_cell().y)
	if dragging:
		map_panel.position = (pointer_position-drag_offset).clamp(Vector2.ZERO,(size-map_panel.size*SCALE).max(Vector2.ZERO))

func toggle_map() -> void:
	if is_instance_valid(world.world_travel) and world.world_travel.overlay.visible:return
	if is_instance_valid(world.battle_view) and world.battle_view.visible:
		world.play_battle_sound(220)
		return
	if world.dialogue.visible or world.help.visible or (is_instance_valid(world.adventure_menu) and world.adventure_menu.visible) or (is_instance_valid(world.battle_view) and world.battle_view.visible):
		return
	map_panel.visible = not map_panel.visible
	task_buttons[0].texture_normal = art[26151 if map_panel.visible else 26150]
	task_buttons[0].texture_hover = task_buttons[0].texture_normal
	world.play_ui_sound(202 if map_panel.visible else 203)

## The HUD outlives map changes; only the map window's title and picture change.
func refresh_map() -> void:
	map_name.text = world.area_name()
	if not is_same(map_view.built_for,world.data):map_view.rebuild()

func build_map() -> void:
	map_panel = Control.new()
	map_panel.size = Vector2(248,240)
	map_panel.scale = Vector2.ONE*SCALE
	map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(map_panel)
	picture(map_panel,26081,Vector2.ZERO)
	var name_label: Label = world.text(world.area_name(),13)
	map_name = name_label
	name_label.position = Vector2(22,30)
	name_label.add_theme_color_override("font_color",Color.WHITE)
	name_label.add_theme_color_override("font_outline_color",Color.BLACK)
	name_label.add_theme_constant_override("outline_size",1)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(name_label)
	map_view = preload("res://scripts/classic_map.gd").new()
	map_view.world = world
	map_panel.add_child(map_view)
	# The original frame has two separate 20px direction plaques and number slots.
	for info in [["东",61],["南",134]]:
		var direction: Label = world.text(info[0],12)
		direction.position = Vector2(info[1],185)
		direction.size = Vector2(18,18)
		direction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		direction.add_theme_color_override("font_color",Color.YELLOW)
		direction.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_panel.add_child(direction)
	map_coordinates = coordinate_number(Vector2(83,185))
	map_south_coordinates = coordinate_number(Vector2(156,185))
	var close := icon(map_panel,26042,26042,Vector2(84,214),"关闭地图")
	close.name = "CloseMap"
	close.pressed.connect(toggle_map)
	var title := Control.new()
	title.size = Vector2(248,27)
	title.mouse_default_cursor_shape = Control.CURSOR_DRAG
	title.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			drag_offset = pointer_position-map_panel.position)
	map_panel.add_child(title)
	_travel_menu()
	map_panel.hide()

## Below the map window: this project's travel windows (also in 游戏助手).
func _travel_menu() -> void:
	var strip := HBoxContainer.new()
	strip.name = "MapTravelMenu"
	strip.position = Vector2(4,244)
	strip.add_theme_constant_override("separation",4)
	map_panel.add_child(strip)
	for entry in [["MapOverviewButton","地图导航","按地图查看和传送",func(): world.dev_map_overview.open_map()],["MapTravelButton","刷怪传送","按练级点传送到原版刷怪位置",func(): world.leveling_destinations.open_menu()]]:
		var open: Button = world.button(entry[1],func():
			if map_panel.visible:toggle_map()
			entry[3].call())
		open.name = entry[0]
		open.tooltip_text = entry[2]
		open.add_theme_font_size_override("font_size",11)
		open.custom_minimum_size = Vector2(118,26)
		strip.add_child(open)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pointer_position = get_global_transform_with_canvas().affine_inverse()*event.position
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false

func coordinate_number(point: Vector2) -> Label:
	var number: Label = world.text("",12)
	number.position = point
	number.size = Vector2(36,18)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	number.add_theme_color_override("font_color",Color.YELLOW)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(number)
	return number
