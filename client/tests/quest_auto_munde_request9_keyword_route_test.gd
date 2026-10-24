extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## UNRUN: real QuestAuto lifecycle through REQUEST9/11/10, one original WPM
## KEYWORD transaction, source-rooted Warp, and first Boss BATTLE page (before yes).
## Policy/Registry files and their normal job-8 closure remain unchanged.
const Backend = preload("res://server/backend.gd")
const Candidate = preload("res://server/quest_auto_munde_keyword_route_candidate.gd")
const Plan = preload("res://server/quest_auto_munde_plan.gd")
const Auto = preload("res://server/quest_auto.gd")
const Runner = preload("res://tests/support/quest_auto_munde_keyword_route_candidate_runner.gd")
const Rules = preload("res://server/original_quests.gd")
const Session = preload("res://server/game_session.gd")
const Policy = preload("res://scripts/quest_auto_policy.gd")
const Registry = preload("res://server/quest_auto_registry.gd")
const Motion = preload("res://server/quest_auto_motion.gd")
const Passage = preload("res://scripts/passage_rules.gd")
const ArrivalPolicy = preload("res://server/quest_arrival_policy.gd")
const Wait = preload("res://tests/support/wait.gd")

const MAX_LOGICAL_POINTS := 6000
const WAIT_PER_REQUEST := 150.0
const HARD_EXTERNAL_PROPOSAL := 300
const SUITE_NAME := "quest_auto_munde_request9_keyword_route_test"
const TRACE_PATH := "user://munde-request9-10-runner-candidate-trace.json"
const TRACE_TEMP_PATH := "user://munde-request9-10-runner-candidate-trace.json.tmp"
const MAX_FAILURE_TEXT := 160
const MAX_JSON_AUDIT_DEPTH := 32
const MAX_JSON_AUDIT_NODES := 1000000
const MAX_JSON_CONTAINER_ITEMS := 50000
const MAX_ORDINARY_TRACE_SAMPLES := 16
const MAX_TRACE_VARIANT_BYTES := 8388608
const CLIENT_ID := "munde-request9-10-runner-candidate"
const CONNECTION_ID := 91008
const WORLD_MANIFEST_SHA := "5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639"

class DiagnosticBackend extends "res://server/backend.gd":
	var candidate_field_calls := 0
	func _cmd_field_step(command: Dictionary) -> Dictionary:
		candidate_field_calls += 1
		return super._cmd_field_step(command)

## Exact source-locked original roads, villages, and cave doors needed by this candidate.
## Every live portal must match one complete manifest record; map IDs alone
## never authorize an alternate route.
const REVIEWED_PORTALS := [
	{"source":"100warp.create:43","from_map":1000,"cell":[49,116],"to_map":100,"target":[637,491]},
	{"source":"100warp.create:52","from_map":1000,"cell":[49,117],"to_map":100,"target":[637,492]},
	{"source":"100warp.create:61","from_map":1000,"cell":[49,118],"to_map":100,"target":[637,493]},
	{"source":"100warp.create:70","from_map":1000,"cell":[49,119],"to_map":100,"target":[637,494]},
	{"source":"100warp.create:124","from_map":1000,"cell":[117,112],"to_map":100,"target":[706,488]},
	{"source":"100warp.create:133","from_map":1000,"cell":[118,112],"to_map":100,"target":[707,488]},
	{"source":"100warp.create:142","from_map":1000,"cell":[119,112],"to_map":100,"target":[708,488]},
	{"source":"100warp.create:151","from_map":1000,"cell":[120,112],"to_map":100,"target":[709,488]},
	{"source":"100warp.create:160","from_map":1000,"cell":[121,112],"to_map":100,"target":[710,488]},
	{"source":"100warp.create:7","from_map":100,"cell":[638,491],"to_map":1000,"target":[50,116]},
	{"source":"100warp.create:16","from_map":100,"cell":[638,492],"to_map":1000,"target":[50,117]},
	{"source":"100warp.create:25","from_map":100,"cell":[638,493],"to_map":1000,"target":[50,118]},
	{"source":"100warp.create:34","from_map":100,"cell":[638,494],"to_map":1000,"target":[50,119]},
	{"source":"100warp.create:79","from_map":100,"cell":[706,487],"to_map":1000,"target":[117,111]},
	{"source":"100warp.create:88","from_map":100,"cell":[707,487],"to_map":1000,"target":[118,111]},
	{"source":"100warp.create:97","from_map":100,"cell":[708,487],"to_map":1000,"target":[119,111]},
	{"source":"100warp.create:106","from_map":100,"cell":[709,487],"to_map":1000,"target":[120,111]},
	{"source":"100warp.create:115","from_map":100,"cell":[710,487],"to_map":1000,"target":[121,111]},
	{"source":"dungeon00.create:142","from_map":100,"cell":[318,428],"to_map":10101,"target":[14,49]},
	{"source":"dungeon00.create:151","from_map":10101,"cell":[14,49],"to_map":100,"target":[318,428]},
	{"source":"dungeon00.create:160","from_map":10101,"cell":[41,40],"to_map":10102,"target":[46,44]},
	{"source":"dungeon00.create:169","from_map":10102,"cell":[46,44],"to_map":10101,"target":[41,40]},
	{"source":"dungeon00.create:178","from_map":10102,"cell":[13,1],"to_map":10103,"target":[13,8]},
	{"source":"dungeon00.create:187","from_map":10103,"cell":[13,8],"to_map":10102,"target":[13,1]},
	{"source":"dungeon00.create:196","from_map":10103,"cell":[43,49],"to_map":1200,"target":[49,26]},
	{"source":"dungeon00.create:205","from_map":1200,"cell":[49,26],"to_map":10103,"target":[43,49]},
	{"source":"100warp.create:547","from_map":100,"cell":[258,170],"to_map":1400,"target":[70,115]},
	{"source":"100warp.create:556","from_map":100,"cell":[259,170],"to_map":1400,"target":[71,115]},
	{"source":"100warp.create:565","from_map":100,"cell":[260,170],"to_map":1400,"target":[72,115]},
	{"source":"100warp.create:574","from_map":1400,"cell":[70,116],"to_map":100,"target":[258,171]},
	{"source":"100warp.create:583","from_map":1400,"cell":[71,116],"to_map":100,"target":[259,171]},
	{"source":"100warp.create:592","from_map":1400,"cell":[72,116],"to_map":100,"target":[260,171]},
	{"source":"100warp.create:403","from_map":100,"cell":[622,190],"to_map":1300,"target":[24,59]},
	{"source":"100warp.create:412","from_map":100,"cell":[622,191],"to_map":1300,"target":[24,60]},
	{"source":"100warp.create:421","from_map":100,"cell":[622,192],"to_map":1300,"target":[24,61]},
	{"source":"100warp.create:430","from_map":100,"cell":[622,193],"to_map":1300,"target":[24,62]},
	{"source":"100warp.create:439","from_map":100,"cell":[622,194],"to_map":1300,"target":[24,63]},
	{"source":"100warp.create:448","from_map":100,"cell":[622,195],"to_map":1300,"target":[24,64]},
	{"source":"100warp.create:457","from_map":100,"cell":[622,196],"to_map":1300,"target":[24,65]},
	{"source":"100warp.create:466","from_map":100,"cell":[622,197],"to_map":1300,"target":[24,66]},
	{"source":"100warp.create:475","from_map":1300,"cell":[23,59],"to_map":100,"target":[621,190]},
	{"source":"100warp.create:484","from_map":1300,"cell":[23,60],"to_map":100,"target":[621,191]},
	{"source":"100warp.create:493","from_map":1300,"cell":[23,61],"to_map":100,"target":[621,192]},
	{"source":"100warp.create:502","from_map":1300,"cell":[23,62],"to_map":100,"target":[621,193]},
	{"source":"100warp.create:511","from_map":1300,"cell":[23,63],"to_map":100,"target":[621,194]},
	{"source":"100warp.create:520","from_map":1300,"cell":[23,64],"to_map":100,"target":[621,195]},
	{"source":"100warp.create:529","from_map":1300,"cell":[23,65],"to_map":100,"target":[621,196]},
	{"source":"100warp.create:538","from_map":1300,"cell":[23,66],"to_map":100,"target":[621,197]},
	{"source":"11101d.create:16","from_map":11101,"cell":[64,5],"to_map":11102,"target":[46,7]},
	{"source":"11101d.create:34","from_map":11102,"cell":[9,44],"to_map":11103,"target":[11,37]},
	{"source":"11101d.create:52","from_map":11103,"cell":[7,3],"to_map":11104,"target":[7,3]},
	{"source":"11101d.create:70","from_map":11104,"cell":[45,43],"to_map":11105,"target":[46,44]},
	{"source":"11101d.create:88","from_map":11105,"cell":[24,3],"to_map":11106,"target":[24,3]},
	{"source":"11101d.create:106","from_map":11106,"cell":[18,39],"to_map":11107,"target":[18,41]}
]

var backend: Variant
var assertions := 0
var failures := 0
var failed := false
var done := false
var target: Dictionary = {}
var trace: Array = []
var ordinary_trace_total := 0
var ordinary_trace_samples: Array[Dictionary] = []
var ordinary_trace_next := 0
var current_ordinary_failure_detail: Dictionary = {}
var first_failure: Dictionary = {}
var manual_boundary_observation: Dictionary = {}
var trace_write_attempted := false
var trace_write_status := "not_attempted"
var logical_points := 0
var ordinary_walks := 0
var portals := 0
var original_script_warps := 0
var portal_sequence: Array[String] = []
var phase := "request9"
var started_msec := 0
var wait_deadline_msec := 0
var first_live_receipt: Dictionary = {}
var inrun_stale_checked := false
var cancel_probe_done := false
var cancel_old_receipt: Dictionary = {}
var second_step_checked := false
var request11_route_prefix_checked := false
var request10_step_checked := false
var keyword_profile_checked := false
var first_boss_step_checked := false
var transaction_open := false
var transaction_before: Dictionary = {}
var transaction_step_id := ""
var transaction_serial_before := 0
var recorded_transactions: Array[int] = []
var json_audit_nodes := 0

func _initialize() -> void:
	call_deferred("run")

func runner() -> Variant:
	return backend.quest_auto

func locked_request10_branch() -> Dictionary:
	var table_value: Variant = Plan.request10_table()
	if not table_value is Dictionary:return {}
	var table: Dictionary = table_value
	var npcs_value: Variant = table.get("npcs")
	if not npcs_value is Array or npcs_value.size() != 1:return {}
	var npc_value: Variant = npcs_value[0]
	if not npc_value is Dictionary:return {}
	var branches_value: Variant = npc_value.get("branches")
	if not branches_value is Array or branches_value.size() <= 2:return {}
	var branch_value: Variant = branches_value[2]
	return branch_value if branch_value is Dictionary else {}

func navigation():
	return runner().navigation

func state() -> Dictionary:
	if backend == null:return {}
	var result: Dictionary = {"map_id":backend.automation.position_map,"cell":[backend.automation.position_cell.x,backend.automation.position_cell.y],"location":backend.session._profile.get("location",{}),"scope":backend.quest_arrival._scope,"marks":backend.quest_arrival._marks,"stages":backend.quest_arrival._stages,"npc_version":backend.original_quests.npc_state.version,"running":runner().running,"phase":runner().phase,"run_id":runner().identity.run_id,"step_id":runner().identity.step_id,"revision":runner().identity.revision,"position_serial":runner().position_serial}
	return result.duplicate(true)

## Passive snapshot of the original in-memory authority. This reads private
## fields directly and deliberately does not call has_arrival/check_action.
func arrival_observation() -> Dictionary:
	if backend == null:return {}
	var arrival: Variant = backend.quest_arrival
	var authority_cell: Vector2i = arrival._cell
	return {"scope":arrival._scope,"map_id":arrival._map,"cell":[authority_cell.x,authority_cell.y],"can_leave_portal":arrival._can_leave_portal,"marks":arrival._marks.duplicate(true),"stages":arrival._stages.duplicate(true),"epoch":arrival._epoch,"serial":arrival._serial}

func arrival_authority_matches(observation: Dictionary, expected_scope: String, live_map: int, live_cell: Vector2i) -> bool:
	var expected_authority_map: int = live_map if not expected_scope.is_empty() else -1
	var expected_authority_cell: Array = [live_cell.x,live_cell.y] if not expected_scope.is_empty() else [-1,-1]
	var can_leave_value: Variant = observation.get("can_leave_portal")
	return saved_equal(observation.get("scope"),expected_scope) and Plan.same_source(observation.get("map_id"),expected_authority_map) and saved_equal(observation.get("cell"),expected_authority_cell) and can_leave_value is bool

func arrival_auxiliary_unchanged(before: Dictionary, after: Dictionary) -> bool:
	var before_marks: Variant = before.get("marks")
	var after_marks: Variant = after.get("marks")
	var before_stages: Variant = before.get("stages")
	var after_stages: Variant = after.get("stages")
	if not before_marks is Dictionary or not after_marks is Dictionary or not before_stages is Dictionary or not after_stages is Dictionary:return false
	return saved_equal(before_marks,after_marks) and saved_equal(before_stages,after_stages) and not after_marks.has("munde_final") and not after_stages.has("munde_final")

func phase_deadline_open(label: String) -> bool:
	if wait_deadline_msec <= 0 or Clock.ticks_msec() < wait_deadline_msec:return true
	check(false,label)
	return false

func codec_check(ok: bool, label: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		failed = true
		if first_failure.is_empty():first_failure = {"label":label,"phase":phase,"assertions":assertions,"state":state()}
		push_error(label)
	return ok

func check(ok: bool, label: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		failed = true
		if first_failure.is_empty():
			var remaining: Array = []
			if backend != null:
				var current_route: Array = navigation().route
				remaining = current_route.duplicate(true)
			first_failure = {"label":label,"state":state(),"target":target.duplicate(true),"remaining":remaining}
			if not current_ordinary_failure_detail.is_empty():
				first_failure["ordinary_transition_failure_detail"] = current_ordinary_failure_detail.duplicate(true)
			print("MUNDE FAILURE SUMMARY " + JSON.stringify(bounded_failure_summary(label)))
			write_trace()
		push_error(label)
	return ok

## An explicit trace DTO for the successful adapter observation. Its `frame`
## is deliberately omitted: that internal CAS dictionary holds Object refs.
## Existing complete profiles are held once under profile_oracle; the later
## transaction event points here and adds only the independently loaded disk.
func keyword_observation_trace_dto(value: Variant, include_profiles: bool = true) -> Dictionary:
	if not value is Dictionary:return {"dto_error":"observation_type:" + type_string(typeof(value))}
	var observed: Dictionary = value
	var branch_value: Variant = observed.get("branch")
	var resolver_value: Variant = observed.get("resolver")
	var result_value: Variant = observed.get("result")
	var before_profile_value: Variant = observed.get("before")
	var expected_profile_value: Variant = observed.get("expected")
	var after_profile_value: Variant = observed.get("after")
	var evidence_value: Variant = resolver_value.get("evidence") if resolver_value is Dictionary else null
	var authority_value: Variant = observed.get("authority")
	if not branch_value is Dictionary or not resolver_value is Dictionary or not evidence_value is Dictionary or not result_value is Dictionary or not authority_value is Dictionary:
		return {"dto_error":"required_observation_container_shape"}
	if include_profiles and (not before_profile_value is Dictionary or not expected_profile_value is Dictionary or not after_profile_value is Dictionary):
		return {"dto_error":"profile_oracle_container_shape"}
	var resolver: Dictionary = resolver_value
	var evidence: Dictionary = evidence_value
	var original_reply: Dictionary = result_value
	var authority: Dictionary = authority_value
	var cell_value: Variant = authority.get("cell")
	if not cell_value is Array or cell_value.size() != 2:return {"dto_error":"authority_cell_shape"}
	var cell: Array = cell_value
	var arrival_value: Variant = observed.get("arrival")
	var serial_before: Variant = observed.get("save_serial_before")
	var serial_after: Variant = observed.get("save_serial_after")
	var token_value: Variant = observed.get("token")
	if not token_value is String or not arrival_value is bool or not serial_before is int or not serial_after is int:
		return {"dto_error":"required_observation_scalar_type"}
	if not resolver.get("status") is String or not resolver.get("choice") is String or not resolver.get("text") is String:
		return {"dto_error":"resolver_scalar_type"}
	if not evidence.get("source") is String or not evidence.get("source_sha") is String or not evidence.get("table_sha") is String:
		return {"dto_error":"resolver_evidence_type"}
	if not original_reply.get("ok") is bool or not original_reply.get("closed") is bool:
		return {"dto_error":"choose_reply_type"}
	var authority_map: Variant = authority.get("map_id")
	if authority_map is bool or not (authority_map is int or authority_map is float) or (authority_map is float and (not is_finite(float(authority_map)) or float(authority_map) != floor(float(authority_map)))):
		return {"dto_error":"authority_map_type"}
	var safe_cell: Array = []
	for coordinate in cell:
		if coordinate is bool or not (coordinate is int or coordinate is float) or (coordinate is float and (not is_finite(float(coordinate)) or float(coordinate) != floor(float(coordinate)))):
			return {"dto_error":"authority_cell_coordinate_type"}
		safe_cell.append(int(coordinate) if coordinate is float else coordinate)
	var reply_dto: Dictionary = {"ok":original_reply.ok,"closed":original_reply.closed}
	if original_reply.has("reason"):
		if not original_reply.reason is String:return {"dto_error":"choose_reason_type"}
		reply_dto["reason"] = original_reply.reason.substr(0,MAX_FAILURE_TEXT)
	var profile_oracle: Dictionary = {"source":"adapter_existing_snapshots"}
	if include_profiles:
		profile_oracle["before"] = before_profile_value
		profile_oracle["expected"] = expected_profile_value
		profile_oracle["after"] = after_profile_value
	else:
		profile_oracle["source"] = "failure_snapshot_fields"
	return {"ok":observed.get("ok") is bool and observed.get("ok"),"token":token_value,"branch":branch_value.duplicate(true),"resolver":{"status":resolver.status,"choice":resolver.choice,"text":resolver.text,"evidence":{"source":evidence.source,"source_sha":evidence.source_sha,"table_sha":evidence.table_sha}},"original_choose_reply":reply_dto,"save_serial_before":serial_before,"save_serial_after":serial_after,"authority":{"map_id":int(authority_map) if authority_map is float else authority_map,"cell":safe_cell},"arrival":arrival_value,"profile_oracle":profile_oracle}

## Validate the complete payload before touching the output file. This rejects
## Object/RefCounted, Vector, packed containers, non-finite floats and non-string
## dictionary keys instead of stringifying or silently normalizing them.
func json_safety_issue(value: Variant, path: String, depth: int = 0) -> String:
	json_audit_nodes += 1
	if json_audit_nodes > MAX_JSON_AUDIT_NODES:return path.substr(0,240) + ":node_limit"
	if depth > MAX_JSON_AUDIT_DEPTH:return path.substr(0,240) + ":depth_limit"
	var value_type: int = typeof(value)
	if value_type == TYPE_NIL or value_type == TYPE_BOOL or value_type == TYPE_INT or value_type == TYPE_STRING:return ""
	if value_type == TYPE_FLOAT:return "" if is_finite(float(value)) else path.substr(0,240) + ":non_finite_float"
	if value is Array:
		var array_value: Array = value
		if array_value.size() > MAX_JSON_CONTAINER_ITEMS:return path.substr(0,240) + ":array_limit"
		for index in range(array_value.size()):
			var array_issue: String = json_safety_issue(array_value[index],path + "[" + str(index) + "]",depth + 1)
			if not array_issue.is_empty():return array_issue
		return ""
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		if dictionary_value.size() > MAX_JSON_CONTAINER_ITEMS:return path.substr(0,240) + ":dictionary_limit"
		for key in dictionary_value:
			if not key is String:return path.substr(0,240) + ":non_string_key"
			var key_text: String = key
			var child_issue: String = json_safety_issue(dictionary_value[key_text],path + "." + key_text,depth + 1)
			if not child_issue.is_empty():return child_issue
		return ""
	return path.substr(0,240) + ":unsupported_" + type_string(value_type)

func saved_equal(a: Variant, b: Variant) -> bool:
	if a is bool or b is bool:return a is bool and b is bool and a == b
	if a is int or a is float:return (b is int or b is float) and is_finite(float(a)) and is_finite(float(b)) and a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():return false
		for key in a:
			if not b.has(key) or not saved_equal(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():return false
		for index in range(a.size()):
			if not saved_equal(a[index],b[index]):return false
		return true
	return typeof(a) == typeof(b) and a == b

func reviewed_portal(link: Dictionary) -> bool:
	if link.size() != 5:return false
	var source_value: Variant = link.get("source", "")
	if not source_value is String:return false
	for expected in REVIEWED_PORTALS:
		if source_value == expected.source:return saved_equal(link, expected)
	return false

func numeric_container_contract_checks() -> bool:
	var expected: Dictionary = REVIEWED_PORTALS[0]
	var equivalent_float_link: Dictionary = {"source":"100warp.create:43","from_map":1000.0,"cell":[49.0,116.0],"to_map":100.0,"target":[637.0,491.0]}
	if not check(saved_equal(expected,equivalent_float_link) and reviewed_portal(equivalent_float_link) and Motion.cell([49.0,116.0]) == [49,116], "finite integral JSON floats match the same exact source/cell identity"):return false
	var bool_link: Dictionary = equivalent_float_link.duplicate(true)
	bool_link.from_map = true
	if not check(not saved_equal(expected,bool_link) and not reviewed_portal(bool_link) and Motion.cell([true,116]).is_empty(), "boolean map/cell values never compare as numeric coordinates"):return false
	var fractional_link: Dictionary = equivalent_float_link.duplicate(true)
	fractional_link.cell = [49.5,116.0]
	if not check(not saved_equal(expected,fractional_link) and not reviewed_portal(fractional_link) and Motion.cell([49.5,116.0]).is_empty(), "fractional portal coordinates are rejected instead of truncated"):return false
	var nonfinite_link: Dictionary = equivalent_float_link.duplicate(true)
	nonfinite_link.target = [INF,491.0]
	if not check(not saved_equal(expected,nonfinite_link) and not reviewed_portal(nonfinite_link) and Motion.cell([INF,116.0]).is_empty(), "non-finite coordinates are rejected"):return false
	var missing_key_link: Dictionary = equivalent_float_link.duplicate(true)
	missing_key_link.erase("target")
	if not check(not saved_equal(expected,missing_key_link) and not reviewed_portal(missing_key_link), "missing portal identity keys are rejected"):return false
	var extra_key_link: Dictionary = equivalent_float_link.duplicate(true)
	extra_key_link.extra = true
	if not check(not saved_equal(expected,extra_key_link) and not reviewed_portal(extra_key_link), "extra portal identity keys are rejected"):return false
	var reordered_link: Dictionary = equivalent_float_link.duplicate(true)
	reordered_link.cell = [116.0,49.0]
	if not check(not saved_equal(expected,reordered_link) and not reviewed_portal(reordered_link) and Motion.cell(reordered_link.cell) != [49,116], "portal coordinate order remains significant"):return false
	return true

## Receipts remain native Dictionaries for ACK matching. This DTO is only a
## lossless trace encoding: keys and values are stored as typed Variant bytes,
## never coerced into JSON object keys.
func _receipt_variant_traceable(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_JSON_AUDIT_DEPTH:return false
	var value_type: int = typeof(value)
	if value_type == TYPE_OBJECT or value_type == TYPE_CALLABLE or value_type == TYPE_SIGNAL or value_type == TYPE_RID:return false
	if value is Array:
		var array_value: Array = value
		if array_value.size() > MAX_JSON_CONTAINER_ITEMS:return false
		for child in array_value:
			if not _receipt_variant_traceable(child,depth + 1):return false
	elif value is Dictionary:
		var dictionary_value: Dictionary = value
		if dictionary_value.size() > MAX_JSON_CONTAINER_ITEMS:return false
		for key in dictionary_value:
			if not _receipt_variant_traceable(key,depth + 1) or not _receipt_variant_traceable(dictionary_value[key],depth + 1):return false
	return true

func receipt_trace_dto(value: Variant) -> Dictionary:
	if not value is Dictionary:return {"dto_error":"receipt_type:" + type_string(typeof(value))}
	var receipt: Dictionary = value
	if receipt.size() > MAX_JSON_CONTAINER_ITEMS:return {"dto_error":"receipt_entry_limit"}
	var entries: Array = []
	for key in receipt:
		var receipt_value: Variant = receipt[key]
		if not _receipt_variant_traceable(key) or not _receipt_variant_traceable(receipt_value):
			return {"dto_error":"receipt_variant_not_binary_safe"}
		var key_bytes: PackedByteArray = var_to_bytes(key)
		var value_bytes: PackedByteArray = var_to_bytes(receipt_value)
		if key_bytes.is_empty() or value_bytes.is_empty():return {"dto_error":"receipt_variant_encoding_empty"}
		entries.append({"key_type":type_string(typeof(key)),"key_variant_hex":key_bytes.hex_encode(),"value_type":type_string(typeof(receipt_value)),"value_variant_hex":value_bytes.hex_encode()})
	return {"encoding":"godot_variant_bytes_hex_v1","entry_count":entries.size(),"entries":entries}

func receipt_dto_contract_checks() -> bool:
	var sample: Dictionary = {"7":"string-key",7:"integer-key"}
	var sample_before: Dictionary = sample.duplicate(true)
	var dto: Dictionary = receipt_trace_dto(sample)
	if not check(dto.get("encoding") == "godot_variant_bytes_hex_v1" and dto.get("entry_count") == 2 and dto.get("entries") is Array and (dto.get("entries") as Array).size() == 2, "receipt trace DTO preserves each original Dictionary entry in a typed array"):return false
	var found_string := false
	var found_integer := false
	var decoded: Dictionary = {}
	for entry_value in dto.entries:
		if not entry_value is Dictionary:continue
		var entry: Dictionary = entry_value
		var key_hex: Variant = entry.get("key_variant_hex")
		var value_hex: Variant = entry.get("value_variant_hex")
		if not key_hex is String or not value_hex is String or key_hex.is_empty() or value_hex.is_empty():return false
		var decoded_key: Variant = bytes_to_var(key_hex.hex_decode())
		var decoded_value: Variant = bytes_to_var(value_hex.hex_decode())
		if type_string(typeof(decoded_key)) != entry.get("key_type") or type_string(typeof(decoded_value)) != entry.get("value_type"):return false
		if entry.get("key_type") == "String" and entry.get("value_type") == "String":found_string = true
		if entry.get("key_type") == "int" and entry.get("value_type") == "String":found_integer = true
		decoded[decoded_key] = decoded_value
	if not check(found_string and found_integer and saved_equal(decoded,sample_before) and saved_equal(sample,sample_before), "typed receipt entries decode losslessly, preserve distinct String/int keys, and leave the original dictionary unchanged"):return false
	return true

## Flat trace graph codec. Native values are walked with the original node/depth/
## container limits; JSON stores one shallow record per Variant and string refs.
## Typed containers retain a bounded binary witness, but every child is also
## represented and checked, so bytes_to_var never bypasses traversal or safety.
var trace_variant_nodes := 0
var trace_decode_nodes := 0
var trace_graph_records: Array = []
var trace_graph_stack: Array = []
var trace_graph_error := ""
var trace_graph_payload_bytes := 0
var trace_decode_payload_bytes := 0
var trace_decode_records: Array = []
var trace_decode_states: Array[int] = []
const MAX_TRACE_DIAGNOSTIC_NODES: int = 128
const MAX_TRACE_DIAGNOSTIC_DEPTH: int = 16
const MAX_TRACE_DIAGNOSTIC_ITEMS: int = 16
const MAX_TRACE_DIAGNOSTIC_TEXT: int = 96
var trace_diagnostic_nodes: int = 0

func _trace_is_unsafe(value: Variant) -> bool:
	var value_type: int = typeof(value)
	return value_type == TYPE_OBJECT or value_type == TYPE_CALLABLE or value_type == TYPE_SIGNAL or value_type == TYPE_RID

func _trace_is_packed_array(value: Variant) -> bool:
	return value is PackedByteArray or value is PackedInt32Array or value is PackedInt64Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedStringArray or value is PackedVector2Array or value is PackedVector3Array or value is PackedColorArray or value is PackedVector4Array

func _trace_dictionary_key_safe(value: Variant) -> bool:
	return not _trace_is_unsafe(value) and not value is Array and not value is Dictionary and not _trace_is_packed_array(value)

func _trace_account_payload_bytes(amount: int, encode: bool) -> bool:
	if amount < 0:return false
	if encode:
		if amount > MAX_TRACE_VARIANT_BYTES - trace_graph_payload_bytes:return false
		trace_graph_payload_bytes += amount
	else:
		if amount > MAX_TRACE_VARIANT_BYTES - trace_decode_payload_bytes:return false
		trace_decode_payload_bytes += amount
	return true

func _trace_variant_bytes(value: Variant) -> PackedByteArray:
	var encoded: PackedByteArray = var_to_bytes(value)
	if encoded.is_empty():
		trace_graph_error = "variant_encoding_empty_" + type_string(typeof(value))
		return PackedByteArray()
	if not _trace_account_payload_bytes(encoded.size(),true):
		trace_graph_error = "variant_byte_budget"
		return PackedByteArray()
	return encoded

func _trace_native_depth_error(depth: int) -> bool:
	if depth > MAX_JSON_AUDIT_DEPTH:
		trace_graph_error = "native_depth_limit"
		return true
	return false

func _trace_graph_node(value: Variant, depth: int) -> int:
	trace_variant_nodes += 1
	if trace_variant_nodes > MAX_JSON_AUDIT_NODES:
		trace_graph_error = "native_node_limit"
		return -1
	if _trace_native_depth_error(depth):return -1
	if _trace_is_unsafe(value):
		trace_graph_error = "unsafe_" + type_string(typeof(value))
		return -1
	if typeof(value) == TYPE_FLOAT and not is_finite(float(value)):
		trace_graph_error = "non_finite_float"
		return -1
	var node_id: int = trace_graph_records.size()
	trace_graph_records.append([])
	if value is Array or value is Dictionary:
		for ancestor in trace_graph_stack:
			if is_same(ancestor,value):
				trace_graph_error = "native_cycle"
				return -1
		trace_graph_stack.append(value)
		var children_ok := true
		if value is Array:
			var source: Array = value
			if source.size() > MAX_JSON_CONTAINER_ITEMS:
				trace_graph_error = "array_item_limit"
				children_ok = false
			var refs: Array = []
			if children_ok:
				for child in source:
					var child_id: int = _trace_graph_node(child,depth + 1)
					if child_id < 0:
						children_ok = false
						break
					refs.append(str(child_id))
			if children_ok and source.is_typed():
				var witness: PackedByteArray = _trace_variant_bytes(source)
				if witness.is_empty():
					children_ok = false
				else:
					trace_graph_records[node_id] = ["typed_array",witness.hex_encode(),refs]
			elif children_ok:
				trace_graph_records[node_id] = ["array",refs]
		else:
			var source_dictionary: Dictionary = value
			if source_dictionary.size() > MAX_JSON_CONTAINER_ITEMS:
				trace_graph_error = "dictionary_item_limit"
				children_ok = false
			var entries: Array = []
			if children_ok:
				for key in source_dictionary:
					if not _trace_dictionary_key_safe(key):
						trace_graph_error = "unsafe_dictionary_key_" + type_string(typeof(key))
						children_ok = false
						break
					var key_id: int = _trace_graph_node(key,depth + 1)
					if key_id < 0:
						children_ok = false
						break
					var value_id: int = _trace_graph_node(source_dictionary[key],depth + 1)
					if value_id < 0:
						children_ok = false
						break
					entries.append([str(key_id),str(value_id)])
			if children_ok and source_dictionary.is_typed():
				var witness_dictionary: PackedByteArray = _trace_variant_bytes(source_dictionary)
				if witness_dictionary.is_empty():
					children_ok = false
				else:
					trace_graph_records[node_id] = ["typed_dictionary",witness_dictionary.hex_encode(),entries]
			elif children_ok:
				trace_graph_records[node_id] = ["dictionary",entries]
		trace_graph_stack.pop_back()
		if not children_ok:return -1
		return node_id
	if _trace_is_packed_array(value):
		var packed_size: int = value.size()
		if packed_size > MAX_JSON_CONTAINER_ITEMS:
			trace_graph_error = "packed_item_limit"
			return -1
		var packed_refs: Array = []
		for packed_child in value:
			var packed_child_id: int = _trace_graph_node(packed_child,depth + 1)
			if packed_child_id < 0:return -1
			packed_refs.append(str(packed_child_id))
		var packed_bytes: PackedByteArray = _trace_variant_bytes(value)
		if packed_bytes.is_empty():return -1
		trace_graph_records[node_id] = ["packed_array",type_string(typeof(value)),packed_bytes.hex_encode(),packed_refs]
		return node_id
	if value == null:
		trace_graph_records[node_id] = ["nil"]
		return node_id
	if value is bool:
		trace_graph_records[node_id] = ["bool",value]
		return node_id
	if value is String:
		var string_bytes: PackedByteArray = value.to_utf8_buffer()
		if not _trace_account_payload_bytes(string_bytes.size(),true):
			trace_graph_error = "string_byte_budget"
			return -1
		trace_graph_records[node_id] = ["string",value]
		return node_id
	if value is StringName:
		var name_bytes: PackedByteArray = str(value).to_utf8_buffer()
		if not _trace_account_payload_bytes(name_bytes.size(),true):
			trace_graph_error = "string_name_byte_budget"
			return -1
	var scalar_bytes: PackedByteArray = _trace_variant_bytes(value)
	if scalar_bytes.is_empty():return -1
	trace_graph_records[node_id] = ["variant",type_string(typeof(value)),scalar_bytes.hex_encode()]
	return node_id

func _trace_graph_pages(records: Array) -> Array:
	var pages: Array = []
	for start in range(0,records.size(),MAX_JSON_CONTAINER_ITEMS):
		var page: Array = []
		var limit: int = mini(start + MAX_JSON_CONTAINER_ITEMS,records.size())
		for index in range(start,limit):page.append(records[index])
		pages.append(page)
	return pages

func trace_variant_to_dto(value: Variant, depth: int = 0) -> Dictionary:
	trace_variant_nodes = 0
	trace_graph_records.clear()
	trace_graph_stack.clear()
	trace_graph_error = ""
	trace_graph_payload_bytes = 0
	var root_id: int = _trace_graph_node(value,depth)
	if root_id < 0:return {"ok":false,"error":"trace_graph_encode:" + trace_graph_error}
	if root_id != 0:return {"ok":false,"error":"trace_graph_root_not_zero"}
	var dto: Dictionary = {"codec":"variant_graph_v1","root":"0","node_count":str(trace_graph_records.size()),"node_pages":_trace_graph_pages(trace_graph_records)}
	return {"ok":true,"dto":dto,"native_nodes":trace_variant_nodes,"payload_bytes":trace_graph_payload_bytes}

func _trace_parse_canonical_uint(value: Variant, maximum: int) -> int:
	if not value is String:return -1
	var text: String = value
	if text.is_empty() or text.length() > 7 or (text.length() > 1 and text.begins_with("0")):return -1
	for character in text:
		if character < "0" or character > "9":return -1
	var parsed: int = text.to_int()
	if parsed < 0 or parsed > maximum or str(parsed) != text:return -1
	return parsed

func _trace_decode_binary(hex_value: Variant, expected_type: String) -> Dictionary:
	if not hex_value is String:return {"ok":false,"error":"binary_hex_not_string"}
	var hex_text: String = hex_value
	if hex_text.is_empty() or hex_text.length() % 2 != 0 or hex_text.length() > MAX_TRACE_VARIANT_BYTES * 2:return {"ok":false,"error":"binary_hex_shape_or_limit"}
	var bytes: PackedByteArray = hex_text.hex_decode()
	if bytes.is_empty() or bytes.hex_encode() != hex_text:return {"ok":false,"error":"binary_hex_invalid"}
	if not _trace_account_payload_bytes(bytes.size(),false):return {"ok":false,"error":"binary_byte_budget"}
	var decoded: Variant = bytes_to_var(bytes)
	if type_string(typeof(decoded)) != expected_type:return {"ok":false,"error":"binary_type_mismatch"}
	if _trace_is_unsafe(decoded):return {"ok":false,"error":"binary_object_or_unsafe_variant"}
	if typeof(decoded) == TYPE_FLOAT and not is_finite(float(decoded)):return {"ok":false,"error":"binary_non_finite_float"}
	return {"ok":true,"value":decoded}

func _trace_decode_reference(value: Variant, depth: int) -> Dictionary:
	var node_id: int = _trace_parse_canonical_uint(value,trace_decode_records.size() - 1)
	if node_id < 0:return {"ok":false,"error":"invalid_node_reference"}
	if depth > MAX_JSON_AUDIT_DEPTH:return {"ok":false,"error":"native_decode_depth_limit"}
	if trace_decode_states[node_id] == 1:return {"ok":false,"error":"cycle_reference"}
	if trace_decode_states[node_id] == 2:return {"ok":false,"error":"duplicate_node_reference"}
	trace_decode_nodes += 1
	if trace_decode_nodes > MAX_JSON_AUDIT_NODES:return {"ok":false,"error":"native_decode_node_limit"}
	trace_decode_states[node_id] = 1
	var row_value: Variant = trace_decode_records[node_id]
	if not row_value is Array:return {"ok":false,"error":"node_record_not_array"}
	var row: Array = row_value
	if row.is_empty() or not row[0] is String:return {"ok":false,"error":"node_record_tag_shape"}
	var tag: String = row[0]
	var decoded_value: Variant = null
	if tag == "nil":
		if row.size() != 1:return {"ok":false,"error":"nil_node_shape"}
	elif tag == "bool":
		if row.size() != 2 or not row[1] is bool:return {"ok":false,"error":"bool_node_shape"}
		decoded_value = row[1]
	elif tag == "string":
		if row.size() != 2 or not row[1] is String:return {"ok":false,"error":"string_node_shape"}
		var string_bytes: PackedByteArray = row[1].to_utf8_buffer()
		if not _trace_account_payload_bytes(string_bytes.size(),false):return {"ok":false,"error":"string_decode_byte_budget"}
		decoded_value = row[1]
	elif tag == "variant":
		if row.size() != 3 or not row[1] is String:return {"ok":false,"error":"variant_node_shape"}
		var scalar_result: Dictionary = _trace_decode_binary(row[2],row[1])
		if not scalar_result.get("ok",false):return scalar_result
		decoded_value = scalar_result.get("value")
		var scalar_type: int = typeof(decoded_value)
		if scalar_type == TYPE_NIL or scalar_type == TYPE_BOOL or scalar_type == TYPE_STRING or decoded_value is Array or decoded_value is Dictionary or _trace_is_packed_array(decoded_value):return {"ok":false,"error":"variant_node_container_or_dedicated_leaf"}
	elif tag == "array" or tag == "typed_array":
		var typed: bool = tag == "typed_array"
		var ref_field: int = 2 if typed else 1
		if row.size() != ref_field + 1 or not row[ref_field] is Array:return {"ok":false,"error":"array_node_shape"}
		var refs: Array = row[ref_field]
		if refs.size() > MAX_JSON_CONTAINER_ITEMS:return {"ok":false,"error":"array_reference_limit"}
		var child_values: Array = []
		for ref in refs:
			var child_result: Dictionary = _trace_decode_reference(ref,depth + 1)
			if not child_result.get("ok",false):return child_result
			child_values.append(child_result.get("value"))
		if typed:
			var typed_result: Dictionary = _trace_decode_binary(row[1],"Array")
			if not typed_result.get("ok",false):return typed_result
			var typed_value: Variant = typed_result.get("value")
			if not typed_value is Array or not (typed_value as Array).is_typed() or (typed_value as Array).size() != child_values.size():return {"ok":false,"error":"typed_array_witness_shape"}
			for index in range(child_values.size()):
				if not trace_variant_exact_equal((typed_value as Array)[index],child_values[index]):return {"ok":false,"error":"typed_array_child_mismatch"}
			decoded_value = typed_value
		else:
			decoded_value = child_values
	elif tag == "dictionary" or tag == "typed_dictionary":
		var typed_dict: bool = tag == "typed_dictionary"
		var entries_field: int = 2 if typed_dict else 1
		if row.size() != entries_field + 1 or not row[entries_field] is Array:return {"ok":false,"error":"dictionary_node_shape"}
		var entry_refs: Array = row[entries_field]
		if entry_refs.size() > MAX_JSON_CONTAINER_ITEMS:return {"ok":false,"error":"dictionary_entry_limit"}
		var decoded_entries: Array = []
		var decoded_key_probe: Dictionary = {}
		for entry_value in entry_refs:
			if not entry_value is Array or (entry_value as Array).size() != 2:return {"ok":false,"error":"dictionary_entry_reference_shape"}
			var entry: Array = entry_value
			var key_result: Dictionary = _trace_decode_reference(entry[0],depth + 1)
			if not key_result.get("ok",false):return key_result
			var value_result: Dictionary = _trace_decode_reference(entry[1],depth + 1)
			if not value_result.get("ok",false):return value_result
			var key_value: Variant = key_result.get("value")
			if not _trace_dictionary_key_safe(key_value):return {"ok":false,"error":"unsafe_decoded_dictionary_key"}
			var previous_key_count: int = decoded_key_probe.size()
			decoded_key_probe[key_value] = true
			if decoded_key_probe.size() != previous_key_count + 1:return {"ok":false,"error":"duplicate_dictionary_key"}
			decoded_entries.append([key_value,value_result.get("value")])
		if typed_dict:
			var typed_dictionary_result: Dictionary = _trace_decode_binary(row[1],"Dictionary")
			if not typed_dictionary_result.get("ok",false):return typed_dictionary_result
			var typed_dictionary: Variant = typed_dictionary_result.get("value")
			if not typed_dictionary is Dictionary or not (typed_dictionary as Dictionary).is_typed() or (typed_dictionary as Dictionary).size() != decoded_entries.size():return {"ok":false,"error":"typed_dictionary_witness_shape"}
			var matched_typed_keys: Dictionary = {}
			for entry_pair in decoded_entries:
				var found_typed_key := false
				for typed_key in (typed_dictionary as Dictionary):
					if trace_variant_exact_equal(typed_key,entry_pair[0]):
						if not trace_variant_exact_equal((typed_dictionary as Dictionary)[typed_key],entry_pair[1]):return {"ok":false,"error":"typed_dictionary_child_mismatch"}
						var matched_key_bytes: PackedByteArray = _trace_key_bytes(typed_key)
						if matched_key_bytes.is_empty():return {"ok":false,"error":"typed_dictionary_key_encoding"}
						var matched_key_identity: String = type_string(typeof(typed_key)) + ":" + matched_key_bytes.hex_encode()
						if matched_typed_keys.has(matched_key_identity):return {"ok":false,"error":"typed_dictionary_key_reused"}
						matched_typed_keys[matched_key_identity] = true
						found_typed_key = true
						break
				if not found_typed_key:return {"ok":false,"error":"typed_dictionary_key_mismatch"}
			if matched_typed_keys.size() != (typed_dictionary as Dictionary).size():return {"ok":false,"error":"typed_dictionary_key_coverage"}
			decoded_value = typed_dictionary
		else:
			var decoded_dictionary: Dictionary = {}
			for entry_pair in decoded_entries:
				var old_size: int = decoded_dictionary.size()
				decoded_dictionary[entry_pair[0]] = entry_pair[1]
				if decoded_dictionary.size() != old_size + 1:return {"ok":false,"error":"dictionary_key_collision"}
			decoded_value = decoded_dictionary
	elif tag == "packed_array":
		if row.size() != 4 or not row[1] is String or not row[3] is Array:return {"ok":false,"error":"packed_array_shape"}
		var refs: Array = row[3]
		if refs.size() > MAX_JSON_CONTAINER_ITEMS:return {"ok":false,"error":"packed_reference_limit"}
		var child_values: Array = []
		for ref in refs:
			var child_result: Dictionary = _trace_decode_reference(ref,depth + 1)
			if not child_result.get("ok",false):return child_result
			child_values.append(child_result.get("value"))
		var packed_result: Dictionary = _trace_decode_binary(row[2],row[1])
		if not packed_result.get("ok",false):return packed_result
		var packed_value: Variant = packed_result.get("value")
		if not _trace_is_packed_array(packed_value):return {"ok":false,"error":"packed_witness_not_packed"}
		var packed_index: int = 0
		for packed_child in packed_value:
			if packed_index >= child_values.size() or not trace_variant_exact_equal(packed_child,child_values[packed_index]):return {"ok":false,"error":"packed_child_mismatch"}
			packed_index += 1
		if packed_index != child_values.size():return {"ok":false,"error":"packed_child_count_mismatch"}
		decoded_value = packed_value
	else:
		return {"ok":false,"error":"unknown_node_tag"}
	trace_decode_states[node_id] = 2
	return {"ok":true,"value":decoded_value}

func trace_variant_from_dto(dto: Variant, depth: int = 0) -> Dictionary:
	if depth != 0:return {"ok":false,"error":"flat_graph_nonzero_root_depth"}
	if not dto is Dictionary:return {"ok":false,"error":"graph_envelope_not_dictionary"}
	var envelope: Dictionary = dto
	if envelope.size() != 4 or not envelope.has("codec") or not envelope.has("root") or not envelope.has("node_count") or not envelope.has("node_pages"):return {"ok":false,"error":"graph_envelope_keys"}
	for envelope_key in envelope:
		if not envelope_key is String:return {"ok":false,"error":"graph_envelope_key_type"}
	var codec_value: Variant = envelope.get("codec")
	var root_value: Variant = envelope.get("root")
	if not codec_value is String:return {"ok":false,"error":"graph_codec_type"}
	if not root_value is String:return {"ok":false,"error":"graph_root_type"}
	if codec_value != "variant_graph_v1":return {"ok":false,"error":"graph_codec_version"}
	if root_value != "0":return {"ok":false,"error":"graph_root_reference"}
	var node_count: int = _trace_parse_canonical_uint(envelope.get("node_count"),MAX_JSON_AUDIT_NODES)
	if node_count < 1:return {"ok":false,"error":"graph_node_count"}
	var pages_value: Variant = envelope.get("node_pages")
	if not pages_value is Array:return {"ok":false,"error":"graph_pages_not_array"}
	var pages: Array = pages_value
	var expected_pages: int = int((node_count + MAX_JSON_CONTAINER_ITEMS - 1) / MAX_JSON_CONTAINER_ITEMS)
	if pages.size() != expected_pages:return {"ok":false,"error":"graph_page_count"}
	trace_decode_records.clear()
	for page_index in range(pages.size()):
		if not pages[page_index] is Array:return {"ok":false,"error":"graph_page_not_array"}
		var page: Array = pages[page_index]
		var expected_page_size: int = mini(MAX_JSON_CONTAINER_ITEMS,node_count - trace_decode_records.size())
		if page.is_empty() or page.size() != expected_page_size:return {"ok":false,"error":"graph_page_size"}
		trace_decode_records.append_array(page)
	if trace_decode_records.size() != node_count:return {"ok":false,"error":"graph_flattened_count"}
	trace_decode_nodes = 0
	trace_decode_payload_bytes = 0
	trace_decode_states.clear()
	trace_decode_states.resize(node_count)
	for index in range(node_count):trace_decode_states[index] = 0
	var root: Dictionary = _trace_decode_reference("0",0)
	if not root.get("ok",false):return root
	for node_state in trace_decode_states:
		if node_state != 2:return {"ok":false,"error":"orphan_or_duplicate_node_definition"}
	return {"ok":true,"value":root.get("value"),"native_nodes":trace_decode_nodes,"payload_bytes":trace_decode_payload_bytes}

func _trace_key_bytes(value: Variant) -> PackedByteArray:
	return var_to_bytes(value)

func trace_variant_exact_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):return false
	if left is Dictionary and right is Dictionary:
		var a: Dictionary = left
		var b: Dictionary = right
		if a.size() != b.size():return false
		if a.is_typed() or b.is_typed():return _trace_key_bytes(a) == _trace_key_bytes(b)
		for key in a:
			var key_bytes: PackedByteArray = _trace_key_bytes(key)
			var matched: Variant = null
			var found := false
			for other_key in b:
				if typeof(key) == typeof(other_key) and _trace_key_bytes(other_key) == key_bytes:
					matched = other_key
					found = true
					break
			if not found or not trace_variant_exact_equal(a[key],b[matched]):return false
		return true
	if left is Array and right is Array:
		var array_a: Array = left
		var array_b: Array = right
		if array_a.size() != array_b.size():return false
		if array_a.is_typed() or array_b.is_typed():return _trace_key_bytes(array_a) == _trace_key_bytes(array_b)
		for index in range(array_a.size()):
			if not trace_variant_exact_equal(array_a[index],array_b[index]):return false
		return true
	var left_bytes: PackedByteArray = var_to_bytes(left)
	var right_bytes: PackedByteArray = var_to_bytes(right)
	return not left_bytes.is_empty() and left_bytes == right_bytes

func _trace_diagnostic_value(value: Variant) -> Dictionary:
	var value_type: int = typeof(value)
	var summary: Dictionary = {"variant_type":type_string(value_type)}
	if value is Array:
		var array_value: Array = value
		summary["container"] = "Array"
		summary["typed"] = array_value.is_typed()
		summary["typed_builtin"] = str(array_value.get_typed_builtin())
		summary["typed_class_name"] = str(array_value.get_typed_class_name()).substr(0,MAX_TRACE_DIAGNOSTIC_TEXT)
		summary["length"] = str(array_value.size())
	elif value is Dictionary:
		var dictionary_value: Dictionary = value
		summary["container"] = "Dictionary"
		summary["typed"] = dictionary_value.is_typed()
		summary["typed_key_builtin"] = str(dictionary_value.get_typed_key_builtin())
		summary["typed_key_class_name"] = str(dictionary_value.get_typed_key_class_name()).substr(0,MAX_TRACE_DIAGNOSTIC_TEXT)
		summary["typed_value_builtin"] = str(dictionary_value.get_typed_value_builtin())
		summary["typed_value_class_name"] = str(dictionary_value.get_typed_value_class_name()).substr(0,MAX_TRACE_DIAGNOSTIC_TEXT)
		summary["length"] = str(dictionary_value.size())
	elif value == null or value is bool or value is int or value is float or value is String or value is StringName:
		var scalar_text: String = str(value)
		summary["scalar"] = scalar_text.substr(0,MAX_TRACE_DIAGNOSTIC_TEXT)
		if scalar_text.length() > MAX_TRACE_DIAGNOSTIC_TEXT:summary["scalar_truncated"] = true
	return summary

func _trace_diagnostic_difference(path: String, reason: String, left: Variant, right: Variant) -> Dictionary:
	return {"path":path.substr(0,MAX_TRACE_DIAGNOSTIC_TEXT),"reason":reason,"left":_trace_diagnostic_value(left),"right":_trace_diagnostic_value(right)}

func _trace_diagnostic_key_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):return false
	# Flat codec DTO dictionary keys are canonical Strings; avoid broad Variant
	# equality for arbitrary keys while diagnosing this JSON-only graph.
	if not left is String:return false
	return left == right

func trace_variant_first_json_difference(left: Variant, right: Variant, path: String = "$", depth: int = 0) -> Dictionary:
	trace_diagnostic_nodes += 1
	if trace_diagnostic_nodes > MAX_TRACE_DIAGNOSTIC_NODES:return _trace_diagnostic_difference(path,"diagnostic_node_budget",left,right)
	if depth > MAX_TRACE_DIAGNOSTIC_DEPTH:return _trace_diagnostic_difference(path,"diagnostic_depth_budget",left,right)
	if typeof(left) != typeof(right):return _trace_diagnostic_difference(path,"variant_type_mismatch",left,right)
	if left is Array:
		var left_array: Array = left
		var right_array: Array = right
		if left_array.is_typed() != right_array.is_typed() or left_array.get_typed_builtin() != right_array.get_typed_builtin() or left_array.get_typed_class_name() != right_array.get_typed_class_name():
			return _trace_diagnostic_difference(path,"array_typed_metadata_mismatch",left,right)
		if left_array.size() != right_array.size():return _trace_diagnostic_difference(path,"array_length_mismatch",left,right)
		var limit: int = mini(left_array.size(),MAX_TRACE_DIAGNOSTIC_ITEMS)
		for index in range(limit):
			var child_difference: Dictionary = trace_variant_first_json_difference(left_array[index],right_array[index],path + "[" + str(index) + "]",depth + 1)
			if not child_difference.is_empty():return child_difference
		if left_array.size() > limit:return _trace_diagnostic_difference(path + "[" + str(limit) + "]","array_scan_budget",left_array[limit],right_array[limit])
		return {}
	if left is Dictionary:
		var left_dictionary: Dictionary = left
		var right_dictionary: Dictionary = right
		if left_dictionary.is_typed() != right_dictionary.is_typed() or left_dictionary.get_typed_key_builtin() != right_dictionary.get_typed_key_builtin() or left_dictionary.get_typed_key_class_name() != right_dictionary.get_typed_key_class_name() or left_dictionary.get_typed_value_builtin() != right_dictionary.get_typed_value_builtin() or left_dictionary.get_typed_value_class_name() != right_dictionary.get_typed_value_class_name():
			return _trace_diagnostic_difference(path,"dictionary_typed_metadata_mismatch",left,right)
		if left_dictionary.size() != right_dictionary.size():return _trace_diagnostic_difference(path,"dictionary_length_mismatch",left,right)
		var visited: int = 0
		for key in left_dictionary:
			visited += 1
			if visited > MAX_TRACE_DIAGNOSTIC_ITEMS:return _trace_diagnostic_difference(path,"dictionary_scan_budget",left,right)
			var matching_key: Variant = null
			var found: bool = false
			var right_key_count: int = 0
			for other_key in right_dictionary:
				right_key_count += 1
				if right_key_count > MAX_TRACE_DIAGNOSTIC_ITEMS:return _trace_diagnostic_difference(path + ".<key>","dictionary_key_scan_budget",left_dictionary,right_dictionary)
				if _trace_diagnostic_key_equal(key,other_key):
					matching_key = other_key
					found = true
					break
			if not found:return _trace_diagnostic_difference(path + ".<key>","dictionary_key_missing_or_noncanonical",key,right)
			var key_text: String = str(key).substr(0,MAX_TRACE_DIAGNOSTIC_TEXT)
			var child_difference: Dictionary = trace_variant_first_json_difference(left_dictionary[key],right_dictionary[matching_key],path + "." + key_text,depth + 1)
			if not child_difference.is_empty():return child_difference
		return {}
	if left != right:return _trace_diagnostic_difference(path,"safe_scalar_mismatch",left,right)
	return {}

func trace_json_variant_roundtrip(value: Variant) -> Dictionary:
	var encoded: Dictionary = trace_variant_to_dto(value)
	if not encoded.get("ok",false):return {"ok":false,"error":encoded.get("error","dto_encode_failed")}
	var dto: Variant = encoded.get("dto")
	if trace_json_dto_contains_number(dto):return {"ok":false,"error":"dto_contains_json_number"}
	json_audit_nodes = 0
	var unsafe_path: String = json_safety_issue(dto,"flat_graph")
	if not unsafe_path.is_empty():return {"ok":false,"error":"json_safety:" + unsafe_path}
	var json_text: String = JSON.stringify(dto)
	if json_text.is_empty():return {"ok":false,"error":"json_stringify_empty"}
	var parsed := JSON.new()
	var parse_error: int = parsed.parse(json_text)
	if parse_error != OK:return {"ok":false,"error":"json_parse_failed"}
	if not trace_variant_exact_equal(dto,parsed.data):
		trace_diagnostic_nodes = 0
		var first_difference: Dictionary = trace_variant_first_json_difference(dto,parsed.data)
		return {"ok":false,"error":"dto_changed_across_json","first_difference":first_difference}
	var decoded: Dictionary = trace_variant_from_dto(parsed.data)
	if not decoded.get("ok",false):return {"ok":false,"error":decoded.get("error","dto_decode_failed")}
	if not trace_variant_exact_equal(value,decoded.get("value")):return {"ok":false,"error":"native_variant_changed_after_json_roundtrip"}
	return {"ok":true,"dto":dto,"value":decoded.get("value"),"json":json_text}

func trace_json_dto_contains_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	if value_type == TYPE_BOOL:return false
	if value_type == TYPE_INT or value_type == TYPE_FLOAT:return true
	if value is Array:
		for child in value:
			if trace_json_dto_contains_number(child):return true
	elif value is Dictionary:
		for key in value:
			if trace_json_dto_contains_number(key) or trace_json_dto_contains_number(value[key]):return true
	return false

func flat_codec_envelope_for_test(rows: Array, root: String = "0") -> Dictionary:
	var pages: Array = []
	for start in range(0,rows.size(),MAX_JSON_CONTAINER_ITEMS):
		var page: Array = []
		for index in range(start,mini(start + MAX_JSON_CONTAINER_ITEMS,rows.size())):page.append(rows[index])
		pages.append(page)
	return {"codec":"variant_graph_v1","root":root,"node_count":str(rows.size()),"node_pages":pages}

func native_variant_trace_contract_checks() -> bool:
	var same_display_keys: Array = [StringName("7"),"7",7]
	var synthetic: Array = []
	for key in same_display_keys:
		var one_key_dictionary: Dictionary = {}
		one_key_dictionary[key] = {"payload":key,"int64_min":-9223372036854775807 - 1,"int64_max":9223372036854775807,"fractional_float":1.25}
		synthetic.append(one_key_dictionary)
	var json_roundtrip: Dictionary = trace_json_variant_roundtrip(synthetic)
	var first_difference: Variant = json_roundtrip.get("first_difference",{})
	var difference_json: String = JSON.stringify(first_difference) if first_difference is Dictionary else "{}"
	if not codec_check(json_roundtrip.get("ok",false),"same-display StringName/String/int keys, float, and signed-int64 boundaries survive flat graph JSON round-trip: " + str(json_roundtrip.get("error","ok")) + " " + difference_json):return false
	var decoded: Array = json_roundtrip.value
	var decoded_keys: Array = []
	var decoded_keys_valid: bool = decoded.size() == 3
	for index in range(decoded.size()):
		if not decoded[index] is Dictionary or (decoded[index] as Dictionary).size() != 1:
			decoded_keys_valid = false
			break
		decoded_keys.append((decoded[index] as Dictionary).keys()[0])
	var same_display_types_ok: bool = decoded_keys_valid and decoded_keys.size() == 3
	if same_display_types_ok:
		same_display_types_ok = typeof(decoded_keys[0]) == TYPE_STRING_NAME and typeof(decoded_keys[1]) == TYPE_STRING and typeof(decoded_keys[2]) == TYPE_INT and str(decoded_keys[0]) == str(decoded_keys[1]) and str(decoded_keys[1]) == str(decoded_keys[2])
	if not codec_check(same_display_types_ok,"flat JSON graph preserves distinct StringName/String/int keys with the same display text"):return false
	var typed_strings: Array[String] = ["alpha","beta"]
	var typed_roundtrip: Dictionary = trace_json_variant_roundtrip(typed_strings)
	if not codec_check(typed_roundtrip.get("ok",false) and typed_roundtrip.get("value") is Array and (typed_roundtrip.get("value") as Array).is_typed() and trace_variant_exact_equal(typed_strings,typed_roundtrip.get("value")),"typed Array[String] preserves its native type and items through flat JSON graph codec"):return false
	var deep_shape: Dictionary = {}
	var deep_cursor: Dictionary = deep_shape
	for index in range(12):
		var child_dictionary: Dictionary = {}
		deep_cursor["layer_%02d" % index] = child_dictionary
		deep_cursor = child_dictionary
	deep_cursor[StringName("deep-key")] = {"signed64":-9223372036854775807 - 1,"ratio":1.25}
	var deep_roundtrip: Dictionary = trace_json_variant_roundtrip(deep_shape)
	if not codec_check(deep_roundtrip.get("ok",false) and trace_variant_exact_equal(deep_shape,deep_roundtrip.get("value")),"deep native dictionary-value chain with a heterogeneous terminal key stays within native depth while DTO graph remains shallow"):return false
	var unsafe_object: Dictionary = trace_variant_to_dto(RefCounted.new())
	if not codec_check(not unsafe_object.get("ok",false) and str(unsafe_object.get("error","")).contains("unsafe"),"Object/RefCounted payload is refused before binary encoding"):return false
	var cycle: Array = []
	cycle.append(cycle)
	var cycle_result: Dictionary = trace_variant_to_dto(cycle)
	cycle.clear()
	if not codec_check(not cycle_result.get("ok",false) and str(cycle_result.get("error","")).contains("cycle") and trace_graph_stack.is_empty(),"native self-cycle is refused, its self-reference is cleared before assertion exit, and the encoder stack unwinds fully"):return false
	var cycle_dto: Dictionary = flat_codec_envelope_for_test([["array",["0"]]])
	var cycle_decoded: Dictionary = trace_variant_from_dto(cycle_dto)
	if not codec_check(not cycle_decoded.get("ok",false) and cycle_decoded.get("error") == "cycle_reference","decoder refuses a cyclic reference graph"):return false
	var duplicate_ref_dto: Dictionary = flat_codec_envelope_for_test([["array",["1","1"]],["string","child"]])
	var duplicate_ref: Dictionary = trace_variant_from_dto(duplicate_ref_dto)
	if not codec_check(not duplicate_ref.get("ok",false) and duplicate_ref.get("error") == "duplicate_node_reference","decoder refuses shared/duplicate node references rather than silently aliasing"):return false
	var invalid_ref: Dictionary = trace_variant_from_dto(flat_codec_envelope_for_test([["array",["9"]]]))
	if not codec_check(not invalid_ref.get("ok",false) and invalid_ref.get("error") == "invalid_node_reference","decoder rejects out-of-range node references"):return false
	var orphan_ref: Dictionary = trace_variant_from_dto(flat_codec_envelope_for_test([["string","root"],["string","orphan"]]))
	if not codec_check(not orphan_ref.get("ok",false) and orphan_ref.get("error") == "orphan_or_duplicate_node_definition","decoder rejects unreferenced node definitions"):return false
	var malformed_id: Dictionary = trace_variant_from_dto(flat_codec_envelope_for_test([["array",["01"]],["string","child"]]))
	if not codec_check(not malformed_id.get("ok",false) and malformed_id.get("error") == "invalid_node_reference","decoder rejects non-canonical numeric reference strings"):return false
	var boolean_codec_envelope: Dictionary = flat_codec_envelope_for_test([["string","root"]])
	boolean_codec_envelope["codec"] = true
	var boolean_codec: Dictionary = trace_variant_from_dto(boolean_codec_envelope)
	if not codec_check(not boolean_codec.get("ok",false) and boolean_codec.get("error") == "graph_codec_type","decoder type-checks codec before comparing it with a String version"):return false
	var boolean_root_envelope: Dictionary = flat_codec_envelope_for_test([["string","root"]])
	boolean_root_envelope["root"] = false
	var boolean_root: Dictionary = trace_variant_from_dto(boolean_root_envelope)
	if not codec_check(not boolean_root.get("ok",false) and boolean_root.get("error") == "graph_root_type","decoder type-checks root before comparing it with the canonical String reference"):return false
	var disguised_containers: Array = []
	disguised_containers.append(["hidden-array"])
	disguised_containers.append({"hidden":"dictionary"})
	disguised_containers.append(PackedStringArray(["hidden-packed"]))
	var disguised_container_rejected: bool = true
	for disguised_container in disguised_containers:
		var disguised_type: String = type_string(typeof(disguised_container))
		var disguised_bytes: PackedByteArray = var_to_bytes(disguised_container)
		var disguised_result: Dictionary = trace_variant_from_dto(flat_codec_envelope_for_test([["variant",disguised_type,disguised_bytes.hex_encode()]]))
		if disguised_result.get("ok",false) or disguised_result.get("error") != "variant_node_container_or_dedicated_leaf":disguised_container_rejected = false
	if not codec_check(disguised_container_rejected,"variant leaf cannot disguise Array, Dictionary, or packed containers and bypass child traversal"):return false
	var non_finite_bytes: PackedByteArray = var_to_bytes(INF)
	var non_finite_result: Dictionary = trace_variant_from_dto(flat_codec_envelope_for_test([["variant","float",non_finite_bytes.hex_encode()]]))
	if not codec_check(not non_finite_result.get("ok",false) and non_finite_result.get("error") == "binary_non_finite_float","binary float leaves reject non-finite values"):return false
	var typed_witness: Dictionary[String,String] = {"a":"first","b":"second"}
	var typed_duplicate_rows: Array = [["typed_dictionary",var_to_bytes(typed_witness).hex_encode(),[["1","2"],["3","4"]]],["string","a"],["string","first"],["string","a"],["string","first"]]
	var typed_duplicate: Dictionary = trace_variant_from_dto(flat_codec_envelope_for_test(typed_duplicate_rows))
	if not codec_check(not typed_duplicate.get("ok",false) and typed_duplicate.get("error") == "duplicate_dictionary_key","typed dictionary decoder rejects repeated decoded keys before witness matching can reuse one witness key"):return false
	var string_name_bytes: PackedByteArray = var_to_bytes(StringName("same-key"))
	var alias_rows: Array = [["dictionary",[["1","3"],["2","4"]]],["variant","StringName",string_name_bytes.hex_encode()],["string","same-key"],["string","v"],["string","v"]]
	var string_name_alias: Dictionary = trace_variant_from_dto(flat_codec_envelope_for_test(alias_rows))
	if not codec_check(not string_name_alias.get("ok",false) and string_name_alias.get("error") == "duplicate_dictionary_key","decoder rejects String/StringName keys that alias under native Dictionary key equality"):return false
	return true

func continuation_dispatch_contract_checks() -> bool:
	if not check(Candidate.continuation_intent("keyword_route",false) == "keyword", "before keyword commit the original keyword_route can select only KEYWORD"):return false
	if not check(Candidate.continuation_intent("keyword_route",true) == "boss_travel", "after same-run commit keyword_route resumes only travel to the Boss page, never a second KEYWORD"):return false
	if not check(Candidate.continuation_intent("boss_and_stones",false).is_empty(), "boss_and_stones remains manual before same-run keyword commit"):return false
	if not check(Candidate.continuation_intent("boss_and_stones",true) == "boss_page", "at the original Boss boundary same-run commit selects only the Boss page"):return false
	if not check(Candidate.continuation_intent("final_reward",true).is_empty() and Candidate.continuation_intent("partial_state",true).is_empty() and Candidate.continuation_intent("unknown",true).is_empty(), "final reward, partial-state, and unknown stages remain manual"):return false
	return true

func source_sequence_matches(start: int, expected: Array[String]) -> bool:
	if portal_sequence.size() != start + expected.size():return false
	return source_sequence_slice_matches(start, expected)

func source_sequence_slice_matches(start: int, expected: Array[String]) -> bool:
	if start < 0 or portal_sequence.size() < start + expected.size():return false
	for index in range(expected.size()):
		if portal_sequence[start + index] != expected[index]:return false
	return true

func bounded_failure_summary(label: String) -> Dictionary:
	var result: Dictionary = {"label":label.substr(0,MAX_FAILURE_TEXT),"phase":phase,"done":done,"assertions":assertions,"failures":failures,"logical_points":logical_points,"ordinary_walks":ordinary_walks,"portals":portals,"original_script_warps":original_script_warps,"field_calls":backend.candidate_field_calls if backend != null else 0,"trace_write_status":trace_write_status}
	if backend != null:
		var auto: Variant = runner()
		var step_value: Variant = auto.step
		var step_summary: Dictionary = {}
		if step_value is Dictionary:
			var live_step: Dictionary = step_value
			step_summary = {"id":_bounded_scalar(live_step.get("id",""),MAX_FAILURE_TEXT),"npc_id":_bounded_scalar(live_step.get("npc_id",""),MAX_FAILURE_TEXT)}
		var live_cell: Vector2i = backend.automation.position_cell
		var last_handoff_reason := ""
		if not auto.handoff_observations.is_empty():
			var last_handoff_value: Variant = auto.handoff_observations[-1]
			if last_handoff_value is Dictionary:last_handoff_reason = _bounded_scalar(last_handoff_value.get("reason",""),MAX_FAILURE_TEXT)
		result["runner"] = {"running":auto.running,"phase":_bounded_scalar(auto.phase,80),"pause_reason":_bounded_scalar(auto.pause_reason,MAX_FAILURE_TEXT),"keyword_committed":auto.keyword_committed_this_run,"step":step_summary,"live":{"map_id":backend.automation.position_map,"cell":[live_cell.x,live_cell.y]},"handoff_count":auto.handoff_observation_total,"last_handoff_reason":last_handoff_reason}
	var ordinary_failure_value: Variant = first_failure.get("ordinary_transition_failure_detail", {})
	if ordinary_failure_value is Dictionary and not (ordinary_failure_value as Dictionary).is_empty():
		var ordinary_failure: Dictionary = ordinary_failure_value
		result["ordinary_transition_failure"] = {"ordinal":ordinary_failure.get("ordinal",-1),"map":ordinary_failure.get("map",-1),"from":ordinary_failure.get("from",[]),"to":ordinary_failure.get("to",[]),"field_calls_before":ordinary_failure.get("field_calls_before",-1),"field_calls_after":ordinary_failure.get("field_calls_after",-1),"runner_phase":ordinary_failure.get("runner_phase",""),"step":ordinary_failure.get("step",""),"point":_bounded_point_summary(ordinary_failure.get("point",{})),"arrival_conjuncts":ordinary_failure.get("arrival_conjuncts",{})}
	if not manual_boundary_observation.is_empty():
		result["manual_predicates"] = manual_boundary_observation.get("predicates",{}).duplicate(true)
		result["manual_navigation_counts"] = manual_boundary_observation.get("navigation_counts",{}).duplicate(true)
		result["manual_last_point"] = _bounded_point_summary(manual_boundary_observation.get("last_navigation_return",{}))
		result["manual_transactions"] = manual_boundary_observation.get("recorded_transactions",[]).duplicate()
		result["manual_handoffs"] = int(manual_boundary_observation.get("handoff_observation_total",0))
		var failure_value: Variant = manual_boundary_observation.get("keyword_failure",{})
		var failure: Dictionary = failure_value if failure_value is Dictionary else {}
		result["keyword_failure_reason"] = _bounded_scalar(failure.get("reason", ""),MAX_FAILURE_TEXT)
	return result

func _bounded_point_summary(value: Variant) -> Dictionary:
	if not value is Dictionary:return {"type":type_string(typeof(value))}
	var point: Dictionary = value
	var cell_summary: Array[String] = []
	var cell_value: Variant = point.get("cell")
	if cell_value is Array:
		var cell: Array = cell_value
		for index in range(mini(cell.size(), 2)):cell_summary.append(_bounded_scalar(cell[index],24))
	var portal_source: String = ""
	var portal_value: Variant = point.get("portal")
	if portal_value is Dictionary:
		var portal: Dictionary = portal_value
		portal_source = _bounded_scalar(portal.get("source", ""),80)
	return {"has_point":true,"map_id":_bounded_scalar(point.get("map_id", ""),24),"cell":cell_summary,"portal_source":portal_source}

func _bounded_scalar(value: Variant, limit: int) -> String:
	if value is String:return value.substr(0,limit)
	if value is bool or value is int:return str(value).substr(0,limit)
	if value is float:return (str(value) if is_finite(float(value)) else "<non_finite_float>").substr(0,limit)
	return "<" + type_string(typeof(value)) + ">"

func _trace_io_failure(stage: String, error_code: int = -1, expected_bytes: int = -1, actual_bytes: int = -1) -> bool:
	trace_write_status = "failed:" + stage
	print("MUNDE TRACE WRITE FAILURE " + JSON.stringify({"stage":stage,"error":error_code,"expected_bytes":expected_bytes,"actual_bytes":actual_bytes,"original_failure":_bounded_scalar(first_failure.get("label", ""),MAX_FAILURE_TEXT)}))
	return false

func _read_trace_bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:return {"ok":false,"error":FileAccess.get_open_error(),"bytes":PackedByteArray()}
	var length: int = file.get_length()
	var bytes: PackedByteArray = file.get_buffer(length)
	var error_code: int = file.get_error()
	file.close()
	return {"ok":error_code == OK and bytes.size() == length,"error":error_code,"length":length,"bytes":bytes}

func _record_ordinary_trace_sample(record: Dictionary) -> void:
	if ordinary_trace_samples.size() < MAX_ORDINARY_TRACE_SAMPLES:
		ordinary_trace_samples.append(record)
		return
	ordinary_trace_samples[ordinary_trace_next] = record
	ordinary_trace_next = (ordinary_trace_next + 1) % MAX_ORDINARY_TRACE_SAMPLES

func _ordinary_trace_samples_in_order() -> Array:
	var ordered: Array = []
	var sample_count: int = ordinary_trace_samples.size()
	if sample_count < MAX_ORDINARY_TRACE_SAMPLES or ordinary_trace_total <= MAX_ORDINARY_TRACE_SAMPLES:
		for sample_value in ordinary_trace_samples:ordered.append(sample_value.duplicate(true))
		return ordered
	for offset in range(sample_count):
		var index: int = (ordinary_trace_next + offset) % sample_count
		ordered.append(ordinary_trace_samples[index].duplicate(true))
	return ordered

func _ordinary_trace_summary() -> Dictionary:
	return {"kind":"ordinary_cell_trace_summary","observed_transitions":ordinary_trace_total,"successful_ordinary_walks":ordinary_walks,"sample_capacity":MAX_ORDINARY_TRACE_SAMPLES,"retained_samples":ordinary_trace_samples.size(),"overwritten_samples":maxi(0,ordinary_trace_total - ordinary_trace_samples.size()),"samples_oldest_to_newest":_ordinary_trace_samples_in_order()}

func write_trace() -> bool:
	if trace_write_attempted:return false
	trace_write_attempted = true
	var nav_trace: Dictionary = {}
	var handoffs: Array = []
	if backend != null:
		var observed_value: Variant = runner().navigation_observation_probe()
		if observed_value is Dictionary:nav_trace = observed_value.duplicate(true)
		var handoff_value: Variant = runner().handoff_observations
		if handoff_value is Array:handoffs = handoff_value
	# Construct and validate the payload before opening/truncating any output.
	# These are references to already-frozen test observations; no profile is
	# deep-copied a second time solely for serialization.
	var persisted_trace: Array = trace.duplicate()
	persisted_trace.append(_ordinary_trace_summary())
	var payload: Dictionary = {"trace":persisted_trace,"first_failure":first_failure,"manual_boundary":manual_boundary_observation,"handoff_observation_total":runner().handoff_observation_total if backend != null else 0,"handoff_observations":handoffs,"state":state(),"logical_points":logical_points,"ordinary_walks":ordinary_walks,"ordinary_trace_total":ordinary_trace_total,"portals":portals,"portal_sequence":portal_sequence,"original_script_warps":original_script_warps,"field_calls":backend.candidate_field_calls if backend != null else 0,"navigation":nav_trace,"phase":phase,"done":done}
	# Convert the whole frozen native observation graph once. This includes
	# transaction before/earned/disk, keyword profile_oracle, receipts and
	# first-failure/manual snapshots; no separate profile is synthesized here.
	trace_variant_nodes = 0
	var trace_dto_result: Dictionary = trace_variant_to_dto(payload)
	if not trace_dto_result.get("ok",false):return _trace_io_failure("variant_dto:" + str(trace_dto_result.get("error","unknown")))
	var payload_dto: Variant = trace_dto_result.get("dto")
	if trace_json_dto_contains_number(payload_dto):return _trace_io_failure("variant_dto_contains_json_number")
	trace_decode_nodes = 0
	var decoded_payload: Dictionary = trace_variant_from_dto(payload_dto)
	if not decoded_payload.get("ok",false) or not trace_variant_exact_equal(payload,decoded_payload.get("value")):
		return _trace_io_failure("variant_dto_roundtrip:" + str(decoded_payload.get("error","full_native_value_mismatch")))
	# Release the one temporary reconstructed profile graph before the file
	# readback performs its independent decode.
	decoded_payload.clear()
	json_audit_nodes = 0
	var unsafe_path: String = json_safety_issue(payload_dto,"payload_dto")
	if not unsafe_path.is_empty():return _trace_io_failure("json_unsafe:" + unsafe_path)
	var encoded: String = JSON.stringify(payload_dto, "  ")
	if encoded.is_empty():return _trace_io_failure("serialize_empty")
	var expected_bytes: PackedByteArray = encoded.to_utf8_buffer()
	if FileAccess.file_exists(TRACE_PATH) or FileAccess.file_exists(TRACE_TEMP_PATH):return _trace_io_failure("refuse_existing_destination")
	var output := FileAccess.open(TRACE_TEMP_PATH, FileAccess.WRITE)
	if output == null:return _trace_io_failure("open_temp",FileAccess.get_open_error(),expected_bytes.size(),-1)
	output.store_string(encoded)
	output.flush()
	var write_error: int = output.get_error()
	var open_length: int = output.get_length()
	output.close() # FileAccess.close() is void; the closed-file readback below is the close/persistence check.
	if write_error != OK:return _trace_io_failure("store_or_flush",write_error,expected_bytes.size(),open_length)
	if open_length != expected_bytes.size():return _trace_io_failure("open_length",write_error,expected_bytes.size(),open_length)
	var temporary_read: Dictionary = _read_trace_bytes(TRACE_TEMP_PATH)
	if not temporary_read.get("ok",false):return _trace_io_failure("temp_readback",int(temporary_read.get("error",-1)),expected_bytes.size(),int(temporary_read.get("length",-1)))
	var temporary_bytes: Variant = temporary_read.get("bytes")
	if not temporary_bytes is PackedByteArray or temporary_bytes != expected_bytes:return _trace_io_failure("temp_bytes_mismatch",int(temporary_read.get("error",-1)),expected_bytes.size(),temporary_bytes.size() if temporary_bytes is PackedByteArray else -1)
	var absolute_temp: String = ProjectSettings.globalize_path(TRACE_TEMP_PATH)
	var absolute_final: String = ProjectSettings.globalize_path(TRACE_PATH)
	var rename_error: int = DirAccess.rename_absolute(absolute_temp,absolute_final)
	if rename_error != OK:return _trace_io_failure("rename_final",rename_error,expected_bytes.size(),int(temporary_read.get("length",-1)))
	var final_read: Dictionary = _read_trace_bytes(TRACE_PATH)
	if not final_read.get("ok",false):return _trace_io_failure("final_readback",int(final_read.get("error",-1)),expected_bytes.size(),int(final_read.get("length",-1)))
	var final_bytes: Variant = final_read.get("bytes")
	if not final_bytes is PackedByteArray or final_bytes != expected_bytes:return _trace_io_failure("final_bytes_mismatch",int(final_read.get("error",-1)),expected_bytes.size(),final_bytes.size() if final_bytes is PackedByteArray else -1)
	var parsed_trace := JSON.new()
	var parse_error: int = parsed_trace.parse(final_bytes.get_string_from_utf8())
	if parse_error != OK or not trace_variant_exact_equal(parsed_trace.data,payload_dto):return _trace_io_failure("final_json_parse_or_dto_mismatch",parse_error,expected_bytes.size(),final_bytes.size())
	trace_decode_nodes = 0
	var persisted_native: Dictionary = trace_variant_from_dto(parsed_trace.data)
	if not persisted_native.get("ok",false) or not trace_variant_exact_equal(payload,persisted_native.get("value")):
		return _trace_io_failure("final_native_decode_mismatch",-1,expected_bytes.size(),final_bytes.size())
	trace_write_status = "verified"
	print("MUNDE TRACE WRITE VERIFIED " + JSON.stringify({"bytes":expected_bytes.size(),"path":TRACE_PATH,"readback":true,"close_checked_by_reopen":true}))
	return true

func manual_boundary_snapshot() -> Dictionary:
	var profile: Dictionary = backend.session._profile
	var auto: Variant = runner()
	var live_cell: Vector2i = backend.automation.position_cell
	var nav_value: Variant = auto.navigation_observation_probe()
	var nav: Dictionary = nav_value if nav_value is Dictionary else {}
	var step_value: Variant = auto.step
	var step_snapshot: Dictionary = step_value.duplicate(true) if step_value is Dictionary else {}
	var failure_value: Variant = auto.keyword_failure
	var failure_snapshot: Dictionary = failure_value.duplicate(true) if failure_value is Dictionary else {}
	var predicates: Dictionary = {"now9":Rules.flag(profile,"now",9),"now11":Rules.flag(profile,"now",11),"now10":Rules.flag(profile,"now",10),"end10_clear":not Rules.flag(profile,"ended",10),"keyword_committed":auto.keyword_committed_this_run,"boss_page_present":not auto.boss_page_observation.is_empty(),"runner_manual_stopped":not auto.running and auto.phase == "manual"}
	return {"predicates":predicates,"end10":Rules.flag(profile,"ended",10),"runner":{"running":auto.running,"phase":auto.phase,"step":step_snapshot,"step_id":auto.identity.step_id,"pause_reason":auto.pause_reason,"run_id":auto.identity.run_id,"revision":auto.identity.revision,"connection":auto.connection,"client":auto.client},"live":{"map_id":backend.automation.position_map,"cell":[live_cell.x,live_cell.y]},"keyword_failure":failure_snapshot,"boss_page_present":not auto.boss_page_observation.is_empty(),"navigation_counts":{"next":int(nav.get("next_calls",-1)),"plan":int(nav.get("plan_calls",-1)),"local_path":int(nav.get("local_path_calls",-1)),"grid_rebuilds":int(nav.get("grid_rebuilds",-1)),"grid_rebuild_cells":int(nav.get("grid_rebuild_cells",-1))},"last_navigation_return":nav.get("last_point",{}).duplicate(true) if nav.get("last_point",{}) is Dictionary else {},"recorded_transactions":recorded_transactions.duplicate(),"portal_sequence":portal_sequence.duplicate(),"handoff_observation_total":auto.handoff_observation_total,"handoff_observations":auto.handoff_observations.duplicate(true)}

func prepare_backend(save_name: String) -> bool:
	backend = DiagnosticBackend.new()
	backend.set_process(false)
	backend.quest_auto = Runner.new()
	backend.save_path = "user://" + save_name
	var saved_location_value: Variant = backend.session._profile.get("location", {})
	if not check(saved_location_value is Dictionary, "fresh native profile location has its required Dictionary type"):return false
	var saved_location: Dictionary = saved_location_value.duplicate(true)
	if not check(Plan.same_source(saved_location,{"map_id":1000,"x":80,"y":90}), "fresh native default save location is the exact public 1000(80,90) spawn"):return false
	if not check(backend.automation.position_map == -1, "backend starts without a fabricated live position"):return false
	backend.session._profile.player.level = 30
	Rules.set_flag(backend.session._profile, "ended", 4, true)
	if not check(not Rules.flag(backend.session._profile,"now",9) and not Rules.flag(backend.session._profile,"now",11) and not Rules.flag(backend.session._profile,"ended",9) and not Rules.flag(backend.session._profile,"ended",10) and not Rules.flag(backend.session._profile,"ended",11) and not Rules.flag(backend.session._profile,"ended",12), "only explicit LV30/END4 eligibility; no NOW/END completion injected"):return false
	if not check(Plan.same_source(saved_location.get("map_id"),1000) and Plan.same_source(saved_location.get("x"),80) and Plan.same_source(saved_location.get("y"),90), "public spawn components are finite exact integers before creating the normal handshake"):return false
	var handshake: Dictionary = backend.handle({"type":"report_position","map_id":1000,"cell":[80,90],"client":CLIENT_ID})
	if not check(handshake.get("ok",false) and backend.automation.position_map == 1000 and backend.automation.position_cell == Vector2i(80,90), "normal initial client position report establishes saved public spawn"):return false
	if not check(backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty(), "initial handshake gives no protected scope/mark/stage"):return false
	if not check(backend.handle({"type":"no_random_encounters","enabled":true}).get("ok",false), "original no-random compatibility setting saves; not natural-encounter evidence"):return false
	if not check(backend.save(), "isolated candidate save initialized"):return false
	return true

func start_candidate() -> bool:
	var row: Dictionary = runner().row(backend, 8)
	if not check(Plan.same_source(row.get("event", -1),9) and 9 in backend.quest_catalog.enabled_events, "catalog maps job 8 to enabled original event 9"):return false
	if not check(not Policy.supports(8, 9) and not Registry.supports(8), "production Policy and Registry remain closed for job 8/event 9"):return false
	var default_runner: Auto = Auto.new()
	var default_job8_allowed: bool = default_runner._supports_automatic_start(8, 9)
	var default_job2_allowed: bool = default_runner._supports_automatic_start(2, 44)
	if not check(not default_job8_allowed and default_job2_allowed == Policy.supports(2, 44), "production admission method remains default-equivalent to Policy"):return false
	var test_job8_event9_allowed: bool = runner()._supports_automatic_start(8, 9)
	var test_job8_wrong_event_allowed: bool = runner()._supports_automatic_start(8, 10)
	var test_wrong_job_event9_allowed: bool = runner()._supports_automatic_start(1, 9)
	if not check(test_job8_event9_allowed and not test_job8_wrong_event_allowed and not test_wrong_job_event9_allowed, "test subclass admission is limited to original job 8/event 9"):return false
	if not check(not Policy.supports(8, 9) and not Registry.supports(8) and 9 in backend.quest_catalog.enabled_events, "real Policy/Registry stay closed while real catalog and enabled event remain intact"):return false
	if not phase_deadline_open("phase deadline reached before the actual QuestAuto.start call"):return false
	var admitted: Dictionary = backend.handle({"type":"quest_auto_start","quest_id":8,"client":CLIENT_ID,"_quest_connection":CONNECTION_ID})
	if not check(admitted.get("ok",false) and runner().running and runner().strict_walk and runner().phase == "travel", "actual QuestAuto.start and every non-policy start guard admit the real catalog job only through test subclass override"):return false
	if not check(not Policy.supports(8, 9) and not Registry.supports(8) and 9 in backend.quest_catalog.enabled_events, "test-only admission leaves product policy/registry closed and catalog untouched"):return false
	return true

func ack_for(receipt: Dictionary) -> Dictionary:
	var receipt_cell: Array = Motion.cell(receipt.get("cell",[]))
	var ack: Dictionary = {"type":"report_position","map_id":receipt.get("map_id",-1),"cell":receipt_cell,"quest_position_seq":receipt.get("quest_position_seq",-1),"client":CLIENT_ID,"_quest_connection":CONNECTION_ID}
	for field in Motion.IDENTITY_FIELDS:
		if receipt.has(field):ack[field] = receipt[field]
	return ack

func replay_stale(receipt: Dictionary, label: String, expect_running: bool) -> bool:
	if not phase_deadline_open("phase deadline reached before stale-ACK probe"):return false
	var before_state: Dictionary = state()
	var before_profile: Dictionary = backend.session.snapshot()
	var before_serial: int = runner().position_serial
	var before_save: int = backend.quest_save_serial
	var reply: Dictionary = backend.handle(ack_for(receipt))
	return check(reply.get("ok",false) and state() == before_state and saved_equal(backend.session.snapshot(),before_profile) and runner().position_serial == before_serial and backend.quest_save_serial == before_save and runner().running == expect_running, label)

func start_snapshot_check() -> bool:
	if not numeric_container_contract_checks():return false
	if not receipt_dto_contract_checks():return false
	if not native_variant_trace_contract_checks():return false
	if not continuation_dispatch_contract_checks():return false
	var manifest_path := "res://assets/legacy/world/manifest.json"
	var manifest: String = FileAccess.get_file_as_string(manifest_path) if FileAccess.file_exists(manifest_path) else ""
	return check(not manifest.is_empty() and manifest.sha256_text() == WORLD_MANIFEST_SHA, "complete original world manifest matches the reviewed portal identity set")

func run() -> void:
	started_msec = Clock.ticks_msec()
	if not start_snapshot_check():finish();return
	if not prepare_backend("munde-request9-10-runner-candidate.json"):finish();return
	var initial_nav_observation: Dictionary = runner().navigation_observation_probe()
	var initial_last_point: Variant = initial_nav_observation.get("last_point")
	var observer_counters_are_zero: bool = initial_nav_observation.get("next_calls") is int and initial_nav_observation.get("next_calls") == 0 and initial_nav_observation.get("plan_calls") is int and initial_nav_observation.get("plan_calls") == 0 and initial_nav_observation.get("local_path_calls") is int and initial_nav_observation.get("local_path_calls") == 0 and initial_nav_observation.get("grid_rebuilds") is int and initial_nav_observation.get("grid_rebuilds") == 0 and initial_nav_observation.get("grid_rebuild_cells") is int and initial_nav_observation.get("grid_rebuild_cells") == 0
	if not check(initial_nav_observation.get("installed") is bool and initial_nav_observation.get("installed") == true and initial_last_point is Dictionary and (initial_last_point as Dictionary).is_empty() and observer_counters_are_zero, "test runner installs the passive ObservedNavigation subclass and exposes all typed zeroed counters before start/tick"):finish();return
	var first: Dictionary = Candidate.select(backend, 8, false)
	if not check(first.get("status") == "step" and first.step.id == "munde:request:9" and first.step.npc_id == Plan.REQUEST_NPC and Plan.same_source(first.step.map_id,1200) and Plan.same_source(first.step.cell,[97,75]), "exact original REQUEST9 candidate selected from current stage"):finish();return
	if not check(first.step.source.type == "REQUEST" and Plan.same_source(first.step.source.branch_index,1) and Plan.same_source(first.step.source.source_line,14) and first.step.source.source_sha == "7d201e34ea3b230dc9deac43556e6cc50c43647fae01d1a35a6df4cc114618e7" and first.step.source.actions.is_empty() and Plan.same_source(first.step.auto_choices,["yes","ok"]), "complete locked event09 REQUEST source, empty actions only"):finish();return
	if not check(Auto.new().safe_step(first.step, 8), "the existing strict REQUEST guard accepts the reviewed candidate shape"):finish();return
	target = first.step.duplicate(true)
	if not start_candidate():finish();return
	if not check(runner().step.id == first.step.id and Plan.same_source(runner().step.source,first.step.source), "actual QuestAuto.start selected the same full source-locked REQUEST9 step"):finish();return
	wait_deadline_msec = Clock.ticks_msec() + int(WAIT_PER_REQUEST * 1000)
	var reached: bool = await Wait.until(self, drive_request11, WAIT_PER_REQUEST)
	if failed:finish();return
	if not check(reached and phase == "request11" and runner().step.id == "munde:request11", "runner's first native transaction advances to the selected REQUEST11 step within Wait 150"):finish();return
	var first_route_ok := portal_sequence.size() == 5 and portal_sequence[0] in ["100warp.create:43","100warp.create:52","100warp.create:61","100warp.create:70","100warp.create:124","100warp.create:133","100warp.create:142","100warp.create:151","100warp.create:160"] and source_sequence_matches(1, ["dungeon00.create:142","dungeon00.create:160","dungeon00.create:178","dungeon00.create:196"])
	if not check(first_route_ok, "runner's accepted route uses only the original road floors 10101→10102→10103→1200"):finish();return
	if not phase_deadline_open("REQUEST9 phase deadline expired before next source selector"):finish();return
	var second: Dictionary = Candidate.select(backend, 8)
	if not check(second.get("status") == "step" and second.step.id == "munde:request11" and second.step.npc_id == Plan.REQUEST11_NPC and Plan.same_source(second.step.map_id,1400) and Motion.cell(second.step.cell) == [71,76], "earned NOW9 selects exact original Katan REQUEST11"):finish();return
	if not check(second.step.source.type == "REQUEST" and Plan.same_source(second.step.source.branch_index,3) and Plan.same_source(second.step.source.source_line,41) and second.step.source.source_sha == "e6b9230968cbd1669bcade7223c0fc7c4d7b6213320fc0311db0f1394a0540f3" and second.step.source.actions.is_empty() and Plan.same_source(second.step.auto_choices,["yes","ok"]), "full selected REQUEST11 branch3 source and empty actions"):finish();return
	if not check(Auto.new().safe_step(second.step, 8), "the existing strict REQUEST guard accepts the earned next step"):finish();return
	if not phase_deadline_open("REQUEST9 phase deadline expired before the next phase starts"):finish();return
	target = second.step.duplicate(true)
	wait_deadline_msec = Clock.ticks_msec() + int(WAIT_PER_REQUEST * 1000)
	reached = await Wait.until(self, drive_request10_manual, WAIT_PER_REQUEST)
	if failed:finish();return
	if not check(reached and done and phase == "first_boss" and not runner().running and not runner().boss_page_observation.is_empty(), "real REQUEST9/11/10 continuation captures the first original Boss page, then stops before yes within Wait 150"):finish();return
	if not check(recorded_transactions == [9, 11, 10], "all three original transactions were recorded with full profile and native save readback"):finish();return
	if not check(keyword_profile_checked and runner().keyword_committed_this_run and not runner().keyword_observation.is_empty(), "one real public WPM keyword submission committed exactly once before the Boss manual page"):finish();return
	if not check(original_script_warps == 1, "exactly one source-rooted original script Warp was observed after KEYWORD"):finish();return
	var full_route_ok: bool = request11_route_prefix_checked and portal_sequence.size() == 19
	if full_route_ok:full_route_ok = portal_sequence[0] in ["100warp.create:43","100warp.create:52","100warp.create:61","100warp.create:70","100warp.create:124","100warp.create:133","100warp.create:142","100warp.create:151","100warp.create:160"]
	if full_route_ok:full_route_ok = source_sequence_slice_matches(1, ["dungeon00.create:142","dungeon00.create:160","dungeon00.create:178","dungeon00.create:196"])
	if full_route_ok:full_route_ok = source_sequence_slice_matches(5, ["dungeon00.create:205","dungeon00.create:187","dungeon00.create:169","dungeon00.create:151"])
	if full_route_ok:full_route_ok = portal_sequence[9] in ["100warp.create:547","100warp.create:556","100warp.create:565"] and portal_sequence[10] in ["100warp.create:574","100warp.create:583","100warp.create:592"] and portal_sequence[11] in ["100warp.create:403","100warp.create:412","100warp.create:421","100warp.create:430","100warp.create:439","100warp.create:448","100warp.create:457","100warp.create:466"]
	if full_route_ok:full_route_ok = portal_sequence[12] in ["100warp.create:475","100warp.create:484","100warp.create:493","100warp.create:502","100warp.create:511","100warp.create:520","100warp.create:529","100warp.create:538"]
	if full_route_ok:full_route_ok = source_sequence_slice_matches(13, ["11101d.create:16","11101d.create:34","11101d.create:52","11101d.create:70","11101d.create:88","11101d.create:106"])
	if not check(full_route_ok, "the actual prior twelve portals, one original 1300-to-100 door, and all six cave portals occur in source order"):finish();return
	if not check(logical_points <= MAX_LOGICAL_POINTS and backend.candidate_field_calls == ordinary_walks and portals > 0, "all ordinary runner movements executed one original field step; total logical points stay <= 6000"):finish();return
	var boss_observation: Dictionary = runner().boss_page_observation
	if not check(not backend.battle_open and backend.original_quests.pending.is_empty() and backend.session._pending.is_empty(), "base handoff clears the captured source pending page and no battle was started"):finish();return
	if not check(not boss_observation.is_empty() and boss_observation.get("pending",{}).get("phase","") == "BATTLE" and boss_observation.get("branch",{}).get("type","") == "BATTLE" and Plan.same_source(boss_observation.get("dialogue",{}).get("choices",[]),[{"id":"yes","text":"是"},{"id":"no","text":"否"}]), "runner captured the exact original BATTLE yes/no page before base handoff cleared pending; player must reopen it to choose and no choose occurred"):finish();return
	var boss_profile_value: Variant = boss_observation.get("profile")
	var keyword_save_after: Variant = runner().keyword_observation.get("save_serial_after")
	if not check(keyword_save_after is int and not keyword_save_after is bool and boss_profile_value is Dictionary and saved_equal(backend.session.snapshot(),boss_profile_value) and backend.quest_save_serial == keyword_save_after, "manual Boss page and stop add no save/transaction after the one source KEYWORD transaction"):finish();return
	var observed: Variant = navigation()
	print("MUNDE RUNNER REQUEST9->FIRST_BOSS_PAGE_CAPTURED_THEN_CLEARED: points=%d walks=%d portals=%d script_warps=%d fields=%d sources=%s tx=[9,11,10,KEYWORD] next=%d plans=%d local_path=%d grid_rebuilds=%d grid_cells=%d elapsed_ms=%d stop=manual_reopen_battle_page_before_yes" % [logical_points,ordinary_walks,portals,original_script_warps,backend.candidate_field_calls,str(portal_sequence),observed.next_calls,observed.plan_calls,observed.local_path_calls,observed.grid_rebuilds,observed.grid_rebuild_cells,Clock.ticks_msec()-started_msec])
	finish()

func drive_request11() -> bool:
	if failed:return true
	if Clock.ticks_msec() >= wait_deadline_msec:
		check(false, "REQUEST9 Wait 150 deadline; do not begin another synchronous runner/AStar call")
		return true
	if phase == "request11" and runner().step.get("id", "") == "munde:request11":return true
	if not runner().running:
		check(false, "runner stopped before the committed REQUEST9 advanced to REQUEST11")
		return true
	return runner_frame()

func drive_request10_manual() -> bool:
	if failed:return true
	if Clock.ticks_msec() >= wait_deadline_msec:
		check(false, "REQUEST11→REQUEST10 continuation Wait 150 deadline; do not begin another synchronous runner/AStar call")
		return true
	if done:return true
	if not runner().running and runner().phase != "manual":
		check(false, "runner stopped outside the reviewed manual boundary")
		return true
	return runner_frame()

func runner_frame() -> bool:
	current_ordinary_failure_detail = {}
	if failed or done:return true
	if Clock.ticks_msec() - started_msec > int(HARD_EXTERNAL_PROPOSAL * 1000):
		check(false, "300 second hard external wall limit (checked between synchronous runner calls only)")
		return true
	if not phase_deadline_open("absolute phase deadline reached before the next synchronous runner call"):return true
	if runner().phase == "landing":
		var receipts: Array = runner().issued
		if not check(not receipts.is_empty(), "cross-map landing has a server-issued receipt"):return true
		var latest_receipt: Variant = receipts[-1]
		if not check(latest_receipt is Dictionary, "server-issued landing receipt retains its native Dictionary type"):return true
		var receipt_source: Dictionary = latest_receipt
		var receipt: Dictionary = receipt_source.duplicate(true)
		var before_phase: String = runner().phase
		if not phase_deadline_open("phase deadline reached before original portal ACK handling"):return true
		var ack: Dictionary = backend.handle(ack_for(receipt))
		var ack_returned_msec: int = Clock.ticks_msec()
		if wait_deadline_msec > 0 and ack_returned_msec >= wait_deadline_msec:
			trace.append({"kind":"portal_ack_deadline_overrun","phase":before_phase,"returned_msec":ack_returned_msec,"deadline_msec":wait_deadline_msec,"receipt":receipt_trace_dto(receipt),"ack":ack.duplicate(true),"state":state(),"arrival":arrival_observation()})
			check(false, "phase deadline expired during portal ACK handling; stop before another runner call")
			return true
		if not check(ack.get("ok",false) and runner().phase == "travel" and before_phase == "landing", "real Backend report_position dispatch accepts the current full-identity portal ACK"):return true
		trace.append({"kind":"portal_ack","receipt":receipt_trace_dto(receipt),"state":state()})
		return false
	if logical_points >= MAX_LOGICAL_POINTS and runner().phase == "travel":
		var npc: Dictionary = backend.original_quests.npc_by_id(str(runner().step.get("npc_id", "")))
		var npc_cell: Array = Motion.cell(npc.get("cell", []))
		var npc_map: Variant = npc.get("map_id")
		if npc_cell.size() != 2 or not Motion.same_integer(npc_map,backend.automation.position_map):
			check(false, "6000-point cap could not verify the exact locked destination before another runner tick")
			return true
		var offset: Vector2i = backend.automation.position_cell - Vector2i(npc_cell[0],npc_cell[1])
		if maxi(absi(offset.x),absi(offset.y)) > 2:
			check(false, "6000 total logical movement point cap prevents another runner travel tick")
			return true
	var before_map: int = backend.automation.position_map
	var before_cell: Vector2i = backend.automation.position_cell
	var before_phase: String = runner().phase
	var before_step: String = str(runner().step.get("id", ""))
	var before_pending: Dictionary = backend.original_quests.pending.duplicate(true)
	var before_profile: Dictionary = backend.session.snapshot()
	var before_save_serial: int = backend.quest_save_serial
	var fields_before: int = backend.candidate_field_calls
	var keyword_before_tick: bool = runner().keyword_observation.is_empty()
	var before_arrival: Dictionary = arrival_observation()
	if not phase_deadline_open("phase deadline reached before synchronous runner tick"):return true
	runner().tick(backend, 0.21)
	var tick_returned_msec: int = Clock.ticks_msec()
	var phase_deadline_expired: bool = wait_deadline_msec > 0 and tick_returned_msec >= wait_deadline_msec
	var after_map: int = backend.automation.position_map
	var after_cell: Vector2i = backend.automation.position_cell
	var after_arrival: Dictionary = arrival_observation()
	if phase_deadline_expired:
		var script_warp_observed_after_deadline: bool = keyword_before_tick and not runner().keyword_observation.is_empty() and (before_map != after_map or before_cell != after_cell)
		if script_warp_observed_after_deadline:original_script_warps += 1
		var deadline_point: Dictionary = navigation().last_point.duplicate(true)
		first_failure = {"kind":"phase_deadline_after_tick","phase":before_phase,"step":before_step,"returned_msec":tick_returned_msec,"deadline_msec":wait_deadline_msec,"from":[before_map,before_cell.x,before_cell.y],"to":[after_map,after_cell.x,after_cell.y],"point":deadline_point,"arrival_before":before_arrival,"arrival_after":after_arrival,"pending_before":before_pending,"pending_after":backend.original_quests.pending.duplicate(true),"profile_before":before_profile,"profile_after_raw":backend.session._profile.duplicate(true),"save_serial_before":before_save_serial,"save_serial_after":backend.quest_save_serial,"keyword_observation":keyword_observation_trace_dto(runner().keyword_observation,false),"script_warp_observed":script_warp_observed_after_deadline,"runner_running":runner().running,"runner_phase":runner().phase}
		check(false, "phase deadline expired during synchronous runner tick; preserve its result and stop before transaction observation or another runner call")
		return true
	if before_map != after_map or before_cell != after_cell:
		logical_points += 1
		if keyword_before_tick and not runner().keyword_observation.is_empty():
			original_script_warps += 1
			var before_keyword_policy_scope: String = ArrivalPolicy.scope(before_map)
			var before_public_authority: bool = before_keyword_policy_scope.is_empty() and arrival_authority_matches(before_arrival,"",before_map,before_cell)
			var after_munde_authority: bool = arrival_authority_matches(after_arrival,"munde",11101,Vector2i(33,29))
			var warp_arrival_auxiliary_stable: bool = arrival_auxiliary_unchanged(before_arrival,after_arrival)
			var warp_can_leave_value: Variant = after_arrival.get("can_leave_portal")
			var warp_can_leave_matches: bool = warp_can_leave_value is bool and warp_can_leave_value == true
			trace.append({"kind":"source_keyword_warp","from":[before_map,before_cell.x,before_cell.y],"to":[after_map,after_cell.x,after_cell.y],"policy_scope_before":before_keyword_policy_scope,"arrival_before":before_arrival,"arrival_after":after_arrival,"arrival_conjuncts":{"before_public_authority":before_public_authority,"after_munde_authority":after_munde_authority,"auxiliary_stable":warp_arrival_auxiliary_stable,"can_leave_portal":warp_can_leave_matches},"observation":keyword_observation_trace_dto(runner().keyword_observation)})
			if not check(before_public_authority and after_munde_authority and warp_arrival_auxiliary_stable and warp_can_leave_matches and runner().keyword_observation.get("authority",{}).get("map_id") == after_map and Motion.cell(runner().keyword_observation.get("authority",{}).get("cell",[])) == [after_cell.x,after_cell.y] and after_map == 11101 and after_cell == Vector2i(33,29), "original script_root KEYWORD Warp changes empty public scope to Munde authority only through publish_warp"):return true
			if not record_keyword_transaction():return true
		else:
			var point: Dictionary = navigation().last_point.duplicate(true)
			if after_map != before_map:
				var live: Dictionary = backend.quest_helper.places.links(before_map).get(before_cell, {})
				var has_portal: bool = point.has("portal")
				var point_portal_matches_live: bool = has_portal and saved_equal(point.get("portal",{}),live)
				var live_matches_reviewed_source: bool = reviewed_portal(live)
				var point_map_matches: bool = Motion.same_integer(point.get("map_id"),after_map)
				var point_cell_value: Array = Motion.cell(point.get("cell",[]))
				var point_cell_matches: bool = point_cell_value == [after_cell.x,after_cell.y]
				var link_enabled: bool = not bool(live.get("disabled",false))
				var no_gate_source: bool = not live.has("gate_source")
				var no_travel_pass: bool = not bool(live.get("requires_travel_pass",false))
				var no_permit: bool = not Passage.requires_permit(before_map,after_map)
				var origin_scope: String = ArrivalPolicy.scope(before_map)
				var destination_scope: String = ArrivalPolicy.scope(after_map)
				var portal_index: int = portal_sequence.size()
				var expected_portal_scope: String = "" if portal_index < 13 else "munde"
				var origin_scope_matches_route_phase: bool = origin_scope == expected_portal_scope
				var destination_scope_matches_route_phase: bool = destination_scope == expected_portal_scope
				var arrival_before_matches_scope_and_authority: bool = arrival_authority_matches(before_arrival,expected_portal_scope,before_map,before_cell)
				var arrival_after_matches_scope_and_authority: bool = arrival_authority_matches(after_arrival,expected_portal_scope,after_map,after_cell)
				var expected_can_leave_portal: bool = not expected_portal_scope.is_empty()
				var after_can_leave_value: Variant = after_arrival.get("can_leave_portal")
				var after_can_leave_matches: bool = after_can_leave_value is bool and after_can_leave_value == expected_can_leave_portal
				var arrival_auxiliary_stable: bool = arrival_auxiliary_unchanged(before_arrival,after_arrival)
				var arrival_scope_contract: bool = origin_scope_matches_route_phase and destination_scope_matches_route_phase and arrival_before_matches_scope_and_authority and arrival_after_matches_scope_and_authority and after_can_leave_matches and arrival_auxiliary_stable
				var ordinary: bool = has_portal and point_portal_matches_live and live_matches_reviewed_source and point_map_matches and point_cell_matches and link_enabled and no_gate_source and no_travel_pass and no_permit and arrival_scope_contract
				var arrival_checked: bool = ordinary
				var arrival_observed: bool = false
				if arrival_checked:arrival_observed = backend.quest_arrival.has_arrival(backend,after_map,after_cell)
				if not ordinary or not arrival_observed:
					first_failure = {"kind":"portal_rejected" if not ordinary else "arrival_rejected","origin":[before_map,before_cell.x,before_cell.y],"point":point,"live_link":live.duplicate(true),"arrival_before":before_arrival,"arrival_after":after_arrival,"conjuncts":{"has_portal":has_portal,"point_portal_matches_live":point_portal_matches_live,"live_matches_reviewed_source":live_matches_reviewed_source,"point_map_matches":point_map_matches,"point_cell_matches":point_cell_matches,"link_enabled":link_enabled,"no_gate_source":no_gate_source,"no_travel_pass":no_travel_pass,"no_permit":no_permit,"portal_index":portal_index,"expected_portal_scope":expected_portal_scope,"origin_scope_matches_route_phase":origin_scope_matches_route_phase,"destination_scope_matches_route_phase":destination_scope_matches_route_phase,"arrival_before_matches_scope_and_authority":arrival_before_matches_scope_and_authority,"arrival_after_matches_scope_and_authority":arrival_after_matches_scope_and_authority,"after_can_leave_matches":after_can_leave_matches,"arrival_auxiliary_stable":arrival_auxiliary_stable,"arrival_checked":arrival_checked,"arrival_observed":arrival_observed},"raw":{"point_map_id":point.get("map_id"),"expected_map_id":after_map,"point_cell":point.get("cell"),"normalized_point_cell":point_cell_value,"expected_cell":[after_cell.x,after_cell.y],"origin_scope":origin_scope,"destination_scope":destination_scope,"live_link_size":live.size()}}
				if not check(ordinary and arrival_observed, "runner crosses only a source-locked portal with phase-correct scope and observed destination arrival"):return true
				var committed_source_value: Variant = live.get("source", "")
				if not check(committed_source_value is String, "source-locked committed portal retains its String source identity"):return true
				var committed_source: String = committed_source_value
				portal_sequence.append(committed_source)
				portals += 1
				trace.append({"kind":"portal_transition","index":portal_index,"source":_bounded_scalar(live.get("source", ""),160),"source_type":type_string(typeof(live.get("source", ""))),"from":[before_map,before_cell.x,before_cell.y],"to":[after_map,after_cell.x,after_cell.y],"point":point.duplicate(true),"live_link":live.duplicate(true),"expected_scope":expected_portal_scope,"origin_scope":origin_scope,"destination_scope":destination_scope,"arrival_before":before_arrival,"arrival_after":after_arrival,"conjuncts":{"point_portal_matches_live":point_portal_matches_live,"live_matches_reviewed_source":live_matches_reviewed_source,"point_map_matches":point_map_matches,"point_cell_matches":point_cell_matches,"link_enabled":link_enabled,"no_gate_source":no_gate_source,"no_travel_pass":no_travel_pass,"no_permit":no_permit,"origin_scope_matches_route_phase":origin_scope_matches_route_phase,"destination_scope_matches_route_phase":destination_scope_matches_route_phase,"arrival_before_matches_scope_and_authority":arrival_before_matches_scope_and_authority,"arrival_after_matches_scope_and_authority":arrival_after_matches_scope_and_authority,"after_can_leave_matches":after_can_leave_matches,"arrival_auxiliary_stable":arrival_auxiliary_stable,"has_arrival_called_once":arrival_checked,"has_arrival_result":arrival_observed}})
			else:
				var delta := after_cell - before_cell
				var walk_scope: String = ArrivalPolicy.scope(before_map)
				var walk_before_authority: bool = arrival_authority_matches(before_arrival,walk_scope,before_map,before_cell)
				var walk_after_authority: bool = arrival_authority_matches(after_arrival,walk_scope,after_map,after_cell)
				var walk_can_leave_value: Variant = after_arrival.get("can_leave_portal")
				var walk_can_leave_matches: bool = walk_can_leave_value is bool and not walk_can_leave_value
				var walk_arrival_auxiliary_stable: bool = arrival_auxiliary_unchanged(before_arrival,after_arrival)
				var ordinary_record: Dictionary = {"ordinal":ordinary_trace_total + 1,"map":after_map,"from":[before_map,before_cell.x,before_cell.y],"to":[after_map,after_cell.x,after_cell.y],"delta":[delta.x,delta.y],"field_calls_before":fields_before,"field_calls_after":backend.candidate_field_calls,"runner_phase":runner().phase,"step":runner().identity.step_id,"position_serial":runner().position_serial,"arrival_scope":walk_scope,"before_authority":walk_before_authority,"after_authority":walk_after_authority,"can_leave_portal":walk_can_leave_matches,"marks_stages_stable":walk_arrival_auxiliary_stable,"point_has_portal":point.has("portal"),"point_has_gate":point.has("gate")}
				ordinary_trace_total += 1
				_record_ordinary_trace_sample(ordinary_record)
				current_ordinary_failure_detail = {"kind":"ordinary_cell_transition","ordinal":ordinary_trace_total,"map":after_map,"from":[before_map,before_cell.x,before_cell.y],"to":[after_map,after_cell.x,after_cell.y],"delta":[delta.x,delta.y],"point":point.duplicate(true),"field_calls_before":fields_before,"field_calls_after":backend.candidate_field_calls,"runner_phase":runner().phase,"step":runner().identity.step_id,"position_serial":runner().position_serial,"arrival_before":before_arrival,"arrival_after":after_arrival,"arrival_conjuncts":{"scope":walk_scope,"before_authority":walk_before_authority,"after_authority":walk_after_authority,"can_leave_portal":walk_can_leave_matches,"marks_stages_stable":walk_arrival_auxiliary_stable}}
				if not check(absi(delta.x) + absi(delta.y) == 1 and not point.has("portal") and not point.has("gate"), "runner movement remains one original cardinal field cell"):return true
				if not check(walk_before_authority and walk_after_authority and walk_can_leave_matches and walk_arrival_auxiliary_stable, "ordinary field step preserves the source scope/authority contract and does not create a Boss mark"):return true
				ordinary_walks += 1
				if not check(backend.candidate_field_calls == fields_before + 1, "each committed ordinary cell receives exactly one original field_step call"):return true
				if first_live_receipt.is_empty():
					var current_receipts: Array = runner().issued
					if not check(not current_receipts.is_empty(), "ordinary committed move appended its server receipt"):return true
					var latest_live_receipt: Variant = current_receipts[-1]
					if not check(latest_live_receipt is Dictionary, "ordinary server receipt retains its native Dictionary type"):return true
					var live_receipt_source: Dictionary = latest_live_receipt
					first_live_receipt = live_receipt_source.duplicate(true)
			if not inrun_stale_checked and logical_points >= 2 and not first_live_receipt.is_empty():
				inrun_stale_checked = true
				if not replay_stale(first_live_receipt, "an older real-run position ACK is consumed without moving authority, saving, changing sequence, or stopping the current run", true):return true
	else:
		var stationary_arrival_stable: bool = saved_equal(before_arrival,after_arrival)
		if not check(stationary_arrival_stable, "a no-movement runner tick cannot silently change arrival scope, authority, marks, stages, or portal eligibility"):return true
	if before_phase == "travel" and before_pending.is_empty() and runner().phase == "strict_dialogue" and not backend.original_quests.pending.is_empty():
		if before_step == "munde:request11" and not cancel_probe_done:
			if not phase_deadline_open("phase deadline reached before cancellation/restart probe"):return true
			if not cancel_mid_dialogue_and_restart():return true
		else:
			transaction_open = true
			transaction_before = before_profile
			transaction_step_id = before_step
			transaction_serial_before = before_save_serial
	if transaction_open and backend.original_quests.pending.is_empty() and runner().phase == "travel" and backend.quest_save_serial > transaction_serial_before:
		if not phase_deadline_open("phase deadline reached before transaction/readback observation"):return true
		if not record_transaction():return true
	if not keyword_profile_checked and not runner().keyword_observation.is_empty():
		if not phase_deadline_open("phase deadline reached before KEYWORD transaction readback observation"):return true
		if not record_keyword_transaction():return true
	if runner().keyword_committed_this_run and runner().step.get("id","") == "munde:first-boss:100/sb_go.arg" and not first_boss_step_checked:
		first_boss_step_checked = true
		phase = "first_boss"
		if not check(Candidate.exact_travel_step(runner().step,true) and runner().step.source.type == "BATTLE", "after one original keyword transaction the runner selects the exact Boss travel target without selecting battle choice"):return true
		if not check(not runner().safe_step(runner().step, 1), "test-only Boss-page admission is closed when another selected job is supplied"):return true
	if phase == "request11" and runner().step.get("id", "") == "munde:request11" and not second_step_checked:
		second_step_checked = true
		var selected: Dictionary = runner().step
		if not check(selected.npc_id == Plan.REQUEST11_NPC and selected.source.type == "REQUEST" and Plan.same_source(selected.source.branch_index,3) and Plan.same_source(selected.source.source_line,41) and selected.source.source_sha == "e6b9230968cbd1669bcade7223c0fc7c4d7b6213320fc0311db0f1394a0540f3" and selected.source.actions.is_empty(), "actual runner strict selection consumes the exact complete REQUEST11 candidate"):return true
	if phase == "request10" and runner().step.get("id", "") == "munde:request10" and not request10_step_checked:
		request10_step_checked = true
		var selected10: Dictionary = runner().step
		var locked_request10: Dictionary = locked_request10_branch()
		if not check(selected10.npc_id == "sainasu/event/event10@1300:65:65" and Plan.same_source(selected10.map_id,1300) and Motion.cell(selected10.cell) == [65,65], "actual runner reaches the locked Hottle REQUEST10 NPC after live route execution"):return true
		if not check(selected10.source.type == "REQUEST" and Plan.same_source(selected10.source.branch_index,2) and Plan.same_source(selected10.source.source_line,28) and selected10.source.source_sha == "7bfb456f3d7f3604224036554b0abfebbc0a27a33cd3e3df572697d5ba39f13b" and selected10.source.condition == "LV>29&ENDEV=4&NOWEV=9&NOWEV=11" and selected10.source.actions.is_empty() and Plan.same_source(selected10.auto_choices,["yes","ok"]) and not locked_request10.is_empty() and Plan.same_source(selected10.source.branch_data,locked_request10), "highest matching original REQUEST10 source branch 2 exactly matches its full frozen source record"):return true
	if not runner().running and runner().phase == "manual":
		manual_boundary_observation = manual_boundary_snapshot()
		var predicates_value: Variant = manual_boundary_observation.get("predicates")
		var predicates: Dictionary = predicates_value if predicates_value is Dictionary else {}
		done = bool(predicates.get("now9",false)) and bool(predicates.get("now11",false)) and bool(predicates.get("now10",false)) and bool(predicates.get("end10_clear",false)) and bool(predicates.get("keyword_committed",false)) and bool(predicates.get("boss_page_present",false)) and bool(predicates.get("runner_manual_stopped",false))
		trace.append({"kind":"runner_first_boss_manual_stop","observation":manual_boundary_observation.duplicate(true)})
		if not done:check(false, "runner stopped before the one keyword/Warp/first-Boss page boundary or changed an END boundary")
		phase = "first_boss"
	current_ordinary_failure_detail = {}
	return failed or done

func cancel_mid_dialogue_and_restart() -> bool:
	if not phase_deadline_open("phase deadline reached before cancellation stop call"):return false
	var old_run: String = runner().identity.run_id
	var current_map: int = backend.automation.position_map
	var current_cell: Vector2i = backend.automation.position_cell
	var old_receipt: Dictionary = {}
	for receipt_value in runner().issued:
		if not check(receipt_value is Dictionary, "issued receipt retains its native Dictionary type during cancellation scan"):return false
		var receipt: Dictionary = receipt_value
		if Motion.same_integer(receipt.get("map_id"),current_map) and Motion.cell(receipt.get("cell",[])) != [current_cell.x,current_cell.y]:old_receipt = receipt.duplicate(true)
	if not check(not old_receipt.is_empty(), "request11 arrival has an earlier same-map server receipt for cancellation replay"):return false
	var profile_before: Dictionary = backend.session.snapshot()
	var serial_before: int = backend.quest_save_serial
	if not phase_deadline_open("phase deadline reached before quest_auto_stop"):return false
	var stop_reply: Dictionary = backend.handle({"type":"quest_auto_stop"})
	if not check(stop_reply.get("ok",false) and not runner().running and runner().phase == "stopped" and backend.original_quests.pending.is_empty(), "real quest_auto_stop cancels the live runner and clears its pending dialogue"):return false
	if not check(saved_equal(backend.session.snapshot(),profile_before) and backend.quest_save_serial == serial_before and backend.automation.position_map == current_map and backend.automation.position_cell == current_cell, "cancellation before REQUEST11 choice changes neither saved profile nor authority"):return false
	if not replay_stale(old_receipt, "cancelled-run old ACK is consumed and cannot restore an earlier authority position", false):return false
	cancel_probe_done = true
	transaction_open = false
	if not phase_deadline_open("phase deadline reached before restart of the same source-locked route"):return false
	if not start_candidate():return false
	if not check(runner().identity.run_id != old_run and runner().running and backend.automation.position_map == current_map and backend.automation.position_cell == current_cell, "a new admitted run has a fresh identity at the actual current arrival"):return false
	if not replay_stale(old_receipt, "prior-run ACK remains inert after a new run starts", true):return false
	trace.append({"kind":"cancel_restart","old_run":old_run,"new_run":runner().identity.run_id,"old_receipt":receipt_trace_dto(old_receipt)})
	return true

func record_transaction() -> bool:
	if not phase_deadline_open("phase deadline reached before full transaction/readback verification"):return false
	var event_id: int = 9 if transaction_step_id == "munde:request:9" else (11 if transaction_step_id == "munde:request11" else (10 if transaction_step_id == "munde:request10" else -1))
	if not check(event_id in [9,11,10], "transaction observer only accepts the three reviewed native request steps"):return false
	var earned: Dictionary = backend.session.snapshot()
	var expected: Dictionary = transaction_before.duplicate(true)
	Rules.set_flag(expected, "now", event_id, true)
	if not check(saved_equal(earned, expected), "full profile diff is exactly the runner-earned NOW%d flag" % event_id):return false
	var disk = Session.new()
	if not phase_deadline_open("phase deadline reached before original transaction load_game verification"):return false
	var disk_loaded: bool = disk.load_game(backend.save_path)
	var disk_snapshot: Dictionary = disk.snapshot() if disk_loaded else {}
	if not check(disk_loaded and saved_equal(disk_snapshot, earned), "normal native transaction save reads back the complete profile"):return false
	if not phase_deadline_open("phase deadline reached before selector verification of the next source step"):return false
	var following: Dictionary = Candidate.select(backend, 8, runner().keyword_committed_this_run)
	if event_id == 9:
		if not check(following.get("status") == "step" and following.step.id == "munde:request11" and Rules.flag(earned,"now",9), "only actually committed NOW9 enables the next source REQUEST"):return false
		phase = "request11"
	elif event_id == 11:
		if not check(following.get("status") == "step" and following.step.id == "munde:request10" and following.step.npc_id == "sainasu/event/event10@1300:65:65" and Plan.same_source(following.step.source.branch_index,2) and Plan.same_source(following.step.source.source_line,28) and following.step.source.source_sha == "7bfb456f3d7f3604224036554b0abfebbc0a27a33cd3e3df572697d5ba39f13b" and following.step.source.actions.is_empty() and Plan.same_source(following.step.auto_choices,["yes","ok"]) and Rules.flag(earned,"now",11), "only the actual NOW11 save enables the highest locked REQUEST10 proposal"):return false
		var request11_prefix_ok: bool = portal_sequence.size() == 10 and portal_sequence[9] in ["100warp.create:547","100warp.create:556","100warp.create:565"]
		if request11_prefix_ok:request11_prefix_ok = source_sequence_matches(5, ["dungeon00.create:205","dungeon00.create:187","dungeon00.create:169","dungeon00.create:151",portal_sequence[9]])
		if not check(request11_prefix_ok, "at the committed REQUEST11 boundary, exactly the original ten-portal prefix is complete"):return false
		request11_route_prefix_checked = true
		phase = "request10"
	else:
		if not check(following.get("status") == "step" and following.step.get("id","") == "munde:keyword:genout/wpm_100_443_127" and following.step.get("source",{}).get("type","") == "KEYWORD" and Rules.flag(earned,"now",10) and not Rules.flag(earned,"ended",10), "only actually earned NOW10 selects the exact original single-keyword step"):return false
		if not check(not runner().safe_step(following.step, 1), "test-only KEYWORD admission is closed when another selected job is supplied"):return false
		phase = "keyword_route"
	recorded_transactions.append(event_id)
	trace.append({"transaction":"request%d" % event_id,"before":transaction_before,"earned":earned,"disk":disk_snapshot,"disk_location":disk_snapshot.get("location",{}),"next":following.duplicate(true),"state":state()})
	transaction_open = false
	transaction_before = {}
	transaction_step_id = ""
	return true

func record_keyword_transaction() -> bool:
	if not phase_deadline_open("phase deadline reached before KEYWORD save/load verification"):return false
	var observed: Dictionary = runner().keyword_observation
	if not check(portal_sequence.size() == 13 and portals == 13, "exactly thirteen individually source-checked public portals precede the original KEYWORD script root"):return false
	var before_value: Variant = observed.get("before")
	var after_value: Variant = observed.get("after")
	var expected_value: Variant = observed.get("expected")
	if not check(before_value is Dictionary and after_value is Dictionary and expected_value is Dictionary, "keyword transaction observation preserves three complete profile dictionaries"):return false
	var before: Dictionary = before_value
	var after: Dictionary = after_value
	var expected: Dictionary = before.duplicate(true)
	expected["location"] = {"map_id":11101,"x":33,"y":29}
	if not check(saved_equal(expected,expected_value) and saved_equal(after,expected) and saved_equal(observed.get("after"),expected), "single original KEYWORD Warp changes only the complete saved location field; flags/items/equipment/UIDs remain identical"):return false
	var save_before_value: Variant = observed.get("save_serial_before")
	var save_after_value: Variant = observed.get("save_serial_after")
	if not check(save_before_value is int and not save_before_value is bool and save_after_value is int and not save_after_value is bool and Plan.same_source(save_after_value, int(save_before_value) + 1), "the original KEYWORD transaction performs exactly one native save with strict integer serials"):return false
	var disk = Session.new()
	if not phase_deadline_open("phase deadline reached before original KEYWORD load_game verification"):return false
	var disk_loaded: bool = disk.load_game(backend.save_path)
	var disk_snapshot: Dictionary = disk.snapshot() if disk_loaded else {}
	if not check(disk_loaded and saved_equal(disk_snapshot,after), "normal original keyword save independently reloads the entire profile"):return false
	if not check(observed.get("authority",{}).get("map_id") == 11101 and Motion.cell(observed.get("authority",{}).get("cell",[])) == [33,29] and observed.get("arrival") == true, "original publish_warp supplies the expected live destination and exactly observed legitimate arrival"):return false
	if not check(str(observed.get("token","")) != "" and observed.get("result",{}).get("closed",false) and backend.original_quests.pending.is_empty(), "one fresh source token was consumed by one successful original choose"):return false
	keyword_profile_checked = true
	trace.append({"kind":"native_keyword_transaction","profile_oracle_ref":"trace.source_keyword_warp.observation.profile_oracle","disk":disk_snapshot,"resolver":observed.get("resolver",{}),"branch":observed.get("branch",{}),"authority":observed.get("authority",{}),"arrival":observed.get("arrival"),"save_serial_before":observed.get("save_serial_before"),"save_serial_after":observed.get("save_serial_after")})
	return true

func finish() -> void:
	if not trace_write_attempted and not write_trace() and failures == 0:
		failures += 1
		failed = true
		push_error("diagnostic trace could not be persisted and read back")
	if backend != null:backend.free()
	print("%s: %d assertions, %d failures" % [SUITE_NAME,assertions,failures])
	quit(1 if failures else 0)
