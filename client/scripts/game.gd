extends Node2D

const LegacyActor = preload("res://scripts/legacy_actor.gd")
const GameSession = preload("res://server/game_session.gd")
const AdventureMenu = preload("res://scripts/adventure_menu.gd")
const PetFollower = preload("res://scripts/pet_follower.gd")
const BattleSession = preload("res://server/battle_session.gd")
const BattleView = preload("res://scripts/battle_view.gd")
const LegacyGround = preload("res://scripts/legacy_ground.gd")
const SPAWN := Vector2i(80,90)
const STEP_TIME := 0.19
const MIN_ZOOM := 0.4
const MAX_ZOOM := 2.0
const ZOOM_STEP := 0.1
const SCREEN_DIRECTIONS := [Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1)]
var terrain: Node2D
var ui_layer: CanvasLayer
var battle_view: Control
var battle_session = BattleSession.new()
var field_steps := 0
var battle_sounds: Dictionary = {}
var wilderness_music: AudioStream
var village_music: AudioStream
var session = GameSession.new()
var adventure_menu: Control
var profile_persistence := true
var save_path := "user://single-player.json"
var pet_follower: Node2D
var pet_trail: Array[Vector2i] = []
var adventure_hint: Label
var encounter_serial := 0
var save_elapsed := 0.0
var mvp_manifest: Dictionary = {}
var last_adventure_message := ""
var last_saved_payload := ""
var boss_button: Button
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
var ui_sounds: Dictionary = {}
var last_ui_sound := -1
var ui_sound_count := 0
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
var classic_hud: Control
var npc_data: Dictionary = {}
var npc: Node2D
var npc_sprite: Sprite2D
var npc_cell := Vector2i(-1,-1)
var pending_talk := false
var dialogue: Control
var dialogue_name: Label
var dialogue_text: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	configure_input()
	if "--script" in OS.get_cmdline_args():profile_persistence = false
	if FileAccess.file_exists("res://assets/legacy/mvp/manifest.json"):
		mvp_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/mvp/manifest.json"))
	if profile_persistence and (FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak")):
		load_profile()
	if not FileAccess.file_exists("res://assets/legacy/samgir.json") or not FileAccess.file_exists("res://assets/legacy/ui/manifest.json"):
		load_error = "Original client assets have not been imported.\nSee README.md → Import original resources."
		var error_label := Label.new()
		error_label.text = load_error
		error_label.position = Vector2(50,100)
		add_child(error_label)
		return
	data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/samgir.json"))
	build_world()
	setup_audio()
	build_ui()
	if profile_persistence:
		restore_location()
	refresh_companion()
	get_window().focus_exited.connect(clear_input)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(close_game)
	if "--capture-once" in OS.get_cmdline_user_args():
		capture_frame()


func area_name() -> String:
	return str(data.get("name","萨姆吉尔村"))

func display_cell() -> Vector2i:
	var origin: Array = data.get("origin",[0,0])
	return cell+Vector2i(int(origin[0]),int(origin[1]))

func build_world() -> void:
	for ident in data.images:
		textures[ident] = load("res://assets/legacy/images/"+ident+".png")
	terrain = LegacyGround.new()
	terrain.world = self
	for entry in data.ground:
		terrain.ground[int(entry[1])*int(data.width)+int(entry[0])] = str(int(entry[2]))
	add_child(terrain)
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
	player.character_id = ["100000","100005","100010"][character_index]
	player.position = project(logical_position)
	actors.add_child(player)
	camera = Camera2D.new()
	camera.position = Vector2(0,-25)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10
	player.add_child(camera)
	navigation.clear()
	navigation.region = Rect2i(0,0,int(data.width),int(data.height))
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	navigation.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	navigation.update()
	for y in range(int(data.height)):
		for x in range(int(data.width)):
			navigation.set_point_solid(Vector2i(x,y),not is_walkable(Vector2i(x,y)))
	if int(data.map_id) in [1000,1002]:
		setup_npc()
	pet_trail.assign([cell,cell])
	pet_follower = null

func switch_area(wilderness: bool, destination: Vector2i) -> bool:
	return load_area_id(100 if wilderness else 1000,destination)

func load_area_id(map_id: int, destination: Vector2i) -> bool:
	var filenames := {100:"wilderness.json",1000:"samgir.json",1002:"shop.json"}
	if not filenames.has(map_id):return false
	var file := "res://assets/legacy/"+str(filenames[map_id])
	if not FileAccess.file_exists(file):
		message.text = "Import the wilderness assets first; see README.md."
		return false
	var next_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not next_data is Dictionary:
		return false
	var width := int(next_data.width)
	var height := int(next_data.height)
	if destination.x<0 or destination.y<0 or destination.x>=width or destination.y>=height or int(next_data.blocked[destination.y*width+destination.x])!=0:
		return false
	var previous_zoom: Vector2 = camera.zoom
	clear_input()
	for node in [terrain,actors,ui_layer]:
		remove_child(node)
		node.queue_free()
	data = next_data
	textures.clear()
	npc_data.clear()
	npc_cell = Vector2i(-1,-1)
	npc = null
	npc_sprite = null
	cell = destination
	from_cell = destination
	target_cell = destination
	logical_position = Vector2(destination)
	moving = false
	paused_input = false
	marker_cell = Vector2i(-1,-1)
	field_steps = 0
	build_world()
	camera.zoom = previous_zoom
	build_ui()
	camera.reset_smoothing()
	set_music(exploration_music())
	queue_redraw()
	refresh_companion()
	checkpoint()
	return true

func walk_to_exit() -> void:
	if paused_input:
		return
	var exits := {1000:Vector2i(49,118),100:Vector2i(46,45),1002:Vector2i(10,15)}
	walk_to(exits[int(data.map_id)])

func handle_arrival() -> bool:
	pet_trail.append(cell)
	while pet_trail.size()>3:pet_trail.pop_front()
	if int(data.map_id)==1000:
		if cell.x==67 and cell.y in [108,109]:
			return load_area_id(1002,Vector2i(11,cell.y-93))
		if cell.x==49 and cell.y>=116 and cell.y<=119:
			return switch_area(true,Vector2i(45,cell.y-73))
	elif int(data.map_id)==1002:
		if cell.x==10 and cell.y in [15,16]:
			return load_area_id(1000,Vector2i(67,cell.y+93))
	elif int(data.map_id)==100:
		if cell.x==46 and cell.y>=43 and cell.y<=46:
			return switch_area(false,Vector2i(50,cell.y+73))
		field_steps += 1
		if field_steps>=8:
			return begin_battle(session.can_fight_boss())
	return false

func begin_battle(boss: bool = false) -> bool:
	if moving or paused_input or int(data.map_id)!=100 or battle_view==null:
		return false
	if not FileAccess.file_exists("res://assets/legacy/battle/manifest.json"):
		message.text = "Import original battle assets first; see README.md."
		return false
	clear_input()
	paused_input = true
	player.set_action(3)
	help.hide()
	classic_hud.map_panel.hide()
	var species := ["wooli","wooli_wooli","woolistan"]
	var config: Dictionary = session.start_battle_config("woolistan" if boss else species[encounter_serial%3],boss)
	if config.is_empty():
		paused_input = false
		return false
	encounter_serial += 1
	battle_session.rng_seed = 42+encounter_serial
	var state: Dictionary = battle_session.start_battle(config)
	battle_view.open_battle(state)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/battle/manifest.json"))
	set_music(load("res://assets/legacy/battle/"+str(manifest.audio.bgm)))
	play_ui_sound(202)
	return true

func battle_action(action: String) -> void:
	if not battle_view.visible:
		return
	var before: Dictionary = session.snapshot()
	var state: Dictionary = battle_session.submit_action(action)
	if not bool(state.active) and session.apply_battle_result(state):
		if state.outcome=="win":
			state.events.append("获得经验 %d，石币 %d。" % [int(state.get("xp",0)),int(state.get("gold",0))])
			var after: Dictionary = session.snapshot()
			if int(after.player.level)>int(before.player.level):
				state.events.append("升级！你达到了 %d 级，体力恢复。" % int(after.player.level))
			if int(after.active_pet)>=0:
				var index: int = after.active_pet
				if int(after.pets[index].level)>int(before.pets[index].level):
					state.events.append("%s 成长到 %d 级！" % [after.pets[index].name,after.pets[index].level])
					if not before.pets[index].skill_unlocked and after.pets[index].skill_unlocked:
						state.events.append("伙伴学会了强力攻击！")
		elif state.outcome=="captured":
			state.events.append("伙伴已加入宠物栏，可为它取名并选择出战。")
		checkpoint()
	battle_view.show_state(state)
	play_ui_sound(217 if ui_sounds.has(217) else 201)

func return_from_battle() -> void:
	if not battle_view.visible or battle_session.snapshot().active:
		return
	var outcome: String = battle_session.snapshot().outcome
	battle_view.close_battle()
	clear_input()
	paused_input = false
	field_steps = 0
	if outcome!="defeat":set_music(exploration_music())
	play_ui_sound(203)
	if outcome=="defeat":
		switch_area(false,SPAWN)
	refresh_companion()
	checkpoint()

func capture_frame() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").path_join("../artifacts")
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join("samgir-original.png"))

func close_game() -> void:
	checkpoint()
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
	return point != npc_cell and int(data.blocked[point.y*int(data.width)+point.x])==0

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
		if event.is_action_pressed(action) and not event.is_echo() and not paused_input:
			pending_talk = false
			held.erase(action)
			held.append(action)
			path.clear()
		elif event.is_action_released(action):
			held.erase(action)

func _unhandled_input(event: InputEvent) -> void:
	if data.is_empty():
		return
	if is_instance_valid(battle_view) and battle_view.visible:
		if event.is_action_pressed("mute"):
			toggle_mute()
		elif event.is_action_pressed("ui_accept") and not battle_session.snapshot().active:
			return_from_battle()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(adventure_menu) and adventure_menu.visible:
		if event.is_action_pressed("ui_cancel"):close_adventure_menu()
		get_viewport().set_input_as_handled()
		return
	if dialogue.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			close_dialogue()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode==KEY_M:
		classic_hud.toggle_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and classic_hud.map_panel.visible:
		classic_hud.toggle_map()
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
			handle_world_click(get_global_transform_with_canvas().affine_inverse()*event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(camera.zoom.x+ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(camera.zoom.x-ZOOM_STEP)

func walk_to(destination: Vector2i) -> void:
	pending_talk = false
	if not is_walkable(destination):
		message.text = "That spot is blocked. Choose a path or clearing."
		return
	var start := target_cell if moving else cell
	path = navigation.get_id_path(start,destination)
	if not path.is_empty():
		path.pop_front()
		marker_cell = destination
		message.text = "Walking to (%d, %d)" % [destination.x,destination.y]
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
			if handle_arrival():
				return
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
	if pending_talk and not moving and path.is_empty():
		pending_talk = false
		if in_talk_range(cell):
			open_dialogue()
	if player.action == 6 and player.elapsed>1.1:
		player.set_action(3)
	save_elapsed += delta
	if profile_persistence and save_elapsed>=5.0 and not moving and not battle_session.snapshot().active:
		checkpoint()
	update_adventure_hint()
	coordinates.text = "%s  ·  %d, %d" % [area_name(),display_cell().x,display_cell().y]

func _draw() -> void:
	if marker_cell.x>=0:
		var p := project(Vector2(marker_cell))
		draw_polyline(PackedVector2Array([p+Vector2(0,-10),p+Vector2(15,0),p+Vector2(0,10),p+Vector2(-15,0),p+Vector2(0,-10)]),Color("fff1a6"),1)

func clear_input() -> void:
	pending_talk = false
	held.clear()
	path.clear()

func reset_player() -> void:
	if is_instance_valid(battle_view) and battle_view.visible:
		return
	if int(data.map_id)!=1000:
		switch_area(false,SPAWN)
		return
	if dialogue.visible:
		close_dialogue()
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
	camera.zoom = Vector2.ONE*clampf(value,MIN_ZOOM,MAX_ZOOM)

func maximum_zoom_out() -> void:
	set_zoom(MIN_ZOOM)

func exploration_music() -> AudioStream:
	return wilderness_music if int(data.map_id)==100 and wilderness_music!=null else village_music

func set_music(stream: AudioStream) -> void:
	if music.stream==stream and music.playing:return
	music.stop()
	music.stream = stream
	if stream is AudioStreamWAV:
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length()*stream.mix_rate)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.play()

func setup_audio() -> void:
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/legacy/sabgm_t0.wav")
	music.stream.loop_begin = 0
	music.stream.loop_end = int(music.stream.get_length()*music.stream.mix_rate)
	music.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	village_music = music.stream
	if mvp_manifest.get("audio",{}).has("wilderness"):
		wilderness_music = load("res://assets/legacy/mvp/"+str(mvp_manifest.audio.wilderness))
	music.volume_db = linear_to_db(volume)
	add_child(music)
	music.play()
	effect = AudioStreamPlayer.new()
	for entry in [[201,"sas_01.wav"],[202,"sas_02.wav"],[203,"sas_03.wav"]]:
		ui_sounds[entry[0]] = load("res://assets/legacy/"+entry[1])
	if FileAccess.file_exists("res://assets/legacy/battle/manifest.json"):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/battle/manifest.json"))
		for ident in manifest.get("frame_sounds",{}):
			battle_sounds[int(ident)] = load("res://assets/legacy/battle/"+str(manifest.frame_sounds[ident]))
		if manifest.audio.has("battle_cancel"):
			ui_sounds[217] = load("res://assets/legacy/battle/"+str(manifest.audio.battle_cancel))
	effect.stream = ui_sounds[201]
	effect.volume_db = -10
	add_child(effect)

func play_battle_sound(ident: int) -> void:
	if muted or not battle_sounds.has(ident):
		return
	effect.stream = battle_sounds[ident]
	effect.play()

func play_click() -> void:
	play_ui_sound(201)

func play_ui_sound(ident: int) -> void:
	if muted:
		return
	last_ui_sound = ident
	ui_sound_count += 1
	effect.stream = ui_sounds[ident]
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
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	var font: Font = load("res://assets/fonts/NotoSansSC.ttf")
	var readable_font := FontVariation.new()
	readable_font.base_font = font
	readable_font.variation_opentype = {2003265652:450.0} # OpenType wght axis tag.
	ui_theme.default_font = readable_font
	root.theme = ui_theme
	ui_layer.add_child(root)
	coordinates = text("")
	message = text("")
	root.add_child(coordinates)
	root.add_child(message)
	coordinates.hide()
	message.hide()
	classic_hud = preload("res://scripts/classic_hud.gd").new()
	classic_hud.world = self
	root.add_child(classic_hud)
	boss_button = null
	var dev := HBoxContainer.new()
	dev.position = Vector2(12,85)
	dev.add_theme_constant_override("separation",5)
	root.add_child(dev)
	dev.add_child(text("DEV",12))
	var zoom_minus := button("−",func(): set_zoom(camera.zoom.x-ZOOM_STEP))
	zoom_minus.name = "ZoomMinus"
	dev.add_child(zoom_minus)
	var zoom_plus := button("+",func(): set_zoom(camera.zoom.x+ZOOM_STEP))
	zoom_plus.name = "ZoomPlus"
	dev.add_child(zoom_plus)
	var max_out := button("Max out",maximum_zoom_out)
	max_out.name = "MaxOut"
	dev.add_child(max_out)
	if int(data.map_id)==1000:
		dev.add_child(button("Villager",approach_npc))
	var exit_button := button("村外探险" if int(data.map_id)==1000 else "返回村庄",walk_to_exit)
	exit_button.name = "ExploreOutside"
	dev.add_child(exit_button)
	if int(data.map_id)==1000:
		dev.add_child(button("道具店",func():
			if not paused_input:walk_to(Vector2i(67,108))))
	if int(data.map_id)==100:
		boss_button = button("挑战强敌",func():
			if session.can_fight_boss():begin_battle(true))
		boss_button.tooltip_text = "接受委托、战胜三个对手并捕获伙伴后开放"
		dev.add_child(boss_button)
	mute_button = button("Music: on  [M]",toggle_mute)
	mute_button.text = "Music: off  [M]" if muted else "Music: on  [M]"
	dev.add_child(mute_button)
	var help_button := button("Help [H]",func():
		if not dialogue.visible:
			help.visible = not help.visible
			paused_input = help.visible
			clear_input())
	help_button.name = "DevHelp"
	dev.add_child(help_button)
	help = PanelContainer.new()
	help.position = Vector2(310,200)
	help.size = Vector2(660,330)
	help.add_theme_stylebox_override("panel",box(Color("303b2e"),Color("c3a26d")))
	root.add_child(help)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",14)
	help.add_child(content)
	content.add_child(text("Welcome back to 萨姆吉尔",25))
	content.add_child(text("Click a walkable tile to find a path, or use WASD / arrow keys.\nE: wave   X: sit / stand   Tab: change original character\nMouse wheel or + / −: zoom   M: mute   R: return to square\n\nOriginal 2.5-era map and client assets, rendered in Godot.\nClick 村外探险 to leave through the west exit.\nWalk eight steps outside to encounter 乌力 and try a battle.\nClick the villager to approach and talk. Enter / Esc closes dialogue.",17))
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
	build_dialogue(root)
	adventure_menu = AdventureMenu.new()
	adventure_menu.configure(self)
	root.add_child(adventure_menu)
	adventure_hint = text("",14)
	adventure_hint.position = Vector2(18,132)
	adventure_hint.add_theme_color_override("font_shadow_color",Color.BLACK)
	adventure_hint.add_theme_constant_override("shadow_offset_x",1)
	adventure_hint.add_theme_constant_override("shadow_offset_y",1)
	adventure_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(adventure_hint)
	battle_view = BattleView.new()
	root.add_child(battle_view)
	battle_view.configure(self)
	battle_view.action_requested.connect(battle_action)
	battle_view.return_requested.connect(return_from_battle)
	battle_view.sound_requested.connect(play_battle_sound)
	battle_view.pet_command_requested.connect(func(command: String): battle_session.set_pet_command(command))


func setup_npc() -> void:
	if int(data.map_id)==1002 and not mvp_manifest.is_empty():
		npc_data = mvp_manifest.merchant.duplicate(true)
	elif not FileAccess.file_exists("res://assets/legacy/samgir-npc.json"):
		return
	else:
		npc_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/samgir-npc.json"))
	npc_cell = Vector2i(npc_data.cell[0],npc_data.cell[1])
	navigation.set_point_solid(npc_cell,true)
	npc = Node2D.new()
	npc.position = project(Vector2(npc_cell))
	actors.add_child(npc)
	npc_sprite = Sprite2D.new()
	npc_sprite.texture = load("res://assets/legacy/mvp/"+str(npc_data.path)) if int(data.map_id)==1002 else load("res://assets/legacy/samgir-villager.png")
	npc_sprite.centered = false
	npc_sprite.position = Vector2(npc_data.offset[0],npc_data.offset[1])
	npc.add_child(npc_sprite)
	var label := text(npc_data.name,14)
	label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	label.position = Vector2(-28,-94)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	npc.add_child(label)

func handle_world_click(point: Vector2) -> void:
	if paused_input:
		return
	if is_instance_valid(npc_sprite) and npc_sprite.get_rect().has_point(npc_sprite.to_local(point)):
		approach_npc()
	else:
		walk_to(Vector2i(unproject(point).round()))

func in_talk_range(point: Vector2i) -> bool:
	var delta := (point-npc_cell).abs()
	# Cardinal neighbours avoid talking diagonally through blocked corners.
	return (point==Vector2i(16,15)) if int(data.map_id)==1002 else delta.x+delta.y == 1

func approach_npc() -> void:
	if paused_input:
		return
	if npc_data.is_empty():
		message.text = "The villager has not been imported. See README.md."
		return
	clear_input()
	var start := target_cell if moving else cell
	var best: Array[Vector2i] = []
	var approaches := [Vector2i(-2,0)] if int(data.map_id)==1002 else [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
	for offset in approaches:
		var destination: Vector2i = npc_cell+offset
		if not is_walkable(destination):
			continue
		var candidate := navigation.get_id_path(start,destination)
		if not candidate.is_empty() and (best.is_empty() or candidate.size()<best.size()):
			best = candidate
	if best.is_empty():
		message.text = "There is no clear path to the villager."
		return
	best.pop_front()
	path = best
	pending_talk = true
	message.text = "正在走向 %s…" % str(npc_data.name)

func open_dialogue() -> void:
	if moving or not in_talk_range(cell):
		return
	if int(data.map_id)==1002:
		show_adventure_menu("shop")
		return
	clear_input()
	paused_input = true
	player.set_action(3)
	player.facing = (SCREEN_DIRECTIONS.find(npc_cell-cell)+4)%8
	dialogue_name.text = npc_data.name
	dialogue_text.text = npc_data.text
	dialogue.show()
	play_ui_sound(202)

func close_dialogue() -> void:
	if not dialogue.visible:
		return
	play_ui_sound(203)
	dialogue.hide()
	paused_input = help.visible
	clear_input()
	message.text = "Click the villager to talk again, or keep exploring."

func build_dialogue(root: Control) -> void:
	dialogue = Control.new()
	dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dialogue)
	var panel := Control.new()
	panel.name = "OriginalDialogue"
	panel.size = Vector2(384,192)
	panel.scale = Vector2.ONE*classic_hud.SCALE
	panel.position = Vector2((1280-384*classic_hud.SCALE)/2,450)
	dialogue.add_child(panel)
	# WindowDisp composes a stone frame from the original 64×48 tiles.
	for y in range(4):
		for x in range(6):
			var row := 0 if y==0 else (2 if y==3 else 1)
			var column := 0 if x==0 else (2 if x==5 else 1)
			classic_hud.picture(panel,26001+row*3+column,Vector2(x*64,y*48))
	dialogue_name = text("",15)
	dialogue_name.position = Vector2(18,15)
	dialogue_name.add_theme_color_override("font_color",Color.YELLOW)
	dialogue_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dialogue_name)
	dialogue_text = text("",15)
	dialogue_text.position = Vector2(18,45)
	dialogue_text.size = Vector2(348,90)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.add_theme_color_override("font_color",Color.WHITE)
	dialogue_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dialogue_text)
	var button_art: Texture2D = classic_hud.art[26091]
	var close_button: TextureButton = classic_hud.icon(panel,26091,26091,Vector2((384-button_art.get_width())/2.0,156),"确定 · Enter / Esc")
	close_button.name = "ConfirmDialogue"
	close_button.pressed.connect(close_dialogue)
	var quest_choice := Button.new()
	quest_choice.text = "村外的伙伴 / 休息"
	quest_choice.position = Vector2(105,112)
	quest_choice.size = Vector2(190,30)
	quest_choice.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	quest_choice.add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	quest_choice.pressed.connect(func(): close_dialogue(); show_adventure_menu("quest"))
	panel.add_child(quest_choice)
	dialogue.hide()


func restore_location() -> void:
	var location: Dictionary = session.snapshot().location
	var point := Vector2i(int(location.x),int(location.y))
	if int(location.map_id)==100:point -= Vector2i(592,448)
	if not load_area_id(int(location.map_id),point):
		load_area_id(1000,SPAWN)

func checkpoint() -> bool:
	if battle_session.snapshot().active:return false
	var point := display_cell()
	if is_instance_valid(battle_view) and battle_view.visible and battle_session.snapshot().outcome=="defeat":
		session.set_location(1000,SPAWN.x,SPAWN.y)
	else:
		session.set_location(int(data.map_id),point.x,point.y)
	save_elapsed = 0
	if not profile_persistence:return true
	var payload := JSON.stringify(session.snapshot())
	if payload==last_saved_payload:return true
	var success: bool = session.save_game(save_path)
	if success:last_saved_payload = payload
	if not success:last_adventure_message = "保存失败，请检查存储空间。"
	return success

func refresh_companion() -> void:
	if is_instance_valid(pet_follower):
		pet_follower.queue_free()
	pet_follower = null
	var profile: Dictionary = session.snapshot()
	if int(profile.active_pet)<0 or not FileAccess.file_exists("res://assets/legacy/battle/manifest.json"):return
	var pet: Dictionary = profile.pets[int(profile.active_pet)]
	if int(pet.hp)<=0:return
	pet_follower = PetFollower.new()
	pet_follower.world = self
	pet_follower.position = player.position
	actors.add_child(pet_follower)
	pet_follower.select_pet(str(int(pet.sprite)),str(pet.name))

func update_adventure_hint() -> void:
	if not is_instance_valid(adventure_hint):return
	adventure_hint.visible = not battle_view.visible and not adventure_menu.visible and not dialogue.visible
	var profile: Dictionary = session.snapshot()
	var q: Dictionary = profile.quest
	if is_instance_valid(boss_button):boss_button.disabled = not session.can_fight_boss()
	var objective := "找村民聊聊，准备你的第一次冒险。"
	if q.claimed:objective = "委托完成！继续培养与收集你的伙伴。"
	elif session.can_fight_boss():objective = "强壮的乌力斯坦出现了：准备好后在村外继续探索。"
	elif q.boss_defeated:objective = "回到村民身边领取报酬。"
	elif q.accepted:objective = "村外的伙伴：胜利 %d/3 · 捕获伙伴 %d/1" % [mini(3,int(q.wins)),mini(1,profile.pets.size())]
	adventure_hint.text = "Lv.%d  体力 %d/%d  石币 %d   %s" % [profile.player.level,profile.player.hp,profile.player.max_hp,profile.player.gold,objective]
	if not last_adventure_message.is_empty():adventure_hint.text += "\n"+last_adventure_message

func show_adventure_menu(kind: String) -> void:
	if moving or battle_view.visible or dialogue.visible or help.visible:return
	if kind=="shop" and (int(data.map_id)!=1002 or not in_talk_range(cell)):return
	if kind=="quest" and (int(data.map_id)!=1000 or not in_talk_range(cell)):return
	clear_input()
	paused_input = true
	classic_hud.map_panel.hide()
	adventure_menu.open_menu(kind)
	play_ui_sound(202)

func close_adventure_menu() -> void:
	adventure_menu.hide()
	paused_input = false
	clear_input()
	refresh_companion()
	checkpoint()
	play_ui_sound(203)

func perform_adventure_action(action: String, value: Variant = null) -> void:
	if not adventure_menu.visible or battle_view.visible:return
	var success := false
	var note := ""
	var at_shop := int(data.map_id)==1002 and in_talk_range(cell)
	var at_villager := int(data.map_id)==1000 and in_talk_range(cell)
	match action:
		"pet_preview":
			adventure_menu.selected_pet = int(value)
			adventure_menu.refresh()
			return
		"buy_potion":success = at_shop and session.buy_item("potion")
		"buy_club":success = at_shop and session.buy_item("club")
		"sell_potion":success = at_shop and session.sell_item("potion")
		"sell_club":success = at_shop and session.sell_item("club")
		"use_potion":success = session.use_item("potion")
		"equip":success = session.equip_item("club")
		"select_pet":success = session.select_pet(int(value))
		"rename_pet":success = session.rename_pet(int(value),adventure_menu.name_edit.text)
		"accept_quest":success = at_villager and session.accept_quest()
		"claim_quest":success = at_villager and session.claim_quest()
		"heal":success = at_villager and session.heal()
		"save":success = checkpoint()
		"mute":toggle_mute(); success = true
	if success:
		checkpoint()
		note = "已完成。"
		if action=="claim_quest":note = "委托完成！获得石币、经验与回复药。"
		elif action=="heal":note = "你与伙伴恢复了体力。"
		elif action=="accept_quest":note = "委托已接受，出发去村外吧！"
	else:note = "现在无法这样做，请检查条件、石币或数量。"
	adventure_menu.refresh(note)
	play_ui_sound(201)

func load_profile() -> bool:
	if session.load_game(save_path):return true
	# Never overwrite an unreadable save by autosaving a fresh profile.
	profile_persistence = false
	last_adventure_message = "存档未能读取；现以临时旅程运行，原文件保留。"
	return false
