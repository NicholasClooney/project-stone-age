extends "res://server/quest_auto.gd"
## UNRUN test-only bridge: exercise the production QuestAuto lifecycle while job 8
## remains absent from the shared Policy/Registry. It supplies only the
## reviewed Munde proposal to the runner's existing strict selector.
const Candidate = preload("res://server/quest_auto_munde_request10_candidate.gd")

class ObservedNavigation extends "res://server/quest_auto_navigation.gd":
	var next_calls := 0
	var plan_calls := 0
	var local_path_calls := 0
	var grid_rebuilds := 0
	var grid_rebuild_cells := 0
	var last_point: Dictionary = {}

	func next(b, npc: Dictionary) -> Dictionary:
		next_calls += 1
		var origin := {"map_id": b.automation.position_map, "cell": [b.automation.position_cell.x, b.automation.position_cell.y]}
		var point: Dictionary = super.next(b, npc)
		last_point = point.duplicate(true)
		return point

	func plan(b, npc: Dictionary) -> Array:
		plan_calls += 1
		return super.plan(b, npc)

	func local_path(b, map_id: int, origin: Vector2i, goal: Vector2i, occupied: Dictionary) -> Array:
		local_path_calls += 1
		var previous_key := grid_key
		var path: Array = super.local_path(b, map_id, origin, goal, occupied)
		if previous_key != grid_key and nav != null:
			grid_rebuilds += 1
			grid_rebuild_cells += nav.region.size.x * nav.region.size.y
		return path

func _init() -> void:
	navigation = ObservedNavigation.new()

func _supports_automatic_start(job_id:int,event_id:int)->bool:
	return job_id == 8 and event_id == 9

func strict_select(b, selected_id: int = -1, _allow_clean: Variant = null) -> Dictionary:
	var id: int = quest_id if selected_id < 0 else selected_id
	return Candidate.select(b, id)
