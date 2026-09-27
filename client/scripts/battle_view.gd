extends Control
## Presentation only: the caller submits commands to the authority and supplies snapshots.
signal action_requested(action: String)
signal pet_command_requested(command: String)
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
const SPECIES_ART := {"wooli":"100250","wooli_wooli":"100251","wooli_stan":"100252"}
var built := false
var pending_action := ""
var feedback_until := 0.0
const ENTRY_SECONDS := 1.0
const TRANSITION_SECONDS := 1.9
var transition_tiles: Array[Dictionary] = []
const MENU_SLIDE_SECONDS := 0.4
var menu_slide_at := 0.0
var selected_action := ""
var last_player_command := "attack"
var last_pet_command := ""
var remembered_pet := ""
var queued_player_action := ""
var command_phase := "player"
var command_panel: Control
var choice_panel: Control
var target_buttons: Array[Button] = []
var actor_labels: Array[Label] = []
var hint: Label
# Legacy entry820 minus slide sum24..0=300, plus160 for800-wide stage.
const MENU_ANCHOR := Vector2(680,65)
const PET_MENU_ANCHOR := Vector2(675,48)

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
	status = label("",16,Vector2(20,12),Vector2(420,26))
	report = label("",16,Vector2(20,508),Vector2(760,65))
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint = label("",16,Vector2(20,578),Vector2(760,22))
	command_panel = Control.new()
	command_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(command_panel)
	# StockDispBuffer uses a common anchor plus each bitmap's stored offset.
	# battlemenu.cpp:3757-3765, anim_tbl.h:25000-series classic menu.
	ui_picture(25116,MENU_ANCHOR,command_panel)
	var choices := [["attack",25100,"攻击"],["magic",25102,"咒术（尚未习得）"],["capture",25104,"捕捉"],["help",25106,"求救（单人模式）"],["defend",25108,"防御"],["item",25110,"道具"],["pet",25112,"宠物"],["escape",25114,"逃跑"]]
	for choice in choices:
		var button := TextureButton.new()
		button.name = str(choice[0]).capitalize()
		button.set_meta("action",choice[0])
		button.texture_normal = load(ART_ROOT+"ui/%d.png" % int(choice[1]))
		button.texture_hover = button.texture_normal
		button.texture_pressed = load(ART_ROOT+"ui/%d.png" % (int(choice[1])+1))
		button.position = MENU_ANCHOR+ui_offset(int(choice[1]))
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = str(choice[2])
		button.pressed.connect(_request_action.bind(str(choice[0])))
		command_panel.add_child(button)
		commands.append(button)
	choice_panel = Control.new()
	choice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice_panel.z_index = 10
	stage.add_child(choice_panel)
	for i in range(3):
		var target := Button.new()
		target.name = ["PlayerTarget","EnemyTarget","PetTarget"][i]
		target.flat = true
		target.position = [Vector2(525,240),Vector2(205,120),Vector2(425,295)][i]
		target.size = Vector2(80,125)
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		target.focus_mode = Control.FOCUS_NONE
		target.pressed.connect(select_target.bind(i))
		stage.add_child(target)
		target_buttons.append(target)
		actor_labels.append(label("",14,target.position+Vector2(-30,125),Vector2(200,45)))
	return_button = Button.new()
	return_button.name = "ReturnFromBattle"
	return_button.text = "继续探索"
	return_button.flat = true
	return_button.position = Vector2(325,460)
	return_button.size = Vector2(150,32)
	return_button.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	return_button.pressed.connect(func():
		if not is_animating(): return_requested.emit())
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
	actors.append({"sprite":sprite,"point":point,"home":point,"motions":[],"animation":animations[key],"animations":animations,"facing":facing,"temporary":"","until":0.0,"cues":[],"started":0.0,"last_frame":""})

func layout() -> void:
	if stage == null:
		return
	var factor := minf(size.x/STAGE_SIZE.x,size.y/STAGE_SIZE.y)
	stage.scale = Vector2.ONE*factor
	stage.position = (size-STAGE_SIZE*factor)/2

func open_battle(next_state: Dictionary) -> void:
	capture_transition()
	elapsed = 0.0
	state = {}
	last_player_command = "attack"
	feedback_until = 0.0
	if is_instance_valid(world) and actors.size() > 0:
		var ident: String = str(world.player.character_id)
		if manifest.characters.has(ident):
			actors[0].animations = manifest.characters[ident]
			actors[0].animation = manifest.characters[ident]["3_%d" % int(actors[0].facing)]
	var enemy_art := str(next_state.get("enemy_sprite",SPECIES_ART.get(str(next_state.get("enemy_species","wooli")),"100250")))
	set_actor_art(1,enemy_art)
	if actors.size() > 2:
		actors[2].sprite.queue_free()
		actors.resize(2)
	var pet: Dictionary = next_state.get("pet",{})
	var pet_key := str(pet.get("species",""))+":"+str(pet.get("name",""))
	if pet_key!=remembered_pet:
		last_pet_command = ""
		remembered_pet = pet_key
	if not pet.is_empty():
		add_actor(str(pet.get("sprite",SPECIES_ART.get(str(pet.get("species","wooli")),"100250"))),Vector2(465,420),3)
	for actor in actors:
		actor.temporary = ""
		actor.cues = []
	show_state(next_state)
	for i in range(actors.size()):
		var actor: Dictionary = actors[i]
		actor.point = actor.home+Vector2(-300,-300) if i==1 else actor.home+Vector2(300,300)
		actor.motions = []
		queue_motion(i,actor.point,actor.home,TRANSITION_SECONDS,ENTRY_SECONDS,int(actor.facing))
		queue_pose(i,4,TRANSITION_SECONDS,ENTRY_SECONDS)
	menu_slide_at = TRANSITION_SECONDS+ENTRY_SECONDS
	feedback_until = TRANSITION_SECONDS+ENTRY_SECONDS+MENU_SLIDE_SECONDS
	command_panel.position.x = 300
	show()

# produce.cpp ProduceHagare(mode2): 8x8 viewport tiles, one released each
# frame, then y += ++acceleration. Reconstructed at60Hz independent of render FPS.
func capture_transition() -> void:
	for tile in transition_tiles:
		tile.node.queue_free()
	transition_tiles.clear()
	if DisplayServer.get_name()=="headless": return
	var screenshot := get_viewport().get_texture().get_image()
	if screenshot==null or screenshot.is_empty(): return
	var source := ImageTexture.create_from_image(screenshot)
	var order: Array[int] = []
	for i in range(64): order.append(i)
	var random := RandomNumberGenerator.new()
	random.seed = 215
	for i in range(63,0,-1):
		var other := random.randi_range(0,i)
		var swap := order[i]
		order[i] = order[other]
		order[other] = swap
	for release in range(64):
		var cell := Vector2i(order[release]%8,order[release]/8)
		var region := Rect2(Vector2(cell)*Vector2(screenshot.get_size())/8.0,Vector2(screenshot.get_size())/8.0)
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		atlas.region = region
		var tile := TextureRect.new()
		tile.texture = atlas
		tile.position = Vector2(cell)*size/8.0
		tile.size = size/8.0
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.z_index = 100
		add_child(tile)
		transition_tiles.append({"node":tile,"origin":tile.position,"release":float(release)/60.0})

func set_actor_art(index: int, ident: String) -> void:
	if index >= actors.size() or not manifest.get("characters",{}).has(ident): return
	actors[index].animations = manifest.characters[ident]
	var key := "3_%d" % int(actors[index].facing)
	if manifest.characters[ident].has(key): actors[index].animation = manifest.characters[ident][key]

func close_battle() -> void:
	hide()

func show_state(next_state: Dictionary) -> void:
	var previous := state
	state = next_state.duplicate(true)
	if actors.size() >= 2 and not previous.is_empty() and int(state.get("turn",0)) != int(previous.get("turn",0)):
		queue_turn_animation(previous)
	pending_action = ""
	if not built:
		return
	selected_action = ""
	queued_player_action = ""
	command_phase = "player"
	clear_choices()
	status.text = "第 %d 回合" % (int(state.get("turn",0))+1)
	actor_labels[0].text = "你  HP %d / %d" % [int(state.get("player_hp",0)),int(state.get("player_max_hp",0))]
	actor_labels[1].text = "%s  HP %d / %d" % [str(state.get("enemy_name",manifest.get("enemy_name","乌力"))),int(state.get("enemy_hp",0)),int(state.get("enemy_max_hp",0))]
	var pet: Dictionary = state.get("pet",{})
	actor_labels[2].text = "" if pet.is_empty() else "%s  HP %d / %d" % [str(pet.get("name","宠物")),int(state.get("pet_hp",pet.get("hp",0))),int(state.get("pet_max_hp",pet.get("max_hp",0)))]
	var messages := PackedStringArray()
	for event in state.get("events",[]): messages.append(str(event))
	var outcome := str(state.get("outcome",""))
	var ending := {"win":"战斗胜利！","defeat":"战斗结束，返回村庄恢复体力。","escaped":"成功逃离战斗。","captured":"捕捉成功！"}
	if ending.has(outcome): messages.append(ending[outcome])
	report.text = "\n".join(messages.slice(maxi(0,messages.size()-3)))
	hint.text = "请选择指令；攻击或捕捉后点击目标。右键 / Esc 取消。" if outcome.is_empty() else "按 Enter 继续"
	command_panel.visible = outcome.is_empty()
	return_button.visible = not outcome.is_empty()
	return_button.text = "返回村庄" if outcome=="defeat" else "继续探索"
	if bool(state.get("active",false)):
		selected_action = last_player_command if last_player_command=="attack" or (last_player_command=="capture" and not bool(state.get("boss",false)) and bool(state.get("can_capture",true))) else "attack"
		hint.text = "攻击：请选择敌人；右键 / Esc 取消。" if selected_action=="attack" else "捕捉：请选择敌人；右键 / Esc 取消。"

func queue_pose(index: int, action: int, at: float, seconds: float) -> void:
	if index >= actors.size(): return
	actors[index].cues.append({"at":at,"action":action,"seconds":seconds})

func is_animating() -> bool:
	return visible and elapsed < feedback_until

func queue_motion(index: int, origin: Vector2, destination: Vector2, at: float, seconds: float, facing: int) -> void:
	actors[index].motions.append({"from":origin,"to":destination,"at":at,"end":at+seconds,"facing":facing})

func queue_strike(index: int, target: int, at: float) -> Dictionary:
	var actor: Dictionary = actors[index]
	var home: Vector2 = actor.home
	var target_home: Vector2 = actors[target].home
	var contact := target_home+(home-target_home).normalized()*64.0
	var travel := clampf(home.distance_to(contact)/650.0,0.2,0.6)
	var facing := 7 if index==1 else 3
	var clip: Dictionary = actor.animations.get("0_%d" % facing,{})
	var strike := clampf(float(clip.get("duration_ms",600))/1000.0,0.35,1.2)
	var hit_fraction := 0.5
	var frames: Array = clip.get("frames",[])
	for i in range(frames.size()):
		if int(frames[i].get("sound",0))>=10000:
			hit_fraction = float(i)/frames.size()
			break
	queue_motion(index,home,contact,at,travel,facing)
	queue_pose(index,4,at,travel)
	actors[index].cues.append({"at":at+travel,"action":0,"seconds":strike,"facing":facing})
	queue_motion(index,contact,home,at+travel+strike,travel,(facing+4)%8)
	actors[index].cues.append({"at":at+travel+strike,"action":4,"seconds":travel,"facing":(facing+4)%8})
	actors[index].cues.append({"at":at+travel*2+strike,"action":3,"seconds":0.01,"facing":int(actor.facing)})
	return {"hit":at+travel+strike*hit_fraction,"end":at+travel*2+strike}

func queue_turn_animation(previous: Dictionary) -> void:
	for actor in actors:
		actor.cues = []
		actor.motions = []
		actor.point = actor.home
	var fallback: Array = ["player"]
	if actors.size()>2: fallback.append("pet")
	if int(state.get("enemy_hp",0))>0: fallback.append("enemy")
	var order: Array = state.get("turn_order",fallback)
	var pet_command := str(state.get("last_pet_command",state.get("pet_command","attack")))
	var at := elapsed
	for step in range(order.size()):
		var who := str(order[step])
		var index: int = {"player":0,"enemy":1,"pet":2}.get(who,0)
		if index>=actors.size(): continue
		var attack := who=="enemy" or (who=="player" and pending_action in ["attack","capture"]) or (who=="pet" and pet_command!="defend")
		var target := 1 if who!="enemy" else (2 if actors.size()>2 and int(state.get("pet_hp",0))<int(previous.get("pet_hp",0)) else 0)
		var timing := {"hit":at+0.25,"end":at+0.5}
		if attack:
			timing = queue_strike(index,target,at)
		else:
			queue_pose(index,10,at,0.5)
		if who=="enemy":
			for recipient in [[0,"player_hp"],[2,"pet_hp"]]:
				var hp_key: String = recipient[1]
				if int(state.get(hp_key,0)) < int(previous.get(hp_key,0)):
					var defeated := int(state.get(hp_key,0))<=0
					queue_pose(int(recipient[0]),2 if defeated else 1,float(timing.hit),60.0 if defeated else 0.35)
		elif attack and int(state.get("enemy_hp",0)) < int(previous.get("enemy_hp",0)):
			var defeated := int(state.get("enemy_hp",0))<=0 and step==order.size()-1
			queue_pose(1,2 if defeated else 1,float(timing.hit),60.0 if defeated else 0.35)
		at = float(timing.end)+0.08
	menu_slide_at = at
	feedback_until = at+(MENU_SLIDE_SECONDS if bool(state.get("active",false)) else 0.0)
	for actor in actors:
		actor.cues.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.at)<float(b.at))

func ui_offset(ident: int) -> Vector2:
	var info: Dictionary = manifest.get("ui",{}).get(str(ident),{})
	return Vector2(float(info.get("x",0)),float(info.get("y",0)))

func ui_picture(ident: int, anchor: Vector2, parent: Control) -> void:
	var path := ART_ROOT+"ui/%d.png" % ident
	if not ResourceLoader.exists(path): return
	var image := TextureRect.new()
	image.texture = load(path)
	image.position = anchor+ui_offset(ident)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)

func clear_choices() -> void:
	for child in choice_panel.get_children():
		choice_panel.remove_child(child)
		child.queue_free()

func choice(text: String, position_at: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.position = position_at
	button.size = Vector2(220,30)
	button.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	button.add_theme_color_override("font_color",Color.WHITE)
	button.add_theme_color_override("font_outline_color",Color.BLACK)
	button.add_theme_constant_override("outline_size",3)
	button.add_theme_font_size_override("font_size",16)
	button.pressed.connect(callback)
	choice_panel.add_child(button)
	return button

func _request_action(action: String) -> void:
	if not bool(state.get("active",false)) or elapsed < feedback_until: return
	if action in ["magic","help"]: return
	if action=="capture" and (bool(state.get("boss",false)) or not bool(state.get("can_capture",true))): return
	sound_requested.emit(217)
	clear_choices()
	selected_action = action
	last_player_command = action if action in ["attack","capture"] else "attack"
	if action == "item":
		ui_picture(26061,Vector2(650,235),choice_panel)
		ui_picture(26072,Vector2(650,222),choice_panel)
		if ResourceLoader.exists("res://assets/legacy/mvp/images/potion.png"):
			var icon := TextureRect.new()
			icon.texture = load("res://assets/legacy/mvp/images/potion.png")
			icon.position = Vector2(530,196)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			choice_panel.add_child(icon)
		var item_button := choice("",Vector2(522,188),func():
			if int(state.get("potions",0)) > 0 and int(state.get("player_hp",0)) < int(state.get("player_max_hp",0)):
				clear_choices()
				selected_action = "item_target"
				hint.text = "请选择自己使用回复药。")
		item_button.size = Vector2(52,48)
		item_button.disabled = int(state.get("potions",0))<=0 or int(state.get("player_hp",0))>=int(state.get("player_max_hp",0))
		item_button.tooltip_text = "回复药 × %d" % int(state.get("potions",0))
		if item_button.disabled:
			item_button.tooltip_text += "（已用完）" if int(state.get("potions",0))<=0 else "（体力已满）"
		var description := Label.new()
		description.text = item_button.tooltip_text+"\n点击药瓶，再选择自己。"
		description.position = Vector2(540,365)
		description.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
		description.add_theme_color_override("font_outline_color",Color.BLACK)
		description.add_theme_constant_override("outline_size",2)
		choice_panel.add_child(description)
		hint.text = "选择道具；右键 / Esc 取消。"
	elif action == "pet":
		ui_picture(26040,Vector2(650,280),choice_panel)
		var pet: Dictionary = state.get("pet",{})
		choice("无出战宠物" if pet.is_empty() else str(pet.get("name","宠物"))+"（出战中）",Vector2(545,165),cancel_selection)
		hint.text = "出战宠物；战斗外可更换。"
	elif action in ["attack","capture"]:
		hint.text = "请选择敌人；右键 / Esc 取消。"
	else:
		complete_player_command(action)

func select_target(index: int) -> void:
	if elapsed < feedback_until or not bool(state.get("active",false)): return
	if command_phase == "pet" and index == 1 and selected_action in ["pet_attack","pet_skill"]:
		finish_pet_command(selected_action.trim_prefix("pet_"))
	elif index == 1 and selected_action in ["attack","capture"]:
		complete_player_command(selected_action)
	elif index == 0 and selected_action == "item_target":
		complete_player_command("item")

func complete_player_command(action: String) -> void:
	queued_player_action = action
	selected_action = ""
	var pet: Dictionary = state.get("pet",{})
	if not pet.is_empty() and int(state.get("pet_hp",pet.get("hp",0))) > 0 and action != "escape":
		command_phase = "pet"
		command_panel.hide()
		if not last_pet_command.is_empty():
			var remembered := last_pet_command
			if remembered=="skill" and (not bool(state.get("skill_unlocked",false)) or bool(state.get("skill_used",false))): remembered = "attack"
			clear_choices()
			selected_action = "pet_"+remembered
			hint.text = "宠物%s：请选择敌人；右键 / Esc 更换指令。" % ("技能" if remembered=="skill" else "攻击")
		else:
			show_pet_choices()
	else:
		submit_command()

func show_pet_choices() -> void:
	clear_choices()
	ui_picture(25140,PET_MENU_ANCHOR,choice_panel)
	ui_picture(25141,PET_MENU_ANCHOR,choice_panel)
	var pet_title := label(str(state.get("pet_name",state.get("pet",{}).get("name","宠物"))),16,PET_MENU_ANCHOR+Vector2(-96,-14),Vector2(192,28))
	pet_title.reparent(choice_panel)
	ui_picture(26130,Vector2(650,300),choice_panel)
	var actions := [["攻击","attack"],["技能","skill"],["防御","defend"]]
	for i in range(actions.size()):
		var action: String = actions[i][1]
		var button := choice(str(actions[i][0]),Vector2(540,170+i*38),func():
			sound_requested.emit(217)
			if action == "defend": finish_pet_command(action)
			else:
				clear_choices()
				selected_action = "pet_"+action
				hint.text = "宠物：请选择敌人；右键 / Esc 重新选择。")
		if action=="skill" and (not bool(state.get("skill_unlocked",false)) or bool(state.get("skill_used",false))):
			button.disabled = true
			button.text = "技能（本场已使用）" if bool(state.get("skill_used",false)) else "技能（宠物 2 级解锁）"
	hint.text = "请选择宠物指令；右键 / Esc 返回人物指令。"

func finish_pet_command(command: String) -> void:
	last_pet_command = command if command in ["attack","skill"] else "attack"
	pet_command_requested.emit(command)
	submit_command()

func submit_command() -> void:
	pending_action = queued_player_action
	var action := queued_player_action
	queued_player_action = ""
	selected_action = ""
	clear_choices()
	action_requested.emit(action)

func cancel_selection() -> void:
	if not bool(state.get("active",false)): return
	sound_requested.emit(217)
	if command_phase == "pet" and selected_action.begins_with("pet_"):
		selected_action = ""
		show_pet_choices()
		return
	command_phase = "player"
	queued_player_action = ""
	selected_action = ""
	clear_choices()
	command_panel.show()
	hint.text = "请选择指令；攻击或捕捉后点击目标。"

func _input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_accept") and is_animating():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		cancel_selection()
		get_viewport().set_input_as_handled()

func animate_actor(index: int, action: int, seconds: float = 0.65, facing: int = -1) -> void:
	var actor: Dictionary = actors[index]
	var key := "%d_%d" % [action,int(actor.facing) if facing<0 else facing]
	if actor.animations.has(key):
		actor.temporary = key
		actor.until = elapsed+seconds
		actor.started = elapsed
		actor.last_frame = ""

func _process(delta: float) -> void:
	if not visible:
		return
	elapsed += delta
	for tile in transition_tiles:
		var frames := maxf(0.0,(elapsed-float(tile.release))*60.0)
		tile.node.position = tile.origin+Vector2(0,frames*(frames+1.0)*0.5*size.y/600.0)
	if elapsed>=TRANSITION_SECONDS and not transition_tiles.is_empty():
		for tile in transition_tiles: tile.node.queue_free()
		transition_tiles.clear()
	return_button.disabled = is_animating()
	if bool(state.get("active",false)) and command_phase=="player":
		command_panel.visible = elapsed>=menu_slide_at
		var slide := clampf((elapsed-menu_slide_at)/MENU_SLIDE_SECONDS,0.0,1.0)
		command_panel.position.x = 300.0*pow(1.0-slide,2)
	for button in commands:
		button.disabled = not bool(state.get("active",false)) or elapsed < feedback_until or str(button.get_meta("action","")) in ["magic","help"]
		if str(button.get_meta("action",""))=="capture":
			var unavailable := bool(state.get("boss",false)) or not bool(state.get("can_capture",true))
			button.disabled = button.disabled or unavailable
			button.tooltip_text = "此战对手无法捕捉" if bool(state.get("boss",false)) else ("宠物栏已满" if not bool(state.get("can_capture",true)) else "捕捉")
		button.texture_normal = load(ART_ROOT+"ui/%d.png" % (25100+commands.find(button)*2+(1 if selected_action==str(button.get_meta("action","")) else 0)))
		button.texture_hover = button.texture_normal
	for actor_index in range(actors.size()):
		var actor: Dictionary = actors[actor_index]
		var cues: Array = actor.cues
		while not cues.is_empty() and elapsed >= float(cues[0].at):
			var cue: Dictionary = cues.pop_front()
			animate_actor(actor_index,int(cue.action),float(cue.seconds),int(cue.get("facing",-1)))
			actor.started = float(cue.at)
			actor.until = float(cue.at)+float(cue.seconds)
		var motions: Array = actor.get("motions",[])
		while not motions.is_empty() and elapsed>=float(motions[0].at):
			var motion: Dictionary = motions[0]
			var amount := clampf((elapsed-float(motion.at))/(float(motion.end)-float(motion.at)),0.0,1.0)
			actor.point = Vector2(motion.from).lerp(Vector2(motion.to),amount)
			if amount<1.0: break
			motions.pop_front()
		if actor_index<actor_labels.size():
			actor_labels[actor_index].position = actor.point+Vector2(-70,15)
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
			index = int(fmod(elapsed-float(actor.started),duration)/duration*frames.size()) if str(actor.temporary).begins_with("4_") else mini(int((elapsed-float(actor.started))/duration*frames.size()),frames.size()-1)
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
