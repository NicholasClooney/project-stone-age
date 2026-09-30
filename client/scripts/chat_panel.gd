extends Control
## 一般频道 (LAN phase 2): the chat lines of everyone on this map, bottom left
## above the classic bar as in the original (chat.cpp ChatBufferToFontBuffer:
## lines stacked upwards from x 8, y 400, no background), and the line to
## type in (Enter, or 说话). 记录 opens the scrollback of the last MAX_LINES.
## Only a device logged into a multi-profile server shows it; the lone
## single-player game has nobody to talk to.
const MAX_LINES := 100
## Collapsed, the newest lines of the last RECENT_SECONDS stay on the field.
const SHOWN_LINES := 4
const RECENT_SECONDS := 60.0
const MAX_CHARS := 60
const SYSTEM_COLOR := Color("ffe070")
const PARTY_COLOR := Color("a8f0a0")

var world: Node2D
## {text, color, time}
var lines: Array = []
var recent: VBoxContainer
var history: ScrollContainer
var history_lines: VBoxContainer
var input: LineEdit
var talk_button: Button
var log_button: Button
## 频道 (LAN phase 3): 一般 or 队伍, shown while in a party.
var channel_button: Button
var channel := "一般"
var clock: Callable = func() -> float:return Time.get_ticks_msec()/1000.0

func configure(owner: Node2D) -> void:
	world = owner
	name = "ChatPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 8
	offset_right = 8
	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation",2)
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(column)
	history = ScrollContainer.new()
	history.name = "History"
	history.custom_minimum_size = Vector2(420,220)
	history.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0.04,0.05,0.06,0.82)
	backdrop.set_corner_radius_all(3)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:backdrop.set_content_margin(side,4)
	history.add_theme_stylebox_override("panel",backdrop)
	history.hide()
	column.add_child(history)
	history_lines = VBoxContainer.new()
	history_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_lines.add_theme_constant_override("separation",0)
	history.add_child(history_lines)
	recent = VBoxContainer.new()
	recent.name = "Recent"
	recent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recent.add_theme_constant_override("separation",0)
	column.add_child(recent)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation",4)
	column.add_child(row)
	talk_button = world.button("说话",open_input)
	talk_button.name = "Talk"
	talk_button.tooltip_text = "一般频道：同一地图上的玩家都能看到（Enter）"
	log_button = world.button("记录",toggle_history)
	log_button.name = "Log"
	log_button.tooltip_text = "聊天记录"
	channel_button = world.button("一般",toggle_channel)
	channel_button.name = "Channel"
	channel_button.tooltip_text = "频道：一般（同地图）或队伍（队友，不论在哪张地图）"
	channel_button.hide()
	for button in [channel_button,talk_button,log_button]:
		button.add_theme_font_size_override("font_size",11)
		row.add_child(button)
	input = LineEdit.new()
	input.name = "Input"
	input.max_length = MAX_CHARS
	input.placeholder_text = "一般频道：Enter 发送，Esc 取消"
	input.custom_minimum_size = Vector2(320,0)
	input.add_theme_font_size_override("font_size",13)
	input.hide()
	input.text_submitted.connect(_submit)
	input.gui_input.connect(func(event: InputEvent):
		if event.is_action_pressed("ui_cancel"):
			close_input()
			input.accept_event())
	input.focus_exited.connect(func():if input.text.is_empty():close_input())
	row.add_child(input)
	hide()

## Whether this device talks to anyone: logged into a multi-profile server.
func available() -> bool:
	return world!=null and world.link!=null and not world.link.is_local() and not world.link.account.is_empty()

func _process(_delta: float) -> void:
	var wanted: bool = available() and not world.data.is_empty()
	if wanted!=visible:
		visible = wanted
		if not wanted:close_input()
	if not visible:return
	var partied: bool = is_instance_valid(world.party_panel) and world.party_panel.in_party()
	if partied!=channel_button.visible:
		channel_button.visible = partied
		_update_channel()
	var bar: float = world.classic_hud.bar.size.y if is_instance_valid(world.classic_hud) else 30.0
	var column: Control = get_node("Column")
	column.position = Vector2(0,-column.size.y-bar-6)
	_refresh_recent()

func open_input() -> void:
	if not available():return
	input.show()
	input.grab_focus()
	world.clear_input()

func close_input() -> void:
	if input==null:return
	input.text = ""
	input.hide()
	if input.has_focus():input.release_focus()

func typing() -> bool:
	return input!=null and input.visible and input.has_focus()

func toggle_history() -> void:
	history.visible = not history.visible
	if history.visible:_scroll_to_end()

func _submit(line: String) -> void:
	var text := line.strip_edges()
	close_input()
	if text.is_empty():return
	var command := {"type":"say","text":text}
	if party_channel():command.channel = "队伍"
	world.link.request(command,func(reply: Dictionary):
		if not bool(reply.get("ok",false)) and str(reply.get("reason",""))!="offline":add_line(str(reply.get("reason","")),SYSTEM_COLOR))

## A chat event from the server: 一般频道, 队伍频道 (LAN phase 3) or a system
## line (组队 news, in the original's yellow).
func on_event(event: Dictionary) -> void:
	if str(event.get("type",""))!="chat":return
	match str(event.get("channel","一般")):
		"系统":add_line(str(event.get("text","")),SYSTEM_COLOR)
		"队伍":add_line("[队伍] %s：%s" % [str(event.get("name","")),str(event.get("text",""))],PARTY_COLOR)
		_:add_line("%s：%s" % [str(event.get("name","")),str(event.get("text",""))],Color("b8f0ff") if bool(event.get("mine",false)) else Color.WHITE)

## 队伍频道 while in a party and chosen with the 频道 button.
func party_channel() -> bool:
	return channel=="队伍" and is_instance_valid(world.party_panel) and world.party_panel.in_party()

func toggle_channel() -> void:
	channel = "一般" if channel=="队伍" else "队伍"
	_update_channel()

func _update_channel() -> void:
	var party := party_channel()
	channel_button.text = "队伍" if party else "一般"
	input.placeholder_text = ("队伍频道" if party else "一般频道")+"：Enter 发送，Esc 取消"

func add_line(text: String, color: Color = Color.WHITE) -> void:
	lines.append({"text":text,"color":color,"time":float(clock.call())})
	while lines.size()>MAX_LINES:lines.pop_front()
	if history_lines==null:return
	history_lines.add_child(_line_label(text,color))
	while history_lines.get_child_count()>MAX_LINES:
		var oldest := history_lines.get_child(0)
		history_lines.remove_child(oldest)
		oldest.queue_free()
	_refresh_recent(true)
	if history.visible:_scroll_to_end()

func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(history):history.scroll_vertical = int(history.get_v_scroll_bar().max_value)

## The field shows the newest lines of the last minute, unless 记录 is open.
func recent_lines() -> Array:
	if history!=null and history.visible:return []
	var now := float(clock.call())
	return lines.slice(maxi(0,lines.size()-SHOWN_LINES)).filter(func(line):return now-float(line.time)<RECENT_SECONDS)

var _recent_key := ""
func _refresh_recent(force: bool = false) -> void:
	var shown := recent_lines()
	var key := "%d:%d" % [lines.size(),shown.size()]
	if key==_recent_key and not force:return
	_recent_key = key
	for child in recent.get_children():child.queue_free()
	for line in shown:recent.add_child(_line_label(str(line.text),line.color))

func _line_label(text: String, color: Color) -> Label:
	var label: Label = world.text(text,13)
	label.add_theme_color_override("font_color",color)
	# An outline, not a 1-pixel shadow: lines stay readable on snow and on the backdrop.
	label.add_theme_color_override("font_outline_color",Color(0,0,0,0.9))
	label.add_theme_constant_override("outline_size",4)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.custom_minimum_size.x = 410
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
