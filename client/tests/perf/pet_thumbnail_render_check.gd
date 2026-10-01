extends "res://tests/perf/palette_render_check.gd"
## GPU proof for every atlas texel and every 104×86 encyclopedia cell.
## References come independently from the original standing frames, nearest.
const INDEX := "res://thumbs/index.json"
var book: Dictionary

func mosaic(textures: Array, palette: bool, linear: bool) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(26*104,ceili(book.sprites.size()/26.0)*86)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var layer := CanvasLayer.new()
	viewport.add_child(layer)
	var number := 0
	for sprite in book.sprites:
		var spot: Array = book.sprites[sprite]
		var frame := AtlasTexture.new()
		frame.atlas = textures[int(spot[0])]
		frame.region = Rect2(int(spot[1]),int(spot[2]),int(spot[3]),int(spot[4]))
		var rect := TextureRect.new()
		rect.texture = frame
		rect.position = Vector2((number%26)*104,(number/26)*86)
		rect.size = Vector2(104,86)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if linear else CanvasItem.TEXTURE_FILTER_NEAREST
		if palette:PaletteSheet.apply(rect,frame)
		layer.add_child(rect)
		number += 1
	add_child(viewport)
	for i in range(3):await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	viewport.queue_free()
	return image

func settled() -> void:
	for i in range(5):await get_tree().process_frame
	await RenderingServer.frame_post_draw

func allocations() -> Dictionary:
	return JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.__paletteAllocations())")))

func run() -> void:
	book = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	var count: int = book.files.size()
	for i in range(count):
		var reference := rgba_texture(FileAccess.get_file_as_bytes("res://thumbs/nearest-%d.sheet" % i))
		var palette := palette_texture(FileAccess.get_file_as_bytes("res://thumbs/palette-%d.sheet" % i))
		var region := Rect2(Vector2.ZERO,reference.get_size())
		var a := await render(reference,region,false,{})
		var b := await render(palette,region,true,{})
		var exact := a.get_data()==b.get_data()
		check(exact,"thumbnail atlas %d: ALL texels GPU byte-exact to independent nearest originals" % i)
		reference = null
		palette = null
	await settled()
	var reference: Array = []
	var palettes: Array = []
	var originals: Array = []
	var baseline: Array = []
	for i in range(count):
		reference.append(rgba_texture(FileAccess.get_file_as_bytes("res://thumbs/nearest-%d.sheet" % i)))
		palettes.append(palette_texture(FileAccess.get_file_as_bytes("res://thumbs/palette-%d.sheet" % i)))
		originals.append(load("res://thumbs/rgba-%d.png" % i))
		baseline.append(load("res://thumbs/baseline-%d.png" % i))
	var a := await mosaic(reference,false,false)
	var b := await mosaic(palettes,true,false)
	check(a.get_data()==b.get_data(),"all %d real 104×86 CanvasLayer cells: palette nearest GPU byte-exact to independent nearest originals" % book.sprites.size())
	a = await mosaic(baseline,false,true)
	b = await mosaic(originals,false,true)
	check(a.get_data()==b.get_data(),"all %d off cells: original Lanczos with explicit linear GPU byte-exact to old linear baseline" % book.sprites.size())
	reference.clear()
	palettes.clear()
	originals.clear()
	baseline.clear()
	a = null
	b = null
	await settled()
	# Start with no palette allocation so ON includes its actual 1024-byte
	# WebGL allocation. After ON the shared material may remain cached, but
	# none of its five index atlases may remain.
	PaletteSheet._materials.clear()
	await settled()
	var shared_bytes := 0
	for on in [false,true,false]:
		var before := allocations()
		var godot_before := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
		var held: Array = []
		for i in range(count):
			held.append(palette_texture(FileAccess.get_file_as_bytes("res://thumbs/palette-%d.sheet" % i)) if on else load("res://thumbs/rgba-%d.png" % i))
		await settled()
		var after := allocations()
		var newly_shared := 1024 if on and shared_bytes==0 else 0
		check(after.unknown.is_empty(),"instrumentation recognizes every WebGL allocation format: %s" % str(after.unknown))
		print("MEASURE all %d atlases %s: WebGL live allocation delta %d bytes, Godot texture allocation delta %d bytes, palette %d bytes already shared" % [count,"ON" if on else "OFF",int(after.bytes)-int(before.bytes),int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)-godot_before),shared_bytes])
		held.clear()
		await settled()
		var freed := allocations()
		check(int(freed.bytes)==int(before.bytes)+newly_shared,"%s releases every atlas allocation before the next variant" % ("ON" if on else "OFF"))
		shared_bytes += newly_shared
	print("MEASURE shared palette retained after ON: %d WebGL bytes" % shared_bytes)
	print("palette_render_check: %d failures" % failures)
