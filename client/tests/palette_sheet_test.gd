extends SceneTree
## Palette sheets (scripts/palette_sheet.gd, docs/technical/palette-textures.md):
## indices plus palette reproduce Godot's own RGBA decode of each sample
## sheet byte for byte and the imported texture's visible pixels, the
## textures and material are laid out as the shader expects, SheetFrames
## follows the setting, and the expected video memory of every sheet is
## reported.
## The shader itself is checked on a GPU by tools/palette_web_check.py.
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const SheetFrames = preload("res://scripts/sheet_frames.gd")
## The kinds the project draws from palette sheets so far.
const ON := ["battle","riding","characters","tiles"]
const ROOT := "res://assets/legacy/"
const FOLDERS := ["battle/sheets","riding/sheets","characters/sheets","images"]
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func sheets(folder: String) -> PackedStringArray:
	var result := PackedStringArray()
	for name in DirAccess.get_files_at(ROOT+folder):
		if name.get_extension()=="png":result.append(ROOT+folder+"/"+name)
	result.sort()
	return result

## Width and height from a PNG's header, without decoding it.
func png_size(path: String) -> Vector2i:
	var file := FileAccess.open(path,FileAccess.READ)
	var header := file.get_buffer(24)
	return Vector2i(be32(header,16),be32(header,20))

func be32(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at]<<24)|(bytes[at+1]<<16)|(bytes[at+2]<<8)|bytes[at+3]

## Decoded both ways: Godot's RGBA decode of the PNG and index -> palette.
func compare_sheet(path: String) -> bool:
	var png := FileAccess.get_file_as_bytes(path)
	var decoded := PaletteSheet.decode(png)
	if decoded.is_empty():
		print("  not a palette sheet: ",path);return false
	var godot := Image.new()
	godot.load_png_from_buffer(png)
	godot.convert(Image.FORMAT_RGBA8)
	var mine := PaletteSheet.to_rgba(decoded)
	if mine.get_data()!=godot.get_data():
		print("  differs from Godot's decode: ",path);return false
	# The imported texture (fix_alpha_border recolours hidden pixels) shows
	# the same visible pixels.
	var imported: Image = load(path).get_image()
	imported.convert(Image.FORMAT_RGBA8)
	var a := imported.get_data()
	var b := mine.get_data()
	if a.size()!=b.size():
		print("  imported size differs: ",path);return false
	for i in range(0,a.size(),4):
		if a[i+3]!=b[i+3] or (b[i+3]!=0 and (a[i]!=b[i] or a[i+1]!=b[i+1] or a[i+2]!=b[i+2])):
			print("  imported pixel %d differs: %s" % [i/4,path]);return false
	return true

func run() -> void:
	var all := {}
	for folder in FOLDERS:all[folder] = sheets(folder)
	# Samples: the smallest sheets of each folder (the CPU decode is slow in
	# GDScript) plus a mid-sized one.
	for folder in FOLDERS:
		var files: PackedStringArray = all[folder]
		var by_area := Array(files)
		by_area.sort_custom(func(a,b):var sa := png_size(a);var sb := png_size(b);return sa.x*sa.y < sb.x*sb.y)
		var samples: Array = by_area.slice(0,3)
		if by_area.size() > 3:samples.append(by_area[by_area.size()/3])
		var ok := not samples.is_empty()
		for path in samples:ok = compare_sheet(path) and ok
		check(ok,"%s: index -> palette reproduces Godot's RGBA decode byte for byte (%d sheets)" % [folder,samples.size()])
	# The textures: R8 indices of the sheet's size, a 256x1 palette.
	var sample: String = all[FOLDERS[0]][0]
	var decoded := PaletteSheet.decode(FileAccess.get_file_as_bytes(sample))
	var indices: Image = decoded.indices
	var texture := PaletteSheet.load_texture(sample)
	var image := texture.get_image()
	var material := PaletteSheet.material_of(texture)
	var palette: Image = material.get_shader_parameter("palette").get_image()
	check(image.get_format()==Image.FORMAT_R8 and image.get_size()==indices.get_size() and image.get_data()==indices.get_data(),"the index texture is R8 at the sheet's size, holding its indices")
	check(palette.get_size()==Vector2i(256,1) and palette.get_format()==Image.FORMAT_RGBA8 and palette.get_data()==decoded.palette and material.shader==PaletteSheet.shader(),"the sheet's material holds its 256 colours as RGBA")
	var frame := AtlasTexture.new()
	frame.atlas = texture
	check(PaletteSheet.is_palette(texture) and PaletteSheet.material_of(frame)==material and not PaletteSheet.is_palette(load(sample)),"a palette sheet and its frames know their material; imported textures have none")
	var sprite := Sprite2D.new()
	PaletteSheet.apply(sprite,frame)
	var given := sprite.material
	PaletteSheet.apply(sprite,load(sample))
	check(given==material and sprite.material==null,"apply gives the sheet's material only while a palette texture is shown")
	sprite.free()
	# The setting: only the listed kinds.
	check(PaletteSheet.kinds()==PackedStringArray(ON),"%s lists %s" % [PaletteSheet.SETTING,ON])
	PaletteSheet.set_kinds([])
	check(not PaletteSheet.wanted(sample) and PaletteSheet.kind_of(sample)=="battle","an empty setting turns palette sheets off")
	check(not PaletteSheet.is_palette(SheetFrames.sheet(sample)),"off, SheetFrames loads the imported RGBA sheet")
	var plain := PaletteSheet.picture(sample)
	check(plain!=null and plain.get_size()==indices.get_size(),"off, a sheet's picture is read from the imported texture")
	SheetFrames._sheets.clear()
	PaletteSheet.set_kinds(["battle"])
	check(PaletteSheet.wanted(sample) and not PaletteSheet.wanted(all[FOLDERS[1]][0]) and not PaletteSheet.wanted("res://assets/legacy/battle/images/1.png") and not PaletteSheet.wanted(sample+".import"),"a listed kind turns on its sheets only")
	var region := SheetFrames.region(sample,Rect2i(0,0,8,8))
	check(PaletteSheet.is_palette(region) and region.atlas.get_size()==Vector2(indices.get_size()) and not PaletteSheet.is_palette(SheetFrames.sheet(all[FOLDERS[1]][0])),"on, SheetFrames cuts frames from the palette sheet; other kinds stay RGBA")
	var expanded := Image.new()
	expanded.load_png_from_buffer(FileAccess.get_file_as_bytes(sample))
	expanded.convert(Image.FORMAT_RGBA8)
	check(PaletteSheet.picture(sample).get_data()==expanded.get_data() and PaletteSheet.exists(sample) and not PaletteSheet.exists(ROOT+"battle/sheets/missing.png"),"on, a sheet's picture and presence come from its PNG")
	# The player's switch off: the old RGBA textures, also where only the PNG
	# is here (a web pack of an enabled kind).
	SheetFrames.flush()
	PaletteSheet.user_on = false
	var rgba_sheet := SheetFrames.sheet(sample)
	check(PaletteSheet.wanted(sample) and not PaletteSheet.draws(sample) and not PaletteSheet.is_palette(rgba_sheet) and rgba_sheet.get_size()==Vector2(indices.get_size()),"switched off, an enabled kind draws its imported RGBA sheet")
	var copy := "user://palette-sheet-test-copy.png"
	var out := FileAccess.open(copy,FileAccess.WRITE)
	out.store_buffer(FileAccess.get_file_as_bytes(sample))
	out.close()
	var from_png := PaletteSheet.load_any(copy)
	var from_png_image := from_png.get_image()
	from_png_image.convert(Image.FORMAT_RGBA8)
	check(not PaletteSheet.is_palette(from_png) and from_png_image.get_data()==expanded.get_data(),"without an imported copy, an RGBA texture is decoded from the PNG")
	PaletteSheet.user_on = true
	SheetFrames.flush()
	PaletteSheet.set_kinds(null)
	check(PaletteSheet.load_texture(ROOT+"battle/sheets/missing.png")==null,"a missing sheet loads as null")
	# Map tiles share one palette (tools/palette_images.py), so one material.
	var tiles: PackedStringArray = all["images"]
	var shared := {}
	for path in tiles.slice(0,40):
		shared[PaletteSheet.material_of(PaletteSheet.load_texture(path))] = true
	check(shared.size()==1 and not shared.has(null),"map tiles share one palette material (%d sampled)" % mini(40,tiles.size()))
	check(PaletteSheet.ships_png(tiles[0]) and PaletteSheet.ships_png(sample) and not PaletteSheet.ships_png(ROOT+"faces/missing.png"),"web packs ship palette PNGs of enabled kinds")
	var rgba_path := "user://palette-sheet-test-rgba.png"
	Image.create(2,2,false,Image.FORMAT_RGBA8).save_png(rgba_path)
	check(not PaletteSheet.is_palette_png(rgba_path) and PaletteSheet.is_palette_png(tiles[0]),"an RGBA PNG is not shipped as a palette PNG")
	# Not palette PNGs: RGBA and greyscale stay out.
	var rgba := Image.create(4,4,false,Image.FORMAT_RGBA8)
	var grey := Image.create(4,4,false,Image.FORMAT_L8)
	check(PaletteSheet.decode(rgba.save_png_to_buffer()).is_empty() and PaletteSheet.decode(grey.save_png_to_buffer()).is_empty() and PaletteSheet.decode(PackedByteArray([1,2,3])).is_empty(),"RGBA, greyscale and broken PNGs are refused")
	# Expected video memory of every sheet.
	for folder in FOLDERS:
		var rgba_bytes := 0
		var palette_bytes := 0
		var largest := 0
		for path in all[folder]:
			var size := png_size(path)
			var vram := PaletteSheet.vram_bytes(size.x,size.y)
			rgba_bytes += vram.rgba
			palette_bytes += vram.palette
			largest = maxi(largest,vram.rgba)
		print("VRAM %s: %d sheets, RGBA %.1f MB -> palette %.1f MB (%.1f MB average -> %.1f MB, largest %.1f MB)" % [folder,all[folder].size(),rgba_bytes/1e6,palette_bytes/1e6,rgba_bytes/1e6/maxi(1,all[folder].size()),palette_bytes/1e6/maxi(1,all[folder].size()),largest/1e6])
	print("palette_sheet_test: %d failures" % failures)
	quit(1 if failures else 0)
