extends Node
## Palette sheets on a real GPU (scripts/palette_sheet.gd): draws sample
## sheets as plain RGBA textures and through the palette shader into
## offscreen viewports and compares the pixels read back byte for byte:
## plain, modulated, flipped and scaled sprites, both ends of each sheet,
## a TextureRect, and draw_texture() on a node (the map's ground layer). Then it measures texture memory both ways.
##
## Headless suites cannot render, so tools/palette_web_check.py runs this
## node in a small web export in headless Chromium (WebGL 2, the renderer
## iPhone and Vision Pro use). It reads the sheets listed in SHEETS_FILE
## (raw PNG bytes, any extension) and prints PASS/FAIL/MEASURE lines and
## "palette_render_check: <n> failures".
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const SHEETS_FILE := "res://sheets/list.txt"
var failures := 0

class Drawn extends Node2D:
	var texture: Texture2D
	func _draw() -> void:
		draw_texture(texture,Vector2.ZERO)

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func _ready() -> void:
	run.call_deferred()

## Today's picture of a sheet: Godot's RGBA decode of the PNG, which the
## imported texture shows pixel for pixel wherever it is visible
## (palette_sheet_test.gd compares those).
func rgba_texture(png: PackedByteArray) -> Texture2D:
	var image := Image.new()
	image.load_png_from_buffer(png)
	image.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(image)

func palette_texture(png: PackedByteArray) -> Texture2D:
	return PaletteSheet.texture_of(PaletteSheet.decode(png))

## The picture a node of this texture draws into a transparent viewport.
func render(texture: Texture2D, region: Rect2, palette: bool, look: Dictionary) -> Image:
	var scale: float = look.get("scale",look.get("zoom",1.0))
	var viewport := SubViewport.new()
	viewport.size = Vector2i((region.size*scale).ceil())+Vector2i(2,2)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var frame := AtlasTexture.new()
	frame.atlas = texture
	frame.region = region
	var item: CanvasItem
	var holder: Node = null
	if look.has("zoom"):
		# As the field draws an actor (legacy_actor.gd): the actor node is
		# nearest, its sprite inherits that, under a zoomed Camera2D in a
		# viewport whose default filter is the project's (linear).
		var actor := Node2D.new()
		actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		actor.position = Vector2(1,1)/scale+Vector2(look.get("offset",Vector2.ZERO))
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = frame
		actor.add_child(sprite)
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		camera.zoom = Vector2(scale,scale)
		viewport.add_child(camera)
		holder = actor
		item = sprite
	elif look.get("draw",false):
		# Custom drawing on a node with the material, like the map's ground.
		var drawn := Drawn.new()
		drawn.texture = frame
		drawn.position = Vector2(1,1)
		drawn.scale = Vector2(scale,scale)
		item = drawn
	elif look.get("rect",false):
		var rect := TextureRect.new()
		rect.texture = frame
		rect.position = Vector2(1,1)
		rect.size = region.size*scale
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		item = rect
	else:
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = frame
		sprite.position = Vector2(1,1)+Vector2(look.get("offset",Vector2.ZERO))
		sprite.scale = Vector2(scale,scale)
		sprite.flip_h = look.get("flip",false)
		item = sprite
	if holder == null:item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.modulate = look.get("modulate",Color.WHITE)
	if palette:PaletteSheet.apply(item,frame)
	viewport.add_child(holder if holder != null else item)
	add_child(viewport)
	for i in range(3):await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	viewport.queue_free()
	return image

## "x,y: rgba -> palette" of the first pixel that differs, and how many do.
func first_difference(a: Image, b: Image) -> String:
	if a.get_size()!=b.get_size():return "size %s -> %s" % [a.get_size(),b.get_size()]
	var count := 0
	var first := ""
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x,y)!=b.get_pixel(x,y):
				if first.is_empty():first = "%d,%d: %s -> %s" % [x,y,a.get_pixel(x,y).to_html(),b.get_pixel(x,y).to_html()]
				count += 1
	return "%s (%d pixels)" % [first,count]

func run() -> void:
	var looks := [{},{"modulate":Color(1,0.4,0.4,0.6)},{"flip":true},{"scale":2.0},{"scale":1.37},{"modulate":Color(0,0,0,0.5),"scale":0.75},{"offset":Vector2(0.4,0.6)},{"rect":true,"scale":1.5},{"zoom":1.0},{"zoom":0.5},{"zoom":0.73,"offset":Vector2(0.3,0.6)},{"zoom":1.6},{"draw":true},{"draw":true,"scale":1.37}]
	var paths := FileAccess.get_file_as_string(SHEETS_FILE).split("\n",false)
	check(not paths.is_empty(),"sample sheets listed")
	var largest := {}
	for path in paths:
		var png := FileAccess.get_file_as_bytes(path)
		var decoded := PaletteSheet.decode(png)
		if decoded.is_empty():
			check(false,"%s is a palette PNG" % path);continue
		var rgba := rgba_texture(png)
		var palette := palette_texture(png)
		var size := rgba.get_size()
		if size.x*size.y > largest.get("area",0):largest = {"area":size.x*size.y,"png":png}
		var drawn := 0
		var same := true
		# A frame-sized window at the top left and at the bottom right (next
		# to the palette rows).
		for region in [Rect2(0,0,mini(160,size.x),mini(160,size.y)),Rect2(maxf(0,size.x-120),maxf(0,size.y-120),mini(120,size.x),mini(120,size.y))]:
			for look in looks:
				var a := await render(rgba,region,false,look)
				var b := await render(palette,region,true,look)
				if a.get_data()!=b.get_data():
					same = false
					print("  differs: %s %s %s %s" % [path,region,look,first_difference(a,b)])
				if not a.is_invisible():drawn += 1
		# A fully transparent image (some map images are) draws nothing either way.
		check(same and (drawn > 0 or rgba.get_image().is_invisible()),"%s: the palette shader draws the same bytes as RGBA (%d views)" % [path.get_file(),2*looks.size()])
	# Texture memory of the largest sample, both ways.
	if not largest.is_empty():
		for palette in [false,true]:
			await get_tree().process_frame
			var before := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
			var held: Texture2D = palette_texture(largest.png) if palette else rgba_texture(largest.png)
			for i in range(3):await get_tree().process_frame
			var used := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)-before
			print("MEASURE %s: %dx%d sheet, texture memory +%.2f MB" % ["palette" if palette else "RGBA",held.get_width(),held.get_height(),used/1048576.0])
			held = null
	print("palette_render_check: %d failures" % failures)
