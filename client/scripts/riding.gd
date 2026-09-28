extends RefCounted
## Native composite lookup. No rider sprite is painted on top of a pet.
const PATH := "res://assets/legacy/riding/manifest.json"
static var _manifest: Dictionary = {}

static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(PATH):
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _manifest

static func pair(character_id: String, pet_sprite: int) -> Dictionary:
	return manifest().get("pairs",{}).get(character_id+":"+str(pet_sprite),{})

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
	for pair in manifest().get("pairs",{}).values():
		if str(int(pair.rider)) == character_id and not result.has(int(pair.pet)):result.append(int(pair.pet))
	result.sort()
	return result

static func pet_name(pet_sprite: int) -> String:
	return str(manifest().get("names",{}).get(str(pet_sprite),pet_sprite))

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
