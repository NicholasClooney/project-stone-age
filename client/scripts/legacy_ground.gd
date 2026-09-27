extends Node2D
var world: Node2D
var center := Vector2i(-999,-999)
var ground: Dictionary = {}

func _process(_delta: float) -> void:
	if world == null:
		return
	var next := Vector2i(world.logical_position.round())
	if center != next:
		center = next
		queue_redraw()

func _draw() -> void:
	if world == null:
		return
	# Cull by logical distance. The original isometric projection is 64 × 48.
	for y in range(maxi(0,center.y-28),mini(int(world.data.height),center.y+29)):
		for x in range(maxi(0,center.x-28),mini(int(world.data.width),center.x+29)):
			var key := y*int(world.data.width)+x
			if not ground.has(key):
				continue
			var ident: String = ground[key]
			var metadata: Dictionary = world.data.images[ident]
			draw_texture(world.textures[ident],world.project(Vector2(x,y))+Vector2(metadata.x,metadata.y))
