extends RefCounted
## Frames cut from imported sprite sheets (docs/technical/sprite-sheets.md,
## tools/sprite_sheets.py). Battle sprites, riding composites and player
## characters keep their frame rectangles in their own sprite files
## (scripts/sprite_art.gd), which call region(). The faces manifest's `sheets`
## maps a key to {files, frames: bitmap -> [sheet, x, y, w, h]}, read by
## texture(); file names are relative to the manifest's folder.

const PerfRegistry = preload("res://scripts/perf_registry.gd")

static var _sheets: Dictionary = {}
static var _frames: Dictionary = {}

## The sheet texture, loaded once, or null when it is not available yet (a
## web pack still downloading).
static func sheet(path: String) -> Texture2D:
	var atlas: Texture2D = _sheets.get(path)
	if atlas == null:
		if not ResourceLoader.exists(path): return null
		atlas = load(path)
		_sheets[path] = atlas
		PerfRegistry.track_texture(PerfRegistry.folder_category(path.get_base_dir()+"/"),path,atlas)
	return atlas

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
