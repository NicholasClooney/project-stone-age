extends Control
## Presentation only: the caller submits commands to the authority and supplies snapshots.
signal action_requested(action: String)
signal return_requested
signal sound_requested(ident: int)

const ART_ROOT := "res://assets/legacy/battle/"
const STAGE_SIZE := Vector2(800,600)
var world: Node
var stage: Control
var manifest: Dictionary = {}
var state: Dictionary = {}
var status: Label
var report: Label
var return_button: Button
var commands: Array[TextureButton] = []
var actors: Array[Dictionary] = []
var textures: Dictionary = {}
var elapsed := 0.0
var built := false
var pending_action := ""
var feedback_until := 0.0

func configure(next_world: Node) -> void:
	world = next_world

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shade := ColorRect.new()
	shade.color = Color.BLACK
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	stage = Control.new()
	stage.size = STAGE_SIZE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	if FileAccess.file_exists(ART_ROOT+"manifest.json"):
		manifest = JSON.parse_string(FileAccess.get_file_as_string(ART_ROOT+"manifest.json"))
		picture("background.png",Vector2.ZERO)
		for ident in manifest.get("images",{}):
			textures[str(ident)] = load(ART_ROOT+"images/%s.png" % ident)
		add_actor(str(manifest.get("player_id","100000")),Vector2(565,350),3)
		add_actor(str(manifest.get("enemy_id","")),Vector2(245,230),7)
	status = label("",19,Vector2(24,18),Vector2(752,60))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Reuse the original dialogue tiles for this first slice's combat transcript.
	for y in range(3):
		for x in range(8):
			var row := 0 if y==0 else (2 if y==2 else 1)
			var column := 0 if x==0 else (2 if x==7 else 1)
			var tile := TextureRect.new()
			tile.texture = load("res://assets/legacy/ui/%d.png" % (26001+row*3+column))
			tile.position = Vector2(16+x*64,438+y*48)
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stage.add_child(tile)
	report = label("",15,Vector2(34,451),Vector2(472,115))
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var choices := [["attack",25100,25101,"攻击"],["defend",25108,25109,"防御"],["escape",25114,25115,"逃跑"]]
	for i in range(choices.size()):
		var choice: Array = choices[i]
		var button := TextureButton.new()
		button.name = str(choice[0]).capitalize()
		var art_path := ART_ROOT+"ui/%d.png" % int(choice[1])
		if ResourceLoader.exists(art_path):
			button.texture_normal = load(art_path)
			button.texture_hover = button.texture_normal
			button.texture_pressed = load(ART_ROOT+"ui/%d.png" % int(choice[2]))
		button.position = Vector2(556+i*74,446)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = str(choice[3])
		button.pressed.connect(_request_action.bind(str(choice[0])))
		stage.add_child(button)
		commands.append(button)
		label(str(choice[3]),17,Vector2(558+i*74,500),Vector2(72,32))
	return_button = Button.new()
	return_button.name = "ReturnFromBattle"
	return_button.text = "返回村庄"
	return_button.position = Vector2(553,541)
	return_button.size = Vector2(215,36)
	return_button.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	return_button.pressed.connect(func(): return_requested.emit())
	stage.add_child(return_button)
	resized.connect(layout)
	built = true
	layout()
	hide()

func label(value: String, font_size: int, point: Vector2, dimensions: Vector2) -> Label:
	var result := Label.new()
	result.text = value
	result.position = point
	result.size = dimensions
	result.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",Color.WHITE)
	result.add_theme_color_override("font_outline_color",Color.BLACK)
	result.add_theme_constant_override("outline_size",3)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(result)
	return result

func picture(path: String, point: Vector2) -> TextureRect:
	var result := TextureRect.new()
	result.texture = load(ART_ROOT+path)
	result.position = point
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(result)
	return result

func add_actor(ident: String, point: Vector2, facing: int) -> void:
	var characters: Dictionary = manifest.get("characters",{})
	if not characters.has(ident):
		return
	var animations: Dictionary = characters[ident]
	var key := "3_%d" % facing
	if not animations.has(key):
		for candidate in animations:
			if str(candidate).begins_with("3_"):
				key = str(candidate)
				break
	if not animations.has(key):
		return
	var sprite := Sprite2D.new()
	sprite.centered = false
	stage.add_child(sprite)
	actors.append({"sprite":sprite,"point":point,"animation":animations[key],"animations":animations,"facing":facing,"temporary":"","until":0.0,"cues":[],"started":0.0,"last_frame":""})

func layout() -> void:
	if stage == null:
		return
	var factor := minf(size.x/STAGE_SIZE.x,size.y/STAGE_SIZE.y)
	stage.scale = Vector2.ONE*factor
	stage.position = (size-STAGE_SIZE*factor)/2

func open_battle(next_state: Dictionary) -> void:
	elapsed = 0.0
	state = {}
	feedback_until = 0.0
	if is_instance_valid(world) and actors.size() > 0:
		var ident: String = str(world.player.character_id)
		if manifest.characters.has(ident):
			actors[0].animations = manifest.characters[ident]
			actors[0].animation = manifest.characters[ident]["3_%d" % int(actors[0].facing)]
	for actor in actors:
		actor.temporary = ""
		actor.cues = []
	show_state(next_state)
	show()

func close_battle() -> void:
	hide()

func show_state(next_state: Dictionary) -> void:
	var previous := state
	state = next_state.duplicate(true)
	if actors.size() == 2 and not previous.is_empty():
		feedback_until = elapsed+1.2
		for actor in actors:
			actor.cues = []
		animate_actor(0,0 if pending_action=="attack" else 10,0.55)
		if int(state.get("enemy_hp",0)) < int(previous.get("enemy_hp",0)):
			animate_actor(1,1,0.55)
		if int(state.get("enemy_hp",0)) <= 0:
			actors[1].cues.append({"at":elapsed+0.55,"action":2,"seconds":60.0})
		elif int(state.get("player_hp",0)) < int(previous.get("player_hp",0)):
			actors[1].cues.append({"at":elapsed+0.55,"action":0,"seconds":0.6})
			actors[0].cues.append({"at":elapsed+0.55,"action":2 if int(state.get("player_hp",0))<=0 else 1,"seconds":60.0 if int(state.get("player_hp",0))<=0 else 0.6})
	pending_action = ""
	if not built:
		return
	status.text = "你  HP %d / %d       第 %d 回合       %s  HP %d / %d" % [int(state.get("player_hp",0)),int(state.get("player_max_hp",0)),int(state.get("turn",1)),str(manifest.get("enemy_name","野生石器宠物")),int(state.get("enemy_hp",0)),int(state.get("enemy_max_hp",0))]
	var messages := PackedStringArray()
	for event in state.get("events",[]):
		messages.append(str(event))
	var outcome := str(state.get("outcome",""))
	var ending := {"win":"战斗胜利！","defeat":"战斗结束，返回村庄恢复体力。","escaped":"成功逃离战斗。"}
	if ending.has(outcome) and not messages.has(str(ending[outcome])):
		messages.append(ending[outcome])
	if messages.is_empty():
		messages.append("野生宠物出现了！请选择攻击、防御或逃跑。")
	report.text = "\n".join(messages)
	for button in commands:
		button.disabled = not bool(state.get("active",false))
	return_button.visible = not outcome.is_empty()
	return_button.text = "返回村庄" if outcome=="defeat" else "继续探索"

func _request_action(action: String) -> void:
	if not bool(state.get("active",false)) or elapsed < feedback_until:
		return
	pending_action = action
	action_requested.emit(action)

func animate_actor(index: int, action: int, seconds: float = 0.65) -> void:
	var actor: Dictionary = actors[index]
	var key := "%d_%d" % [action,int(actor.facing)]
	if actor.animations.has(key):
		actor.temporary = key
		actor.until = elapsed+seconds
		actor.started = elapsed
		actor.last_frame = ""

func _process(delta: float) -> void:
	if not visible:
		return
	elapsed += delta
	for button in commands:
		button.disabled = not bool(state.get("active",false)) or elapsed < feedback_until
	for actor_index in range(actors.size()):
		var actor: Dictionary = actors[actor_index]
		var cues: Array = actor.cues
		if not cues.is_empty() and elapsed >= float(cues[0].at):
			var cue: Dictionary = cues.pop_front()
			animate_actor(actor_index,int(cue.action),float(cue.seconds))
		var animation: Dictionary = actor.animation
		if elapsed < float(actor.until) and not str(actor.temporary).is_empty():
			animation = actor.animations[actor.temporary]
		var frames: Array = animation.frames
		if frames.is_empty():
			continue
		var duration := maxf(float(animation.duration_ms)/1000.0,0.1)
		var index := int(fmod(elapsed,duration)/duration*frames.size())%frames.size()
		var temporary := elapsed < float(actor.until) and not str(actor.temporary).is_empty()
		if temporary:
			index = mini(int((elapsed-float(actor.started))/duration*frames.size()),frames.size()-1)
		var frame: Dictionary = frames[index]
		var frame_key := str(actor.temporary)+"_"+str(index) if temporary else "idle_"+str(index)
		if frame_key != str(actor.last_frame):
			actor.last_frame = frame_key
			var sound_id := int(frame.get("sound",0))
			if temporary and manifest.get("frame_sounds",{}).has(str(sound_id)):
				sound_requested.emit(sound_id)
		var ident := str(int(frame.image))
		var metadata: Dictionary = manifest.images[ident]
		var sprite: Sprite2D = actor.sprite
		sprite.texture = textures[ident]
		sprite.position = actor.point+Vector2(float(metadata.x)+float(frame.x),float(metadata.y)+float(frame.y))
