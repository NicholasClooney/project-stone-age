extends RefCounted
## Battle art, shared by the battle view, pet follower, portraits, audio and
## TroopArt. tools/split_manifests.py writes it:
##   battle/index.json         player and enemy ids, club variants, UI,
##                             audio, frame sounds, and the sprite lists
##   battle/sprites/<id>.json  one sprite's animations and frames
## Startup reads only the index. A sprite's file is read when something draws
## it and kept among the last LIMIT used (scripts/art_cache.gd); each is a
## few tens of KB in memory (scripts/sprite_art.gd).
##
## `sprites` ship in the core web pack. `extra_sprites` (pets only 宠物大全,
## GM grants and 后台搜宠 need) ship in the sprite's own web pack with its
## sheets, so their file may not be here yet. Each list maps a sprite to the
## sheet files a battle needs, or false when it cannot fight (TroopArt).
const ROOT := "res://assets/legacy/battle/"
const INDEX := ROOT+"index.json"
const LIMIT := 32
const SpriteArt = preload("res://scripts/sprite_art.gd")
const ArtCache = preload("res://scripts/art_cache.gd")

static var _index: Dictionary = {}
static var _cache: ArtCache

## Whether battle art was imported at all.
static func present() -> bool:
	return not index().is_empty()

static func index() -> Dictionary:
	if _index.is_empty() and FileAccess.file_exists(INDEX):
		var text := FileAccess.get_file_as_string(INDEX)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:_index = parsed
		preload("res://scripts/perf_registry.gd").track_manifest("battle",text.length())
	return _index

static func cache() -> ArtCache:
	if _cache == null:_cache = ArtCache.new(LIMIT,"battle sprites")
	return _cache

## The sprite has art in this build (its file may still be waiting for its
## web pack).
static func known(ident: Variant) -> bool:
	var key := str(ident)
	return index().get("sprites",{}).has(key) or is_extra(key)

static func is_extra(ident: Variant) -> bool:
	return index().get("extra_sprites",{}).has(str(ident))

## The sprite's entry (scripts/sprite_art.gd), or {} when there is none or
## its file is not here yet.
static func art(ident: Variant) -> Dictionary:
	var key := str(ident)
	if not known(key):return {}
	return cache().get_entry(key,read)

## The entry without keeping it among the recent ones (宠物大全's pictures
## read hundreds of sprites once each).
static func peek(ident: Variant) -> Dictionary:
	var key := str(ident)
	if not known(key):return {}
	var entry := cache().cached(key)
	return entry if not entry.is_empty() else read(key)

static func read(key: String) -> Dictionary:
	var path := ROOT+"sprites/"+key+".json"
	if not FileAccess.file_exists(path):return {}
	return SpriteArt.parse(FileAccess.get_file_as_string(path),key,ROOT)

## Whether the sprite's animations are here (false while its web pack is
## missing).
static func ensure(ident: Variant) -> bool:
	return not art(ident).is_empty()

static func animations(ident: Variant) -> Dictionary:
	return art(ident).get("animations",{})

static func frame_sounds() -> Dictionary:
	return index().get("frame_sounds",{})

## Whether a battle can show the sprite: every action and direction a battle
## plays has frames, each in the sprite's own sheet (checked by the split
## tool), and, when art is not downloaded on demand, those sheets are here.
static func renderable(ident: Variant, downloadable: bool) -> bool:
	var key := str(ident)
	var needed = index().get("sprites",{}).get(key,index().get("extra_sprites",{}).get(key,false))
	if not needed is Array:return false
	if downloadable:return true
	for file in needed:
		if not ResourceLoader.exists(ROOT+str(file)):return false
	return true
