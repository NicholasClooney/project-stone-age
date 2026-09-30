extends Control
## Presentation only: the caller submits commands to the authority and supplies snapshots.
signal action_requested(action: String)
signal pet_command_requested(command: String)
signal return_requested
signal sound_requested(ident: int)
signal capture_music_requested(celebrating: bool)

const Elements = preload("res://server/elements.gd")
const PetSkills = preload("res://scripts/pet_skills.gd")
const BattleEffects = preload("res://scripts/battle_effects.gd")
const SpriteArt = preload("res://scripts/sprite_art.gd")
const BattleArt = preload("res://scripts/battle_art.gd")
const Riding = preload("res://scripts/riding.gd")
const PerfRegistry = preload("res://scripts/perf_registry.gd")
const ART_ROOT := "res://assets/legacy/battle/"
const STAGE_SIZE := Vector2(800,600)
var world: Node
var stage: Control
## battle/index.json (scripts/battle_art.gd): player and enemy ids, club
## variants, UI pictures and audio. Each actor holds its sprite's own entry.
var manifest: Dictionary = {}
## Frame sound id -> file: the battle sprites', plus the riding composites'
## once a mounted battle has shown one.
var frame_sounds: Dictionary = {}
var state: Dictionary = {}
var status: Label
var report: Label
var hover_info: Label
var displayed_mount: Dictionary = {}
var displayed_ally_mounts: Array[Dictionary] = []
var ally_mount_bars: Array[Control] = []
var ally_mount_fills: Array[ColorRect] = []
var return_button: Button
var battle_effects: Control
var result_panel: Control
var result_text: Label
var starting_profile: Dictionary = {}
var result_sound_played := false
var result_level_up := false
var commands: Array[TextureButton] = []
var actors: Array[Dictionary] = []
var riding_art_cues: Array[Dictionary] = []
var riding_hp_bar: Control
var riding_hp_fill: ColorRect
var unmounted_player_art := "100000"
# Only the battle presentation clock changes; authority and world clocks stay intact.
var playback_speed := 1.0:
	set(value): playback_speed = clampf(value,1.0,8.0) if is_finite(value) else 1.0
var elapsed := 0.0
const SPECIES_ART := {"wooli":"100250","wooli_wooli":"100251","wooli_stan":"100252"}
var built := false
var pending_action := ""
var mirror_cues: Array[Dictionary] = []
var mirror_effects: Array[Control] = []
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
var target_highlights: Array[Panel] = []
var pet_slide_at := -10.0
var actor_labels: Array[Label] = []
var hp_bars: Array[Control] = []
var hp_fills: Array[ColorRect] = []
var displayed_hp: Array[int] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
var player_target := 0
var pet_target := 0
var switch_pet_index := -2
var selected_pet_skill := 0
var pet_art_cues: Array[Dictionary] = []
# oft.cpp:144,11514-11605: classic two enemy rows and center-first ordering.
const ENEMY_SLOT_ORDER := [2,1,3,0,4]
# At 800x600 the friendly side receives DISPLACEMENT (160,120).
func enemy_home(index: int) -> Vector2:
	var slot: int = ENEMY_SLOT_ORDER[index % 5]
	return Vector2(37,198)+Vector2(32,-24)*slot if index<5 else Vector2(69,298)+Vector2(64,-48)*slot

func can_render_troop(enemies: Array) -> bool:
	return preload("res://server/troop_art.gd").can_render(enemies)

func enemy_actor(index: int) -> int:
	return 1 if index==0 else index+2
func enemy_index(index: int) -> int:
	return 0 if index==1 else index-2 if index>=3 and index<12 else -1
func ally_actor(index: int) -> int:
	return 12+index
func ally_home(index: int) -> Vector2:
	# oft.cpp11399-11456, classic five-person row plus800x600 displacement.
	return Vector2(613,552)+Vector2(32,-24)*int(ENEMY_SLOT_ORDER[index+1])
func ally_pet_actor(index: int) -> int:
	return 16+index
func ally_pet_home(index: int) -> Vector2:
	return Vector2(453,528)+Vector2(64,-48)*int(ENEMY_SLOT_ORDER[index+1])
func ally_art(ally: Dictionary, mounted: bool = true) -> String:
	var mount_id := int(ally.get("mounted_sprite",-1))
	if mounted and mount_id>=0 and ensure_riding_art(str(mount_id)): return str(mount_id)
	var ident := str(ally.get("character_id",100000))
	var weapon := str(ally.get("weapon",""))
	return str(manifest.get("equipment_variants",{}).get(weapon,{}).get(ident,ident))
func can_render_allies(allies: Array) -> bool:
	if allies.size()>4:return false
	for ally in allies:
		var animations: Dictionary=sprite_art(ally_art(ally)).get("animations",{})
		for action in [0,1,2,3,4,10]:
			if SpriteArt.frame_count(animations.get("%d_3"%action,{}))==0:return false
	return true
func enemies_of(snapshot: Dictionary) -> Array:
	return snapshot.get("enemies",[{"hp":snapshot.get("enemy_hp",0),"max_hp":snapshot.get("enemy_max_hp",1),"name":snapshot.get("enemy_name","乌力"),"sprite":snapshot.get("enemy_sprite",100250)}])
func health_of(snapshot: Dictionary, index: int, maximum: bool = false) -> int:
	var key := "max_hp" if maximum else "hp"
	if index>=16:
		var pets: Array = snapshot.get("ally_pets",[])
		return int(pets[index-16].get(key,0)) if index-16<pets.size() else 0
	if index>=12:
		var allies: Array = snapshot.get("allies",[])
		return int(allies[index-12].get(key,0)) if index-12<allies.size() else 0
	if index==0: return int(snapshot.get("player_"+key,0))
	if index==2: return int(snapshot.get("pet_"+key,0))
	var opponents := enemies_of(snapshot)
	var target := enemy_index(index)
	return int(opponents[target].get(key,0)) if target>=0 and target<opponents.size() else 0

var hp_cues: Array[Dictionary] = []
var word_cues: Array[Dictionary] = []
var music_cues: Array[Dictionary] = []
var sound_cues: Array[Dictionary] = []
var defeat_return_queued := false
var hint: Label
# Legacy entry820 minus slide sum24..0=300, plus160 for800-wide stage.
const MENU_ANCHOR := Vector2(680,65)
const PET_MENU_ANCHOR := Vector2(675,48)

var background_selector = preload("res://scripts/battle_background.gd").new()
var next_background := ""
var battlefield: TextureRect

func configure(next_world: Node) -> void:
	world = next_world

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shade := ColorRect.new()
	shade.color = Color.BLACK
	shade.z_index = -2000
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	stage = Control.new()
	stage.size = STAGE_SIZE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	if BattleArt.present():
		manifest = BattleArt.index()
		frame_sounds = BattleArt.frame_sounds().duplicate()
		battlefield = picture("background.png",Vector2.ZERO)
		battlefield.z_index = -1000
		add_actor(str(manifest.get("player_id","100000")),Vector2(677,504),3)
		add_actor(str(manifest.get("enemy_id","")),Vector2(101,150),7)
	status = label("",16,Vector2(20,12),Vector2(420,26))
	report = label("",16,Vector2(20,508),Vector2(760,65))
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint = label("",16,Vector2(20,578),Vector2(760,22))
	hover_info = label("",14,Vector2(20,552),Vector2(760,22))
	hover_info.name = "BattleHoverInfo"
	hover_info.z_index = 20
	hover_info.hide()
	command_panel = Control.new()
	command_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(command_panel)
	# StockDispBuffer uses a common anchor plus each bitmap's stored offset.
	# battlemenu.cpp:3757-3765, anim_tbl.h:25000-series classic menu.
	ui_picture(25116,MENU_ANCHOR,command_panel)
	var choices := [["attack",25100,"攻击"],["magic",25102,"镜子的精灵（装备护身符后可用）"],["capture",25104,"捕捉"],["help",25106,"求救（单人模式）"],["defend",25108,"防御"],["item",25110,"道具"],["pet",25112,"宠物"],["escape",25114,"逃跑"]]
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
	for i in range(20):
		var target := Button.new()
		target.name = "AllyPetTarget%d" % (i-16) if i>=16 else "AllyTarget%d" % (i-12) if i>=12 else "PlayerTarget" if i==0 else "PetTarget" if i==2 else "EnemyTarget" if i==1 else "EnemyTarget%d" % (enemy_index(i)+1)
		target.flat = true
		for theme in ["normal","hover","pressed","disabled","focus"]:
			target.add_theme_stylebox_override(theme,StyleBoxEmpty.new())
		target.position = Vector2.ZERO
		target.size = Vector2(80,125)
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		target.focus_mode = Control.FOCUS_NONE
		target.pressed.connect(select_target.bind(i))
		stage.add_child(target)
		target_buttons.append(target)
		var highlight := Panel.new()
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight.z_index = 6
		var outline := StyleBoxFlat.new()
		outline.bg_color = Color.TRANSPARENT
		outline.border_color = Color.GREEN
		outline.set_border_width_all(1)
		highlight.add_theme_stylebox_override("panel",outline)
		highlight.hide()
		stage.add_child(highlight)
		target_highlights.append(highlight)
		actor_labels.append(label("",14,target.position+Vector2(-30,125),Vector2(200,45)))
		var meter := Control.new()
		meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.z_index = 5
		stage.add_child(meter)
		ui_picture(26019 if i==0 else 26020 if i==2 or i>=16 else 26014,Vector2.ZERO,meter)
		var fill := ColorRect.new()
		fill.color = Color(0,1,0)
		fill.position = Vector2(-21,-3 if i==0 else -1)
		fill.size = Vector2(40,2)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.add_child(fill)
		hp_bars.append(meter)
		hp_fills.append(fill)
	riding_hp_bar = Control.new()
	riding_hp_bar.position = Vector2(20,25)
	riding_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bars[0].add_child(riding_hp_bar)
	ui_picture(26020,Vector2.ZERO,riding_hp_bar)
	riding_hp_fill = ColorRect.new()
	riding_hp_fill.color = Color.GREEN
	riding_hp_fill.position = Vector2(-21,-1)
	riding_hp_fill.size = Vector2(40,2)
	riding_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	riding_hp_bar.add_child(riding_hp_fill)
	riding_hp_bar.hide()
	for i in range(4):
		var meter := Control.new()
		meter.position = Vector2(20,25)
		meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_bars[ally_actor(i)].add_child(meter)
		ui_picture(26020,Vector2.ZERO,meter)
		var fill := ColorRect.new()
		fill.color = Color.GREEN
		fill.position = Vector2(-21,-1)
		fill.size = Vector2(40,2)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.add_child(fill)
		meter.hide()
		ally_mount_bars.append(meter)
		ally_mount_fills.append(fill)
	battle_effects = BattleEffects.new()
	stage.add_child(battle_effects)
	battle_effects.setup(manifest)
	battle_effects.externally_driven = true
	result_panel = Control.new()
	result_panel.position = Vector2(240,180)
	result_panel.size = Vector2(320,288)
	result_panel.z_index = 20
	stage.add_child(result_panel)
	for row in range(6):
		for column in range(5):
			var tile := TextureRect.new()
			var y := 0 if row==0 else (2 if row==5 else 1)
			var x := 0 if column==0 else (2 if column==4 else 1)
			tile.texture = load("res://assets/legacy/ui/%d.png" % (26001+y*3+x))
			tile.position = Vector2(column*64,row*48)
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			result_panel.add_child(tile)
	ui_picture(26018,Vector2(160,35),result_panel)
	result_text = label("",16,Vector2(24,70),Vector2(272,162))
	result_text.reparent(result_panel,false)
	result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_panel.hide()
	return_button = Button.new()
	return_button.name = "ReturnFromBattle"
	return_button.text = "继续探索"
	return_button.flat = true
	return_button.position = Vector2(85,246)
	return_button.size = Vector2(150,32)
	return_button.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	return_button.add_theme_font_size_override("font_size",16)
	return_button.add_theme_color_override("font_outline_color",Color.BLACK)
	return_button.add_theme_constant_override("outline_size",2)
	return_button.pressed.connect(func():
		if not is_animating() and not world_modal_open():
			return_requested.emit())
	result_panel.add_child(return_button)
	var auto_button:=Button.new()
	auto_button.text="自动战斗设置";auto_button.position=Vector2(12,90)
	auto_button.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	auto_button.pressed.connect(func():
		if is_instance_valid(world) and not is_animating():world.training_helper.open_battle_menu())
	add_child(auto_button)
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
	var art := sprite_art(ident)
	if art.is_empty():
		return
	var animations: Dictionary = art.animations
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
	actors.append({"character_id":ident,"sprite":sprite,"point":point,"home":point,"motions":[],"animation":animations[key],"animations":animations,"art":art,"facing":facing,"temporary":"","until":0.0,"cues":[],"started":0.0,"last_frame":""})

func layout() -> void:
	if stage == null:
		return
	var factor := minf(size.x/STAGE_SIZE.x,size.y/STAGE_SIZE.y)
	stage.scale = Vector2.ONE*factor
	stage.position = (size-STAGE_SIZE*factor)/2

var hunt_target_index := -1

func mark_hunt_target(index: int) -> void:
	hunt_target_index=index
	if index>=0 and index<enemies_of(state).size():
		var target: Label=actor_labels[enemy_actor(index)]
		target.text="★ 达标 " + str(enemies_of(state)[index].get("name",""))
		target.add_theme_color_override("font_color",Color.YELLOW)

## Battle art a battle needs before it can open: battle sprites, mounted
## composites and the background, which is chosen now and reused when opening.
func required_art(next_state: Dictionary) -> Dictionary:
	# open_battle() also builds placeholder actors (an empty pet slot) with 100250.
	var sprites := {"100250":true}
	var riding := {}
	if is_instance_valid(world):
		var ident := str(world.player.character_id)
		sprites[ident] = true
		sprites[str(manifest.get("equipment_variants",{}).get("club",{}).get(ident,ident))] = true
	if int(next_state.get("mounted_sprite",-1)) >= 0:riding[str(next_state.mounted_sprite)] = true
	sprites[str(next_state.get("enemy_sprite",SPECIES_ART.get(str(next_state.get("enemy_species","wooli")),"100250")))] = true
	for actor in enemies_of(next_state)+next_state.get("pets",[])+next_state.get("ally_pets",[])+[next_state.get("pet",{})]:
		if actor is Dictionary and actor.has("sprite"):sprites[str(actor.sprite)] = true
	for ally in next_state.get("allies",[]):
		sprites[ally_art(ally,false)] = true
		if int(ally.get("mounted_sprite",-1)) >= 0:riding[str(ally.mounted_sprite)] = true
	var files: Array = []
	if is_instance_valid(world) and is_instance_valid(battlefield):
		if next_background.is_empty():next_background = background_selector.choose(_ground_bitmap())
		files.append(next_background)
	return {"sprites":sprites.keys(),"riding":riding.keys(),"files":files}

func _ground_bitmap() -> String:
	return world.terrain.ident_at(int(world.cell.y)*int(world.data.width)+int(world.cell.x))

func open_battle(next_state: Dictionary) -> void:
	hunt_target_index=-1
	capture_transition()
	if is_instance_valid(battlefield) and is_instance_valid(world):
		battlefield.texture = load(next_background if not next_background.is_empty() else background_selector.choose(_ground_bitmap()))
		PerfRegistry.track_texture("battle",battlefield.texture.resource_path if battlefield.texture!=null else "",battlefield.texture)
		next_background = ""
	elapsed = 0.0
	state = {}
	starting_profile = world.session.snapshot() if is_instance_valid(world) and world.get("session")!=null else {}
	result_sound_played = false
	result_level_up = false
	battle_effects.reset()
	result_panel.hide()
	last_player_command = "attack"
	defeat_return_queued = false
	for effect in mirror_effects:
		if is_instance_valid(effect): effect.queue_free()
	mirror_effects.clear()
	mirror_cues.clear()
	hp_cues.clear()
	riding_art_cues.clear()
	word_cues.clear()
	music_cues.clear()
	sound_cues.clear()
	feedback_until = 0.0
	if actors.size() > 0:
		var ident: String = str(world.player.character_id) if is_instance_valid(world) else unmounted_player_art
		if is_instance_valid(world) and world.get("session")!=null and bool(world.session.snapshot().get("equipped",false)):
			ident = str(manifest.get("equipment_variants",{}).get("club",{}).get(ident,ident))
		unmounted_player_art = ident
		var mounted := int(next_state.get("mounted_sprite",-1))
		if mounted >= 0 and ensure_riding_art(str(mounted)): ident = str(mounted)
		var art := sprite_art(ident)
		if not art.is_empty():
			actors[0]["character_id"] = ident
			actors[0].art = art
			actors[0].animations = art.animations
			actors[0].animation = art.animations["3_%d" % int(actors[0].facing)]
	update_riding_health(next_state)
	update_ally_mount_health(next_state)
	var enemy_art := str(next_state.get("enemy_sprite",SPECIES_ART.get(str(next_state.get("enemy_species","wooli")),"100250")))
	set_actor_art(1,enemy_art)
	for old_index in range(2,actors.size()): actors[old_index].sprite.queue_free()
	actors.resize(2)
	var pet: Dictionary = next_state.get("pet",{})
	var pet_key := str(pet.get("species",""))+":"+str(pet.get("name",""))
	if pet_key!=remembered_pet:
		last_pet_command = ""
		remembered_pet = pet_key
	# Keep the pet slot stable while changing companions, even when withdrawn.
	add_actor(str(pet.get("sprite",100250)),Vector2(581,432),3)
	actors[2]["enabled"] = not pet.is_empty()
	actors[2]["maximum"] = int(next_state.get("pet_max_hp",pet.get("max_hp",1)))
	var opponents := enemies_of(next_state)
	for i in range(opponents.size()):
		var point: Vector2 = enemy_home(i)
		if i>0: add_actor(str(opponents[i].get("sprite",100250)),point,7)
		else:
			actors[1].home = point
			set_actor_art(1,str(opponents[0].get("sprite",enemy_art)))
	var allies: Array = next_state.get("allies",[])
	if not allies.is_empty():
		# Preserve enemy actor0..9 mapping and the pet slot even for small troops.
		while actors.size()<12:
			add_actor(unmounted_player_art,Vector2.ZERO,3)
			actors[-1]["enabled"]=false
		for i in range(mini(4,allies.size())):
			add_actor(ally_art(allies[i]),ally_home(i),3)
	var ally_pets: Array = next_state.get("ally_pets",[])
	if not allies.is_empty() and ally_pets.any(func(p): return not p.is_empty()):
		while actors.size()<16:
			add_actor(unmounted_player_art,Vector2.ZERO,3)
			actors[-1]["enabled"]=false
		for i in range(4):
			var companion: Dictionary = ally_pets[i] if i<ally_pets.size() else {}
			add_actor(str(companion.get("sprite",100250)),ally_pet_home(i),3)
			actors[-1]["enabled"]=not companion.is_empty()
	player_target = 0
	pet_target = 0
	switch_pet_index = -2
	pet_art_cues.clear()
	for i in range(actor_labels.size()):
		actor_labels[i].hide()
		target_buttons[i].hide()
		target_highlights[i].hide()
	for actor in actors:
		actor.temporary = ""
		actor.cues = []
	show_state(next_state)
	for i in range(actors.size()):
		var actor: Dictionary = actors[i]
		actor.point = actor.home
		actor.hide_at = INF
		actor.spin_start = INF
		actor.spin_end = -INF
		actor.rate = 1.0
		actor.point = actor.home+Vector2(-300,-300) if enemy_index(i)>=0 else actor.home+Vector2(300,300)
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
	var art := sprite_art(ident)
	if index >= actors.size() or art.is_empty(): return
	actors[index]["character_id"] = ident
	if index==0 and not Riding.has_composite(ident):unmounted_player_art=ident
	actors[index].art = art
	actors[index].animations = art.animations
	var key := "3_%d" % int(actors[index].facing)
	if art.animations.has(key): actors[index].animation = art.animations[key]

func close_battle() -> void:
	hide()

func show_state(next_state: Dictionary) -> void:
	var previous := state
	state = next_state.duplicate(true)
	if previous.is_empty():
		for i in range(displayed_hp.size()): displayed_hp[i] = health_of(state,i)
	if actors.size() >= 2 and not previous.is_empty() and int(state.get("turn",0)) != int(previous.get("turn",0)):
		# The command the backend resolved: an automated capture (自动抓宠,
		# 后台搜宠) or another device's choice animates like this device's own.
		if state.has("last_player_command"):pending_action = str(state.last_player_command)
		queue_turn_animation(previous)
	pending_action = ""
	if not built:
		return
	selected_action = ""
	queued_player_action = ""
	command_phase = "player"
	clear_choices()
	status.text = "第 %d 回合" % (int(state.get("turn",0))+1)
	actor_labels[0].text = "你"+(" LV%d" % int(state.player_level) if state.has("player_level") else "")
	actor_labels[1].text = str(state.get("enemy_name",manifest.get("enemy_name","乌力")))+(" LV%d" % int(state.enemy_level) if state.has("enemy_level") else "")
	var pet: Dictionary = state.get("pet",{})
	actor_labels[2].text = "" if pet.is_empty() else str(pet.get("name","宠物"))+(" LV%d" % int(pet.level) if pet.has("level") else "")
	for i in range(actor_labels.size()):
		actor_labels[i].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		actor_labels[i].add_theme_color_override("font_color",Color.WHITE if enemy_index(i)>=0 else Color.YELLOW)
	for i in range(enemies_of(state).size()):
		actor_labels[enemy_actor(i)].text = str(enemies_of(state)[i].get("name","乌力"))
	for i in range(mini(4,state.get("allies",[]).size())):
		actor_labels[ally_actor(i)].text=str(state.allies[i].get("name","伙伴"))
	for i in range(mini(4,state.get("ally_pets",[]).size())):
		actor_labels[ally_pet_actor(i)].text="分身%d · %s" % [i+1,state.ally_pets[i].get("name","宠物")]
	mark_hunt_target(hunt_target_index)
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
	update_result_text()
	if bool(state.get("active",false)):
		selected_action = last_player_command if last_player_command=="attack" or (last_player_command=="capture" and not bool(state.get("boss",false)) and bool(state.get("can_capture",true))) else "attack"
		hint.text = "攻击：请选择敌人；右键 / Esc 取消。" if selected_action=="attack" else "捕捉：请选择敌人；右键 / Esc 取消。"

func update_result_text() -> void:
	var outcome := str(state.get("outcome",""))
	if outcome.is_empty(): return
	var lines := PackedStringArray()
	var profile: Dictionary = world.session.snapshot() if is_instance_valid(world) and world.get("session")!=null else {}
	result_level_up = false
	if outcome=="win" or (outcome=="captured" and int(state.get("xp",0))>0):
		lines.append("战斗胜利！" if outcome=="win" else "捕捉成功，战斗结束！")
		lines.append("获得经验值  %d" % int(state.get("xp",0)))
		lines.append("获得石币  %d" % int(state.get("gold",0)))
		var summary: Array = state.get("result_summary",[])
		if not summary.is_empty():
			for participant in summary:
				var leveled := bool(participant.get("level_up",false))
				result_level_up = result_level_up or leveled
				lines.append("%s  经验 +%d%s" % [str(participant.get("name","伙伴")),int(participant.get("xp",0)),"  LvUp!" if leveled else ""])
		else:
			var before: Dictionary = starting_profile.get("player",{})
			var after: Dictionary = profile.get("player",{})
			if not after.is_empty():
				var leveled := int(after.get("level",1))>int(before.get("level",1))
				result_level_up = leveled
				lines.append("你  Lv.%d%s" % [int(after.get("level",1)),"  LvUp!" if leveled else ""])
			var index := int(profile.get("active_pet",-1))
			var pets: Array = profile.get("pets",[])
			var previous_pets: Array = starting_profile.get("pets",[])
			if index>=0 and index<pets.size():
				var pet: Dictionary = pets[index]
				var old_level := int(previous_pets[index].get("level",1)) if index<previous_pets.size() else int(pet.get("level",1))
				var leveled := int(pet.get("level",1))>old_level
				result_level_up = result_level_up or leveled
				lines.append("%s  经验 +%d\nLv.%d%s" % [str(pet.get("name","宠物")),int(state.get("xp",0)),int(pet.get("level",1)),"  LvUp!" if leveled else ""])
	elif outcome=="captured": lines.append("捕捉成功！\n%s成为了新的伙伴。" % str(state.get("enemy_name","宠物")))
	elif outcome=="escaped": lines.append("成功逃离战斗。")
	else: lines.append("返回村庄恢复体力。")
	result_text.text = "\n".join(lines)

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
	var facing := 7 if enemy_index(index)>=0 else 3
	var clip: Dictionary = actor.animations.get("0_%d" % facing,{})
	var strike := clampf(float(clip.get("duration_ms",600))/1000.0,0.35,1.2)
	var hit_fraction := 0.5
	var hit_frame := SpriteArt.hit_frame(clip)
	if hit_frame>=0:hit_fraction = float(hit_frame)/SpriteArt.frame_count(clip)
	queue_motion(index,home,contact,at,travel,facing)
	queue_pose(index,4,at,travel)
	actors[index].cues.append({"at":at+travel,"action":0,"seconds":strike,"facing":facing})
	queue_motion(index,contact,home,at+travel+strike,travel,(facing+4)%8)
	actors[index].cues.append({"at":at+travel+strike,"action":4,"seconds":travel,"facing":(facing+4)%8})
	actors[index].cues.append({"at":at+travel*2+strike,"action":3,"seconds":0.01,"facing":int(actor.facing)})
	return {"hit":at+travel+strike*hit_fraction,"end":at+travel*2+strike}

# oft.cpp states35–46: contact, hit-marker capture, 60-tick pause,
# slow return with a spinning follower, then anger/break-away or happy255.
## Capture animations queued so far (tests check automated captures play one).
var captures_presented := 0

func queue_capture(at: float, success: bool, target: int = 1) -> Dictionary:
	captures_presented += 1
	var home: Vector2 = actors[0].home
	var enemy: Vector2 = actors[target].home
	var contact := enemy+(home-enemy).normalized()*64.0
	var travel := home.distance_to(contact)/480.0
	var clip: Dictionary = actors[0].animations["0_3"]
	var strike := float(clip.duration_ms)/1000.0
	var hit := at+travel+strike*0.5
	var hit_frame := SpriteArt.hit_frame(clip)
	if hit_frame>=0:hit = at+travel+strike*float(hit_frame)/SpriteArt.frame_count(clip)
	queue_motion(0,home,contact,at,travel,3)
	actors[0].cues.append({"at":at,"action":4,"seconds":travel,"facing":3})
	actors[0].cues.append({"at":at+travel,"action":0,"seconds":strike,"facing":3})
	var retreat := at+travel+strike+1.0
	var duration := contact.distance_to(home)/120.0
	var arrival := retreat+duration
	queue_motion(0,contact,home,retreat,duration,7)
	actors[0].cues.append({"at":retreat,"action":4,"seconds":duration,"facing":7})
	var follower := enemy+(home-contact)
	queue_motion(target,enemy,follower,retreat,duration,7)
	actors[target].spin_start = hit
	actors[target].spin_end = arrival+(4.25 if success else 0.0)
	word_cues.append({"at":hit,"index":0,"id":26512})
	var impact := impact_sound(0)
	if impact >= 0: sound_cues.append({"at":hit,"id":impact})
	word_cues.append({"at":arrival,"index":0,"id":26506 if success else 26505})
	var end := arrival+(4.25 if success else 100.0/60.0)
	actors[0].cues.append({"at":arrival,"action":7 if success else 8,"seconds":end-arrival,"facing":3})
	if success:
		actors[target].hide_at = end
		music_cues.append({"at":arrival,"celebrate":true})
		music_cues.append({"at":end,"celebrate":false})
	else:
		var back := follower.distance_to(enemy)/240.0
		queue_motion(target,follower,enemy,arrival,back,3)
		actors[target].cues.append({"at":arrival,"action":4,"seconds":back,"facing":3})
		end = maxf(end,arrival+back)
	return {"hit":hit,"end":end}

# oft.cpp52/53/54: 11 eight-tick gait stages accelerating, then
# either state50 off-screen retreat or deceleration and SAD for60ticks.
func queue_escape(at: float, success: bool, health: Dictionary) -> Dictionary:
	word_cues.append({"at":at,"index":0,"id":26511})
	var tick := 8.0/60.0
	var phase := 0.0
	for i in range(11):
		actors[0].cues.append({"at":at+i*tick,"action":4,"seconds":tick,"facing":7,"rate":12.0/(12-i),"phase":phase})
		phase += tick*12.0/(12-i)
	var end := at+11*tick
	if success:
		for index in [0,2,12,13,14,15,16,17,18,19]:
			if index>=actors.size() or health_of(health,index)<=0: continue
			var origin: Vector2 = actors[index].home
			var destination := origin+Vector2(960-origin.x,(960-origin.x)*0.75)
			var duration := origin.distance_to(destination)/240.0
			queue_motion(index,origin,destination,end,duration,7)
			actors[index].cues.append({"at":end,"action":4,"seconds":duration,"facing":7})
			actors[index].hide_at = end+duration
			# All living allies finish before exploration/result controls become available.
		end = maxf(float(actors[0].hide_at),float(actors[2].get("hide_at",end)) if actors.size()>2 and int(health.get("pet_hp",0))>0 else end)
		for index in range(12,actors.size()):
			if health_of(health,index)>0:end=maxf(end,float(actors[index].hide_at))
	else:
		for i in range(11):
			actors[0].cues.append({"at":end+i*tick,"action":4,"seconds":tick,"facing":7,"rate":12.0/(i+1),"phase":phase})
			phase += tick*12.0/(i+1)
		end += 11*tick
		word_cues.append({"at":end,"index":0,"id":26505})
		actors[0].cues.append({"at":end,"action":9,"seconds":1.0,"facing":7})
		end += 1.0
	return {"hit":at,"end":end}

func queue_turn_animation(previous: Dictionary) -> void:
	if state.has("enemies"):
		queue_group_turn(previous)
		return
	hp_cues.clear()
	riding_art_cues.clear()
	word_cues.clear()
	music_cues.clear()
	sound_cues.clear()
	for actor in actors:
		actor.cues = []
		actor.motions = []
		actor.point = actor.home
		actor.hide_at = INF
		actor.spin_start = INF
		actor.spin_end = -INF
		actor.rate = 1.0
	var fallback: Array = ["player"]
	if actors.size()>2: fallback.append("pet")
	if int(state.get("enemy_hp",0))>0: fallback.append("enemy")
	var order: Array = state.get("turn_order",fallback)
	var pet_command := str(state.get("last_pet_command",state.get("pet_command","attack")))
	var at := elapsed
	var turn_frames: Array = state.get("turn_frames",[])
	for step in range(order.size()):
		var who := str(order[step])
		var before_step: Dictionary = turn_frames[step-1] if step>0 and step-1<turn_frames.size() else previous
		var after_step: Dictionary = turn_frames[step] if step<turn_frames.size() else state
		var index: int = {"player":0,"enemy":1,"pet":2}.get(who,0)
		if index>=actors.size(): continue
		var attack := who=="enemy" or (who=="player" and pending_action=="attack") or (who=="pet" and pet_command!="defend")
		var target := 1 if who!="enemy" else (2 if actors.size()>2 and (str(after_step.get("enemy_target",""))=="pet" or int(after_step.get("pet_hp",0))<int(before_step.get("pet_hp",0))) else 0)
		var timing := {"hit":at+0.25,"end":at+0.5}
		if who=="player" and pending_action=="capture":
			timing = queue_capture(at,str(state.get("outcome",""))=="captured")
		elif who=="player" and pending_action=="escape":
			timing = queue_escape(at,str(state.get("outcome",""))=="escaped",before_step)
		elif attack:
			timing = queue_strike(index,target,at)
		else:
			queue_pose(index,10,at,0.5)
		if who=="enemy":
			for recipient in [[0,"player_hp"],[2,"pet_hp"]]:
				var hp_key: String = recipient[1]
				if int(after_step.get(hp_key,0)) < int(before_step.get(hp_key,0)):
					var defeated := int(after_step.get(hp_key,0))<=0
					queue_pose(int(recipient[0]),2 if defeated else (10 if (int(recipient[0])==0 and pending_action=="defend") or (int(recipient[0])==2 and pet_command=="defend") else 1),float(timing.hit),60.0 if defeated else 0.35)
		elif attack and int(after_step.get("enemy_hp",0)) < int(before_step.get("enemy_hp",0)):
			var defeated := int(after_step.get("enemy_hp",0))<=0 and step==order.size()-1
			queue_pose(1,2 if defeated else 1,float(timing.hit),60.0 if defeated else 0.35)
		if (who=="player" and pending_action=="defend") or (who=="pet" and pet_command=="defend"):
			word_cues.append({"at":at,"index":index,"id":26510})
		if step<turn_frames.size():
			var health: Dictionary = turn_frames[step]
			for recipient in range(3):
				var key: String = ["player_hp","enemy_hp","pet_hp"][recipient]
				if health.has(key): hp_cues.append({"at":float(timing.hit),"index":recipient,"hp":int(health[key]),"guarded":(recipient==0 and pending_action=="defend") or (recipient==2 and pet_command=="defend")})
		else:
			var recipients: Array = [target] if attack else []
			if who=="player" and pending_action=="item": recipients = [0]
			for recipient in recipients:
				for old in hp_cues.duplicate():
					if int(old.index)==int(recipient): hp_cues.erase(old)
				var key: String = ["player_hp","enemy_hp","pet_hp"][recipient]
				hp_cues.append({"at":float(timing.hit),"index":recipient,"hp":int(state.get(key,0)),"guarded":(int(recipient)==0 and pending_action=="defend") or (int(recipient)==2 and pet_command=="defend")})
		at = float(timing.end)+0.08
	hp_cues.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.at)<float(b.at))
	menu_slide_at = at
	feedback_until = at+(MENU_SLIDE_SECONDS if bool(state.get("active",false)) else 0.0)
	if not bool(state.get("active",false)) and not hp_cues.is_empty():
		feedback_until = maxf(feedback_until,float(hp_cues.back().at)+85.0/60.0)
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
	choice_panel.position.x = 0
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
	if world_modal_open(): return
	if not bool(state.get("active",false)) or elapsed < feedback_until: return
	if action == "help": return
	if action == "magic" and not (bool(state.get("mirror_available",false)) or bool(state.get("healing_available",false))): return
	if action=="capture" and (bool(state.get("boss",false)) or not bool(state.get("can_capture",true))): return
	sound_requested.emit(217)
	clear_choices()
	selected_action = action
	last_player_command = action if action in ["attack","capture"] else "attack"
	if action == "magic":
		var mirror_choice:=choice("镜子的精灵 → 自己",Vector2(500,220),func(): complete_player_command("mirror_self"))
		mirror_choice.disabled=not bool(state.get("mirror_available",false))
		var pet_choice := choice("镜子的精灵 → 出战宠物",Vector2(500,265),func(): complete_player_command("mirror_pet"))
		pet_choice.disabled = not bool(state.get("mirror_available",false)) or int(state.get("pet_hp",0))<=0
		var healing_choice:=choice("恢复护符 → 出战宠物",Vector2(500,310),func(): complete_player_command("heal_pet"))
		healing_choice.disabled=not bool(state.get("healing_available",false)) or int(state.get("pet_hp",0))<=0 or int(state.get("pet_hp",0))>=int(state.get("pet_max_hp",0))
		hint.text = "反射一次直接物理攻击；暂不计算气力。"
	elif action == "item":
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
		show_pet_roster(0)
	elif action in ["attack","capture"]:
		hint.text = "请选择敌人；右键 / Esc 取消。"
	else:
		complete_player_command(action)

func select_target(index: int) -> void:
	if world_modal_open(): return
	if elapsed < feedback_until or not bool(state.get("active",false)): return
	if command_phase == "pet" and enemy_index(index)>=0 and health_of(state,index)>0 and selected_action in ["pet_attack","pet_skill"]:
		pet_target = enemy_index(index)
		finish_pet_command(selected_action.trim_prefix("pet_"))
	elif enemy_index(index)>=0 and health_of(state,index)>0 and selected_action in ["attack","capture"]:
		player_target = enemy_index(index)
		complete_player_command(selected_action)
	elif index == 0 and selected_action == "item_target":
		complete_player_command("item")

## Every command the original sends plays SE 203 (battlemenu.cpp
## BattleTargetSelect:3207, BattleButtonGuard:1253, pet skills:2715): once
## for the character's command here and once for the pet's in
## finish_pet_command, the two confirmation beeps of a turn.
func complete_player_command(action: String) -> void:
	sound_requested.emit(203)
	queued_player_action = action
	selected_action = ""
	var pet: Dictionary = state.get("pet",{})
	if not pet.is_empty() and int(state.get("pet_hp",pet.get("hp",0))) > 0 and action not in ["escape","switch"]:
		command_phase = "pet"
		command_panel.hide()
		var remembered := last_pet_command if not last_pet_command.is_empty() else "attack"
		if remembered=="skill" and selected_pet_skill not in pet.get("learned_skills",[]): remembered = "attack"
		selected_action = "pet_"+remembered
		show_pet_choices()
		pet_slide_at = elapsed
		feedback_until = elapsed+MENU_SLIDE_SECONDS
		choice_panel.position.x = 300
	else:
		submit_command()

func show_pet_choices() -> void:
	clear_choices()
	ui_picture(25140,PET_MENU_ANCHOR,choice_panel)
	ui_picture(25141,PET_MENU_ANCHOR,choice_panel)
	var pet_title := label(str(state.get("pet_name",state.get("pet",{}).get("name","宠物"))),16,PET_MENU_ANCHOR+Vector2(-96,-14),Vector2(192,28))
	pet_title.reparent(choice_panel)
	ui_picture(26130,Vector2(650,300),choice_panel)
	var actions := [["攻击","attack"],["技能","skill"],["防御","defend"],["待机","standby"]]
	for i in range(actions.size()):
		var action: String = actions[i][1]
		var button := choice(str(actions[i][0]),Vector2(540,170+i*38),func():
			if is_animating() or world_modal_open(): return
			sound_requested.emit(217)
			if action in ["defend","standby"]: finish_pet_command(action)
			elif action == "skill" and state.get("pet",{}).has("learned_skills"): show_learned_skills()
			else:
				selected_action = "pet_"+action
				for candidate in choice_panel.get_children():
					if candidate is Button: candidate.set_pressed_no_signal(str(candidate.get_meta("pet_action",""))==action)
				hint.text = "宠物：请选择敌人，或点击其他指令；右键 / Esc 取消。")
		button.set_meta("pet_action",action)
		button.toggle_mode = action not in ["defend","standby"]
		button.set_pressed_no_signal(selected_action=="pet_"+action)
		if action=="skill" and (state.get("pet",{}).get("learned_skills",[]).is_empty() if state.get("pet",{}).has("learned_skills") else (not bool(state.get("skill_unlocked",false)) or bool(state.get("skill_used",false)))):
			button.disabled = true
			button.text = "技能（尚未学习）"
	hint.text = "宠物：请选择敌人，或点击其他指令；右键 / Esc 取消。" if selected_action.begins_with("pet_") else "请选择宠物指令；右键 / Esc 返回人物指令。"

func finish_pet_command(command: String) -> void:
	sound_requested.emit(203)
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

func nothing_to_cancel() -> bool:
	return not bool(state.get("active",false)) or (command_phase=="player" and selected_action.is_empty() and queued_player_action.is_empty())

func world_modal_open() -> bool:
	if not is_instance_valid(world): return false
	# Windows opened over the battle (宠物, 设置, 电台, 宠物大全…): commands wait.
	if world.has_method("battle_window_open"): return world.battle_window_open()
	var panel = world.get("adventure_menu")
	var helper = world.get("training_helper")
	if is_instance_valid(helper) and helper.visible:return true
	var gm_panel = world.get("dev_gm_menu")
	var settings = world.get("settings_menu")
	if is_instance_valid(settings) and settings.visible:return true
	return (is_instance_valid(panel) and panel.visible) or (is_instance_valid(gm_panel) and gm_panel.visible)

func _input(event: InputEvent) -> void:
	if not visible or world_modal_open(): return
	if event.is_action_pressed("ui_accept") and is_animating():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		# With no command to back out of (an automatic battle, or the top
		# menu) Esc goes on to open 设置 like on the field (game_input.gd).
		if event.is_action_pressed("ui_cancel") and nothing_to_cancel(): return
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
	# Tick through every legacy frame even at 8x so short effects and frame SFX
	# are not skipped. Effects share this clock instead of a separate process delta.
	var remaining := maxf(0.0,delta)*playback_speed
	if remaining == 0.0:
		_advance_playback(0.0)
		return
	while remaining > 0.0:
		var step := minf(remaining,1.0/60.0)
		_advance_playback(step)
		remaining -= step

func _advance_playback(delta: float) -> void:
	elapsed += delta
	while not mirror_cues.is_empty() and elapsed>=float(mirror_cues[0].at):
		var cue: Dictionary = mirror_cues.pop_front()
		var effect = preload("res://scripts/mirror_effect.gd").new()
		stage.add_child(effect)
		effect.setup(int(cue.id),actors[int(cue.index)].point)
		mirror_effects.append(effect)
	for i in range(mirror_effects.size()-1,-1,-1):
		if not is_instance_valid(mirror_effects[i]): mirror_effects.remove_at(i)
		else: mirror_effects[i].advance(delta)
	battle_effects.advance(delta)
	for tile in transition_tiles:
		var frames := maxf(0.0,(elapsed-float(tile.release))*60.0)
		tile.node.position = tile.origin+Vector2(0,frames*(frames+1.0)*0.5*size.y/600.0)
	if elapsed>=TRANSITION_SECONDS and not transition_tiles.is_empty():
		for tile in transition_tiles: tile.node.queue_free()
		transition_tiles.clear()
	while not sound_cues.is_empty() and elapsed>=float(sound_cues[0].at):
		sound_requested.emit(int(sound_cues.pop_front().id))
	while not music_cues.is_empty() and elapsed>=float(music_cues[0].at):
		capture_music_requested.emit(bool(music_cues.pop_front().celebrate))
	while not word_cues.is_empty() and elapsed>=float(word_cues[0].at):
		var word: Dictionary = word_cues.pop_front()
		if int(word.index)<actors.size(): battle_effects.word(actors[int(word.index)].point,int(word.id))
	while not pet_art_cues.is_empty() and elapsed>=float(pet_art_cues[0].at):
		var cue: Dictionary = pet_art_cues.pop_front()
		var companion: Dictionary = cue.pet
		actors[2].enabled = not companion.is_empty()
		actors[2].maximum = int(companion.get("max_hp",1))
		actors[2].hide_at = INF if not companion.is_empty() else elapsed
		actors[2].temporary = ""
		actors[2].until = 0.0
		set_actor_art(2,str(companion.get("sprite",100250)))
		displayed_hp[2] = int(companion.get("hp",0))
		actor_labels[2].text = str(companion.get("name",""))
	while not riding_art_cues.is_empty() and elapsed >= float(riding_art_cues[0].at):
		var ride_cue: Dictionary = riding_art_cues.pop_front()
		if not str(ride_cue.get("art","")).is_empty(): set_actor_art(int(ride_cue.get("index",0)),str(ride_cue.art))
		if ride_cue.has("health"): update_riding_health(ride_cue.health)
		if ride_cue.has("ally_health"): update_ally_mount_health(ride_cue.ally_health)
	while not hp_cues.is_empty() and elapsed>=float(hp_cues[0].at):
		var cue: Dictionary = hp_cues.pop_front()
		var recipient := int(cue.index)
		var difference := displayed_hp[recipient]-int(cue.hp)
		if recipient<actors.size():
			var point: Vector2 = actors[recipient].point
			if difference>0: battle_effects.impact(point,difference,bool(cue.get("guarded",false)),bool(cue.get("critical",false)),int(cue.hp)<=0)
			elif difference<0: battle_effects.heal(point,-difference)
		displayed_hp[recipient] = int(cue.hp)
	hint.visible = not is_animating()
	var finished := not str(state.get("outcome","")).is_empty() and not is_animating()
	result_panel.visible = finished and (str(state.get("outcome",""))!="defeat" or not is_instance_valid(world))
	if result_panel.visible and not result_sound_played:
		result_sound_played = true
		sound_requested.emit(211 if result_level_up else 202)
	return_button.disabled = is_animating()
	if str(state.get("outcome",""))=="defeat" and not is_animating() and not defeat_return_queued and is_instance_valid(world):
		defeat_return_queued = true
		world.call_deferred("return_from_battle")
	if bool(state.get("active",false)) and command_phase=="player":
		command_panel.visible = elapsed>=menu_slide_at
		var slide := clampf((elapsed-menu_slide_at)/MENU_SLIDE_SECONDS,0.0,1.0)
		command_panel.position.x = 300.0*pow(1.0-slide,2)
	if command_phase=="pet" and choice_panel.get_child_count()>0:
		var progress := clampf((elapsed-pet_slide_at)/MENU_SLIDE_SECONDS,0.0,1.0)
		choice_panel.position.x = 300.0*pow(1.0-progress,2)
	for button in commands:
		button.disabled = not bool(state.get("active",false)) or elapsed < feedback_until or (str(button.get_meta("action","")) == "help" or (str(button.get_meta("action","")) == "magic" and not (bool(state.get("mirror_available",false)) or bool(state.get("healing_available",false)))))
		if str(button.get_meta("action",""))=="capture":
			var unavailable := bool(state.get("boss",false)) or not bool(state.get("can_capture",true))
			button.disabled = button.disabled or unavailable
			button.tooltip_text = "此战对手无法捕捉" if bool(state.get("boss",false)) else ("宠物栏已满" if not bool(state.get("can_capture",true)) else "捕捉")
		button.texture_normal = load(ART_ROOT+"ui/%d.png" % (25100+commands.find(button)*2+(1 if selected_action==str(button.get_meta("action","")) else 0)))
		button.texture_hover = button.texture_normal
	for i in range(actors.size(),hp_bars.size()): hp_bars[i].hide()
	for actor_index in range(actors.size()):
		var actor: Dictionary = actors[actor_index]
		var cues: Array = actor.cues
		while not cues.is_empty() and elapsed >= float(cues[0].at):
			var cue: Dictionary = cues.pop_front()
			animate_actor(actor_index,int(cue.action),float(cue.seconds),int(cue.get("facing",-1)))
			actor.rate = float(cue.get("rate",1.0))
			actor.phase = float(cue.get("phase",0.0))
			actor.started = float(cue.at)
			actor.until = float(cue.at)+float(cue.seconds)
		var motions: Array = actor.get("motions",[])
		while not motions.is_empty() and elapsed>=float(motions[0].at):
			var motion: Dictionary = motions[0]
			var amount := clampf((elapsed-float(motion.at))/(float(motion.end)-float(motion.at)),0.0,1.0)
			actor.point = Vector2(motion.from).lerp(Vector2(motion.to),amount)
			if amount<1.0: break
			motions.pop_front()
		var shown := bool(actor.get("enabled",true)) and elapsed<float(actor.get("hide_at",INF))
		actor.sprite.visible = shown
		actor_labels[actor_index].visible = shown
		if actor_index<hp_bars.size():
			var maximum := maxi(1,int(actor.get("maximum",1)) if actor_index==2 else health_of(state,actor_index,true))
			# Original battlemenu.cpp HpMeterDisp: every actor uses y-80,
			# including small pets. The PET label is baked into frame26020.
			hp_bars[actor_index].position = actor.point+Vector2(0,-80)
			hp_bars[actor_index].visible = shown and displayed_hp[actor_index]>0
			hp_fills[actor_index].size.x = int(clampf(float(displayed_hp[actor_index])/maximum,0,1)*40.0)
		if actor_index<actor_labels.size():
			actor_labels[actor_index].position = actor.point+Vector2(-100,-10)
		var animation: Dictionary = actor.animation
		if elapsed < float(actor.until) and not str(actor.temporary).is_empty():
			animation = actor.animations[actor.temporary]
		if elapsed>=float(actor.get("spin_start",INF)) and elapsed<float(actor.get("spin_end",-INF)):
			animation = actor.animations.get("1_%d" % (int(elapsed*60)%8),animation)
		var resting_dead := displayed_hp[actor_index]<=0 and elapsed>=float(actor.until)
		if resting_dead: animation = actor.animations.get("2_%d" % int(actor.facing),animation)
		var count := SpriteArt.frame_count(animation)
		if count==0:
			continue
		var duration := maxf(float(animation.duration_ms)/1000.0,0.1)
		var index := int(fmod(elapsed,duration)/duration*count)%count
		var temporary := elapsed < float(actor.until) and not str(actor.temporary).is_empty()
		if temporary:
			index = int(fmod((elapsed-float(actor.started))*float(actor.get("rate",1.0))+float(actor.get("phase",0.0)),duration)/duration*count) if int(str(actor.temporary).get_slice("_",0)) in [4,7,8] else mini(int((elapsed-float(actor.started))/duration*count),count-1)
		if elapsed>=float(actor.get("spin_start",INF)) and elapsed<float(actor.get("spin_end",-INF)):
			index = int(fmod(elapsed,duration)/duration*count)
		if resting_dead: index = count-1
		var frame_key := str(actor.temporary)+"_"+str(index) if temporary else "idle_"+str(index)
		if frame_key != str(actor.last_frame):
			actor.last_frame = frame_key
			var sound_id := SpriteArt.sound(animation,index)
			if temporary and frame_sounds.has(str(sound_id)):
				sound_requested.emit(sound_id)
		var art: Dictionary = actor.art
		var sprite: Sprite2D = actor.sprite
		sprite.texture = SpriteArt.texture(art,SpriteArt.image(animation,index))
		if sprite.texture==null: continue
		sprite.z_index = clampi(int(actor.point.y),0,599)-600
		sprite.position = actor.point+SpriteArt.offset(art,animation,index)
		var target: Button = target_buttons[actor_index]
		target.visible = shown
		target.position = sprite.position
		target.size = sprite.texture.get_size()
		var eligible := shown and not is_animating() and not world_modal_open() and bool(state.get("active",false)) and ((enemy_index(actor_index)>=0 and displayed_hp[actor_index]>0 and selected_action in ["attack","capture","pet_attack","pet_skill"]) or (actor_index==0 and selected_action=="item_target"))
		target.disabled = not eligible
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if eligible else Control.CURSOR_ARROW
		var highlight: Panel = target_highlights[actor_index]
		highlight.position = target.position-Vector2(2,2)
		highlight.size = target.size+Vector2(4,4)
		highlight.visible = eligible and target.get_rect().has_point(stage.get_local_mouse_position())
		var phase := int(elapsed*60.0)%60
		var outline: StyleBoxFlat = highlight.get_theme_stylebox("panel")
		outline.border_color = Color.GREEN if phase<45 else (Color(0,0.5,0) if phase>=50 and phase<55 else Color.WHITE)

	update_hover_info(stage.get_local_mouse_position())

func hover_actor_text(index: int) -> String:
	var actor_name := actor_labels[index].text
	var maximum := int(actors[index].get("maximum",1)) if index==2 else health_of(state,index,true)
	var level := int(state.get("player_level",0)) if index==0 else 0
	if index==2: level=int(state.get("pet",{}).get("level",0))
	elif index>=16: level=int(state.get("ally_pets",[])[index-16].get("level",0))
	elif index>=12: level=int(state.get("allies",[])[index-12].get("level",0))
	elif enemy_index(index)>=0: level=int(enemies_of(state)[enemy_index(index)].get("level",state.get("enemy_level",0)))
	var text := "%s%s  体力 %d/%d" % [actor_name,"  Lv.%d" % level if level>0 else "",maxi(0,displayed_hp[index]),maximum]
	var elements := hover_elements(index)
	if elements.size()==4:text += "  属性 %s" % Elements.text(elements)
	# mouse.cpp:690-746 exposes friendly HP; enemy HP is _STONDEBUG_ only
	# at797-818. Exposing it here is an intentional single-player convenience.
	if index==0 and not displayed_mount.is_empty():
		text += "  骑宠 %s  体力 %d/%d" % [displayed_mount.get("name",""),displayed_mount.get("hp",0),displayed_mount.get("max_hp",0)]
	if index>=12 and index<16 and index-12<displayed_ally_mounts.size():
		var mount: Dictionary = displayed_ally_mounts[index-12]
		if not mount.is_empty(): text += "  骑宠 %s  体力 %d/%d" % [mount.get("name",""),mount.get("hp",0),mount.get("max_hp",0)]
	return text

## The hovered fighter's stored 属性, or [] when the slot has no fighter.
func hover_elements(index: int) -> Array:
	var actor: Dictionary = {}
	if index==0:return state.get("player_elements",[])
	elif index==2:actor = state.get("pet",{})
	elif index>=16:
		var pets: Array = state.get("ally_pets",[])
		if index-16<pets.size():actor = pets[index-16]
	elif index>=12:
		var allies: Array = state.get("allies",[])
		if index-12<allies.size():actor = allies[index-12]
	elif enemy_index(index)>=0:
		var foes: Array = enemies_of(state)
		if enemy_index(index)<foes.size():actor = foes[enemy_index(index)]
	return [] if actor.is_empty() else Elements.of(actor)

func update_hover_info(point: Vector2) -> void:
	# Reset the normal report before applying this frame's transient hover.
	report.visible = not is_animating()
	hover_info.hide()
	if not visible or world_modal_open() or result_panel.visible or elapsed<menu_slide_at: return
	var hovered := -1
	var front_y := -INF
	for i in range(actors.size()):
		if not actors[i].sprite.visible: continue
		var over_meter := hp_bars[i].visible and Rect2(hp_bars[i].position-Vector2(25,10),Vector2(50,20)).has_point(point)
		if not target_buttons[i].get_rect().has_point(point) and not over_meter: continue
		if float(actors[i].point.y)>=front_y:
			hovered = i
			front_y = float(actors[i].point.y)
	if hovered<0: return
	hover_info.text = hover_actor_text(hovered)
	hover_info.show()
	report.hide()

func show_learned_skills() -> void:
	clear_choices()
	ui_picture(26130,Vector2(650,300),choice_panel)
	var known: Array = state.get("pet",{}).get("learned_skills",[])
	for i in range(known.size()):
		var skill_id := int(known[i])
		if not PetSkills.SKILLS.has(skill_id): continue
		var button := choice(str(PetSkills.SKILLS[skill_id].name),Vector2(530,170+i*38),func():
			if is_animating(): return
			sound_requested.emit(217)
			selected_pet_skill = skill_id
			selected_action = "pet_skill"
			hint.text = "请选择技能目标；右键 / Esc 返回。")
		button.tooltip_text = str(PetSkills.SKILLS[skill_id].description)

# Every effect consumes an authority event. Rendering never rolls combat odds.
func queue_group_turn(previous: Dictionary) -> void:
	mirror_cues.clear()
	hp_cues.clear()
	riding_art_cues.clear()
	word_cues.clear()
	music_cues.clear()
	sound_cues.clear()
	pet_art_cues.clear()
	for actor in actors:
		actor.cues = []
		actor.motions = []
		actor.point = actor.home
		actor.spin_start = INF
		actor.spin_end = -INF
		actor.rate = 1.0
	var at := elapsed
	var before := previous
	for frame in state.get("turn_frames",[]):
		var who := str(frame.actor)
		var index := enemy_actor(int(frame.get("enemy_index",0))) if who=="enemy" else ally_pet_actor(int(frame.get("ally_index",0))) if who=="ally_pet" else ally_actor(int(frame.get("ally_index",0))) if who=="ally" else 2 if who=="pet" else 0
		var target := (ally_pet_actor(int(frame.get("ally_index",0))) if str(frame.get("enemy_target",""))=="ally_pet" else ally_actor(int(frame.get("ally_index",0))) if str(frame.get("enemy_target",""))=="ally" else 2 if str(frame.get("enemy_target",""))=="pet" else 0) if who=="enemy" else enemy_actor(int(frame.get("target_index",0)))
		var outcome := str(frame.get("outcome","hit"))
		# A disobeying pet (battle.c BX): "No!" (CG_ICON_NO 26509) over it
		# first; one attacking its owner strikes the player, one leaving
		# shows "Leave!" (CG_ICON_LEAVE 26513) as it walks off.
		var disobey := str(frame.get("disobey","")) if who=="pet" else ""
		if not disobey.is_empty():
			word_cues.append({"at":at,"index":2,"id":26509})
			at += 0.6
			if disobey=="attack_owner": target = 0
			if disobey=="escape": word_cues.append({"at":at,"index":2,"id":26513})
		var timing := {"hit":at+0.25,"end":at+0.5}
		if outcome=="mirror_cast":
			queue_pose(0,10,at,1.5)
			mirror_cues.append({"at":at,"id":100600,"index":0})
			mirror_cues.append({"at":at+1.5,"id":100610,"index":2 if pending_action=="mirror_pet" else 0})
			timing={"hit":at+1.5,"end":at+3.0}
		elif outcome=="reflect":
			timing=queue_strike(index,target,at)
			mirror_cues.append({"at":float(timing.hit),"id":100610,"index":target})
			queue_pose(index,2 if health_of(frame,index)<=0 else 1,float(timing.hit),60.0 if health_of(frame,index)<=0 else 0.5)
			timing.end=maxf(float(timing.end),float(timing.hit)+1.5)
		elif outcome=="switch":
			var roster: Array = frame.get("pets",[])
			var next_pet := int(frame.get("pet_index",-1))
			if bool(actors[2].get("enabled",false)):
				queue_motion(2,actors[2].home,actors[2].home+Vector2(300,300),at,0.5,7)
				actors[2].cues.append({"at":at,"action":4,"seconds":0.5,"facing":7})
			var companion: Dictionary = roster[next_pet] if next_pet>=0 and next_pet<roster.size() else {}
			pet_art_cues.append({"at":at+0.5,"pet":companion})
			if not companion.is_empty():
				queue_motion(2,actors[2].home+Vector2(300,300),actors[2].home,at+0.5,0.5,3)
				actors[2].cues.append({"at":at+0.5,"action":4,"seconds":0.5,"facing":3})
			timing = {"hit":at+1.0,"end":at+1.0}
		elif who=="player" and pending_action=="capture" and outcome in ["capture","captured"]:
			timing = queue_capture(at,outcome=="captured",target)
		elif who=="player" and pending_action=="escape" and outcome=="escape":
			timing = queue_escape(at,str(state.get("outcome",""))=="escaped",before)
		elif outcome in ["hit","miss","critical","counter","counter_miss","counter_critical"]:
			timing = queue_strike(index,target,at)
			if outcome.begins_with("counter"): word_cues.append({"at":at,"index":index,"id":26507})
			if outcome.ends_with("miss"):
				word_cues.append({"at":float(timing.hit),"index":target,"id":26504})
			elif int(frame.get("damage",0))>0:
				var impact := impact_sound(index)
				if impact >= 0: sound_cues.append({"at":float(timing.hit),"id":impact})
				var dead := health_of(frame,target)<=0
				var guarding := (target==0 and pending_action=="defend") or (target==2 and str(state.get("last_pet_command",""))=="defend") or clone_guarded(frame,target)
				queue_pose(target,2 if dead else 10 if guarding else 1,float(timing.hit),60.0 if dead else 0.35)
		else:
			queue_pose(index,3 if outcome=="standby" else 10,at,0.5)
			if outcome=="defend": word_cues.append({"at":at,"index":index,"id":26510})
		for recipient in range(actors.size()):
			# Capturing removes a target without displaying fictitious damage.
			if enemy_index(recipient)>=0 and enemy_index(recipient)<enemies_of(frame).size() and bool(enemies_of(frame)[enemy_index(recipient)].get("captured",false)): continue
			var guarded := (recipient==0 and pending_action=="defend") or (recipient==2 and str(state.get("last_pet_command",""))=="defend") or clone_guarded(frame,recipient)
			hp_cues.append({"at":float(timing.hit),"index":recipient,"hp":health_of(frame,recipient),"guarded":guarded,"critical":recipient==target and outcome.ends_with("critical")})
		if int(before.get("mounted_sprite",-1)) >= 0 or int(frame.get("mounted_sprite",-1)) >= 0:
			var dismounted := int(frame.get("mounted_sprite",-1)) < 0
			riding_art_cues.append({"at":float(timing.hit),"art":unmounted_player_art if dismounted else "","health":frame})
		for i in range(mini(4,frame.get("allies",[]).size())):
			var ally: Dictionary = frame.allies[i]
			var old: Dictionary = before.get("allies",[])[i]
			if int(old.get("mounted_sprite",-1))>=0 or int(ally.get("mounted_sprite",-1))>=0:
				riding_art_cues.append({"at":float(timing.hit),"index":ally_actor(i),"art":ally_art(ally,false) if int(ally.get("mounted_sprite",-1))<0 else "","ally_health":frame})
		before = frame
		at = float(timing.end)+0.08
	hp_cues.sort_custom(func(a,b): return float(a.at)<float(b.at))
	word_cues.sort_custom(func(a,b): return float(a.at)<float(b.at))
	for actor in actors: actor.cues.sort_custom(func(a,b): return float(a.at)<float(b.at))
	menu_slide_at = at
	feedback_until = at+MENU_SLIDE_SECONDS
	if not bool(state.get("active",false)) and not hp_cues.is_empty(): feedback_until = maxf(feedback_until,float(hp_cues.back().at)+85.0/60.0)

# Classic asset26040 has three rows. Page a five-pet roster using original
# arrow buttons; the later source's five-row126230 asset is absent in2.5.
## Whether the player still carries this pet (true without an id or a world).
func carried_pet(pet_id: String) -> bool:
	if pet_id.is_empty() or not is_instance_valid(world) or world.get("session")==null: return true
	return world.session.snapshot().get("pets",[]).any(func(pet): return str(pet.get("pet_id",""))==pet_id)

func show_pet_roster(page: int) -> void:
	clear_choices()
	ui_picture(26040,Vector2(650,280),choice_panel)
	var roster: Array = state.get("pets",[])
	for row in range(3):
		var index := page*3+row
		if index>=roster.size(): break
		var companion: Dictionary = roster[index]
		var origin := Vector2(522,120+row*87)
		var active := index==int(state.get("active_pet",-1))
		var button := choice(str(companion.get("name","宠物")),origin+Vector2(14,24),func():
			if is_animating() or world_modal_open(): return
			switch_pet_index = index
			complete_player_command("switch"))
		button.name = "RosterPet%d" % index
		button.size = Vector2(228,24)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size",14)
		var color := Color.YELLOW if active else Color.CYAN if int(companion.get("hp",0))>0 else Color.RED
		button.add_theme_color_override("font_color",color)
		button.add_theme_color_override("font_disabled_color",color)
		button.disabled = active or int(companion.get("hp",0))<=0
		# Stored or released from the pet window during this battle.
		if not active and not carried_pet(str(companion.get("pet_id",""))):
			button.disabled = true
			button.tooltip_text = "已存入仓库或放生，不能换上场。"
		for field in [[str(companion.get("level",1)),Vector2(43,59)],[str(companion.get("hp",0)),Vector2(130,59)],[str(companion.get("max_hp",0)),Vector2(183,59)],[str(companion.get("loyalty","—")),Vector2(64,81)]]:
			var value := label(field[0],12,origin+field[1],Vector2(48,18))
			value.add_theme_color_override("font_color",color)
			value.reparent(choice_panel,false)
	var withdraw := original_choice(26041,Vector2(576,423),func():
		if is_animating(): return
		switch_pet_index = -1
		complete_player_command("switch"))
	withdraw.name = "WithdrawPet"
	withdraw.disabled = int(state.get("active_pet",-1))<0
	original_choice(26042,Vector2(734,423),cancel_selection).name = "ClosePetRoster"
	if roster.size()>3:
		var previous := original_choice(26184,Vector2(641,423),func(): sound_requested.emit(217); show_pet_roster(0))
		var next := original_choice(26186,Vector2(675,423),func(): sound_requested.emit(217); show_pet_roster(1))
		previous.name = "PreviousPetPage"
		next.name = "NextPetPage"
		previous.disabled = page==0
		next.disabled = page==1
	hint.text = "选择出战伙伴；本回合更换或收回宠物。"

func original_choice(ident: int, center: Vector2, callback: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load(ART_ROOT+"ui/%d.png" % ident)
	button.texture_hover = button.texture_normal
	button.position = center+ui_offset(ident)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	choice_panel.add_child(button)
	return button

func ensure_riding_art(ident: String) -> bool:
	if Riding.art(ident).is_empty(): return false
	frame_sounds.merge(Riding.index().get("frame_sounds",{}),true)
	return true

## A sprite's entry (scripts/sprite_art.gd): a riding composite's or a battle
## sprite's (their ids do not overlap). {} when its file is not here.
func sprite_art(ident: String) -> Dictionary:
	if Riding.has_composite(ident): return Riding.art(ident)
	return BattleArt.art(ident)

## The hit sound of an attacker's strike: oft.cpp play_damage() maps the hit
## marker (a frame sound >= 10000, pattern.cpp:219-224) of the attack clip to
## an SE, for every attacker that deals damage (oft.cpp:6986-6996), mounted
## or not. 10005/10006 (bow, thrown axe) play nothing: -1.
func impact_sound(index: int) -> int:
	var facing := 7 if enemy_index(index)>=0 else 3
	var clip: Dictionary = actors[index].animations.get("0_%d" % facing,{})
	for i in range(SpriteArt.frame_count(clip)):
		var marker := SpriteArt.sound(clip,i)
		if marker >= 10100: marker -= 100
		if marker >= 10000:
			return {10000:250,10001:254,10002:251,10003:251,10004:252,10005:-1,10006:-1,10007:254}.get(marker,250)
	return 250

func update_riding_health(health: Dictionary) -> void:
	var index := int(health.get("ride_pet",-1))
	var roster: Array = health.get("pets",[])
	displayed_mount = roster[index].duplicate(true) if index>=0 and index<roster.size() else {}
	riding_hp_bar.visible = index >= 0 and index < roster.size()
	if riding_hp_bar.visible:
		riding_hp_fill.size.x = 40.0*clampf(float(roster[index].hp)/maxf(1,float(roster[index].max_hp)),0,1)

func clone_guarded(snapshot: Dictionary, index: int) -> bool:
	var roster: Array = snapshot.get("ally_pets",[]) if index>=16 else snapshot.get("allies",[])
	var slot := index-16 if index>=16 else index-12
	return slot>=0 and slot<roster.size() and bool(roster[slot].get("defending",false))

func update_ally_mount_health(health: Dictionary) -> void:
	displayed_ally_mounts.clear()
	var allies: Array = health.get("allies",[])
	for i in range(4):
		var ally: Dictionary = allies[i] if i<allies.size() else {}
		var mount: Dictionary = ally.get("mount",{})
		displayed_ally_mounts.append(mount.duplicate(true))
		ally_mount_bars[i].visible = int(ally.get("mounted_sprite",-1))>=0 and int(mount.get("hp",0))>0
		ally_mount_fills[i].size.x = 40.0*clampf(float(mount.get("hp",0))/maxf(1,float(mount.get("max_hp",1))),0,1)
