extends RefCounted
## Native composite lookup. No rider sprite is painted on top of a pet.
## tools/split_manifests.py writes riding/index.json (rider and mount pairs,
## names, frame sounds, the composite list) and one file per composite,
## riding/composites/<id>.json, which ships in the composite's web pack with
## its sheet. A composite's file is read when it is drawn and kept among the
## last LIMIT used (scripts/art_cache.gd, scripts/sprite_art.gd).
const ROOT := "res://assets/legacy/riding/"
const INDEX := ROOT+"index.json"
const LIMIT := 8
const Elements = preload("res://server/elements.gd")
const SpriteArt = preload("res://scripts/sprite_art.gd")
const ArtCache = preload("res://scripts/art_cache.gd")
static var _index: Dictionary = {}
static var _cache: ArtCache

static func index() -> Dictionary:
	if _index.is_empty() and FileAccess.file_exists(INDEX):
		var text := FileAccess.get_file_as_string(INDEX)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:_index = parsed
		preload("res://scripts/perf_registry.gd").track_manifest("riding",text.length())
	return _index

static func cache() -> ArtCache:
	if _cache == null:_cache = ArtCache.new(LIMIT,"riding composites")
	return _cache

static func has_composite(composite: String) -> bool:
	return index().get("composites",{}).has(composite)

## The composite's entry (scripts/sprite_art.gd), or {} when there is none or
## its web pack is not here yet.
static func art(composite: String) -> Dictionary:
	if not has_composite(composite):return {}
	return cache().get_entry(composite,read)

static func read(composite: String) -> Dictionary:
	var path := ROOT+"composites/"+composite+".json"
	if not FileAccess.file_exists(path):return {}
	return SpriteArt.parse(FileAccess.get_file_as_string(path),composite,ROOT)

## One frame of a rider+mount composite, cut from the composite's sprite sheet.
## Null while the sheet's web pack is downloading.
static func frame_texture(composite: String, bitmap: int) -> Texture2D:
	return SpriteArt.texture(art(composite),bitmap)

static func pair(character_id: String, pet_sprite: int) -> Dictionary:
	return index().get("pairs",{}).get(character_id+":"+str(pet_sprite),{})

static func composite(character_id: String, pet_sprite: int) -> int:
	return int(pair(character_id,pet_sprite).get("sprite",-1))

## Riding certificates, the one switch for them. family.c:2376 (_NEW_RIDEPETS)
## lets a rider use a RideCodeMode mount (扬奇洛斯, 帖拉所伊朵, 左迪洛斯 ...; pairs
## with a "certificate" field) only when the RIDE_PETn bit is set in
## CHAR_LOWRIDEPETS, which the certificate items teach (item_event.c:3096
## ITEM_useLearnRideCode). The game has no certificate items, so, like the
## family-leader requirement, it is skipped: anyone may ride these mounts under
## the other rules. Set to true to require `player.riding_certificates` (the
## learned RIDE_PETn numbers).
const REQUIRE_RIDING_CERTIFICATES := false

## Whether riding this pair needs a certificate the player has not learned.
static func missing_certificate(player: Dictionary, ride: Dictionary) -> bool:
	if not REQUIRE_RIDING_CERTIFICATES or not ride.has("certificate"): return false
	return not player.get("riding_certificates",[]).has(int(ride.certificate))

## Pet sprites this rider appearance has a native composite for (ridePetTable).
static func rideable_pets(character_id: String) -> Array:
	var result: Array = []
	for pair in index().get("pairs",{}).values():
		if str(int(pair.rider)) == character_id and not result.has(int(pair.pet)):result.append(int(pair.pet))
	result.sort()
	return result

## Only selectable appearances with an indexed original composite.
static func compatible_characters(pet_sprite: int) -> Array[String]:
	var result: Array[String] = []
	for id in preload("res://scripts/character_art.gd").index().get("characters",{}):
		var number := int(id)
		if number < 100000 or number > 100235 or (number-100000)%5 != 0:continue
		var sprite := composite(str(id),pet_sprite)
		if sprite >= 0 and has_composite(str(sprite)):result.append(str(id))
	result.sort()
	return result

## The pet window permits choosing a compatible appearance, never bypassing
## the ordinary health, loyalty, level, deployment or certificate rules.
static func selection_reason(profile: Dictionary, pet_index: int) -> String:
	if pet_index < 0 or pet_index >= profile.get("pets",[]).size():return "没有这只伙伴。"
	var candidates := compatible_characters(int(profile.pets[pet_index].get("sprite",0)))
	if candidates.is_empty():return "任何造型都不能骑乘此宠物。\n没有已确认的原版骑乘图。"
	var candidate := profile.duplicate()
	var reason := ""
	for id in candidates:
		candidate.character_id = id
		reason = can_mount(candidate,pet_index)
		if reason.is_empty():return ""
	return reason

static func pet_name(pet_sprite: int) -> String:
	return str(index().get("names",{}).get(str(pet_sprite),pet_sprite))

## Why this pet cannot be ridden now, or "" when it can. Source order and rules:
## family.c FAMILY_RidePet (battle pet, already riding, learned riding level,
## loyalty 100, player level + 5, exact ridePetTable match or a certificate
## mount, see REQUIRE_RIDING_CERTIFICATES) and the client's checkRidePet
## (menu.cpp:21965).
static func can_mount(profile: Dictionary, index: int) -> String:
	var pets: Array = profile.get("pets",[])
	if index < 0 or index >= pets.size(): return "没有这只伙伴。"
	var pet: Dictionary = pets[index]
	if index == int(profile.get("active_pet",-1)): return "骑乘伙伴不能同时出战，请先设为待机。"
	var riding := int(profile.get("ride_pet",-1))
	if riding >= 0 and riding != index: return "请先下骑当前骑宠。"
	if int(pet.get("hp",0)) <= 0: return "伙伴需要先恢复体力。"
	var player: Dictionary = profile.get("player",{})
	if player.has("riding_level") and int(pet.get("level",1)) > int(player.riding_level): return "骑乘等级不足，只能骑乘%d级以下的宠物。" % int(player.riding_level)
	if int(pet.get("loyalty",100)) < 100: return "骑乘需要忠诚度100。"
	if int(pet.get("level",1)) > int(player.get("level",1))+5: return "伙伴等级不能超过人物等级5级。"
	var character := str(profile.get("character_id","100000"))
	if composite(character,int(pet.get("sprite",0))) < 0:
		var names := PackedStringArray()
		for sprite in rideable_pets(character):names.append(pet_name(sprite))
		if names.is_empty(): return "此造型没有原版骑乘动画。"
		return "此造型不能骑乘这只伙伴。可骑乘：%s。" % "、".join(names)
	if missing_certificate(player,pair(character,int(pet.get("sprite",0)))): return "尚未学会骑乘%s，需要骑乘证明。" % pet_name(int(pet.get("sprite",0)))
	return ""

static func adjusted_stats(player: Dictionary, pet: Dictionary, combat_profile: String = "classic", defending: bool = false) -> Dictionary:
	# battle_event.c:180 BATTLE_adjustRidePet3A, supported melee subset.
	var result := player.duplicate(true)
	result["mounted"] = true
	result["critical_defence"] = float(player.get("defence",0))
	result.attack = 0.8*(float(player.get("attack",0))+float(pet.get("attack",0)))
	result.defence = 0.7*(float(player.get("defence",0))+float(pet.get("defence",0)))
	# BATTLE_GetAttr (battle_event.c:840): the rider fights with the averaged
	# 属性 of rider and mount, unless the profile enables _BATTLE_NEWPOWER.
	result["attr_pow"] = Elements.mounted_power(Elements.of(player),Elements.of(pet),combat_profile)
	if defending:
		result.speed = 0.1*float(player.get("speed",0))+0.9*float(pet.get("speed",0))
	elif combat_profile == "reference":
		result.speed = 0.2*float(player.get("speed",0))+0.8*float(pet.get("speed",0))
	else:
		result.speed = 0.5*(float(player.get("speed",0))+float(pet.get("speed",0)))
	return result

static func experience(base: int, mount_level: int, enemy_level: int) -> int:
	# battle.c:4773-4795: over-level adjustment, then 60%, C integer truncation.
	var difference := mount_level-enemy_level
	var earned := base
	if difference > 5:
		earned = maxi(1,int(float(base*maxi(0,20-difference))/15.0))
	return int(earned*0.6)
