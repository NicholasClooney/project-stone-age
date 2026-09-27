extends Control
## Developer chooser; previews are original animated SPR actors, not portraits.
var world: Node2D
var shell: PanelContainer
var previous_pause := false
var buttons: Dictionary = {}
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
func _refresh() -> void:
	var current: String = world.session.snapshot().get("character_id","100000")
	for id in buttons:
		buttons[id].modulate = Color("f8d678") if id == current else Color.WHITE
func _layout() -> void:
	if shell == null:return
	shell.position = Vector2(maxf(8,(size.x-858)/2),maxf(8,(size.y-690)/2))
	shell.size = Vector2(minf(858,size.x-16),minf(690,size.y-16))
