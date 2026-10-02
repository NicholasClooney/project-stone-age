extends Node
## Source-backed residents and reusable item 2422 undersea travel permit.
var world: Node
var entries: Array = []
var sprites: Array[Sprite2D] = []
var resident_nodes: Array[Node2D] = []
var applied_npc_overrides: Dictionary = {}
var pending := -1
var selected := -1
var overlay: Control
var body: Label
var choice: Button
var quest_dialogue: Node

func setup(owner: Node, ui_root: Control, residents: Array) -> void:
	world = owner
	applied_npc_overrides=world.state.derived.get("quest_npcs",{}).duplicate(true)
	_render_residents(residents)
	_build_dialogue(ui_root)
	quest_dialogue=preload("res://scripts/quest_dialogue.gd").new()
	add_child(quest_dialogue)
	quest_dialogue.setup(world,overlay,body)

func _render_residents(residents:Array)->void:
	entries = residents
	for entry in entries:
		var cell := Vector2i(entry.cell[0],entry.cell[1])
		world.navigation.set_point_solid(cell,true)
		var actor := Node2D.new()
		actor.position = world.project(Vector2(cell))
		world.actors.add_child(actor)
		resident_nodes.append(actor)
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

func sync_npc_state()->void:
	var overrides:Dictionary=world.state.derived.get("quest_npcs",{})
	if overrides==applied_npc_overrides:return
	applied_npc_overrides=overrides.duplicate(true)
	world.world_catalog.quest_catalog.npc_overrides=overrides.duplicate(true)
	world.world_catalog.set_quest_catalog(world.world_catalog.quest_catalog)
	var visible:Array=[]
	for entry in world.world_catalog.residents:
		if int(entry.map_id)==int(world.data.map_id) and Vector2i(entry.cell[0],entry.cell[1])!=world.npc_cell:visible.append(entry)
	if visible==entries:return
	var waiting_id:String=str(entries[pending].get("id","")) if pending>=0 else ""
	var selected_id:String=str(entries[selected].get("id","")) if selected>=0 else ""
	pending=-1;selected=-1
	for i in range(visible.size()):
		if not waiting_id.is_empty() and str(visible[i].get("id",""))==waiting_id:pending=i
		if not selected_id.is_empty() and str(visible[i].get("id",""))==selected_id:selected=i
	for entry in entries:
		var cell:=Vector2i(entry.cell[0],entry.cell[1])
		var index:=cell.y*int(world.data.width)+cell.x
		var blocked:bool=index<0 or index>=world.data.blocked.size() or bool(world.data.blocked[index])
		world.navigation.set_point_solid(cell,blocked)
	for actor in resident_nodes:
		actor.hide();actor.queue_free()
	resident_nodes.clear();sprites.clear()
	_render_residents(visible)

func blocks(cell: Vector2i) -> bool:
	for entry in entries:
		if cell == Vector2i(entry.cell[0],entry.cell[1]):return true
	return false

func handle_click(point: Vector2) -> bool:
	for i in range(sprites.size()-1,-1,-1):
		if sprites[i].texture and sprites[i].get_rect().has_point(sprites[i].to_local(point)):
			if entries[i].get("role","")!="decoration":approach(i)
			return true
	pending = -1
	return false

func approach(index: int) -> void:
	if world.paused_input:return
	world.clear_input()
	var cell := Vector2i(entries[index].cell[0],entries[index].cell[1])
	var start: Vector2i = world.target_cell if world.moving else world.cell
	var best: Array[Vector2i] = []
	var offsets: Array = preload("res://scripts/npc_interaction.gd").offsets() if entries[index].get("role","")=="quest" else [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
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
	sync_npc_state()
	if pending < 0 or world.moving or not world.path.is_empty():return
	var point := Vector2i(entries[pending].cell[0],entries[pending].cell[1])
	var distance: Vector2i = (world.cell-point).abs()
	var reach := 2 if entries[pending].get("role", "")=="trainer" else 1
	if (maxi(distance.x,distance.y)<=2 if entries[pending].get("role","")=="quest" else distance.x+distance.y<=reach):
		selected = pending
		pending = -1
		_open()
	else:pending=-1

func _open() -> void:
	var resident: Dictionary=entries[selected]
	if resident.get("role","")=="quest":
		choice.hide()
		quest_dialogue.open(str(resident.id))
		return
	world.clear_input()
	world.paused_input = true
	world.player.set_action(3)
	var entry: Dictionary = entries[selected]
	if entry.get("role", "")=="trainer":
		world.pet_training.open_training(int(world.data.map_id))
		return
	var dialogue: String=str(entry.get("text",""))
	if entry.get("handler","")=="npcgen_man" and not entry.get("dialogues",[]).is_empty():
		dialogue=str(entry.dialogues.pick_random())
	body.text = str(entry.get("name",""))+"\n\n"+dialogue
	if entry.get("role","")=="deferred_service":body.text+="\n\n【尚未还原此服务】"
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
	if is_instance_valid(quest_dialogue) and quest_dialogue.active:
		quest_dialogue.close()
		return
	if not overlay.visible:return
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
	var layout:=func():
		var viewport:Vector2=world.get_viewport_rect().size
		var factor:float=minf(world.classic_hud.SCALE,(viewport.x-16.0)/384.0)
		panel.scale=Vector2.ONE*factor
		panel.position=Vector2((viewport.x-panel.size.x*factor)/2,minf(350,viewport.y-panel.size.y*factor-16))
	world.get_viewport().size_changed.connect(layout)
	layout.call()
	overlay.add_child(panel)
	var backdrop:=ColorRect.new()
	backdrop.color=Color(0.06,0.065,0.055,0.97)
	backdrop.size=panel.size
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(backdrop)
	for y in range(5):
		for x in range(6):
			var row := 0 if y==0 else (2 if y==4 else 1)
			var col := 0 if x==0 else (2 if x==5 else 1)
			world.classic_hud.picture(panel,26001+row*3+col,Vector2(x*64,y*48))
	body = world.text("",15)
	body.add_theme_color_override("font_color",Color("f3eddd"))
	body.custom_minimum_size.x=328
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scroll:=ScrollContainer.new()
	scroll.name="OriginalDialogueScroll"
	scroll.position=Vector2(18,15);scroll.size=Vector2(348,140)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll);scroll.add_child(body)
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
