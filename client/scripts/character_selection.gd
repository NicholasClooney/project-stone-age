extends Control
## Developer chooser; previews are original animated SPR actors, not portraits.
var world: Node2D
var shell: PanelContainer
var previous_pause := false
var buttons: Dictionary = {}
const Riding = preload("res://scripts/riding.gd")
var ride_pet: Dictionary = {}
var ride_context: Dictionary = {}
var ride_choices: Array[String] = []
var ride_selected := ""
var grid: GridContainer
var face_row: HBoxContainer
var ride_controls: VBoxContainer
var confirmation: Label
var confirm_button: Button
var direction := 1
var preview_bounds: Dictionary = {}
var _intent := 0
var _loading := false
var _pending_confirm := false
var _ride_error := ""


func open_for_mount(pet: Dictionary) -> void:
	if world.battle_view.visible or world.area_transition_busy or world.moving:return
	ride_pet = pet.duplicate(true)
	ride_choices = Riding.compatible_characters(int(pet.get("sprite",0)))
	ride_context = {"expected_character":str(world.session.snapshot().get("character_id","")),"map_id":int(world.data.map_id),"cell":[world.cell.x,world.cell.y]}
	ride_selected = ""
	_ride_error = ""
	title_text = "骑乘 · 选择兼容造型"
	open_menu(true)

func _choose(id: String) -> void:
	if _pending_confirm or _loading:return
	_ride_error = ""
	if ride_pet.is_empty():
		world.change_character(id)
	else:
		ride_selected = id
	_refresh()

func _confirm_mount() -> void:
	if ride_selected.is_empty() or _pending_confirm or _loading:return
	_pending_confirm = true
	_ride_error = ""
	_refresh()
	var command := ride_context.duplicate(true)
	command.merge({"type":"mount_pet_as","pet_id":str(ride_pet.get("pet_id","")),"character_id":ride_selected},true)
	var ticket := _intent
	var owner_ref: WeakRef = weakref(self)
	world.link.request(command,func(reply: Dictionary):
		var owner = owner_ref.get_ref()
		if is_instance_valid(owner):owner._mount_reply(ticket,reply))

func _mount_reply(ticket: int, reply: Dictionary) -> void:
	if not is_inside_tree() or ticket!=_intent or not visible:return
	_pending_confirm = false
	if reply.get("ok",false):
		close_menu()
		world.refresh_companion()
		world.adventure_menu.refresh()
	else:
		var reason := str(reply.get("reason","骑乘失败，请重试。"))
		_ride_error = "保存失败，造型和骑乘未改变，请重试。" if reason=="save_failed" else ("连接已断开，尚未确认骑乘，请重连后重试。" if reason=="offline" else reason)
		_refresh()

## Fit every walking direction/frame inside the preview, including large mounts.
## Keep a single scale and origin across the cycle so feet do not jitter.
func _fit_mount(actor) -> void:
	var id: String = actor.mounted_character_id
	if id.is_empty():return
	if not preview_bounds.has(id):
		var art := Riding.art(id)
		if art.is_empty():return
		var bounds := Rect2()
		var first := true
		for key in art.animations:
			if not str(key).begins_with("4_"):continue
			var animation: Dictionary = art.animations[key]
			for i in range(preload("res://scripts/sprite_art.gd").frame_count(animation)):
				var bitmap := preload("res://scripts/sprite_art.gd").image(animation,i)
				if not art.bitmaps.has(bitmap):continue
				var row := int(art.bitmaps[bitmap])*8
				var rect := Rect2(preload("res://scripts/sprite_art.gd").offset(art,animation,i),Vector2(art.rows[row+3],art.rows[row+4]))
				bounds = rect if first else bounds.merge(rect)
				first = false
		preview_bounds[id] = bounds
	var bounds: Rect2 = preview_bounds[id]
	if not bounds.has_area():return
	var factor := minf(0.75,minf(134.0/bounds.size.x,128.0/bounds.size.y))
	actor.scale = Vector2.ONE*factor
	actor.position = Vector2(75,72)-bounds.get_center()*factor

func _turn_preview(step: int) -> void:
	direction = posmod(direction+step,8)
	_refresh()

const Faces = preload("res://scripts/faces.gd")
## 人物面部: the chosen appearance's face with the original creation screen's
## eye and mouth choices (login.cpp:3545-3592, five of each, wrapping).
var face_view: TextureRect
var face_label: Label
## The window's title: a new character on a multi-profile server says so.
var title_text := "DEV · 选择角色"
var title_label: Label
func configure(owner: Node2D) -> void:
	world = owner
	world.link.message.connect(_loading_event)
	if world.link.has_signal("disconnected"):world.link.disconnected.connect(_loading_disconnected)

func _loading_event(event: Dictionary) -> void:
	if _loading and str(event.get("type","")) in ["position","battle_started"]:close_menu()

func _loading_disconnected() -> void:
	if _loading:close_menu()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	hide()
	resized.connect(_layout)
	process_mode = Node.PROCESS_MODE_DISABLED
func open_menu(for_mount: bool = false) -> void:
	if world.battle_view.visible or world.area_transition_busy:return
	if not for_mount and not ride_pet.is_empty():
		ride_pet = {}
		ride_context = {}
		ride_choices.clear()
		ride_selected = ""
		title_text = "DEV · 选择角色"
	_intent += 1
	_pending_confirm = false
	_loading = true
	_face = -1
	var ticket := _intent
	var context := {"map_id":int(world.data.get("map_id",-1)),"cell":world.cell,"character_id":str(world.session.snapshot().get("character_id",""))}
	var owner_ref: WeakRef = weakref(self)
	var packs := character_packs()
	world.asset_packs.ensure(packs,func(ok: bool):
		var owner = owner_ref.get_ref()
		if is_instance_valid(owner):owner._finish_open(ticket,context,ok),"角色")

func _finish_open(ticket: int, context: Dictionary, ok: bool) -> void:
	if not is_inside_tree() or ticket!=_intent or not _loading:return
	_loading = false
	if (not world.link.is_local() and not world.link.online) or world.battle_view.visible or world.area_transition_busy:
		close_menu()
		return
	if int(world.data.get("map_id",-1))!=context.map_id or world.cell!=context.cell or str(world.session.snapshot().get("character_id",""))!=context.character_id:
		close_menu()
		return
	if not ok:
		close_menu()
		world.message.text = "角色素材下载失败，请检查与 MacBook 的连接后重试。"
		return
	process_mode = Node.PROCESS_MODE_INHERIT
	if not visible:previous_pause = world.paused_input
	world.clear_input()
	world.paused_input = true
	_set_dev_visible(false)
	if shell == null:_build()
	title_label.text = title_text
	_refresh()
	show()
	move_to_front() # GUI hit testing follows tree order, not z_index.
	world.play_ui_sound(202)
	_layout()
func close_menu() -> void:
	_intent += 1
	_loading = false
	_pending_confirm = false
	_ride_error = ""
	var was_visible := visible
	hide()
	title_text = "DEV · 选择角色"
	ride_pet = {}
	ride_context = {}
	ride_choices.clear()
	ride_selected = ""
	if was_visible:
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
	title_label = title
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "关闭 [Esc]"
	close.pressed.connect(close_menu)
	heading.add_child(close)
	face_row = HBoxContainer.new()
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
	ride_controls = VBoxContainer.new()
	content.add_child(ride_controls)
	var turns := HBoxContainer.new()
	ride_controls.add_child(turns)
	for step in [-1,1]:
		var turn := Button.new()
		turn.text = "◀ 转向" if step < 0 else "转向 ▶"
		turn.custom_minimum_size.y = 44
		turn.pressed.connect(_turn_preview.bind(step))
		turns.add_child(turn)
	confirmation = Label.new()
	confirmation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation.custom_minimum_size.y = 48
	ride_controls.add_child(confirmation)
	var decisions := HBoxContainer.new()
	ride_controls.add_child(decisions)
	confirm_button = Button.new()
	confirm_button.name = "ConfirmMountAppearance"
	confirm_button.text = "确认更换并骑乘"
	confirm_button.custom_minimum_size.y = 44
	confirm_button.pressed.connect(_confirm_mount)
	decisions.add_child(confirm_button)
	var cancel := Button.new()
	cancel.name = "CancelMountAppearance"
	cancel.text = "取消"
	cancel.custom_minimum_size.y = 44
	cancel.pressed.connect(close_menu)
	decisions.add_child(cancel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	grid = GridContainer.new()
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
		for state in ["normal","hover","pressed","disabled"]:
			var variant := style.duplicate()
			if state=="hover":variant.bg_color = Color("344c40")
			button.add_theme_stylebox_override(state,variant)
		button.tooltip_text = "原始角色 "+str(choice.id)
		button.pressed.connect(_choose.bind(str(choice.id)))
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
		if not ride_pet.is_empty() and not str(choice.id) in ride_choices:continue
		var pack: String = world.asset_packs.character_pack(choice.id)
		if not pack.is_empty() and not pack in packs:packs.append(pack)
		if not ride_pet.is_empty():
			var mounted_pack: String = world.asset_packs.riding_pack(Riding.composite(str(choice.id),int(ride_pet.sprite)))
			if not mounted_pack.is_empty() and not mounted_pack in packs:packs.append(mounted_pack)
	return packs

## The face this menu last chose. On a remote client the snapshot catches up
## only when the server's reply arrives, so reading it again right after a
## change undid that change (an eye step, then a mouth step, lost the mouth).
var _face := -1

## Eye (unit 5) or mouth (unit 1) one step on, wrapping within 0..4.
func change_face(unit: int, step: int) -> void:
	var face := _face if _face>=0 else int(world.session.snapshot().get("face",0))
	var eye := int(face/5)
	var mouth := face%5
	if unit == 5:eye = (eye+step+5)%5
	else:mouth = (mouth+step+5)%5
	if world.session.set_face(eye*5+mouth):
		_face = eye*5+mouth
		world.play_click()
	_refresh()

func _refresh() -> void:
	var profile: Dictionary = world.session.snapshot()
	var current: String = profile.get("character_id","100000")
	var mounted := not ride_pet.is_empty()
	face_row.visible = not mounted
	ride_controls.visible = mounted
	for id in buttons:
		var button: Button = buttons[id]
		button.visible = not mounted or id in ride_choices
		button.disabled = mounted and _pending_confirm
		button.modulate = Color("f8d678") if id == (ride_selected if mounted else current) else Color.WHITE
		button.custom_minimum_size = Vector2(150,164) if mounted else Vector2(98,108)
		button.clip_contents = mounted
		for state in ["normal","hover","pressed","disabled"]:
			var style: StyleBoxFlat = button.get_theme_stylebox(state)
			style.content_margin_top = 140 if mounted else 87
		var actor = button.get_child(0)
		actor.mounted_character_id = str(Riding.composite(id,int(ride_pet.sprite))) if mounted and id in ride_choices else ""
		actor.position = Vector2(75,110) if mounted else Vector2(49,83)
		actor.scale = Vector2(0.75,0.75) if mounted else Vector2.ONE
		actor.facing = direction if mounted else 0
		actor.set_action(4 if mounted else 3)
		if mounted and button.visible:_fit_mount(actor)
		actor.process_mode = Node.PROCESS_MODE_INHERIT if button.visible else Node.PROCESS_MODE_DISABLED
	if mounted:
		confirmation.text = "选择造型后确认；更换会永久保存。预览为原版骑乘行走动画。" if ride_selected.is_empty() else "换成%s造型以骑乘%s？" % [buttons[ride_selected].text,str(ride_pet.name)]
		if _pending_confirm:confirmation.text = "正在等待服务器确认骑乘…"
		elif not _ride_error.is_empty():confirmation.text = _ride_error
		confirm_button.disabled = ride_selected.is_empty() or _pending_confirm
	if face_view != null:
		var face := _face if _face>=0 else int(profile.get("face",0))
		face_view.texture = Faces.texture(current,face)
		face_label.text = "人物面部 · 眼睛 %d · 嘴巴 %d" % [int(face/5)+1,face%5+1] if face_view.texture != null else "人物面部未导入（tools/import_faces.py）"
func relayout() -> void:
	_layout()

func _layout() -> void:
	if shell == null:return
	grid.columns = maxi(1,mini(8,int((minf(858,size.x-16)-24)/(156 if not ride_pet.is_empty() else 104))))
	shell.position = Vector2(maxf(8,(size.x-858)/2),maxf(8,(size.y-690)/2))
	shell.size = Vector2(minf(858,size.x-16),minf(690,size.y-16))
