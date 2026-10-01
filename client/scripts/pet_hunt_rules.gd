extends RefCounted
## Developer convenience: inspect newborn weights, never forecast independent maxima.
## Each of the four original weights independently varies by -2..+2 (625 tuples).
static func quality(actor: Dictionary, catalog: Dictionary) -> Dictionary:
	var result := {"valid": false, "offsets": [], "total_offset": 0}
	var template: Dictionary = catalog.get("templates", {}).get(str(int(actor.get("template_id", -1))), {})
	var nominal = template.get("weights", [])
	var actual = actor.get("growth_weights", [])
	if not nominal is Array or not actual is Array or nominal.size() != 4 or actual.size() != 4:
		return result
	for i in range(4):
		if not (actual[i] is int or actual[i] is float) or not (nominal[i] is int or nominal[i] is float):
			return {"valid": false, "offsets": [], "total_offset": 0}
		if float(actual[i]) != float(int(actual[i])) or float(nominal[i]) != float(int(nominal[i])):
			return {"valid": false, "offsets": [], "total_offset": 0}
		var offset := int(actual[i]) - int(nominal[i])
		if offset < -2 or offset > 2:
			return {"valid": false, "offsets": [], "total_offset": 0}
		result.offsets.append(offset)
		result.total_offset += offset
	result.valid = true
	return result

## Missing templates retains the legacy wildcard; an explicit empty set never matches.
static func selected(filter: Dictionary, template_id: int) -> bool:
	if filter.has("templates"):return filter.templates is Array and template_id in filter.templates
	return int(filter.get("template",-1))<0 or int(filter.template)==template_id

static func targets(filter: Dictionary) -> Array:
	return filter.get("usable",[]).filter(func(id):return selected(filter,int(id)))

static func matches(actor: Dictionary, template_id: int, level_one: bool, min_total: int, min_offsets: Array, catalog: Dictionary) -> bool:
	if not actor.get("can_capture", false): return false
	if template_id >= 0 and int(actor.get("template_id", -1)) != template_id: return false
	if level_one and int(actor.get("level", 0)) != 1: return false
	var measured := quality(actor, catalog)
	return measured.valid and _passes(measured.offsets, int(measured.total_offset), min_total, min_offsets)

## 只进无其他敌人的遇敌: every enemy of the troop is Lv.1. Besides the Lv.1
## hunt targets only other Lv.1 pets may be there: they cannot threaten the
## party, and a find-pet capture defeats them once the target is caught.
## tools/fast_hunt/fast_hunt.c implements the same rule.
static func clean_troop(troop: Dictionary) -> bool:
	for enemy in troop.get("enemies", []):
		if int(enemy.get("level", 0)) != 1: return false
	return true

## Whether a Lv.1 hunt with this filter skips troops that are not clean.
static func wants_clean(filter: Dictionary) -> bool:
	return bool(filter.get("clean_only", false)) and bool(filter.get("level_one", true))

static func _passes(offsets: Array, total: int, min_total: int, minimum: Array) -> bool:
	if total < min_total or (not minimum.is_empty() and minimum.size() != 4): return false
	for i in range(minimum.size()):
		if int(offsets[i]) < int(minimum[i]): return false
	return true

static func tail_probability(min_total: int, min_offsets: Array = []) -> float:
	var count := 0
	for a in range(-2, 3):
		for b in range(-2, 3):
			for c in range(-2, 3):
				for d in range(-2, 3):
					if _passes([a,b,c,d], a+b+c+d, min_total, min_offsets): count += 1
	return count / 625.0

static func candidates(catalog_obj, map_id: int, cell: Vector2i, level_one: bool) -> Array:
	var area: Dictionary = catalog_obj.area_at(map_id, cell)
	if area.is_empty() or int(area.get("probability_max", 0)) <= 0 or area.get("invalid_weights", false): return []
	if int(area.get("event_now", -1)) > 0 or int(area.get("event_end", -1)) > 0: return []
	var data: Dictionary = catalog_obj.data
	var found := {}
	for choice in area.get("groups", []):
		if int(choice.get("weight", 0)) <= 0: continue
		var group: Dictionary = data.get("groups", {}).get(str(int(choice.id)), {})
		if group.is_empty() or group.get("invalid_weights", false): continue
		if int(group.get("requires_item", -1)) >= 0 or int(group.get("excludes_item", -1)) >= 0: continue
		var valid := true
		for entry in group.get("enemies", []):
			var enemy: Dictionary = data.get("enemies", {}).get(str(int(entry.id)), {})
			if enemy.is_empty() or not data.get("templates", {}).has(str(int(enemy.get("template_id", -1)))):
				valid = false
				break
		if not valid: continue
		for entry in group.get("enemies", []):
			if int(entry.get("weight", 0)) <= 0: continue
			var enemy: Dictionary = data.enemies[str(int(entry.id))]
			var lo := int(enemy.get("level_min", 0))
			var hi := int(enemy.get("level_max", 0))
			if int(enemy.get("pet_flag", 0)) == 0 or int(enemy.get("max_count", 0)) <= 0 or lo < 1 or hi < lo: continue
			if level_one and (lo > 1 or hi < 1): continue
			var id := int(enemy.template_id)
			var template: Dictionary = data.templates[str(id)]
			if not found.has(id): found[id] = {"id": id, "name": str(template.get("name", id)), "level_min": lo, "level_max": hi}
			else:
				found[id].level_min = mini(int(found[id].level_min), lo)
				found[id].level_max = maxi(int(found[id].level_max), hi)
	var result: Array = found.values()
	result.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return result
