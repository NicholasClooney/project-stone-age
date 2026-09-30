extends CenterContainer
## 登录: shown over the connection notice when the server hosts several
## profiles (server/profile_hub.gd). Pick a character and type its PIN, or
## create a new character (name and PIN; the first one on a server is its
## admin). The link (network/ws_link.gd) does the talking; the game remembers
## the login on this device (game_remote.gd) so the next visit skips this.
var world: Node
var link
var panel: PanelContainer
var list: VBoxContainer
var chosen_label: Label
var pin: LineEdit
var login_button: Button
var error: Label
var create_box: VBoxContainer
var create_toggle: Button
var new_name: LineEdit
var new_pin: LineEdit
var new_pin_again: LineEdit
var create_button: Button
var note: Label
var chosen := ""
var busy := false
## The last reply that logged in, for the game (created: a new character).
var last_login: Dictionary = {}

func configure(owner: Node, target_link) -> void:
	world = owner
	link = target_link

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The link overlay is outside the UI root's theme; without the CJK font the
	# web build (no system fonts) draws buttons and fields as missing glyphs.
	theme = Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansSC.ttf")
	hide()
	panel = PanelContainer.new()
	panel.name = "LoginPanel"
	panel.add_theme_stylebox_override("panel",world.box(Color("18211f"),Color("9d8354")))
	panel.custom_minimum_size = Vector2(380,0)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	panel.add_child(column)
	column.add_child(world.text("登录石器时代",20))
	note = world.text("选择你的角色，输入 PIN。",14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 360
	column.add_child(note)
	list = VBoxContainer.new()
	list.name = "LoginProfiles"
	column.add_child(list)
	chosen_label = world.text("",14)
	column.add_child(chosen_label)
	var row := HBoxContainer.new()
	column.add_child(row)
	pin = _field("LoginPin","PIN（4 到 8 位数字）",true)
	pin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pin.text_submitted.connect(func(_text):submit_login())
	row.add_child(pin)
	login_button = world.button("登录",submit_login)
	login_button.name = "LoginButton"
	row.add_child(login_button)
	error = world.text("",14)
	error.name = "LoginError"
	error.add_theme_color_override("font_color",Color("ff8a70"))
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.custom_minimum_size.x = 360
	column.add_child(error)
	column.add_child(HSeparator.new())
	create_toggle = world.button("创建新角色",func():
		create_box.visible = not create_box.visible
		if create_box.visible:new_name.grab_focus())
	create_toggle.name = "LoginCreateToggle"
	column.add_child(create_toggle)
	create_box = VBoxContainer.new()
	create_box.name = "LoginCreate"
	create_box.hide()
	column.add_child(create_box)
	new_name = _field("LoginNewName","角色名（最多 16 个字）",false)
	new_name.max_length = 16
	create_box.add_child(new_name)
	new_pin = _field("LoginNewPin","PIN（4 到 8 位数字）",true)
	create_box.add_child(new_pin)
	new_pin_again = _field("LoginNewPinAgain","再输一次 PIN",true)
	new_pin_again.text_submitted.connect(func(_text):submit_create())
	create_box.add_child(new_pin_again)
	create_button = world.button("创建并进入",submit_create)
	create_button.name = "LoginCreateButton"
	create_box.add_child(create_button)

func _field(node_name: String, placeholder: String, secret: bool) -> LineEdit:
	var field := LineEdit.new()
	field.name = node_name
	field.placeholder_text = placeholder
	field.secret = secret
	if secret:
		field.max_length = 8
		field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	field.custom_minimum_size = Vector2(220,30)
	return field

## The server wants a login: {profiles: [{name, admin, online}], allow_create, reason?}.
func open(info: Dictionary) -> void:
	busy = false
	var profiles: Array = info.get("profiles",[])
	for child in list.get_children():child.queue_free()
	for entry in profiles:
		var caption := str(entry.name)
		if bool(entry.get("admin",false)):caption += "（管理员）"
		if bool(entry.get("online",false)):caption += " · 在线"
		var choice: Button = world.button(caption,choose.bind(str(entry.name)))
		choice.name = "Profile_"+str(entry.name)
		list.add_child(choice)
	var can_create := bool(info.get("allow_create",true))
	create_toggle.visible = can_create and not profiles.is_empty()
	create_box.visible = can_create and profiles.is_empty()
	if profiles.is_empty():
		note.text = "这台服务器上还没有角色。创建第一个角色，它就是管理员（可用 GM 和开发者功能）。" if can_create else "这台服务器上还没有角色，请找管理员添加。"
	else:
		note.text = "选择你的角色，输入 PIN。" + ("" if can_create else "新角色请找管理员添加。")
	var remembered := str(link.login_name)
	chosen = ""
	for entry in profiles:
		if str(entry.name).to_lower()==remembered.to_lower():chosen = str(entry.name)
	if chosen.is_empty() and profiles.size()==1:chosen = str(profiles[0].name)
	error.text = str(info.get("reason",""))
	_refresh()
	show()
	if not chosen.is_empty():pin.grab_focus()

func choose(name: String) -> void:
	chosen = name
	error.text = ""
	_refresh()
	pin.grab_focus()

func _refresh() -> void:
	for child in list.get_children():
		if child is Button:child.modulate = Color("f8d678") if child.name=="Profile_"+chosen else Color.WHITE
	chosen_label.text = "角色：%s" % chosen if not chosen.is_empty() else "先点一个角色。"
	login_button.disabled = busy or chosen.is_empty()
	create_button.disabled = busy

func submit_login() -> void:
	if busy:return
	if chosen.is_empty():
		error.text = "先点一个角色。"
		return
	_send({"type":"login","name":chosen,"pin":pin.text.strip_edges()})

func submit_create() -> void:
	if busy:return
	if new_pin.text!=new_pin_again.text:
		error.text = "两次输入的 PIN 不一样。"
		return
	_send({"type":"create_profile","name":new_name.text.strip_edges(),"pin":new_pin.text.strip_edges()})

func _send(command: Dictionary) -> void:
	busy = true
	error.text = "正在登录…"
	_refresh()
	link.login(command,_on_reply)

func _on_reply(reply: Dictionary) -> void:
	busy = false
	if bool(reply.get("ok",false)) and reply.has("snapshot"):
		last_login = reply
		pin.text = ""
		new_pin.text = ""
		new_pin_again.text = ""
		error.text = ""
		hide()
		return
	error.text = "未连接服务器，请稍候重试。" if str(reply.get("reason",""))=="offline" else str(reply.get("reason","登录失败。"))
	pin.text = ""
	_refresh()
