extends RefCounted
## Whether original battle art exists for a troop. The authority skips troops it
## cannot present on any client, so the decision must not depend on what one
## client has downloaded; it reads the full asset set next to the backend.
const ART_ROOT := "res://assets/legacy/battle/"
static var _manifest: Dictionary = {}
static var _validation: Dictionary = {}

static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(ART_ROOT+"manifest.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ART_ROOT+"manifest.json"))
		if parsed is Dictionary:_manifest = parsed
	return _manifest

static func can_render(enemies: Array) -> bool:
	if enemies.is_empty() or enemies.size()>10:return false
	for enemy in enemies:
		var ident := str(enemy.get("sprite",-1))
		if not _validation.has(ident):_validation[ident] = _valid(ident)
		if not _validation[ident]:return false
	return true

static func _valid(ident: String) -> bool:
	var data := manifest()
	var valid: bool = data.get("characters",{}).has(ident)
	var animations: Dictionary = data.get("characters",{}).get(ident,{})
	for action in [0,1,2,3,4,10]:
		for direction in range(8):
			var frames: Array = animations.get("%d_%d" % [action,direction],{}).get("frames",[])
			if frames.is_empty():valid = false
			for frame in frames:
				var bitmap := str(int(frame.image))
				if not data.get("images",{}).has(bitmap) or not ResourceLoader.exists(ART_ROOT+"images/%s.png" % bitmap):valid = false
	return valid
