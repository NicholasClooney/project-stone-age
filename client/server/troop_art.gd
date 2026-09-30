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

static func can_render(enemies: Array) -> bool:
	if enemies.is_empty() or enemies.size()>10:return false
	for enemy in enemies:
		var ident := str(enemy.get("sprite",-1))
		if not _validation.has(ident):_validation[ident] = _valid(ident)
		if not _validation[ident]:return false
	return true

## Checked without reading any sprite file: the split tool records in
## battle/index.json whether each sprite has every action and direction a
## battle plays in its own sheet, and which sheet files that needs.
static func _valid(ident: String) -> bool:
	var downloadable := not pack_index.is_empty()
	if downloadable and not pack_index.has(ident):return false
	return BattleArt.renderable(ident,downloadable)
