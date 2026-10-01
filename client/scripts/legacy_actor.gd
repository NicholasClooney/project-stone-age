extends Node2D

var world: Node2D
var character_id := "100000"
var facing := 0
var action := 3
var elapsed := 0.0
var sprite: Sprite2D
var current_image := -1
var mounted_character_id := ""
var last_render_character := ""
var art: Dictionary = {}
const SpriteArt = preload("res://scripts/sprite_art.gd")
const CharacterArt = preload("res://scripts/character_art.gd")
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const Riding = preload("res://scripts/riding.gd")

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
	if rendered_id != last_render_character or art.is_empty():
		var next := _art_for(rendered_id,mounted)
		if next.is_empty(): return
		art = next
		if rendered_id != last_render_character:
			last_render_character = rendered_id
			current_image = -1
			elapsed = 0.0
	var animations: Dictionary = art.animations
	if not animations.has(key):
		key = "3_"+str(facing)
	if not animations.has(key): return
	var animation: Dictionary = animations[key]
	var count := SpriteArt.frame_count(animation)
	if count == 0:
		return
	var duration: float = maxf(float(animation.duration_ms)/1000.0,0.1)
	var index := int(fmod(elapsed,duration)/duration*count) % count
	var ident := SpriteArt.image(animation,index)
	if ident != current_image:
		current_image = ident
		if mounted:
			sprite.texture = SpriteArt.texture(art,ident)
		elif world.has_method("character_frame"):
			sprite.texture = world.character_frame(rendered_id,ident)
		else:
			if not world.textures.has(str(ident)):
				world.textures[str(ident)] = load("res://assets/legacy/images/"+str(ident)+".png")
				preload("res://scripts/perf_registry.gd").track_texture("map",ident,world.textures[str(ident)])
			sprite.texture = world.textures[str(ident)]
		PaletteSheet.apply(sprite,sprite.texture)
	sprite.position = SpriteArt.offset(art,animation,index)

## The art drawn for this appearance: a riding composite, a player
## character's walking art, or walking art the map JSON carries itself.
## {} while it is not here (a web pack still downloading).
func _art_for(id: String, mounted: bool) -> Dictionary:
	if mounted: return Riding.art(id)
	var found := CharacterArt.art(id)
	if not found.is_empty(): return found
	var data = world.get("data")
	if data is Dictionary and data.get("characters",{}).has(id):
		return SpriteArt.from_legacy(id,data.characters[id],data.get("images",{}))
	return {}

func set_action(next: int) -> void:
	if next != action:
		action = next
		elapsed = 0
