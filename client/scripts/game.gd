extends Node2D

const LegacyActor = preload("res://scripts/legacy_actor.gd")
const LegacyGround = preload("res://scripts/legacy_ground.gd")
const SPAWN := Vector2i(80,90)
const STEP_TIME := 0.19
const SCREEN_DIRECTIONS := [Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1)]
var data: Dictionary
var textures: Dictionary = {}
var player: Node2D
var actors: Node2D
var camera: Camera2D
var logical_position := Vector2(SPAWN)
var cell := SPAWN
var from_cell := SPAWN
var target_cell := SPAWN
var moving := false
var step_progress := 0.0
var path: Array[Vector2i] = []
var navigation := AStarGrid2D.new()
var held: Array[String] = []
var music: AudioStreamPlayer
var effect: AudioStreamPlayer
var muted := false
var volume := 0.55
var coordinates: Label
var message: Label
var mute_button: Button
var help: PanelContainer
var marker: Node2D
var marker_cell := Vector2i(-1,-1)
var character_index := 0
var paused_input := false
var load_error := ""

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	configure_input()
	if not FileAccess.file_exists("res://assets/legacy/samgir.json"):
		load_error = "Original client assets have not been imported.\nSee README.md → Import original resources."
		var error_label := Label.new()
		error_label.text = load_error
		error_label.position = Vector2(50,100)
		add_child(error_label)
		return
	data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/samgir.json"))
	for ident in data.images:
		textures[ident] = load("res://assets/legacy/images/"+ident+".png")
	var ground := LegacyGround.new()
	ground.world = self
	for entry in data.ground:
		ground.ground[int(entry[1])*int(data.width)+int(entry[0])] = str(int(entry[2]))
	add_child(ground)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	for entry in data.objects:
		var ident := str(int(entry[2]))
		var metadata: Dictionary = data.images[ident]
		var pivot := Node2D.new()
		pivot.position = project(Vector2(entry[0],entry[1]))
		var art := Sprite2D.new()
		art.texture = textures[ident]
		art.centered = false
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.position = Vector2(metadata.x,metadata.y)
		pivot.add_child(art)
		actors.add_child(pivot)
	player = LegacyActor.new()
	player.world = self
	player.position = project(logical_position)
	actors.add_child(player)
	camera = Camera2D.new()
	camera.position = Vector2(0,-25)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10
	player.add_child(camera)
	navigation.region = Rect2i(0,0,int(data.width),int(data.height))
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	navigation.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	navigation.update()
	for y in range(int(data.height)):
		for x in range(int(data.width)):
			navigation.set_point_solid(Vector2i(x,y),not is_walkable(Vector2i(x,y)))
	setup_audio()
	build_ui()
	get_window().focus_exited.connect(clear_input)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(close_game)
	if "--capture-once" in OS.get_cmdline_user_args():
		capture_frame()

func capture_frame() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").path_join("../artifacts")
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join("samgir-original.png"))

func close_game() -> void:
	clear_input()
	paused_input = true
	music.stop()
	effect.stop()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()

func configure_input() -> void:
	var bindings := {"north":[KEY_W,KEY_UP],"south":[KEY_S,KEY_DOWN],"west":[KEY_A,KEY_LEFT],"east":[KEY_D,KEY_RIGHT],"mute":[KEY_M],"reset":[KEY_R],"character":[KEY_TAB],"sit":[KEY_X],"wave":[KEY_E],"help":[KEY_H]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action,event)

func project(grid: Vector2) -> Vector2:
	return Vector2((grid.x+grid.y)*32,(grid.y-grid.x)*24)

func unproject(point: Vector2) -> Vector2:
	return Vector2(point.x/64-point.y/48,point.x/64+point.y/48)

func is_walkable(point: Vector2i) -> bool:
	if point.x<0 or point.y<0 or point.x>=int(data.width) or point.y>=int(data.height):
		return false
	return int(data.blocked[point.y*int(data.width)+point.x])==0

func can_step(origin: Vector2i, destination: Vector2i) -> bool:
	var d := destination-origin
	if abs(d.x)>1 or abs(d.y)>1 or d==Vector2i.ZERO or not is_walkable(destination):
		return false
	if d.x != 0 and d.y != 0:
		return is_walkable(origin+Vector2i(d.x,0)) and is_walkable(origin+Vector2i(0,d.y))
	return true

func request_step(destination: Vector2i) -> bool:
	if moving or not can_step(cell,destination):
		return false
	var d := destination-cell
	# Legacy moveAddTbl: direction 0 is south, 4 north; increments turn clockwise.
	player.facing = (SCREEN_DIRECTIONS.find(d)+4)%8
	from_cell = cell
	target_cell = destination
	step_progress = 0
	moving = true
	player.set_action(4)
	return true

func _input(event: InputEvent) -> void:
	if data.is_empty():
		return
	for action in ["north","south","west","east"]:
		if event.is_action_pressed(action) and not event.is_echo():
			held.erase(action)
			held.append(action)
			path.clear()
		elif event.is_action_released(action):
			held.erase(action)

func _unhandled_input(event: InputEvent) -> void:
	if data.is_empty():
		return
	if event.is_action_pressed("mute"):
		toggle_mute()
	elif event.is_action_pressed("help") or event.is_action_pressed("ui_cancel"):
		help.visible = not help.visible if event.is_action_pressed("help") else false
		paused_input = help.visible
		clear_input()
	elif event.is_action_pressed("reset"):
		reset_player()
	elif event.is_action_pressed("character"):
		change_character()
	elif event.is_action_pressed("sit") and not moving:
		player.set_action(3 if player.action==5 else 5)
	elif event.is_action_pressed("wave") and not moving:
		player.set_action(6)
	elif event is InputEventMouseButton and event.pressed and not paused_input:
		if event.button_index == MOUSE_BUTTON_LEFT:
			walk_to(Vector2i(unproject(get_global_mouse_position()).round()))
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(camera.zoom.x+0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(camera.zoom.x-0.1)

func walk_to(destination: Vector2i) -> void:
	if not is_walkable(destination):
		message.text = "That spot is blocked. Choose a path or clearing."
		return
	var start := target_cell if moving else cell
	path = navigation.get_id_path(start,destination)
	if not path.is_empty():
		path.pop_front()
		marker_cell = destination
		message.text = "Walking to (%d, %d)" % [destination.x,destination.y]
		play_click()
	else:
		message.text = "No walkable route to that spot."
	queue_redraw()

func _physics_process(delta: float) -> void:
	if data.is_empty():
		return
	if moving:
		var d := target_cell-from_cell
		var distance_scale := sqrt(2.0) if d.x != 0 and d.y != 0 else 1.0
		step_progress = minf(1,step_progress+delta/(STEP_TIME*distance_scale))
		logical_position = Vector2(from_cell).lerp(Vector2(target_cell),step_progress)
		player.position = project(logical_position)
		if step_progress>=1:
			cell = target_cell
			moving = false
	if not moving:
		var destination := cell
		if not paused_input and not held.is_empty():
			var d := Vector2i.ZERO
			for action in held:
				match action:
					"north": d += Vector2i(1,-1)
					"south": d += Vector2i(-1,1)
					"east": d += Vector2i(1,1)
					"west": d += Vector2i(-1,-1)
			destination += Vector2i(signi(d.x),signi(d.y))
		elif not paused_input and not path.is_empty():
			destination = path.pop_front()
		if destination != cell:
			if not request_step(destination):
				path.clear()
				player.set_action(3)
		elif player.action == 4:
			player.set_action(3)
			marker_cell = Vector2i(-1,-1)
			queue_redraw()
	if player.action == 6 and player.elapsed>1.1:
		player.set_action(3)
	coordinates.text = "萨姆吉尔村  ·  %d, %d" % [cell.x,cell.y]

func _draw() -> void:
	if marker_cell.x>=0:
		var p := project(Vector2(marker_cell))
		draw_polyline(PackedVector2Array([p+Vector2(0,-10),p+Vector2(15,0),p+Vector2(0,10),p+Vector2(-15,0),p+Vector2(0,-10)]),Color("fff1a6"),1)

func clear_input() -> void:
	held.clear()
	path.clear()

func reset_player() -> void:
	clear_input()
	moving = false
	cell = SPAWN
	target_cell = SPAWN
	logical_position = Vector2(SPAWN)
	player.position = project(logical_position)
	player.set_action(3)
	camera.reset_smoothing()
	message.text = "Back at the village square."

func change_character() -> void:
	character_index = (character_index+1)%3
	player.character_id = ["100000","100005","100010"][character_index]
	player.current_image = -1
	message.text = "Original character %s" % player.character_id
	play_click()

func set_zoom(value: float) -> void:
	camera.zoom = Vector2.ONE * clampf(value,0.65,2.0)

func setup_audio() -> void:
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/legacy/sabgm_t0.wav")
	music.stream.loop_begin = 0
	music.stream.loop_end = int(music.stream.get_length()*music.stream.mix_rate)
	music.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.volume_db = linear_to_db(volume)
	add_child(music)
	music.play()
	effect = AudioStreamPlayer.new()
	effect.stream = load("res://assets/legacy/sas_01.wav")
	effect.volume_db = -10
	add_child(effect)

func play_click() -> void:
	if not muted:
		effect.play()

func toggle_mute() -> void:
	muted = not muted
	music.volume_db = -80 if muted else linear_to_db(maxf(volume,0.0001))
	effect.volume_db = -80 if muted else -10
	mute_button.text = "Music: off  [M]" if muted else "Music: on  [M]"

func _exit_tree() -> void:
	if is_instance_valid(music): music.stop()
	if is_instance_valid(effect): effect.stop()

func box(color: Color, border: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(2)
	result.set_corner_radius_all(3)
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 7
	result.content_margin_bottom = 7
	return result

func text(value: String, size: int = 15) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("f8edc7"))
	return label

func button(value: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = value
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size",13)
	b.add_theme_stylebox_override("normal",box(Color("574431"),Color("9d8354")))
	b.add_theme_stylebox_override("hover",box(Color("775b3c"),Color("e6c284")))
	b.pressed.connect(callback)
	return b

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	var font: Font = load("res://assets/fonts/NotoSansSC.ttf")
	ui_theme.default_font = font
	root.theme = ui_theme
	layer.add_child(root)
	var map_panel := PanelContainer.new()
	map_panel.position = Vector2(18,16)
	map_panel.add_theme_stylebox_override("panel",box(Color(0.16,0.2,0.16,0.92),Color("9d8354")))
	root.add_child(map_panel)
	coordinates = text("萨姆吉尔村",16)
	map_panel.add_child(coordinates)
	var info := PanelContainer.new()
	info.position = Vector2(905,16)
	info.add_theme_stylebox_override("panel",box(Color(0.16,0.2,0.16,0.92),Color("9d8354")))
	root.add_child(info)
	info.add_child(text("STONE AGE · Original resources\nGodot local preview · map 1000",13))
	var bottom := PanelContainer.new()
	bottom.position = Vector2(12,710)
	bottom.size = Vector2(1256,78)
	bottom.add_theme_stylebox_override("panel",box(Color(0.16,0.18,0.14,0.95),Color("9d8354")))
	root.add_child(bottom)
	var v := VBoxContainer.new()
	bottom.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	v.add_child(row)
	var controls := text("Click to walk · WASD / arrows · E wave · X sit · Tab character",14)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(controls)
	row.add_child(button("−",func(): set_zoom(camera.zoom.x-0.15)))
	row.add_child(button("+",func(): set_zoom(camera.zoom.x+0.15)))
	mute_button = button("Music: on  [M]",toggle_mute)
	row.add_child(mute_button)
	row.add_child(button("Help [H]",func(): help.visible = not help.visible; paused_input = help.visible; clear_input()))
	message = text("Original Samgir map, character animation, palette, and village music. Explore the square.",12)
	message.add_theme_color_override("font_color",Color("bdc6ae"))
	v.add_child(message)
	help = PanelContainer.new()
	help.position = Vector2(310,200)
	help.size = Vector2(660,330)
	help.add_theme_stylebox_override("panel",box(Color("303b2e"),Color("c3a26d")))
	root.add_child(help)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",14)
	help.add_child(content)
	content.add_child(text("Welcome back to 萨姆吉尔",25))
	content.add_child(text("Click a walkable tile to find a path, or use WASD / arrow keys.\nE: wave   X: sit / stand   Tab: change original character\nMouse wheel or + / −: zoom   M: mute   R: return to square\n\nOriginal 2.5-era map and client assets, rendered in Godot.\nThis slice supports exploration, animation, collision, and audio.\nNPC logic, interiors, saving, and the Swift server come next.",17))
	content.add_child(text("Music volume",14))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = volume
	slider.value_changed.connect(func(value: float): volume = value; music.volume_db = -80 if muted else linear_to_db(maxf(volume,0.0001)))
	content.add_child(slider)
	content.add_child(button("Back to the village",func(): help.hide(); paused_input = false; clear_input()))
	help.hide()
