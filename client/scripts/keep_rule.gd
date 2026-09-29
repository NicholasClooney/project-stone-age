extends RefCounted
## 保留规则: which pets of one species to keep, judged against the pets the
## player already has (a rolling standard, no fixed thresholds).
##
##   Tiers      group by 三围合 (attack + defence + speed); in each of the top
##              `tiers` distinct sums keep the best `per_tier`, ranked by
##              `order` (default 攻击 → 敏捷 → 血), then the remaining keys in
##              pet_stat_filter.gd RANK_KEYS order, then the older pet id.
##   Champions  for each stat in `champion_stats` keep the best `champions`
##              across all of them (ties: 三围合, then the tier order).
##   Keep       the union, plus favourites and any `protected` pet (出战中,
##              骑乘中, 削血宠); everything else is released.
##
## Pets under Lv120 are judged by their exact Lv120 stats (the growth-seed
## projection 同种比较 shows). Identical stats resolve to the older pet id, so
## duplicates beyond a quota are released. Settings: stat_filters.<id>.keep_rule
## (automation_settings.gd); used by 同种比较's 按保留规则选中 and, when `auto`
## is on, by the find-pet cycle after each stored pet.
const StatFilter = preload("res://scripts/pet_stat_filter.gd")
const PetComparison = preload("res://scripts/pet_comparison.gd")
const STATS := ["attack", "defence", "speed", "max_hp"]
const STAT_NAMES := {"attack":"攻击", "defence":"防御", "speed":"敏捷", "max_hp":"血"}

## The stats a pet is judged by: current at Lv120, else the exact Lv120 projection.
static func stats_of(pet: Dictionary) -> Dictionary:
	var source: Dictionary = pet if int(pet.get("level", 1)) >= 120 else PetComparison.expected(pet)
	var result := {"projected": int(pet.get("level", 1)) < 120}
	for key in STATS:result[key] = int(source.get(key, 0))
	return result

static func _id_number(pet: Dictionary) -> int:
	var suffix := str(pet.get("pet_id", "")).trim_prefix("pet-")
	return int(suffix) if suffix.is_valid_int() else 1 << 62

## pets: one species. protected: pet_id -> reason for pets that must stay
## (出战中, 骑乘中, 削血宠); favourites are always kept.
## Returns {reasons: pet_id -> [text], release: [pet_id], stats: pet_id -> stats}
## where every pet with no reason is released.
static func evaluate(pets: Array, rule: Dictionary, protected: Dictionary = {}) -> Dictionary:
	var stats := {}
	var reasons := {}
	for pet in pets:
		var id := str(pet.get("pet_id", ""))
		stats[id] = stats_of(pet)
		reasons[id] = []
	var order := StatFilter.rank_order(rule.get("order", ["attack", "speed", "max_hp"]))
	var better := func(a: Dictionary, b: Dictionary) -> bool:
		for key in order:
			var va := StatFilter.rank_value(stats[str(a.pet_id)], key)
			var vb := StatFilter.rank_value(stats[str(b.pet_id)], key)
			if va != vb:return va > vb
		return _id_number(a) < _id_number(b)
	var sum_of := func(pet: Dictionary) -> int:return StatFilter.rank_value(stats[str(pet.pet_id)], "sum")
	var sums := []
	for pet in pets:
		if not sums.has(sum_of.call(pet)):sums.append(sum_of.call(pet))
	sums.sort()
	sums.reverse()
	for total in sums.slice(0, maxi(0, int(rule.get("tiers", 2)))):
		var group := pets.filter(func(pet):return sum_of.call(pet) == total)
		group.sort_custom(better)
		for i in range(mini(group.size(), maxi(0, int(rule.get("per_tier", 3))))):
			reasons[str(group[i].pet_id)].append("%d档第%d" % [total, i + 1])
	var champions := maxi(0, int(rule.get("champions", 2)))
	var chosen: Array = rule.get("champion_stats", STATS)
	for stat in STATS:
		if not chosen.has(stat) or champions == 0:continue
		var ranked := pets.duplicate()
		ranked.sort_custom(func(a, b):
			var va := int(stats[str(a.pet_id)][stat])
			var vb := int(stats[str(b.pet_id)][stat])
			if va != vb:return va > vb
			if sum_of.call(a) != sum_of.call(b):return sum_of.call(a) > sum_of.call(b)
			return better.call(a, b))
		for i in range(mini(ranked.size(), champions)):
			reasons[str(ranked[i].pet_id)].append("%s第%d" % [STAT_NAMES[stat], i + 1])
	for pet in pets:
		var id := str(pet.pet_id)
		if pet.get("favorite", false):reasons[id].append("收藏")
		if protected.has(id):reasons[id].append(str(protected[id]))
	var release := []
	for pet in pets:
		if reasons[str(pet.pet_id)].is_empty():release.append(str(pet.pet_id))
	return {"reasons":reasons, "release":release, "stats":stats}

## The pets of this species in a profile (party and warehouse), by the same
## species grouping as 同种比较 (the starter 蓝人龙 is original 92).
static func species_pets(profile: Dictionary, template_id: int) -> Array:
	var key := "original_%d" % template_id
	var result := []
	for pet in profile.get("pets", []) + profile.get("pet_storage", []):
		if PetComparison.species_key(pet) == key or int(pet.get("template_id", -1)) == template_id:result.append(pet)
	return result

## Pets release_pets would refuse anyway, with the reason the rule shows.
static func always_kept(profile: Dictionary) -> Dictionary:
	var result := {}
	var pets: Array = profile.get("pets", [])
	var active := int(profile.get("active_pet", -1))
	var ride := int(profile.get("ride_pet", -1))
	if active >= 0 and active < pets.size():result[str(pets[active].get("pet_id", ""))] = "出战中"
	if ride >= 0 and ride < pets.size():result[str(pets[ride].get("pet_id", ""))] = "骑乘中"
	return result

## Carried pets the find-pet capture step may use (automation settings'
## capture section): the chosen helper by id or slot, or with automatic choice
## every carried pet at or under the level cap. The rule never releases them.
static func capture_helpers(profile: Dictionary, capture: Dictionary) -> Dictionary:
	var pets: Array = profile.get("pets", [])
	var result := {}
	var ident := str(capture.get("pet_id", ""))
	var chosen := int(capture.get("pet", -1))
	for i in range(pets.size()):
		var id := str(pets[i].get("pet_id", ""))
		if not ident.is_empty():
			if id == ident:result[id] = "削血宠"
		elif chosen >= 0:
			if i == chosen:result[id] = "削血宠"
		elif int(pets[i].get("level", 1)) <= int(capture.get("pet_max_level", 10)):result[id] = "削血宠"
	return result

## One line for a pet: why it stays, or that it would be released.
static func describe(reasons: Array) -> String:
	return "保留：" + "、".join(reasons) if not reasons.is_empty() else "按规则放生"
