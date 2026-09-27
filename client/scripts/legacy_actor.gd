extends Node2D

var world: Node2D
var character_id := "100000"
var facing := 0
var action := 3
var elapsed := 0.0
var sprite: Sprite2D
var current_image := -1

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
	var animations: Dictionary = world.data.characters[character_id]
	if not animations.has(key):
		key = "3_"+str(facing)
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
		sprite.texture = world.textures[str(ident)]
	var metadata: Dictionary = world.data.images[str(ident)]
	sprite.position = Vector2(metadata.x+frame.x,metadata.y+frame.y)

func set_action(next: int) -> void:
	if next != action:
		action = next
		elapsed = 0
