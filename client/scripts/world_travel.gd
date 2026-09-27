extends Node
## Source-backed residents and reusable item 2422 undersea travel permit.
var world: Node
var entries: Array = []
var sprites: Array[Sprite2D] = []
var pending := -1
var selected := -1
var overlay: Control
var body: Label
var choice: Button

func setup(owner: Node, ui_root: Control, residents: Array) -> void:
	world = owner
	entries = residents
	for entry in entries:
		var cell := Vector2i(entry.cell[0],entry.cell[1])
		world.navigation.set_point_solid(cell,true)
		var actor := Node2D.new()
		actor.position = world.project(Vector2(cell))
		world.actors.add_child(actor)
		var sprite := Sprite2D.new()
		var path := str(entry.get("path",""))
		if not path.begins_with("res://"):path = "res://assets/legacy/"+path
		if ResourceLoader.exists(path):sprite.texture = load(path)
		sprite.centered = false
		var offset: Array = entry.get("offset",[0,0])
		sprite.position = Vector2(offset[0],offset[1])
		actor.add_child(sprite)
		sprites.append(sprite)
		var name_label: Label = world.text(str(entry.get("name","")),14)
		name_label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
		name_label.position = Vector2(-90,-100)
		name_label.size.x = 180
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		actor.add_child(name_label)
	_build_dialogue(ui_root)

func blocks(cell: Vector2i) -> bool:
	for entry in entries:
		if cell == Vector2i(entry.cell[0],entry.cell[1]):return true
	return false

func handle_click(point: Vector2) -> bool:
	for i in range(sprites.size()-1,-1,-1):
		if sprites[i].texture and sprites[i].get_rect().has_point(sprites[i].to_local(point)):
			approach(i)
			return true
	pending = -1
	return false

func approach(index: int) -> void:
	if world.paused_input:return
	world.clear_input()
	var cell := Vector2i(entries[index].cell[0],entries[index].cell[1])
	var start: Vector2i = world.target_cell if world.moving else world.cell
	var best: Array[Vector2i] = []
	var offsets := [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
	if entries[index].get("role", "")=="trainer":offsets.append_array([Vector2i(-2,0),Vector2i(2,0),Vector2i(0,-2),Vector2i(0,2)])
	for offset in offsets:
		var destination: Vector2i = cell+offset
		if not world.is_walkable(destination):continue
		var route: Array[Vector2i] = world.navigation.get_id_path(start,destination)
		if not route.is_empty() and (best.is_empty() or route.size()<best.size()):best=route
	if best.is_empty():
		world.message.text = "无法走到这里。"
		return
	best.pop_front()
	world.path = best
	pending = index

func _process(_delta: float) -> void:
	if pending < 0 or world.moving or not world.path.is_empty():return
	var point := Vector2i(entries[pending].cell[0],entries[pending].cell[1])
	var distance: Vector2i = (world.cell-point).abs()
	var reach := 2 if entries[pending].get("role", "")=="trainer" else 1
	if distance.x+distance.y<=reach:
		selected = pending
		pending = -1
		_open()
	else:pending=-1

func _open() -> void:
	world.clear_input()
	world.paused_input = true
	world.player.set_action(3)
	var entry: Dictionary = entries[selected]
	if entry.get("role", "")=="trainer":
		world.pet_training.open_training(int(world.data.map_id))
		return
	body.text = str(entry.get("name",""))+"\n\n"+str(entry.get("text",""))
	choice.hide()
	if entry.get("role","")=="vendor":
		body.text += "\n\n"+("持有通行证。" if world.session.has_travel_pass() else "通行证：200 石币")
		choice.text = "购买通行证"
		choice.visible = not world.session.has_travel_pass()
	elif entry.get("role","")=="gate":
		if world.session.has_travel_pass():body.text = str(entry.get("free_text", "你好像有通行证嘛，那请进去吧。路上请小心。"))
		choice.text = "出示通行证"
		choice.visible = world.session.has_travel_pass()
	overlay.show()
	world.play_ui_sound(202)

func _choose() -> void:
	var entry: Dictionary = entries[selected]
	world.play_ui_sound(202)
	if entry.get("role","")=="vendor":
		if world.session.buy_travel_pass():
			world.checkpoint()
			body.text = "已取得通行证。\n\n可以重复使用。"
			choice.hide()
		else:body.text = "石币不足，需要 200 石币。"
	elif entry.get("role","")=="gate" and world.session.has_travel_pass():
		var destination: Array = entry.destination
		_close()
		world.call_deferred("load_area_id",int(world.data.map_id),Vector2i(destination[0],destination[1]))

func _close() -> void:
	overlay.hide()
	world.paused_input = false
	world.clear_input()
	world.play_ui_sound(203)

func _unhandled_key_input(event: InputEvent) -> void:
	if overlay and overlay.visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _build_dialogue(root: Control) -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(overlay)
	var panel := Control.new()
	panel.size = Vector2(384,240)
	panel.scale = Vector2.ONE*world.classic_hud.SCALE
	panel.position = Vector2((1280-384*world.classic_hud.SCALE)/2,350)
	overlay.add_child(panel)
	for y in range(5):
		for x in range(6):
			var row := 0 if y==0 else (2 if y==4 else 1)
			var col := 0 if x==0 else (2 if x==5 else 1)
			world.classic_hud.picture(panel,26001+row*3+col,Vector2(x*64,y*48))
	body = world.text("",15)
	body.position = Vector2(18,15)
	body.size = Vector2(348,150)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	choice = Button.new()
	choice.position = Vector2(80,166)
	choice.size = Vector2(224,28)
	for style in ["normal","hover","pressed","focus"]:choice.add_theme_stylebox_override(style,StyleBoxEmpty.new())
	choice.add_theme_color_override("font_color",Color.YELLOW)
	choice.pressed.connect(_choose)
	panel.add_child(choice)
	var button_art: Texture2D = world.classic_hud.art[26091]
	var close: TextureButton = world.classic_hud.icon(panel,26091,26091,Vector2((384-button_art.get_width())/2.0,204),"关闭")
	close.pressed.connect(_close)
	overlay.hide()
