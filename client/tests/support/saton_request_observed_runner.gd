extends "res://server/quest_auto.gd"
## Observation only; no admission or selector override. UNRUN.

class ObservedNavigation extends "res://server/quest_auto_navigation.gd":
	var next_calls: int = 0
	var plan_calls: int = 0
	var local_path_calls: int = 0
	var grid_rebuilds: int = 0
	var grid_rebuild_cells: int = 0
	var last_point: Dictionary = {}

	func next(b, npc: Dictionary) -> Dictionary:
		next_calls += 1
		var point: Dictionary = super.next(b, npc)
		last_point = point.duplicate(true)
		return point

	func plan(b, npc: Dictionary) -> Array:
		plan_calls += 1
		return super.plan(b, npc)

	func local_path(b, map_id: int, origin: Vector2i, goal: Vector2i, occupied: Dictionary) -> Array:
		local_path_calls += 1
		var previous_key: String = grid_key
		var path: Array = super.local_path(b, map_id, origin, goal, occupied)
		if previous_key != grid_key and nav != null:
			grid_rebuilds += 1
			grid_rebuild_cells += nav.region.size.x * nav.region.size.y
		return path

func _init() -> void:
	navigation = ObservedNavigation.new()
