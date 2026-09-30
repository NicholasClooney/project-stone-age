extends RefCounted
## Player characters' walking art. tools/split_manifests.py writes
## characters/index.json (the chooser's `choices`, `skipped` and the list of
## `characters`) and one file per character, characters/art/<id>.json, with
## its animations and sheet frames (scripts/sprite_art.gd). A character's
## file is read when it is drawn and kept among the last LIMIT used; the
## chooser shows every appearance at once, so LIMIT covers them all.
const ROOT := "res://assets/legacy/characters/"
const INDEX := ROOT+"index.json"
const LIMIT := 64
const SpriteArt = preload("res://scripts/sprite_art.gd")
const ArtCache = preload("res://scripts/art_cache.gd")
static var _index: Dictionary = {}
static var _cache: ArtCache

static func index() -> Dictionary:
	if _index.is_empty() and FileAccess.file_exists(INDEX):
		var text := FileAccess.get_file_as_string(INDEX)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:_index = parsed
		preload("res://scripts/perf_registry.gd").track_manifest("characters",text.length())
	return _index

static func cache() -> ArtCache:
	if _cache == null:_cache = ArtCache.new(LIMIT,"characters art")
	return _cache

static func has(character: String) -> bool:
	return index().get("characters",{}).has(character)

## The character's entry, or {} when there is none.
static func art(character: String) -> Dictionary:
	if not has(character):return {}
	return cache().get_entry(character,read)

static func read(character: String) -> Dictionary:
	var path := ROOT+"art/"+character+".json"
	if not FileAccess.file_exists(path):return {}
	return SpriteArt.parse(FileAccess.get_file_as_string(path),character,ROOT)
