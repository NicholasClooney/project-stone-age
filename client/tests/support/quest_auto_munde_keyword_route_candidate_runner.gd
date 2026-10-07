extends "res://server/quest_auto.gd"
## UNRUN test subclass. Product Policy/Registry stay unchanged and job 8 stays closed.
const Candidate = preload("res://server/quest_auto_munde_keyword_route_candidate.gd")


class ObservedNavigation extends "res://server/quest_auto_navigation.gd":
	var next_calls := 0
	var plan_calls := 0
	var local_path_calls := 0
	var grid_rebuilds := 0
	var grid_rebuild_cells := 0
	var last_point: Dictionary = {}

	func observation_snapshot() -> Dictionary:
		return {"installed":true,"next_calls":next_calls,"plan_calls":plan_calls,"local_path_calls":local_path_calls,"grid_rebuilds":grid_rebuilds,"grid_rebuild_cells":grid_rebuild_cells,"last_point":last_point.duplicate(true)}

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

var keyword_committed_this_run := false
var keyword_observation: Dictionary = {}
var keyword_failure: Dictionary = {}
var boss_page_observation: Dictionary = {}
var handoff_observations: Array[Dictionary] = []
var handoff_observation_total := 0
var handoff_observation_generation := 0
const MAX_HANDOFF_OBSERVATIONS := 12

func _init() -> void:
	navigation = ObservedNavigation.new()

func navigation_observation_probe() -> Dictionary:
	var observed: Variant = navigation
	if not observed is ObservedNavigation:return {"installed":false}
	return observed.observation_snapshot()

func start(b, command: Dictionary) -> Dictionary:
	keyword_committed_this_run = false
	keyword_observation = {}
	keyword_failure = {}
	boss_page_observation = {}
	handoff_observation_generation += 1
	handoff_observations.clear()
	handoff_observation_total = 0
	return super.start(b, command)

func _handoff_state(b) -> Dictionary:
	var pending_value: Variant = b.original_quests.pending
	var pending_summary: Dictionary = {}
	if pending_value is Dictionary:
		var pending: Dictionary = pending_value
		var npc_value: Variant = pending.get("npc")
		var npc_id: String = ""
		if npc_value is Dictionary:
			var pending_npc: Dictionary = npc_value
			var pending_npc_id: Variant = pending_npc.get("id", "")
			if pending_npc_id is String:npc_id = pending_npc_id
		var pending_phase: Variant = pending.get("phase", "")
		var pending_token: Variant = pending.get("token", "")
		var pending_phase_text: String = pending_phase if pending_phase is String else "<" + type_string(typeof(pending_phase)) + ">"
		var has_pending_token: bool = false
		if pending_token is String:
			var pending_token_text: String = pending_token
			has_pending_token = not pending_token_text.is_empty()
		pending_summary = {"phase":pending_phase_text, "npc_id":npc_id, "has_token":has_pending_token}
	var checkpoint_value: Variant = identity.checkpoint()
	var checkpoint: Dictionary = checkpoint_value if checkpoint_value is Dictionary else {}
	var cell: Vector2i = b.automation.position_cell
	var step_id_value: Variant = step.get("id", "")
	var safe_step_id: String = "<" + type_string(typeof(step_id_value)) + ">"
	if step_id_value is String:safe_step_id = step_id_value
	return {"running":running,"phase":phase,"pause_reason":pause_reason,"quest_id":quest_id,"step_id":safe_step_id,"client":client,"connection":connection,"identity":checkpoint.duplicate(true),"live_map":b.automation.position_map,"live_cell":[cell.x,cell.y],"pending":pending_summary}

func handoff(b, reason: String) -> void:
	handoff_observation_total += 1
	var ordinal: int = handoff_observation_total
	var generation: int = handoff_observation_generation
	var record: Dictionary = {"ordinal":ordinal,"generation":generation,"reason":reason.substr(0, 240),"before":_handoff_state(b)}
	var keep_record: bool = handoff_observations.size() < MAX_HANDOFF_OBSERVATIONS
	if keep_record:handoff_observations.append(record)
	super.handoff(b, reason)
	if keep_record:
		# Keep the local Dictionary reference: super.handoff may publish/reenter,
		# nest another handoff, or start a new run which clears the public array.
		# Never locate this record via the array tail and never reattach it after reset.
		if handoff_observation_generation == generation:
			record["after"] = _handoff_state(b)
		else:
			record["after_capture"] = {"status":"discarded_after_run_reset","generation_before":generation,"generation_after":handoff_observation_generation}

func _supports_automatic_start(job_id: int, event_id: int) -> bool:
	return job_id == 8 and event_id == 9

func strict_select(b, selected_id: int = -1, _allow_clean: Variant = null) -> Dictionary:
	var id: int = quest_id if selected_id < 0 else selected_id
	return Candidate.select(b, id, keyword_committed_this_run)

func safe_step(value: Dictionary, selected_id: int = -1, allow_clean: Variant = null) -> bool:
	if super.safe_step(value, selected_id, allow_clean):return true
	var id: int = quest_id if selected_id < 0 else selected_id
	if id != 8:return false
	return Candidate.exact_travel_step(value, keyword_committed_this_run)

func strict_dialogue_reply(b, reply: Dictionary) -> void:
	var dialogue_value: Variant = reply.get("dialogue")
	if not dialogue_value is Dictionary:
		super.strict_dialogue_reply(b, reply)
		return
	var dialogue: Dictionary = dialogue_value
	var current_step_id: Variant = step.get("id", "")
	if current_step_id is String and current_step_id == "munde:keyword:genout/wpm_100_443_127":
		var owner_frame: Dictionary = transition_frame(b)
		var result: Dictionary = Candidate.submit_original_keyword(b, reply)
		if not transition_current(b, owner_frame):return
		if not result.get("ok", false):
			keyword_failure = result.duplicate(true)
			var failure_reason: Variant = result.get("reason", "原口令事务失败。")
			handoff(b, failure_reason if failure_reason is String else "原口令事务返回了非文本错误。")
			return
		var original_reply_value: Variant = result.get("result")
		if not original_reply_value is Dictionary:
			keyword_failure = {"ok":false,"reason":"adapter没有保留OriginalQuests.choose的原始返回字典。"}
			handoff(b, keyword_failure.reason)
			return
		var original_reply: Dictionary = original_reply_value
		if not original_reply.get("ok", false) or not original_reply.get("closed", false):
			keyword_failure = {"ok":false,"reason":"OriginalQuests.choose原始返回没有成功关闭。","reply":original_reply.duplicate(true)}
			handoff(b, keyword_failure.reason)
			return
		keyword_observation = result.duplicate(true)
		keyword_committed_this_run = true
		# Parent contract consumes OriginalQuests.choose's no-dialogue reply,
		# not this adapter's observation wrapper. The post-call frame check only
		# observes whether this callback's owner stayed current; strict_advance's
		# caller continuation remains a separate production lifecycle boundary.
		var continuation_frame: Dictionary = transition_frame(b)
		super.strict_dialogue_reply(b, original_reply)
		if not transition_current(b, continuation_frame):return
		return
	if current_step_id is String and current_step_id == "munde:first-boss:100/sb_go.arg":
		var boss: Dictionary = Candidate.observe_boss_page(b, reply)
		if not boss.get("ok", false):
			keyword_failure = boss.duplicate(true)
			var boss_reason: Variant = boss.get("reason", "首Boss原对话页不匹配。")
			handoff(b, boss_reason if boss_reason is String else "首Boss观察返回了非文本错误。")
			return
		boss_page_observation = boss.duplicate(true)
		# Capture the original page, then handoff. Base stop clears pending, so the
		# player must talk to the NPC again to receive a fresh manual yes/no page.
		handoff(b, "已到首Boss；自动任务已关闭原页面，请玩家重新交谈后自行决定。")
		return
	super.strict_dialogue_reply(b, reply)
