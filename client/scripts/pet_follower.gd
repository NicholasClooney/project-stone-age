extends Node2D
var world: Node2D
var sprite: Sprite2D
## The pet's sprite entry (scripts/sprite_art.gd); its frames are cut on first draw.
var art: Dictionary = {}
var animations: Dictionary = {}
const SpriteArt = preload("res://scripts/sprite_art.gd")
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
	name_label.add_theme_color_override("font_color",Color.WHITE)
	name_label.add_theme_color_override("font_outline_color",Color.BLACK)
	name_label.add_theme_constant_override("outline_size",4)
	name_label.position = Vector2(-30,-58)
	add_child(name_label)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
func select_pet(ident: String, caption: String) -> void:
	pet_name = caption
	name_label.text = caption
	if sprite_id==ident:return
	# A pet sprite in its own file whose web pack is not here yet: retry on the next call.
	art = preload("res://scripts/battle_art.gd").art(ident)
	sprite_id = ident if not art.is_empty() else ""
	animations = art.get("animations",{})
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
	var count := SpriteArt.frame_count(animation)
	if count == 0:return
	var index := int(fmod(elapsed,duration)/duration*count)%count
	sprite.texture = SpriteArt.texture(art,SpriteArt.image(animation,index))
	sprite.position = SpriteArt.offset(art,animation,index)
