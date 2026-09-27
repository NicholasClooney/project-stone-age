extends Control
const SCALE := 1.25
var world: Node2D
var art: Dictionary = {}
var map_panel: Control
var map_coordinates: Label
var status: Label
var hover_label := ""
var taskbar: Control
var bar: TextureRect
var reveal := 0.0
var task_buttons: Array[TextureButton] = []
var right_panel: Control
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
	var left := Control.new()
	left.scale = Vector2.ONE*SCALE
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	picture(left,26236,Vector2.ZERO)
	var names := ["游戏设定","交换名片","加入队伍","交易","家族"]
	var ids := [26101,26103,26105,26234,26237]
	for i in range(ids.size()):
		icon(left,ids[i],ids[i]+1,Vector2(3+i*33,3),names[i])
	right_panel = Control.new()
	right_panel.scale = Vector2.ONE*SCALE
	right_panel.size = Vector2(164,63)
	right_panel.clip_contents = true
	right_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right_panel)
	picture(right_panel,26120,Vector2(128,0))
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
	var labels := ["地图  Ctrl+M","状态","宠物","道具","邮件","相簿","系统"]
	for i in range(7):
		var item := icon(taskbar,26150+i*2,26151+i*2,Vector2(i*92,0),labels[i])
		task_buttons.append(item)
		if i==0:
			item.pressed.connect(toggle_map)
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
	result.texture_hover = art[pressed]
	result.position = point
	result.focus_mode = Control.FOCUS_NONE
	result.tooltip_text = caption
	result.mouse_entered.connect(func(): hover_label = caption)
	result.mouse_exited.connect(func(): hover_label = "")
	parent.add_child(result)
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
	reveal = move_toward(reveal,1.0 if at_bottom and not world.dialogue.visible else 0.0,delta*6)
	taskbar.position = Vector2((size.x-640*SCALE)/2,size.y-24*SCALE*reveal)
	taskbar.visible = reveal>0
	status.visible = reveal<0.05
	status.text = hover_label if not hover_label.is_empty() else "一般频道                     萨姆吉尔村 (1000) 坐标 (%d, %d)                     玩家模式 0" % [world.cell.x,world.cell.y]
	map_coordinates.text = "东 %3d      南 %3d" % [world.cell.x,world.cell.y]
	if dragging:
		map_panel.position = (pointer_position-drag_offset).clamp(Vector2.ZERO,(size-map_panel.size*SCALE).max(Vector2.ZERO))

func toggle_map() -> void:
	if world.dialogue.visible or world.help.visible:
		return
	map_panel.visible = not map_panel.visible
	task_buttons[0].texture_normal = art[26151 if map_panel.visible else 26150]
	world.play_click()

func build_map() -> void:
	map_panel = Control.new()
	map_panel.size = Vector2(248,240)
	map_panel.scale = Vector2.ONE*SCALE
	map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(map_panel)
	picture(map_panel,26081,Vector2.ZERO)
	var name_label: Label = world.text("萨姆吉尔村",13)
	name_label.position = Vector2(22,30)
	name_label.add_theme_color_override("font_color",Color.WHITE)
	name_label.add_theme_color_override("font_outline_color",Color.BLACK)
	name_label.add_theme_constant_override("outline_size",1)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(name_label)
	var map_view := preload("res://scripts/classic_map.gd").new()
	map_view.world = world
	map_panel.add_child(map_view)
	map_coordinates = world.text("",13)
	map_coordinates.position = Vector2(61,183)
	map_coordinates.add_theme_color_override("font_color",Color.YELLOW)
	map_coordinates.add_theme_color_override("font_outline_color",Color.BLACK)
	map_coordinates.add_theme_constant_override("outline_size",1)
	map_coordinates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(map_coordinates)
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
	map_panel.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pointer_position = get_global_transform_with_canvas().affine_inverse()*event.position
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
