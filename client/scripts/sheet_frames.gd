extends RefCounted
## Frames cut from imported sprite sheets (docs/technical/sprite-sheets.md,
## tools/sprite_sheets.py). A manifest's `sheets` maps a key (a riding
## composite, a battle sprite, a character) to {files, frames: bitmap ->
## [sheet, x, y, w, h]}; file names are relative to the manifest's folder.

static var _sheets: Dictionary = {}
static var _frames: Dictionary = {}

## The frame as an AtlasTexture of its sheet, or null when the sheet is not
## available yet (a web pack still downloading); nothing is cached then.
static func texture(folder: String, sheets: Dictionary, key: String, bitmap: int) -> Texture2D:
	var cache_key := folder+key+":"+str(bitmap)
	var cached: Texture2D = _frames.get(cache_key)
	if cached != null: return cached
	var sheet: Dictionary = sheets.get(key,{})
	var spot: Array = sheet.get("frames",{}).get(str(bitmap),[])
	if spot.size() < 5: return null
	var path: String = folder+str(sheet.files[int(spot[0])])
	var atlas: Texture2D = _sheets.get(path)
	if atlas == null:
		if not ResourceLoader.exists(path): return null
		atlas = load(path)
		_sheets[path] = atlas
	var frame := AtlasTexture.new()
	frame.atlas = atlas
	frame.region = Rect2(int(spot[1]),int(spot[2]),int(spot[3]),int(spot[4]))
	_frames[cache_key] = frame
	return frame

## Which sheet key holds bitmap, for callers that only know the bitmap.
static func owner(sheets: Dictionary, bitmap: int, prefer: String = "") -> String:
	var id := str(bitmap)
	if not prefer.is_empty() and sheets.get(prefer,{}).get("frames",{}).has(id): return prefer
	for key in sheets:
		if sheets[key].get("frames",{}).has(id): return key
	return ""
