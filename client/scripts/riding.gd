extends RefCounted
## Native composite lookup. No rider sprite is painted on top of a pet.
const PATH := "res://assets/legacy/riding/manifest.json"
static var _manifest: Dictionary = {}

static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(PATH):
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _manifest

static func composite(character_id: String, pet_sprite: int) -> int:
	return int(manifest().get("pairs",{}).get(character_id+":"+str(pet_sprite),{}).get("sprite",-1))

static func can_mount(profile: Dictionary, index: int) -> String:
	var pets: Array = profile.get("pets",[])
	if index < 0 or index >= pets.size(): return "没有这只伙伴。"
	var pet: Dictionary = pets[index]
	if int(pet.get("hp",0)) <= 0: return "伙伴需要先恢复体力。"
	if index == int(profile.get("active_pet",-1)): return "骑乘伙伴不能同时出战，请先设为待机。"
	if int(pet.get("loyalty",100)) < 100: return "骑乘需要忠诚度100。"
	var player: Dictionary = profile.get("player",{})
	if int(pet.get("level",1)) > int(player.get("level",1))+5: return "伙伴等级不能超过人物等级5级。"
	if int(pet.get("level",1)) > int(player.get("riding_level",int(player.get("level",1))+5)): return "骑乘等级不足。"
	if composite(str(profile.get("character_id","100000")),int(pet.get("sprite",0))) < 0:
		return "此造型没有这只伙伴的原版骑乘动画。金虎可选择造型100010。"
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
