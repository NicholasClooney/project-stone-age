extends Node2D

var world: Node2D
var character_id := "100000"
var facing := 0
var action := 3
var elapsed := 0.0
var sprite: Sprite2D
var current_image := -1
var mounted_character_id := ""
var mounted_textures: Dictionary = {}
var last_render_character := ""

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)

func _process(delta: float) -> void:
	elapsed += delta
	if world == null or sprite == null:
		return
	var key := str(action)+"_"+str(facing)
	var mounted: bool = not mounted_character_id.is_empty()
	var rendered_id: String = mounted_character_id if mounted else character_id
	var catalogue: Dictionary = preload("res://scripts/riding.gd").manifest() if mounted else world.data
	if not catalogue.get("characters",{}).has(rendered_id): return
	if rendered_id != last_render_character:
		last_render_character = rendered_id
		current_image = -1
		elapsed = 0.0
	var animations: Dictionary = catalogue.characters[rendered_id]
	if not animations.has(key):
		key = "3_"+str(facing)
	if not animations.has(key): return
	var animation: Dictionary = animations[key]
	var frames: Array = animation.frames
	if frames.is_empty():
		return
	var duration: float = maxf(float(animation.duration_ms)/1000.0,0.1)
	var index := int(fmod(elapsed,duration)/duration*frames.size()) % frames.size()
	var frame: Dictionary = frames[index]
	var ident := int(frame.image)
	if ident != current_image:
		current_image = ident
		if mounted:
			if not mounted_textures.has(str(ident)):
				mounted_textures[str(ident)] = load("res://assets/legacy/riding/images/"+str(ident)+".png")
			sprite.texture = mounted_textures[str(ident)]
		else:
			if not world.textures.has(str(ident)):
				world.textures[str(ident)] = load("res://assets/legacy/images/"+str(ident)+".png")
			sprite.texture = world.textures[str(ident)]
	var metadata: Dictionary = catalogue.images[str(ident)]
	sprite.position = Vector2(metadata.x+frame.x,metadata.y+frame.y)

func set_action(next: int) -> void:
	if next != action:
		action = next
		elapsed = 0
