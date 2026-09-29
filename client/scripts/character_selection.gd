extends Control
## Developer chooser; previews are original animated SPR actors, not portraits.
var world: Node2D
var shell: PanelContainer
var previous_pause := false
var buttons: Dictionary = {}
const Faces = preload("res://scripts/faces.gd")
## 人物面部: the chosen appearance's face with the original creation screen's
## eye and mouth choices (login.cpp:3545-3592, five of each, wrapping).
var face_view: TextureRect
var face_label: Label
func configure(owner: Node2D) -> void:world = owner
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	hide()
	resized.connect(_layout)
	process_mode = Node.PROCESS_MODE_DISABLED
func open_menu() -> void:
	if world.battle_view.visible or world.area_transition_busy:return
	# On the web every character's art is a separate pack; fetch them all
	# (once, then cached) before drawing, or most portraits would be empty.
	var packs := character_packs()
	if not world.asset_packs.is_ready(packs):
		world.asset_packs.ensure(packs,func(ok: bool):
			if ok:open_menu()
			else:world.message.text = "角色素材下载失败，请检查与 MacBook 的连接后重试。","角色")
		return
	process_mode = Node.PROCESS_MODE_INHERIT
	previous_pause = world.paused_input
	world.clear_input()
	world.paused_input = true
	_set_dev_visible(false)
	if shell == null:_build()
	_refresh()
	show()
	world.play_ui_sound(202)
	_layout()
func close_menu() -> void:
	hide()
	world.play_ui_sound(203)
	world.paused_input = previous_pause
	_set_dev_visible(true)
	process_mode = Node.PROCESS_MODE_DISABLED
func _set_dev_visible(value: bool) -> void:
	for child in get_parent().get_children():
		if child is HFlowContainer:child.visible=value

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB):
		close_menu()
		get_viewport().set_input_as_handled()
func _build() -> void:
	shell = PanelContainer.new()
	shell.add_theme_stylebox_override("panel",world.box(Color("18211f"),Color("9d8354")))
	add_child(shell)
	var content := VBoxContainer.new()
	shell.add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var title := Label.new()
	title.text = "DEV · 选择角色"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "关闭 [Esc]"
	close.pressed.connect(close_menu)
	heading.add_child(close)
	var face_row := HBoxContainer.new()
	face_row.add_theme_constant_override("separation",8)
	content.add_child(face_row)
	face_view = TextureRect.new()
	face_view.name = "FacePreview"
	face_view.custom_minimum_size = Vector2(64,72)
	face_view.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	face_row.add_child(face_view)
	var face_controls := VBoxContainer.new()
	face_row.add_child(face_controls)
	face_label = Label.new()
	face_controls.add_child(face_label)
	for part in [["眼睛",5],["嘴巴",1]]:
		var row := HBoxContainer.new()
		face_controls.add_child(row)
		var caption := Label.new()
		caption.text = str(part[0])
		row.add_child(caption)
		for step in [-1,1]:
			var arrow := Button.new()
			arrow.text = "◀" if step < 0 else "▶"
			arrow.name = "Face_%s_%s" % [part[0],"prev" if step < 0 else "next"]
			var unit: int = part[1]
			arrow.pressed.connect(func(): change_face(unit,step))
			row.add_child(arrow)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation",6)
	grid.add_theme_constant_override("v_separation",6)
	scroll.add_child(grid)
	var choices: Array = world.character_catalog.get("choices",[])
	if choices.is_empty():
		for id in ["100000","100005","100010"]:choices.append({"id":id,"family":1,"palette":int((int(id)-100000)/5)+1})
	for choice in choices:
		var button := Button.new()
		button.name = "Character_"+str(choice.id)
		button.custom_minimum_size = Vector2(98,108)
		button.text = "角色%02d · 色%d" % [int(choice.family),int(choice.palette)]
		button.add_theme_font_size_override("font_size",11)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("outline_size",0)
		# Text occupies the bottom; the original actor stands above it.
		var style := StyleBoxFlat.new()
		style.bg_color = Color("253830")
		style.content_margin_top = 87
		button.add_theme_stylebox_override("normal",style)
		button.tooltip_text = "原始角色 "+str(choice.id)
		button.pressed.connect(func():
			world.change_character(str(choice.id))
			_refresh())
		grid.add_child(button)
		buttons[str(choice.id)] = button
		var actor = preload("res://scripts/legacy_actor.gd").new()
		actor.world = world
		actor.character_id = str(choice.id)
		actor.facing = 0
		actor.position = Vector2(49,83)
		button.add_child(actor)
## Packs holding the art of every selectable character (empty on desktop).
func character_packs() -> Array:
	var packs: Array = []
	for choice in world.character_catalog.get("choices",[]):
		var pack: String = world.asset_packs.character_pack(choice.id)
		if not pack.is_empty() and not pack in packs:packs.append(pack)
	return packs

## Eye (unit 5) or mouth (unit 1) one step on, wrapping within 0..4.
func change_face(unit: int, step: int) -> void:
	var face := int(world.session.snapshot().get("face",0))
	var eye := int(face/5)
	var mouth := face%5
	if unit == 5:eye = (eye+step+5)%5
	else:mouth = (mouth+step+5)%5
	if world.session.set_face(eye*5+mouth):
		world.play_click()
	_refresh()

func _refresh() -> void:
	var profile: Dictionary = world.session.snapshot()
	var current: String = profile.get("character_id","100000")
	for id in buttons:
		buttons[id].modulate = Color("f8d678") if id == current else Color.WHITE
	if face_view != null:
		var face := int(profile.get("face",0))
		face_view.texture = Faces.texture(current,face)
		face_label.text = "人物面部 · 眼睛 %d · 嘴巴 %d" % [int(face/5)+1,face%5+1] if face_view.texture != null else "人物面部未导入（tools/import_faces.py）"
func _layout() -> void:
	if shell == null:return
	shell.position = Vector2(maxf(8,(size.x-858)/2),maxf(8,(size.y-690)/2))
	shell.size = Vector2(minf(858,size.x-16),minf(690,size.y-16))
