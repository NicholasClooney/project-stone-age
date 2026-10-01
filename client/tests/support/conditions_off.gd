extends RefCounted
## Every species defaults to 属性条件 三围合 or 攻击 ≥ 最高 − 1, so a find-pet
## cycle on a species the player has none of surveys first (摸底) and judges
## each pet. Suites that drive the plain cycle (catch, train, compare) turn
## those defaults off for the species they hunt, through the real
## set_automation_settings path, with this patch.
const Catalog = preload("res://server/encounter_catalog.gd")

## The settings patch: 三围合 and 攻击 off for each template id.
static func patch(template_ids: Array) -> Dictionary:
	var filters := {}
	for id in template_ids:filters[str(int(id))] = {"conditions":{"sum":{"enabled":false},"attack":{"enabled":false}}}
	return {"stat_filters":filters}

## The patch for a fixture troop's species.
static func for_troop(troop: Dictionary) -> Dictionary:
	return patch(troop.get("enemies",[]).map(func(actor):return int(actor.template_id)))

## Every species the encounter area at `cell` can roll.
static func area_species(map_id: int, cell: Vector2i) -> Array:
	var catalog := Catalog.new()
	var result: Array = []
	for choice in catalog.area_at(map_id,cell).get("groups",[]):
		for enemy_choice in catalog.data.get("groups",{}).get(str(int(choice.id)),{}).get("enemies",[]):
			var enemy: Dictionary = catalog.data.get("enemies",{}).get(str(int(enemy_choice.id)),{})
			if not enemy.is_empty() and not result.has(int(enemy.template_id)):result.append(int(enemy.template_id))
	return result
