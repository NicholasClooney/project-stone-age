extends Node2D
var world: Node2D
var center := Vector2i(-999,-999)
## Image id per cell (y*width+x), 0 where the map has no ground tile: the
## map's own packed grid (scripts/map_file.gd), shared, not copied.
var ground := PackedInt32Array()
var radius := 28
var last_zoom := -1.0

func fill(grid: PackedInt32Array) -> void:
	ground = grid

## The ground image id at a cell index as a string key of `images`, "" for none.
func ident_at(index: int) -> String:
	var ident := ground[index] if index>=0 and index<ground.size() else 0
	return str(ident) if ident!=0 else ""

func _process(_delta: float) -> void:
	if world == null:
		return
	var next := Vector2i(world.unproject(world.camera.get_screen_center_position()).round())
	var zoom: float = world.camera.zoom.x
	var view: Vector2 = get_viewport_rect().size/zoom
	var next_radius := ceili(view.x/128+view.y/96)+5
	if center != next or last_zoom != zoom:
		last_zoom = zoom
		radius = next_radius
		center = next
		queue_redraw()

func _draw() -> void:
	if world == null:
		return
	# Cull by logical distance. The original isometric projection is 64 × 48.
	for y in range(maxi(0,center.y-radius),mini(int(world.data.height),center.y+radius+1)):
		for x in range(maxi(0,center.x-radius),mini(int(world.data.width),center.x+radius+1)):
			var id := ground[y*int(world.data.width)+x]
			if id==0:
				continue
			var ident := str(id)
			var metadata: Dictionary = world.data.images[ident]
			draw_texture(world.texture(ident),world.project(Vector2(x,y))+Vector2(metadata.x,metadata.y))
