extends Control
const PATH := "res://data/changelog.json"
var world: Node
var history: Dictionary = {}
var shell: PanelContainer
var previous_pause := false
var text_area: RichTextLabel
func configure(owner: Node) -> void:world = owner
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 250
	if FileAccess.file_exists(PATH):history = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	shell = PanelContainer.new()
	shell.position = Vector2(170,65)
	shell.size = Vector2(940,655)
	shell.add_theme_stylebox_override("panel",world.box(Color("192522"),Color("ac9564")))
	add_child(shell)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	shell.add_child(content)
	var top := HBoxContainer.new()
	content.add_child(top)
	var readable := FontVariation.new()
	readable.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	readable.variation_embolden = 0.25
	readable.variation_opentype = {"wght":500.0}
	var heading: Label = world.text("石器时代 · 更新日志 "+str(history.get("version","v0.0.0")),23)
	heading.add_theme_font_override("font",readable)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var close: Button = world.button("关闭 · Esc",close_menu)
	top.add_child(close)
	text_area = RichTextLabel.new()
	text_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_area.add_theme_font_override("normal_font",readable)
	text_area.add_theme_font_size_override("normal_font_size",18)
	text_area.add_theme_color_override("default_color",Color("f4eee0"))
	content.add_child(text_area)
	for entry in history.get("entries",[]):
		text_area.push_font_size(22)
		text_area.push_color(Color("f4d582"))
		text_area.add_text("%s  %s\n" % [entry.version,entry.title])
		text_area.pop();text_area.pop()
		text_area.add_text("%s · %s\n" % [entry.date,"新增" if entry.kind=="feat" else "修复"])
		for detail in entry.get("details",[]):text_area.add_text("• "+str(detail)+"\n")
		text_area.add_text("\n")
	if history.get("entries",[]).is_empty():text_area.add_text("尚无已提交的功能更新。")
	hide()
func open_menu() -> void:
	if visible:
		close_menu()
		return
	if world.paused_input or world.battle_view.visible or world.area_transition_busy:return
	previous_pause = world.paused_input
	world.clear_input()
	world.paused_input = true
	move_to_front()
	show()
	world.play_ui_sound(202)
func close_menu() -> void:
	hide()
	world.paused_input = previous_pause
	world.clear_input()
	world.play_ui_sound(203)
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
