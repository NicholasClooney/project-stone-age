extends Control
var world: Node2D
var colors: Array[Color] = []
var last_cell := Vector2i(-999,-999)
var last_flash := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/ui/manifest.json"))
	colors.resize(int(world.data.width)*int(world.data.height))
	colors.fill(Color.BLACK)
	for entry in world.data.ground:
		colors[int(entry[1])*int(world.data.width)+int(entry[0])] = map_color(manifest,entry[2])
	for entry in world.data.objects:
		var metadata: Dictionary = world.data.images[str(int(entry[2]))]
		for dy in range(maxi(1,int(metadata.ey)) if int(metadata.hit)==0 else 1):
			for dx in range(maxi(1,int(metadata.ex)) if int(metadata.hit)==0 else 1):
				var point := Vector2i(int(entry[0])+dx,int(entry[1])-dy)
				if Rect2i(0,0,int(world.data.width),int(world.data.height)).has_point(point):
					colors[point.y*int(world.data.width)+point.x] = map_color(manifest,entry[2])

func map_color(manifest: Dictionary, ident: float) -> Color:
	var rgb: Array = manifest.map_colors[str(int(ident))]
	return Color8(int(rgb[0]),int(rgb[1]),int(rgb[2]))

func _process(_delta: float) -> void:
	var flash := int(Time.get_ticks_msec()/1000)%2
	if last_cell != world.cell or flash != last_flash:
		last_cell = world.cell
		last_flash = flash
		queue_redraw()

func _draw() -> void:
	if colors.is_empty():
		return
	# Original DrawAutoMapping uses 54×54 cells and a 4×2 pixel diamond.
	for y in range(54):
		for x in range(54):
			var cell: Vector2i = world.cell+Vector2i(x-27,y-27)
			var color := Color.BLACK
			if Rect2i(0,0,int(world.data.width),int(world.data.height)).has_point(cell):
				color = colors[cell.y*int(world.data.width)+cell.x]
			pixel(Vector2(18+2*(x+y),118+y-x),color)
	pixel(Vector2(126,118),Color.WHITE if last_flash else Color.BLACK)

func pixel(point: Vector2, color: Color) -> void:
	draw_rect(Rect2(point-Vector2(1,0),Vector2(3,1)),color)
	draw_rect(Rect2(point-Vector2(0,1),Vector2.ONE),color)
