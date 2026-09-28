extends Control
var world: Node2D
var colors: Array[Color] = []
var last_cell := Vector2i(-999,-999)
var last_flash := -1
## The UI manifest's default colours, parsed once per run rather than per map.
static var _default_colors: Dictionary = {}
## Colour per image id for this map; maps reuse a few hundred ids across up to
## a million cells, so each id is resolved once.
var _color_by_ident: Dictionary = {}
## The map data these colours were computed from.
var built_for: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rebuild()

## Recomputes the colours for the world's current map.
func rebuild() -> void:
	_color_by_ident.clear()
	built_for = world.data
	last_cell = Vector2i(-999,-999)
	if _default_colors.is_empty():
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/ui/manifest.json"))
		_default_colors = manifest.map_colors
	var width := int(world.data.width)
	var height := int(world.data.height)
	colors.resize(width*height)
	colors.fill(Color.BLACK)
	for entry in world.data.ground:
		colors[int(entry[1])*width+int(entry[0])] = map_color(entry[2])
	var bounds := Rect2i(0,0,width,height)
	for entry in world.data.objects:
		var metadata: Dictionary = world.data.images[str(int(entry[2]))]
		var color := map_color(entry[2])
		for dy in range(maxi(1,int(metadata.ey)) if int(metadata.hit)==0 else 1):
			for dx in range(maxi(1,int(metadata.ex)) if int(metadata.hit)==0 else 1):
				var point := Vector2i(int(entry[0])+dx,int(entry[1])-dy)
				if bounds.has_point(point):
					colors[point.y*width+point.x] = color

func map_color(ident: float) -> Color:
	var cached = _color_by_ident.get(ident)
	if cached!=null:return cached
	var rgb: Array = world.data.get("map_colors",{}).get(str(int(ident)),_default_colors.get(str(int(ident)),[0,0,0]))
	var color := Color8(int(rgb[0]),int(rgb[1]),int(rgb[2]))
	_color_by_ident[ident] = color
	return color

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
