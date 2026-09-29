extends RefCounted
## Whether original battle art exists for a troop. The authority skips troops it
## cannot present on any client, so the decision must not depend on what one
## client has downloaded; it reads the full asset set next to the backend.
const ART_ROOT := "res://assets/legacy/battle/"
const BattleArt = preload("res://scripts/battle_art.gd")
static var _validation: Dictionary = {}
## Set by a client that downloads art on demand: sprite id -> pack. A sprite
## then counts as renderable when its animations are complete and a pack
## exists, since the frames arrive before the battle is shown.
static var pack_index: Dictionary = {}

static func manifest() -> Dictionary:
	return BattleArt.data()

static func can_render(enemies: Array) -> bool:
	if enemies.is_empty() or enemies.size()>10:return false
	for enemy in enemies:
		var ident := str(enemy.get("sprite",-1))
		if not _validation.has(ident):_validation[ident] = _valid(ident)
		if not _validation[ident]:return false
	return true

static func _valid(ident: String) -> bool:
	var data := manifest()
	var downloadable := not pack_index.is_empty()
	if downloadable and not pack_index.has(ident):return false
	# A pet sprite kept in its own file (BattleArt) was checked complete by
	# the importer; on the web its file arrives with the sprite's pack.
	if not BattleArt.ensure(ident) and BattleArt.is_extra(ident):return downloadable
	var valid: bool = data.get("characters",{}).has(ident)
	var animations: Dictionary = data.get("characters",{}).get(ident,{})
	for action in [0,1,2,3,4,10]:
		for direction in range(8):
			var frames: Array = animations.get("%d_%d" % [action,direction],{}).get("frames",[])
			if frames.is_empty():valid = false
			for frame in frames:
				var bitmap := str(int(frame.image))
				if not data.get("images",{}).has(bitmap) or (not downloadable and not preload("res://scripts/sheet_frames.gd").available(ART_ROOT,data.get("sheets",{}),ident,int(bitmap))):valid = false
	return valid
