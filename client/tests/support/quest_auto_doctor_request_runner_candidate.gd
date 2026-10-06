extends "res://server/quest_auto.gd"
## Test-only admission seam. Product Policy/Registry remain closed for job 6.
const Candidate = preload("res://server/quest_auto_doctor_plan.gd")

class ObservedNavigation extends "res://server/quest_auto_navigation.gd":
	var next_calls: int = 0
	var plan_calls: int = 0
	var local_path_calls: int = 0
	var last_point: Dictionary = {}
	var last_path: Array = []

	func next(b, npc: Dictionary) -> Dictionary:
		next_calls += 1
		var point: Dictionary = super.next(b, npc)
		last_point = point.duplicate(true)
		last_path = route.duplicate(true)
		return point

	func plan(b, npc: Dictionary) -> Array:
		plan_calls += 1
		return super.plan(b, npc)

	func local_path(b, map_id: int, origin: Vector2i, goal: Vector2i, occupied: Dictionary) -> Array:
		local_path_calls += 1
		return super.local_path(b, map_id, origin, goal, occupied)

func _init() -> void:
	navigation = ObservedNavigation.new()

func _supports_automatic_start(job_id: int, event_id: int) -> bool:
	return job_id == 6 and event_id == 15

func strict_select(b, selected_id: int = -1, _allow_clean: Variant = null) -> Dictionary:
	var id: int = quest_id if selected_id < 0 else selected_id
	return Candidate.request_proposal(b, id)
