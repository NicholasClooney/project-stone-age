extends RefCounted
## Frames cut from imported sprite sheets (docs/technical/sprite-sheets.md,
## tools/sprite_sheets.py). Battle sprites, riding composites and player
## characters keep their frame rectangles in their own sprite files
## (scripts/sprite_art.gd), which call region(). The faces manifest's `sheets`
## maps a key to {files, frames: bitmap -> [sheet, x, y, w, h]}, read by
## texture(); file names are relative to the manifest's folder.

const PerfRegistry = preload("res://scripts/perf_registry.gd")
const PaletteSheet = preload("res://scripts/palette_sheet.gd")

## The sheets used most recently, at most SHEETS of them (a sheet is about
## 10 MB as RGBA). An older one is let go here; it stays alive only while a
## sprite still on screen (its art entry's frames) holds it, so a long hunt
## across many species no longer keeps every sheet it ever drew.
const SHEETS := 24
static var _sheets: Dictionary = {}
static var _frames: Dictionary = {}

## The sheet texture, or null when it is not available yet (a web pack still
## downloading).
static func sheet(path: String) -> Texture2D:
	var atlas: Texture2D = _sheets.get(path)
	if atlas != null:
		# Most recently used last.
		_sheets.erase(path)
		_sheets[path] = atlas
		return atlas
	# A palette sheet (scripts/palette_sheet.gd) when they are on for this
	# kind of art: one byte a pixel; nodes drawing it take its material.
	if PaletteSheet.wanted(path):atlas = PaletteSheet.load_texture(path)
	if atlas == null:
		if not ResourceLoader.exists(path): return null
		atlas = load(path)
	_sheets[path] = atlas
	PerfRegistry.track_texture(PerfRegistry.folder_category(path.get_base_dir()+"/"),path,atlas)
	while _sheets.size() > SHEETS:_sheets.erase(_sheets.keys()[0])
	return atlas

static func held() -> int:
	return _sheets.size()

## A new AtlasTexture of the sheet's rectangle, or null when the sheet is not
## available yet. The caller caches it.
static func region(path: String, rect: Rect2i) -> Texture2D:
	var atlas := sheet(path)
	if atlas == null: return null
	var frame := AtlasTexture.new()
	frame.atlas = atlas
	frame.region = Rect2(rect)
	return frame

## The frame as an AtlasTexture of its sheet, or null when the sheet is not
## available yet; nothing is cached then.
static func texture(folder: String, sheets: Dictionary, key: String, bitmap: int) -> Texture2D:
	var cache_key := folder+key+":"+str(bitmap)
	var cached: Texture2D = _frames.get(cache_key)
	if cached != null: return cached
	var entry: Dictionary = sheets.get(key,{})
	var spot: Array = entry.get("frames",{}).get(str(bitmap),[])
	if spot.size() < 5: return null
	var frame := region(folder+str(entry.files[int(spot[0])]),Rect2i(int(spot[1]),int(spot[2]),int(spot[3]),int(spot[4])))
	if frame != null: _frames[cache_key] = frame
	return frame
