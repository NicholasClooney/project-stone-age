extends SceneTree
## Full pre-cut index + the real 宠物大全 TextureRects under its CanvasLayer.
const Thumbs = preload("res://scripts/pet_thumbnails.gd")
const Palette = preload("res://scripts/palette_sheet.gd")
var failures := 0
func _initialize() -> void:run.call_deferred()
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func run() -> void:
	var index := Thumbs.atlas_index()
	check(not index.get("palette_files",[]).is_empty(),"palette thumbnails imported")
	var shared := PackedByteArray()
	var images: Array = []
	var valid := true
	for name in index.get("palette_files",[]):
		var path := Thumbs.THUMBS+str(name)
		var decoded := Palette.decode(FileAccess.get_file_as_bytes(path))
		if decoded.is_empty():valid = false;continue
		if shared.is_empty():shared = decoded.palette
		valid = valid and shared == decoded.palette
		for i in range(256):valid = valid and decoded.palette[i*4+3] in [0,255]
		images.append(decoded.indices)
	check(valid and images.size()==index.files.size(),"all atlases use one exact shared palette and binary alpha")
	var bounds := true
	for sprite in index.sprites:
		var spot: Array = index.sprites[sprite]
		var image: Image = images[int(spot[0])]
		bounds = bounds and int(spot[1])>=0 and int(spot[2])>=0 and int(spot[3])>0 and int(spot[4])>0 and int(spot[1])+int(spot[3])<=image.get_width() and int(spot[2])+int(spot[4])<=image.get_height()
	check(bounds,"every one of %d frame rectangles is within its atlas" % index.sprites.size())
	for on in [true,false,true]:
		Palette.user_on = on
		Thumbs.clear()
		check(Thumbs.atlas_paths()==index.get("palette_files" if on else "files",[]).map(func(name):return Thumbs.THUMBS+str(name)),"prefetch selects only the current variant paths")
		var all := true
		for sprite in index.sprites:
			var texture := Thumbs.texture(int(sprite))
			all = all and texture is AtlasTexture and Palette.is_palette(texture)==on
			all = all and Thumbs.atlas_path(int(sprite)).get_file().begins_with("palette-" if on else "atlas-")
		check(all,"all frames select the %s atlas and shader" % ("palette" if on else "RGBA"))
		check(Thumbs._atlases.size()==index.files.size(),"only the current variant's atlases are held")
	await raw_pack(index)
	fallback(index)
	# Existing menu runs through the public device setting (save isolated by run.sh).
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var menu = game.pet_encyclopedia
	var sprite := int(index.sprites.keys()[0])
	var holder: Control = menu._thumb(sprite,Vector2(104,86))
	menu.add_child(holder)
	var picture: TextureRect = holder.get_child(0)
	check(picture.custom_minimum_size==Vector2.ZERO and holder.custom_minimum_size==Vector2(104,86),"real encyclopedia cell keeps its 104×86 layout")
	for on in [false,true,false]:
		var old = weakref(picture.texture.atlas) if picture.texture is AtlasTexture else null
		game.set_palette_textures(on)
		menu._refresh_thumb_mode()
		menu._fill_variant_thumbs()
		check(picture.texture!=null and Palette.is_palette(picture.texture)==on and (picture.material!=null)==on,"public setting changes the real thumbnail immediately")
		check(picture.texture_filter==(CanvasItem.TEXTURE_FILTER_NEAREST if on else CanvasItem.TEXTURE_FILTER_LINEAR),"the individual UI node explicitly samples %s" % ("nearest" if on else "linear"))
		await process_frame
		check(old==null or old.get_ref()==null,"the old variant's atlas is released after toggling")
	# Thumbnail UI reads no backend, including the remote client's case.
	var backend = game.backend
	game.backend = null
	var remote_holder: Control = menu._thumb(sprite,Vector2(104,86))
	menu.add_child(remote_holder)
	check(remote_holder.get_child(0).texture!=null,"thumbnail creation works with no backend on a remote UI")
	game.backend = backend
	game.set_palette_textures(true)
	Thumbs.clear()
	game.queue_free()
	await process_frame
	print("PET THUMBNAIL PALETTE: %d failures" % failures)
	quit(1 if failures else 0)

func raw_pack(original: Dictionary) -> void:
	# A mounted PNG-only PCK with no .import remap, as the web's palette pack.
	# Include a raw RGBA fixture too to cover load_rgba fallback without imports.
	var packer := PCKPacker.new()
	check(packer.pck_start("user://thumb-variants.pck")==OK,"temporary raw pack opens")
	var packed_palette := Thumbs.THUMBS+"palette-web-test.png"
	var packed_rgba := Thumbs.THUMBS+"atlas-web-test.png"
	packer.add_file(packed_palette,Thumbs.THUMBS+str(original.palette_files[0]))
	packer.add_file(packed_rgba,Thumbs.THUMBS+str(original.files[0]))
	packer.flush()
	check(ProjectSettings.load_resource_pack("user://thumb-variants.pck"),"real raw pack mounts")
	var sprite: String = original.sprites.keys()[0]
	var spot: Array = original.sprites[sprite].duplicate()
	spot[0] = 0
	Thumbs._atlas_index = {"files":["atlas-web-test.png"],"palette_files":["palette-web-test.png"],"sprites":{sprite:spot}}
	for on in [true,false]:
		Palette.user_on = on
		Thumbs.clear()
		var texture := Thumbs.texture(int(sprite))
		check(texture!=null and Palette.is_palette(texture)==on,"PNG-only pack loads %s without an imported resource" % ("palette" if on else "RGBA fallback"))
	Thumbs.clear()
	Thumbs._atlas_index = original
	Palette.user_on = true

func fallback(original: Dictionary) -> void:
	# Older/local imports without thumbs/index.json still cut standing art.
	var sprite := int(original.sprites.keys()[0])
	Thumbs.clear()
	Thumbs._atlas_index = {}
	for on in [false,true]:
		Palette.user_on = on
		Thumbs.clear()
		var texture := Thumbs.texture(sprite)
		var picture := TextureRect.new()
		Thumbs.apply(picture,texture)
		check(texture!=null and texture.get_width()<=128 and texture.get_height()<=128 and Palette.is_palette(texture)==on,"local standing-frame fallback follows the %s switch" % ("palette" if on else "RGBA"))
		check(picture.texture_filter==(CanvasItem.TEXTURE_FILTER_NEAREST if on else CanvasItem.TEXTURE_FILTER_LINEAR),"fallback uses the selected explicit filter")
		picture.free()
	Thumbs.clear()
	Thumbs._atlas_index = original
	Palette.user_on = true
