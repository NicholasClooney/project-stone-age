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

static var _owners: Dictionary = {}

## The frame for a caller that knows only the bitmap: each bitmap belongs to
## one sheet key per folder (the importers check this), found through an
## index built once per folder.
static func bitmap_texture(folder: String, sheets: Dictionary, bitmap: int) -> Texture2D:
	return texture(folder,sheets,owner(folder,sheets,bitmap),bitmap)

static func owner(folder: String, sheets: Dictionary, bitmap: int) -> String:
	if not _owners.has(folder):
		var index := {}
		for key in sheets:
			for id in sheets[key].get("frames",{}):index[id] = key
		_owners[folder] = index
	return str(_owners[folder].get(str(bitmap),""))

## Whether the frame's sheet is in the project (or a mounted web pack).
static func available(folder: String, sheets: Dictionary, key: String, bitmap: int) -> bool:
	var sheet: Dictionary = sheets.get(key,{})
	var spot: Array = sheet.get("frames",{}).get(str(bitmap),[])
	return spot.size() >= 5 and ResourceLoader.exists(folder+str(sheet.files[int(spot[0])]))
