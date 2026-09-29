extends RefCounted
## 人物面部: the classic character faces tools/import_faces.py imports. The
## original face graphic is 30000 + family * 100 + colour * 25 + eye * 5 +
## mouth (client login.cpp:3401); the profile keeps `face` = eye * 5 + mouth
## and the appearance gives family and colour. One sheet per appearance.
const ROOT := "res://assets/legacy/faces/"
const SheetFrames = preload("res://scripts/sheet_frames.gd")
static var _manifest: Dictionary = {}
static var _loaded := false

static func manifest() -> Dictionary:
	if not _loaded:
		_loaded = true
		var path := ROOT+"manifest.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:_manifest = parsed
	return _manifest

## The face graphic number, or -1 when that appearance has no imported faces.
static func number(character_id: String, face: int) -> int:
	var info: Dictionary = manifest().get("characters",{}).get(character_id,{})
	if info.is_empty():return -1
	return int(info.base)+clampi(face,0,24)

## The face as a texture, or null (faces not imported, or a web pack loading).
static func texture(character_id: String, face: int) -> Texture2D:
	var graphic := number(character_id,face)
	if graphic < 0:return null
	return SheetFrames.texture(ROOT,manifest().get("sheets",{}),character_id,graphic)

## ADRN draw offset of the face (-32, -36): the original draws it centred.
static func offset(character_id: String, face: int) -> Vector2:
	var info: Dictionary = manifest().get("images",{}).get(str(number(character_id,face)),{})
	return Vector2(float(info.get("x",-32)),float(info.get("y",-36)))
