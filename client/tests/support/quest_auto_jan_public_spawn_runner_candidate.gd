extends "res://server/quest_auto.gd"
## UNRUN candidate. Only this test subclass can admit job27/event20.
## Product Policy and Registry remain unchanged and closed.
const Candidate = preload("res://server/quest_auto_jan_plan.gd")
const DIAG_MAX_PENDING_FIELDS: int = 8

class ObservedNavigation extends "res://server/quest_auto_navigation.gd":
	const TARGET_MAP: int = 10202
	const TARGET_ORIGIN: Vector2i = Vector2i(9, 7)
	const TARGET_GOAL: Vector2i = Vector2i(33, 49)
	const DIAG_MAX_OCCUPIED_CELLS: int = 2400 # Frozen 40x60 source metadata.
	const DIAG_MAX_USABLE_ROWS: int = 8
	const DIAG_MAX_FLOOR_ROWS: int = 8
	const DIAG_RING_RADIUS: int = 1
	const DIAG_MAX_RING_CELLS: int = 18
	const DIAG_MAX_ROUTE_POINTS: int = 16
	const DIAG_MAX_LOCAL_PATH_ROWS: int = 4
	var next_calls: int = 0
	var plan_calls: int = 0
	var local_path_calls: int = 0
	var validate_calls: int = 0
	var last_point: Dictionary = {}
	var calls: Array[Dictionary] = []
	var diagnostic_counts: Dictionary = {"map_route": 0, "plan": 0, "next": 0, "local_path": 0, "usable": 0, "blocked": 0, "blocked_10202": 0, "floor_cell": 0, "entry_fallback": 0}
	var diagnostic: Dictionary = {}
	var diagnostic_usable_rows: Array[Dictionary] = []
	var diagnostic_floor_rows: Array[Dictionary] = []
	var diagnostic_blocked_rows: Array[Dictionary] = []
	var diagnostic_local_path_rows: Array[Dictionary] = []
	var diagnostic_local_path_dropped: int = 0
	var diagnostic_usable_exit_calls: int = 0
	var diagnostic_usable_exit_dropped: int = 0
	var diagnostic_floor_endpoint_calls: int = 0
	var diagnostic_floor_endpoint_dropped: int = 0
	var active_target_plan: bool = false

	func _numeric_map_matches(value: Variant, expected: int) -> bool:
		if value is bool or not (value is int or value is float): return false
		return is_finite(float(value)) and float(value) == float(expected)

	func _is_target_npc(npc: Dictionary) -> bool:
		return _numeric_map_matches(npc.get("map_id", null), 3400) and str(npc.get("id", "")) == "jaruga/event/event20_1@3400:59:66"

	func _target_case(map_id: int, origin: Vector2i, goal: Vector2i) -> bool:
		return map_id == TARGET_MAP and origin == TARGET_ORIGIN and goal == TARGET_GOAL

	func _path_summary(result: Array) -> Dictionary:
		var first: Array = result.slice(0, mini(2, result.size()))
		var last: Array = result.slice(maxi(0, result.size() - 2), result.size())
		return {"size": result.size(), "first": first.duplicate(true), "last": last.duplicate(true), "truncated": result.size() > 4}

	func _fixed_ring(origin: Vector2i, goal: Vector2i) -> Array[Vector2i]:
		var points: Array[Vector2i] = []
		for center_value in [origin, goal]:
			var center: Vector2i = center_value
			for dy in range(-DIAG_RING_RADIUS, DIAG_RING_RADIUS + 1):
				for dx in range(-DIAG_RING_RADIUS, DIAG_RING_RADIUS + 1):
					var cell: Vector2i = center + Vector2i(dx, dy)
					if cell not in points and points.size() < DIAG_MAX_RING_CELLS:
						points.append(cell)
		return points

	func diagnostic_snapshot() -> Dictionary:
		return {
			"counts": diagnostic_counts.duplicate(true),
			"map_route": diagnostic.get("map_route", {}).duplicate(true),
			"plan": diagnostic.get("plan", {}).duplicate(true),
			"next": diagnostic.get("next", {}).duplicate(true),
			"local_path": diagnostic_local_path_rows.duplicate(true),
			"local_path_dropped": diagnostic_local_path_dropped,
			"usable_for_exit": diagnostic_usable_rows.duplicate(true),
			"usable_exit_calls": diagnostic_usable_exit_calls,
			"usable_exit_dropped": diagnostic_usable_exit_dropped,
			"blocked_10202": diagnostic_blocked_rows.duplicate(true),
			"floor_endpoints": diagnostic_floor_rows.duplicate(true),
			"floor_endpoint_calls": diagnostic_floor_endpoint_calls,
			"floor_endpoint_dropped": diagnostic_floor_endpoint_dropped,
			"entry_fallback": diagnostic.get("entry_fallback", {}).duplicate(true)
		}

	func usable(b, link: Dictionary) -> bool:
		var result: bool = super.usable(b, link)
		diagnostic_counts["usable"] = int(diagnostic_counts["usable"]) + 1
		if active_target_plan and _numeric_map_matches(link.get("from_map", null), TARGET_MAP) and _numeric_map_matches(link.get("to_map", null), 10203):
			diagnostic_usable_exit_calls += 1
			if diagnostic_usable_rows.size() < DIAG_MAX_USABLE_ROWS:
				diagnostic_usable_rows.append({"link": link.duplicate(true), "result": result})
			else:
				diagnostic_usable_exit_dropped += 1
		return result

	func blocked(b, map_id: int) -> Dictionary:
		var result: Dictionary = super.blocked(b, map_id)
		diagnostic_counts["blocked"] = int(diagnostic_counts["blocked"]) + 1
		if map_id == TARGET_MAP and active_target_plan:
			diagnostic_counts["blocked_10202"] = int(diagnostic_counts["blocked_10202"]) + 1
			if diagnostic_blocked_rows.is_empty():
				var origin: Vector2i = b.automation.position_cell
				var ring: Array[Vector2i] = _fixed_ring(origin, TARGET_GOAL)
				var ring_rows: Array[Dictionary] = []
				for cell in ring:
					ring_rows.append({"cell": [cell.x, cell.y], "blocked": result.has(cell)})
				diagnostic_blocked_rows.append({"map_id": map_id, "count": result.size(), "ring": ring_rows, "ring_cell_cap": DIAG_MAX_RING_CELLS})
		return result

	func floor_cell(b, map_id: int, cell: Vector2i, occupied: Dictionary) -> bool:
		var result: bool = super.floor_cell(b, map_id, cell, occupied)
		diagnostic_counts["floor_cell"] = int(diagnostic_counts["floor_cell"]) + 1
		if active_target_plan and map_id == TARGET_MAP and cell in [TARGET_ORIGIN, TARGET_GOAL]:
			diagnostic_floor_endpoint_calls += 1
			if diagnostic_floor_rows.size() < DIAG_MAX_FLOOR_ROWS:
				diagnostic_floor_rows.append({"cell": [cell.x, cell.y], "occupied_here": occupied.has(cell), "result": result})
			else:
				diagnostic_floor_endpoint_dropped += 1
		return result

	func map_route(b, origin: int, goal: int) -> Array:
		var result: Array = super.map_route(b, origin, goal)
		diagnostic_counts["map_route"] = int(diagnostic_counts["map_route"]) + 1
		if active_target_plan and origin == TARGET_MAP and goal == 3400:
			var prefix: Array = result.slice(0, mini(DIAG_MAX_ROUTE_POINTS, result.size()))
			diagnostic["map_route"] = {"origin": origin, "goal": goal, "result_prefix": prefix.duplicate(true), "result_size": result.size(), "truncated": result.size() > DIAG_MAX_ROUTE_POINTS}
		return result

	func plan(b, npc: Dictionary) -> Array:
		plan_calls += 1
		var was_target_plan: bool = active_target_plan
		active_target_plan = _is_target_npc(npc)
		var result: Array = super.plan(b, npc)
		active_target_plan = was_target_plan
		diagnostic_counts["plan"] = int(diagnostic_counts["plan"]) + 1
		if _is_target_npc(npc):
			diagnostic["plan"] = {"result": _path_summary(result), "result_empty": result.is_empty()}
		calls.append({"kind": "plan", "target": npc.duplicate(true), "result": result.duplicate(true)})
		return result

	func local_path(b, map_id: int, origin: Vector2i, goal: Vector2i, occupied: Dictionary) -> Array:
		local_path_calls += 1
		var result: Array = super.local_path(b, map_id, origin, goal, occupied)
		diagnostic_counts["local_path"] = int(diagnostic_counts["local_path"]) + 1
		if active_target_plan and _target_case(map_id, origin, goal):
			var occupied_rows: Array = []
			var invalid_key_count: int = 0
			var valid_key_count: int = 0
			var occupied_overflow_count: int = 0
			for key in occupied.keys():
				if key is Vector2i:
					valid_key_count += 1
					if occupied_rows.size() < DIAG_MAX_OCCUPIED_CELLS:
						var occupied_cell: Vector2i = key
						occupied_rows.append([occupied_cell.x, occupied_cell.y])
					else:
						occupied_overflow_count += 1
				else:
					invalid_key_count += 1
			var region_value: Dictionary = {}
			var origin_solid_after_restore: Variant = null
			var goal_solid_after_restore: Variant = null
			if nav != null:
				region_value = {"position": [nav.region.position.x, nav.region.position.y], "size": [nav.region.size.x, nav.region.size.y]}
				if nav.region.has_point(origin): origin_solid_after_restore = nav.is_point_solid(origin)
				if nav.region.has_point(goal): goal_solid_after_restore = nav.is_point_solid(goal)
			var local_record: Dictionary = {
				"map_id": map_id,
				"origin": [origin.x, origin.y],
				"goal": [goal.x, goal.y],
				"occupied_count": occupied.size(),
				"occupied_valid_key_count": valid_key_count,
				"occupied_cells": occupied_rows,
				"occupied_truncated": occupied_overflow_count > 0,
				"invalid_occupied_key_count": invalid_key_count,
				"occupied_overflow_count": occupied_overflow_count,
				"nav_region": region_value,
				"nav_grid_key": grid_key,
				"origin_solid_after_restore": origin_solid_after_restore,
				"goal_solid_after_restore": goal_solid_after_restore,
				"result": _path_summary(result),
				"result_empty": result.is_empty()
			}
			if diagnostic_local_path_rows.size() < DIAG_MAX_LOCAL_PATH_ROWS:
				diagnostic_local_path_rows.append(local_record)
			else:
				diagnostic_local_path_dropped += 1
		calls.append({"kind": "local_path", "map_id": map_id, "origin": [origin.x, origin.y], "goal": [goal.x, goal.y], "result": result.duplicate(true)})
		return result

	func _entry_fallback(b, npc: Dictionary) -> Array:
		var result: Array = super._entry_fallback(b, npc)
		diagnostic_counts["entry_fallback"] = int(diagnostic_counts["entry_fallback"]) + 1
		if active_target_plan and _is_target_npc(npc):
			diagnostic["entry_fallback"] = {"called": true, "enabled": _entry_fallback_enabled, "result_size": result.size(), "searches": entry_routes.searches, "context_copies": entry_routes.context_copies, "last_reason": entry_routes.last_reason}
		return result

	func next(b, npc: Dictionary) -> Dictionary:
		next_calls += 1
		var point: Dictionary = super.next(b, npc)
		last_point = point.duplicate(true)
		diagnostic_counts["next"] = int(diagnostic_counts["next"]) + 1
		if _is_target_npc(npc):
			diagnostic["next"] = {"target_id": str(npc.get("id", "")), "point": point.duplicate(true), "point_empty": point.is_empty()}
		calls.append({"kind": "next", "target": npc.duplicate(true), "point": point.duplicate(true)})
		return point

	func validate(b, point: Dictionary) -> bool:
		validate_calls += 1
		var accepted: bool = super.validate(b, point)
		calls.append({"kind": "validate", "point": point.duplicate(true), "accepted": accepted})
		return accepted

var selections: Array[Dictionary] = []
var passive_handoff_count: int = 0
var pending_post_tick: Dictionary = {}

func _pending_summary(b) -> Dictionary:
	var value: Variant = b.original_quests.pending
	if not value is Dictionary: return {"type": type_string(typeof(value)), "present": null}
	var pending: Dictionary = value
	var branch_value: Variant = pending.get("branch", null)
	var branch_summary: Dictionary = {}
	if branch_value is Dictionary:
		var branch: Dictionary = branch_value
		var branch_fields: Array = ["event", "type", "condition", "source_branch_index", "source_line"]
		for index in range(mini(branch_fields.size(), DIAG_MAX_PENDING_FIELDS)):
			var key: String = str(branch_fields[index])
			if branch.has(key): branch_summary[key] = branch[key]
		branch_summary["field_count"] = branch.size()
	var npc_value: Variant = pending.get("npc", null)
	var npc_id: String = str(npc_value.get("id", "")) if npc_value is Dictionary else ""
	return {"type": "Dictionary", "present": not pending.is_empty(), "key_count": pending.size(), "phase": pending.get("phase", null), "npc_id": npc_id, "branch": branch_summary, "token_present": not str(pending.get("token", "")).is_empty()}

func handoff(b, reason: String) -> void:
	var capture: bool = passive_handoff_count == 0 and b.automation.position_map == 10202 and str(step.get("id", "")) == "jan:flower:2486"
	var before: Dictionary = {}
	if capture:
		passive_handoff_count += 1
		var nav_observed: Variant = navigation
		var nav_summary: Dictionary = nav_observed.diagnostic_snapshot()
		before = {"reason": reason, "running": running, "phase": phase, "step_id": str(step.get("id", "")), "position": [b.automation.position_map, b.automation.position_cell.x, b.automation.position_cell.y], "pending": _pending_summary(b), "target": target.duplicate(true), "navigation": nav_summary}
	super.handoff(b, reason)
	if capture:
		var after: Dictionary = {"running": running, "phase": phase, "pause_reason": pause_reason, "step_id": str(step.get("id", "")), "position": [b.automation.position_map, b.automation.position_cell.x, b.automation.position_cell.y], "pending": _pending_summary(b)}
		var record: Dictionary = {"kind": "bounded_handoff_diagnostic", "before": before, "after_handoff": after, "after_tick": {}}
		var nav_after: Variant = navigation
		nav_after.calls.append(record)
		pending_post_tick = {"record": record}

func tick(b, delta: float) -> void:
	super.tick(b, delta)
	if pending_post_tick.is_empty(): return
	var record_value: Variant = pending_post_tick.get("record", null)
	if record_value is Dictionary:
		var record: Dictionary = record_value
		record["after_tick"] = {"running": running, "phase": phase, "pause_reason": pause_reason, "step_id": str(step.get("id", "")), "position": [b.automation.position_map, b.automation.position_cell.x, b.automation.position_cell.y], "pending": _pending_summary(b), "target": target.duplicate(true)}
	pending_post_tick = {}

func _init() -> void:
	navigation = ObservedNavigation.new()

func _supports_automatic_start(job_id: int, event_id: int) -> bool:
	return job_id == 27 and event_id == 20

func strict_select(b, selected_id: int = -1, _allow_clean: Variant = null) -> Dictionary:
	var id: int = quest_id if selected_id < 0 else selected_id
	var result: Dictionary = Candidate.flower_proposal(b, id)
	selections.append(result.duplicate(true))
	return result
