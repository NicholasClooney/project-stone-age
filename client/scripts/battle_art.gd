extends RefCounted
## The battle manifest (assets/legacy/battle/manifest.json), parsed once and
## shared by the battle view, pet follower, portraits, audio and TroopArt.
##
## Pet sprites that only 宠物大全 and GM grants need live in their own files,
## battle/pets/<sprite>.json (the manifest's `extra_sprites`, written by
## tools/import_encounter_art.py), with the same `characters`, `images` and
## `sheets` parts. ensure() merges one in on first use, so the manifest every
## battle reads stays small and each pet's data ships in its own web pack.
const ROOT := "res://assets/legacy/battle/"
const MANIFEST := ROOT+"manifest.json"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary:_data = parsed
	return _data

## The sprite has art in this build: in the manifest or as an extra file
## (which may still be waiting for its web pack).
static func known(ident: Variant) -> bool:
	var key := str(ident)
	return data().get("characters",{}).has(key) or is_extra(key)

static func is_extra(ident: Variant) -> bool:
	return data().get("extra_sprites",{}).has(str(ident))

## An extra sprite's own file ({characters, images, sheets}) without merging
## it, or {} when it is not here (yet). For callers that need one frame.
static func read_extra(ident: Variant) -> Dictionary:
	var key := str(ident)
	if not is_extra(key):return {}
	var path := ROOT+str(data().extra_sprites[key])
	if not FileAccess.file_exists(path):return {}
	var extra = JSON.parse_string(FileAccess.get_file_as_string(path))
	return extra if extra is Dictionary and extra.get("characters",{}).has(key) else {}

## Makes the sprite's animations available in data(). False when there are
## none, or the extra file is not here yet (its web pack is not mounted).
static func ensure(ident: Variant) -> bool:
	var key := str(ident)
	var manifest := data()
	if manifest.get("characters",{}).has(key):return true
	var extra := read_extra(key)
	if extra.is_empty():return false
	for part in ["images","sheets","characters"]:
		if not manifest.has(part):manifest[part] = {}
		manifest[part].merge(extra.get(part,{}),true)
	return true
