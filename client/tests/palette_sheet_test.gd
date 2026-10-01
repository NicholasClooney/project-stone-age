extends SceneTree
## Palette sheets (scripts/palette_sheet.gd, docs/technical/palette-textures.md):
## indices plus palette reproduce Godot's own RGBA decode of each sample
## sheet byte for byte and the imported texture's visible pixels, the
## textures and material are laid out as the shader expects, the setting is
## off by default, and the expected video memory of every sheet is reported.
## The shader itself is checked on a GPU by tools/palette_web_check.py.
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const ROOT := "res://assets/legacy/"
const FOLDERS := ["battle/sheets","riding/sheets","characters/sheets"]
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
	# The setting: off unless a kind is listed.
	check(PaletteSheet.kinds().is_empty() and not PaletteSheet.wanted(sample),"palette sheets are off by default (%s is empty)" % PaletteSheet.SETTING)
	PaletteSheet.set_kinds(["battle"])
	check(PaletteSheet.wanted(sample) and PaletteSheet.kind_of(sample)=="battle" and not PaletteSheet.wanted(all[FOLDERS[1]][0]) and not PaletteSheet.wanted("res://assets/legacy/battle/images/1.png") and not PaletteSheet.wanted(sample+".import"),"a listed kind turns on its sheets only")
	PaletteSheet.set_kinds(null)
	check(PaletteSheet.load_texture("res://assets/legacy/battle/sheets/missing.png")==null,"a missing sheet loads as null")
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
