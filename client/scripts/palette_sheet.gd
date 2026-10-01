extends RefCounted
## Palette sheets: an 8-bit palette PNG (tools/sprite_sheets.py to_palette)
## kept as one byte a pixel on the GPU instead of four. See
## docs/technical/palette-textures.md.
##
## A sheet becomes two textures: its palette indices as a FORMAT_R8 texture
## of the sheet's own size, and its 256 colours as a 256x1 RGBA8 texture.
## The sheet's material (SHADER_CODE with that palette) looks each pixel's
## colour up. The index texture has the sheet's exact size, so an
## AtlasTexture of it cuts frames exactly as before and the GPU's nearest
## sampling picks the same texel it picks in the RGBA sheet.
##
## Decoding: the PNG's pixel data (IDAT) of a palette image is the same
## bytes as a greyscale image of its indices, so decode() rewrites the header
## to greyscale, drops PLTE and tRNS, and lets Godot's PNG decoder do the
## rest. The palette comes from PLTE (colours) and tRNS (alpha, 255 past its
## end), as libpng reads them when it expands the image to RGBA.

const PALETTE_BYTES := 1024
const _SIGNATURE := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

## Project setting naming the kinds of art drawn from palette sheets
## (PackedStringArray of KINDS keys). Empty, or missing, draws all art from
## Godot's imported RGBA textures as before. tools/build_web_packs.gd reads
## it too: a kind listed here ships its sheets' PNG files as they are instead
## of the imported RGBA copy.
const SETTING := "stone_age/rendering/palette_sheets"
## Kind -> folder under res://assets/legacy/ holding its sheets.
const KINDS := {
	"battle":"battle/sheets/",
	"riding":"riding/sheets/",
	"characters":"characters/sheets/",
	# Map tiles and props, and the walking frames maps draw: one shared
	# palette (tools/palette_images.py), so one material draws them all.
	"tiles":"images/",
}
const LEGACY := "res://assets/legacy/"

const SHADER_CODE := """
shader_type canvas_item;
// Palette sheet (scripts/palette_sheet.gd): TEXTURE holds R8 palette indices,
// palette the sheet's 256 colours. The node samples TEXTURE as it would the
// RGBA sheet (nearest), so the same texel is chosen. COLOR in fragment() is
// already that sample times the vertex colour, so the vertex colour
// (modulate) is carried over on its own.
uniform sampler2D palette : filter_nearest;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	int entry = int(texture(TEXTURE, UV).r * 255.0 + 0.5);
	COLOR = texelFetch(palette, ivec2(entry, 0), 0) * tint;
}
"""

## The kinds palette sheets are on for (the setting, or an override).
static var _kinds: Variant = null
## The player's switch (设置 → 画面 → 调色板贴图, this device's viewer.cfg).
## Off draws every sheet from RGBA textures as before the palette sheets:
## the imported texture, or on the web, where a pack holds only the PNG, an
## RGBA texture decoded from it.
static var user_on := true
static var _shader: Shader
## Palette bytes -> material, so sheets with the same palette (all map tiles)
## share one material and a node can draw several of them.
static var _materials: Dictionary = {}

## Overrides the setting for this run (tests); null goes back to it.
static func set_kinds(kinds: Variant) -> void:
	_kinds = kinds

static func kinds() -> PackedStringArray:
	if _kinds != null:return PackedStringArray(_kinds)
	return PackedStringArray(ProjectSettings.get_setting(SETTING,PackedStringArray()))

## The kind of art a sheet path belongs to, or "" for any other file.
static func kind_of(path: String) -> String:
	for kind in KINDS:
		var folder: String = LEGACY+KINDS[kind]
		if path.begins_with(folder) and path.get_extension()=="png" and not path.substr(folder.length()).contains("/"):return kind
	return ""

## Whether the project uses palette sheets for this kind of art (so a web
## pack holds the sheet as its PNG).
static func wanted(path: String) -> bool:
	var kind := kind_of(path)
	return not kind.is_empty() and kinds().has(kind)

## Whether the sheet at path is drawn from its palette PNG right now.
static func draws(path: String) -> bool:
	return user_on and wanted(path)

static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader

## The material that draws a sheet with this palette (1024 bytes, RGBA of
## entries 0..255), one per distinct palette.
static func material_for(palette: PackedByteArray) -> ShaderMaterial:
	var known: ShaderMaterial = _materials.get(palette)
	if known != null:return known
	var material := ShaderMaterial.new()
	material.shader = shader()
	var image := Image.create_from_data(256,1,false,Image.FORMAT_RGBA8,palette)
	material.set_shader_parameter("palette",ImageTexture.create_from_image(image))
	_materials[palette] = material
	return material

## {"indices": Image (FORMAT_L8), "palette": PackedByteArray (1024 bytes,
## RGBA per entry)} of an 8-bit palette PNG, or {} when it is anything else.
static func decode(png: PackedByteArray) -> Dictionary:
	if png.size() < 33:return {}
	for i in range(8):
		if png[i] != _SIGNATURE[i]:return {}
	var palette := PackedByteArray()
	palette.resize(PALETTE_BYTES)
	for i in range(256):palette[i*4+3] = 255
	var out := PackedByteArray(png.slice(0,8))
	var at := 8
	var header_ok := false
	while at + 12 <= png.size():
		var length := _u32(png,at)
		var kind := png.slice(at+4,at+8).get_string_from_ascii()
		var end := at + 12 + length
		if end > png.size():return {}
		var data := png.slice(at+8,at+8+length)
		match kind:
			"IHDR":
				# Bit depth 8, colour type 3 (palette) only; other depths would
				# be scaled as greyscale.
				if length != 13 or data[8] != 8 or data[9] != 3:return {}
				data[9] = 0
				_chunk(out,kind,data)
				header_ok = true
			"PLTE":
				for i in range(mini(length/3,256)):
					palette[i*4] = data[i*3]
					palette[i*4+1] = data[i*3+1]
					palette[i*4+2] = data[i*3+2]
			"tRNS":
				for i in range(mini(length,256)):palette[i*4+3] = data[i]
			_:
				out.append_array(png.slice(at,end))
		at = end
	if not header_ok:return {}
	var image := Image.new()
	if image.load_png_from_buffer(out) != OK or image.get_format() != Image.FORMAT_L8:return {}
	return {"indices":image,"palette":palette}

## The index texture of a decoded sheet (FORMAT_R8, the sheet's size). Its
## meta "palette_material" is the material that draws it.
static func texture_of(decoded: Dictionary) -> ImageTexture:
	var indices: Image = decoded.indices
	var image := Image.create_from_data(indices.get_width(),indices.get_height(),false,Image.FORMAT_R8,indices.get_data())
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta("palette_material",material_for(decoded.palette))
	return texture

## The sheet at path as a palette texture, or null when the file is missing
## or not an 8-bit palette PNG.
static func load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):return null
	var decoded := decode(FileAccess.get_file_as_bytes(path))
	if decoded.is_empty():return null
	return texture_of(decoded)

## The texture at path: its palette texture when palette sheets are on for
## it (and the player's switch is on) and it is a palette PNG, else the
## imported texture, else an RGBA texture decoded from the PNG; null when
## none is here (a web pack still downloading).
static func load_any(path: String) -> Texture2D:
	if draws(path):
		var texture := load_texture(path)
		if texture != null:return texture
	if ResourceLoader.exists(path):return load(path)
	return load_rgba(path)

## An RGBA texture decoded from the PNG at path (a web pack holds only the
## PNG of an enabled kind), or null when the file is not here.
static func load_rgba(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:return null
	image.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(image)

## Whether the sheet at path can be drawn: its PNG when palette sheets are on
## for it (a web pack then holds only the PNG), else the imported texture.
static func exists(path: String) -> bool:
	return (wanted(path) and FileAccess.file_exists(path)) or ResourceLoader.exists(path)

## Whether the file at path is an 8-bit palette PNG (from its header).
static func is_palette_png(path: String) -> bool:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:return false
	var header := file.get_buffer(26)
	if header.size() < 26:return false
	for i in range(8):
		if header[i] != _SIGNATURE[i]:return false
	return header[24] == 8 and header[25] == 3

## Whether a web pack ships the file as its PNG instead of the imported
## RGBA copy: palette sheets are on for it and it is a palette PNG. An image
## not converted yet keeps its imported copy, and load_any() draws it.
static func ships_png(path: String) -> bool:
	return wanted(path) and is_palette_png(path)

## The sheet's pixels as an RGBA picture on the CPU (thumbnails cut from it),
## or null when it is not here.
static func picture(path: String) -> Image:
	if wanted(path):
		if not FileAccess.file_exists(path):return null
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:return null
		image.convert(Image.FORMAT_RGBA8)
		return image
	if not ResourceLoader.exists(path):return null
	var sheet: Texture2D = load(path)
	return sheet.get_image() if sheet != null else null

## The material a texture (a palette sheet or an AtlasTexture of one) is
## drawn with, or null for any other texture.
static func material_of(texture: Texture2D) -> Material:
	if texture is AtlasTexture:texture = texture.atlas
	if texture == null or not texture.has_meta("palette_material"):return null
	return texture.get_meta("palette_material")

static func is_palette(texture: Texture2D) -> bool:
	return material_of(texture) != null

## Gives a node its sheet's material while it shows a palette texture, and
## takes it away again for any other texture. The node must sample nearest,
## as every sprite node does.
static func apply(item: CanvasItem, texture: Texture2D) -> void:
	var material := material_of(texture)
	if item.material != material:item.material = material

## What the shader draws, on the CPU: the RGBA8 picture of a decoded sheet.
## Tests compare it with Godot's own RGBA decode of the PNG.
static func to_rgba(decoded: Dictionary) -> Image:
	var indices: Image = decoded.indices
	var source := indices.get_data()
	var palette: PackedByteArray = decoded.palette
	var data := PackedByteArray()
	data.resize(source.size()*4)
	for i in range(source.size()):
		var entry := source[i]*4
		data[i*4] = palette[entry]
		data[i*4+1] = palette[entry+1]
		data[i*4+2] = palette[entry+2]
		data[i*4+3] = palette[entry+3]
	return Image.create_from_data(indices.get_width(),indices.get_height(),false,Image.FORMAT_RGBA8,data)

## Bytes a sheet of this size takes as RGBA8 and as a palette texture.
static func vram_bytes(width: int, height: int) -> Dictionary:
	return {"rgba":width*height*4,"palette":width*height+PALETTE_BYTES}

static func _u32(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at]<<24)|(bytes[at+1]<<16)|(bytes[at+2]<<8)|bytes[at+3]

static func _chunk(out: PackedByteArray, kind: String, data: PackedByteArray) -> void:
	var body := kind.to_ascii_buffer()
	body.append_array(data)
	var length := data.size()
	out.append_array(PackedByteArray([(length>>24)&255,(length>>16)&255,(length>>8)&255,length&255]))
	out.append_array(body)
	var crc := _crc32(body)
	out.append_array(PackedByteArray([(crc>>24)&255,(crc>>16)&255,(crc>>8)&255,crc&255]))

static func _crc32(bytes: PackedByteArray) -> int:
	var crc := 0xFFFFFFFF
	for b in bytes:
		crc ^= b
		for k in range(8):
			crc = (crc>>1)^0xEDB88320 if crc & 1 else crc>>1
	return crc ^ 0xFFFFFFFF
