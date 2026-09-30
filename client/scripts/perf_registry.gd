extends RefCounted
## Who owns the memory: loaders report the textures, audio streams and parsed
## manifests they create, and 开发者性能面板 (scripts/perf_panel.gd) asks for
## the totals. A report is one dictionary insert holding a weak reference, so
## loaders pay almost nothing and nothing is scanned per frame; a texture or
## stream that Godot frees drops out the next time summary() runs. Sizes are
## worked out lazily, once, the first time a summary needs them.
##
## Texture bytes are estimates: width × height × bytes per pixel of the GPU
## format (RGBA8 unless the renderer or the texture says otherwise). Audio bytes are the stream's encoded data held in
## memory. Manifest bytes are the JSON text size; the parsed Dictionary is
## several times larger. See docs/technical/perf-panel.md.

## [key, caption] in display order.
const TEXTURES := [["battle","战斗图集"],["riding","骑乘图集"],["map","地图图块"],["characters","人物图集"],["faces","人物面部"],["thumbnails","宠物缩略图"],["ui","界面"],["other","其他"]]
const AUDIO := [["music","音乐"],["radio","电台"],["effects","音效"]]

## category -> {key -> {"ref": WeakRef, "bytes": int (-1 until measured), "seconds": float}}
static var _textures: Dictionary = {}
static var _audio: Dictionary = {}
## name -> JSON text bytes.
static var _manifests: Dictionary = {}

static func reset() -> void:
	_textures.clear()
	_audio.clear()
	_manifests.clear()

static func caption(category: String) -> String:
	for entry in TEXTURES+AUDIO:
		if entry[0]==category:return entry[1]
	return category

## The texture category of a sheet folder (scripts/sheet_frames.gd).
static func folder_category(folder: String) -> String:
	for part in ["riding","characters","faces","battle"]:
		if folder.contains("/"+part+"/"):return part
	return "other"

# ---- reports from loaders ----------------------------------------------------

static func track_texture(category: String, key: Variant, texture: Texture2D) -> void:
	if texture==null:return
	if not _textures.has(category):_textures[category] = {}
	_textures[category][str(key)] = {"ref":weakref(texture),"bytes":-1}

static func track_audio(category: String, key: Variant, stream: AudioStream) -> void:
	if stream==null:return
	if not _audio.has(category):_audio[category] = {}
	_audio[category][str(key)] = {"ref":weakref(stream),"bytes":-1,"seconds":0.0}

static func track_manifest(name: String, bytes: int) -> void:
	_manifests[name] = bytes

static func forget(category: String, key: Variant) -> void:
	if _textures.has(category):_textures[category].erase(str(key))
	if _audio.has(category):_audio[category].erase(str(key))

# ---- sizes -------------------------------------------------------------------

## Bytes per pixel of an Image.Format (block-compressed formats averaged).
static func bytes_per_pixel(format: int) -> float:
	match format:
		Image.FORMAT_L8,Image.FORMAT_R8:return 1.0
		Image.FORMAT_LA8,Image.FORMAT_RG8,Image.FORMAT_RGB565,Image.FORMAT_RGBA4444,Image.FORMAT_RH:return 2.0
		Image.FORMAT_RGB8:return 3.0
		Image.FORMAT_RGBA8,Image.FORMAT_RF,Image.FORMAT_RGH,Image.FORMAT_RGBE9995:return 4.0
		Image.FORMAT_RGBH:return 6.0
		Image.FORMAT_RGF,Image.FORMAT_RGBAH:return 8.0
		Image.FORMAT_RGBF:return 12.0
		Image.FORMAT_RGBAF:return 16.0
		Image.FORMAT_DXT1,Image.FORMAT_RGTC_R,Image.FORMAT_ETC,Image.FORMAT_ETC2_R11,Image.FORMAT_ETC2_R11S,Image.FORMAT_ETC2_RGB8,Image.FORMAT_ETC2_RGB8A1:return 0.5
		Image.FORMAT_DXT3,Image.FORMAT_DXT5,Image.FORMAT_RGTC_RG,Image.FORMAT_BPTC_RGBA,Image.FORMAT_BPTC_RGBF,Image.FORMAT_BPTC_RGBFU,Image.FORMAT_ETC2_RG11,Image.FORMAT_ETC2_RG11S,Image.FORMAT_ETC2_RGBA8,Image.FORMAT_ETC2_RA_AS_RG,Image.FORMAT_DXT5_RA_AS_RG,Image.FORMAT_ASTC_4x4,Image.FORMAT_ASTC_4x4_HDR:return 1.0
		Image.FORMAT_ASTC_8x8,Image.FORMAT_ASTC_8x8_HDR:return 0.25
	return 4.0

static func texture_bytes(width: int, height: int, format: int, mipmaps: bool = false) -> int:
	var base := float(width)*height*bytes_per_pixel(format)
	return int(base*4.0/3.0 if mipmaps else base)

## The GPU format of a texture: an ImageTexture knows it; others ask the
## renderer, which a headless run does not have (RGBA8 then).
static func texture_format(texture: Texture2D) -> int:
	if texture is ImageTexture:return (texture as ImageTexture).get_format()
	if DisplayServer.get_name()!="headless" and texture.get_rid().is_valid():
		return RenderingServer.texture_get_format(texture.get_rid())
	return Image.FORMAT_RGBA8

## The imports keep mipmaps off (mipmaps/generate=false), so none are counted.
static func measure_texture(texture: Texture2D) -> int:
	return texture_bytes(texture.get_width(),texture.get_height(),texture_format(texture))

## Encoded bytes a stream keeps in memory (WAV/QOA and MP3 data, Ogg packets).
static func audio_bytes(stream: AudioStream) -> int:
	if stream is AudioStreamWAV:return (stream as AudioStreamWAV).data.size()
	if stream is AudioStreamMP3:return (stream as AudioStreamMP3).data.size()
	if stream is AudioStreamOggVorbis:
		var sequence: OggPacketSequence = (stream as AudioStreamOggVorbis).packet_sequence
		if sequence==null:return 0
		var total := 0
		for page in sequence.packet_data:
			for packet in page:total += (packet as PackedByteArray).size()
		return total
	return 0

# ---- totals ------------------------------------------------------------------

## {"textures": {category: {count, bytes}}, "audio": {category: {count, bytes,
## seconds}}, "manifests": {name: bytes}, "texture_bytes", "audio_bytes",
## "manifest_bytes"}. Freed resources are dropped here.
static func summary() -> Dictionary:
	var textures := {}
	var texture_total := 0
	for category in _textures:
		var totals := _totals(_textures[category],false)
		if totals.count==0:continue
		textures[category] = totals
		texture_total += int(totals.bytes)
	var audio := {}
	var audio_total := 0
	for category in _audio:
		var totals := _totals(_audio[category],true)
		if totals.count==0:continue
		audio[category] = totals
		audio_total += int(totals.bytes)
	var manifest_total := 0
	for name in _manifests:manifest_total += int(_manifests[name])
	return {"textures":textures,"audio":audio,"manifests":_manifests.duplicate(),"texture_bytes":texture_total,"audio_bytes":audio_total,"manifest_bytes":manifest_total}

static func _totals(entries: Dictionary, is_audio: bool) -> Dictionary:
	var count := 0
	var bytes := 0
	var seconds := 0.0
	for key in entries.keys():
		var entry: Dictionary = entries[key]
		var resource = entry.ref.get_ref()
		if resource==null:
			entries.erase(key)
			continue
		if int(entry.bytes)<0:
			if is_audio:
				entry.bytes = audio_bytes(resource)
				entry.seconds = resource.get_length()
			else:entry.bytes = measure_texture(resource)
		count += 1
		bytes += int(entry.bytes)
		if is_audio:seconds += float(entry.seconds)
	var result := {"count":count,"bytes":bytes}
	if is_audio:result.seconds = snappedf(seconds,0.1)
	return result

## The largest live textures, [{category, key, bytes, size}], for snapshots.
static func largest_textures(limit: int = 10) -> Array:
	var rows: Array = []
	for category in _textures:
		for key in _textures[category]:
			var entry: Dictionary = _textures[category][key]
			var texture = entry.ref.get_ref()
			if texture==null:continue
			if int(entry.bytes)<0:entry.bytes = measure_texture(texture)
			rows.append({"category":category,"key":key,"bytes":int(entry.bytes),"size":[texture.get_width(),texture.get_height()]})
	rows.sort_custom(func(a,b): return a.bytes>b.bytes)
	return rows.slice(0,limit)
