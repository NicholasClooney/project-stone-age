extends Node2D
var world: Node2D
var sprite: Sprite2D
var manifest: Dictionary
var animations: Dictionary = {}
var textures: Dictionary = {}
var sprite_id := ""
var pet_name := ""
var elapsed := 0.0
var facing := 0
var previous := Vector2.ZERO
var name_label: Label
func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	add_child(sprite)
	name_label = world.text("",13)
	name_label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	name_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x",1)
	name_label.add_theme_constant_override("shadow_offset_y",1)
	name_label.position = Vector2(-30,-58)
	add_child(name_label)
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/battle/manifest.json"))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
func select_pet(ident: String, caption: String) -> void:
	pet_name = caption
	name_label.text = caption
	if sprite_id==ident:return
	sprite_id = ident
	animations = manifest.characters.get(ident,{})
	textures.clear()
	for animation in animations.values():
		for frame in animation.frames:
			var key := str(int(frame.image))
			if not textures.has(key):textures[key] = preload("res://scripts/sheet_frames.gd").texture("res://assets/legacy/battle/",manifest.get("sheets",{}),ident,int(key))
func _process(delta: float) -> void:
	if animations.is_empty():return
	elapsed += delta
	var target: Vector2 = world.project(Vector2(world.pet_trail[0])) if not world.pet_trail.is_empty() else world.player.position
	previous = position
	position = position.move_toward(target,delta*220.0)
	var walking := position.distance_to(previous)>0.1
	if walking:
		var direction: Vector2 = world.unproject(position)-world.unproject(previous)
		var step := Vector2i(signi(int(round(direction.x*100))),signi(int(round(direction.y*100))))
		var index: int = world.SCREEN_DIRECTIONS.find(step)
		if index>=0:facing = (index+4)%8
	var key := "%d_%d" % [4 if walking else 3,facing]
	var animation: Dictionary = animations.get(key,animations.get("3_0",{}))
	if animation.is_empty():return
	var duration := maxf(0.1,float(animation.duration_ms)/1000.0)
	var frames: Array = animation.frames
	var frame: Dictionary = frames[int(fmod(elapsed,duration)/duration*frames.size())%frames.size()]
	var ident := str(int(frame.image))
	var meta: Dictionary = manifest.images[ident]
	sprite.texture = textures[ident]
	sprite.position = Vector2(meta.x+frame.x,meta.y+frame.y)
