extends SceneTree
## UNRUN test-only runner facade. Fixture represents satisfied prior state only;
## this does not test the Boss, real NOW41 acquisition, map travel, or public start.
const Rules = preload("res://server/original_quests.gd")
const Policy = preload("res://scripts/quest_auto_policy.gd")
const ArrivalPolicy = preload("res://server/quest_arrival_policy.gd")
const SaveLock = preload("res://server/save_lock.gd")
const NPC_ID = "sainasu/event/genou_3@100:346:356"
const SOURCE_PATH = "res://server/quest_auto_spirit_wind42_sources.json"
const SOURCE_SHA = "871fd717442b974252d12a7a3817f224f95778ca9aead85b745ce2b19841646f"

class Wind42TestBackend:
	extends "res://server/backend.gd"
	var save_calls := 0
	var source_transaction_calls := 0
	func save() -> bool:
		save_calls += 1
		return super.save()
	func save_quest_source_transaction(npc_id: String, branch: Dictionary, phase: String) -> bool:
		source_transaction_calls += 1
		return super.save_quest_source_transaction(npc_id, branch, phase)

class Wind42RunnerFacade:
	extends "res://server/quest_auto.gd"
	const Plan = preload("res://server/quest_auto_spirit_wind42_plan.gd")
	func strict_select(b, selected_id: int = -1, allow_clean: Variant = null) -> Dictionary:
		var requested_id := quest_id if selected_id < 0 else selected_id
		if requested_id != 39:
			return {"status":"manual","reason":"wind42 fixture facade is restricted to job39"}
		return Plan.request_proposal(b, requested_id)

var assertions := 0
var failures := 0
var backends: Array = []
var fixed_login_time := 0
var owned_save_paths: Array[String] = []
var owned_resume_paths: Array[String] = []
var replaced_runner_refs: Array[WeakRef] = []
var backend_refs: Array[WeakRef] = []
var fallback_lock_releases := 0
var natural_lock_leaks := 0
var preserved_file_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok

func source_table() -> Dictionary:
	var raw := FileAccess.get_file_as_string(SOURCE_PATH)
	if raw.sha256_text() != SOURCE_SHA:
		return {}
	var value: Variant = JSON.parse_string(raw)
	return value if value is Dictionary else {}

func source_value_equal(a: Variant, b: Variant) -> bool:
	# Independent finite-integral number normalization: JSON int/float spellings
	# may differ, but booleans never equal numbers and fractions are preserved.
	if a is bool or b is bool:
		return a is bool and b is bool and a == b
	if a is int or a is float:
		return (b is int or b is float) and is_finite(float(a)) and is_finite(float(b)) and float(a) == floor(float(a)) and float(b) == floor(float(b)) and float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not source_value_equal(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not source_value_equal(a[index], b[index]): return false
		return true
	return typeof(a) == typeof(b) and a == b

func source_branches_equal(actual: Variant, locked: Variant) -> bool:
	if not actual is Array or not locked is Array or actual.size() != locked.size():
		return false
	for index in range(actual.size()):
		if not source_value_equal(actual[index], locked[index]): return false
	return true

func fixed_login_clock() -> int:
	return fixed_login_time

func track_backend(b) -> void:
	backends.append(b)
	backend_refs.append(weakref(b))

func fixture_backend(tag: String) -> Variant:
	var b = Wind42TestBackend.new()
	track_backend(b)
	# GameSession.snapshot() first materializes ItemStorage/OriginalEquipment,
	# original_instances, UID/equipment and other current-version fields.
	b.session.snapshot()
	b.save_path = "user://wind42-%s-%d.json" % [tag, Time.get_ticks_usec()]
	var resume_path: String = b._resume_file()
	var lock_path: String = SaveLock.lock_path(b.save_path)
	for path in [b.save_path, b.save_path + ".bak", b.save_path + ".tmp", resume_path, resume_path + ".tmp", lock_path]:
		if FileAccess.file_exists(path):
			return null
	owned_save_paths.append(b.save_path)
	owned_resume_paths.append(resume_path)
	# Disclosed test fixture only: represent an already-satisfied previous step.
	Rules.set_flag(b.session._profile, "ended", 4, true)
	Rules.set_flag(b.session._profile, "now", 41, true)
	Rules.set_flag(b.session._profile, "now", 42, false)
	Rules.set_flag(b.session._profile, "ended", 42, false)
	b.session._profile.player.level = maxi(1, int(b.session._profile.player.level))
	# No route reward, payment, item delivery, or pet handoff belongs to this slice.
	b.session._profile.original_items.clear()
	b.session._profile.original_instances.clear()
	b.session._profile.original_equipment = {"arm":0,"bracelet":0,"amulet":0,"head":0,"body":0}
	b.session._profile.pets.clear()
	b.session._profile.pet_storage.clear()
	# Fixture declares public NPC as its entry. This is not a route or Warp receipt.
	if not b.session.set_location(100, 346, 356):
		return null
	if not b.automation.position_changed(100, Vector2i(346, 356), true, "project").is_empty():
		return null
	if not b.quest_arrival._scope.is_empty() or not b.quest_arrival._marks.is_empty() or not b.quest_arrival._stages.is_empty() or not b.quest_arrival._warp.is_empty():
		return null
	if not b.save():
		return null
	if not check(b.session._valid_profile(b.session._profile), "fixture native profile passes the existing read-only validator after baseline save"):return null
	return b

func visible_choice(reply: Dictionary, wanted: String) -> Dictionary:
	var dialogue: Variant = reply.get("dialogue")
	if not dialogue is Dictionary:
		return {}
	var token: Variant = dialogue.get("token")
	var choices: Variant = dialogue.get("choices")
	if not token is String or str(token).is_empty() or not choices is Array:
		return {}
	for choice in choices:
		if choice is Dictionary and str(choice.get("id", "")) == wanted:
			return {"token": token, "choice": str(choice.id), "visible_choices": choices.duplicate(true)}
	return {}

func enable_runner_facade(b) -> Variant:
	# Production Registry/Policy remain untouched. Seed only the already-authorized
	# post-qualification runner state; call real tick/strict_advance below, not a fake
	# transaction. Public QuestAuto.start remains outside this test seam.
	var replaced = b.quest_auto
	replaced_runner_refs.append(weakref(replaced))
	var runner = Wind42RunnerFacade.new()
	b.quest_auto = runner
	replaced = null
	runner.quest_id = 39
	runner.running = true
	runner.strict_walk = true
	runner.phase = "travel"
	runner.client = "wind42-test-fixture"
	runner.connection = 1
	runner.identity.begin()
	return runner

const FILE_PROFILE_JSON_MAX_DEPTH: int = 64
const FILE_PROFILE_JSON_OPERATION_BUDGET: int = 131072
const JSON_EXACT_INTEGER_MAX: int = 9007199254740991
const NEGATIVE_JSON_SAFE_BOUNDARY: int = -JSON_EXACT_INTEGER_MAX
const POSITIVE_JSON_SAFE_BOUNDARY: int = JSON_EXACT_INTEGER_MAX
const NEGATIVE_JSON_OUT_OF_RANGE: int = -JSON_EXACT_INTEGER_MAX - 2
const NEGATIVE_JSON_FLOAT_SOURCE: int = -JSON_EXACT_INTEGER_MAX - 1
const POSITIVE_JSON_OUT_OF_RANGE: int = JSON_EXACT_INTEGER_MAX + 2
const POSITIVE_JSON_FLOAT_SOURCE: int = JSON_EXACT_INTEGER_MAX + 1
const SAME_TYPE_LARGE_INTEGER: int = JSON_EXACT_INTEGER_MAX + 2

func file_profile_json_consume(state: Dictionary) -> bool:
	if int(state.remaining) <= 0:
		state.truncated = true
		return false
	state.remaining = int(state.remaining) - 1
	state.visited = int(state.visited) + 1
	return true

func file_profile_json_key_index(source: Dictionary, state: Dictionary, allow_string_name: bool) -> Dictionary:
	var index: Dictionary = {}
	for key in source:
		if not file_profile_json_consume(state): return {"ok":false,"keys":{}}
		var key_type: int = typeof(key)
		var normalized: String = ""
		if key_type == TYPE_STRING:
			normalized = String(key)
		elif allow_string_name and key_type == TYPE_STRING_NAME:
			normalized = String(key)
		else:
			return {"ok":false,"keys":{}}
		if index.has(normalized): return {"ok":false,"keys":{}}
		index[normalized] = key
	return {"ok":true,"keys":index}

func file_profile_json_equal_node(expected: Variant, actual: Variant, state: Dictionary, depth: int) -> bool:
	if depth > FILE_PROFILE_JSON_MAX_DEPTH:
		state.truncated = true
		return false
	if not file_profile_json_consume(state): return false
	if expected is bool or actual is bool:
		return expected is bool and actual is bool and expected == actual
	# JSON.parse_string may represent an integer token as float. Permit
	# only this int->float direction; parsed int/int still compares exactly.
	if expected is int and actual is float:
		var expected_integer: int = expected
		var actual_float: float = actual
		if expected_integer < -JSON_EXACT_INTEGER_MAX or expected_integer > JSON_EXACT_INTEGER_MAX: return false
		if not is_finite(actual_float) or actual_float < -float(JSON_EXACT_INTEGER_MAX) or actual_float > float(JSON_EXACT_INTEGER_MAX): return false
		if floor(actual_float) != actual_float: return false
		return float(expected_integer) == actual_float
	if typeof(expected) != typeof(actual): return false
	match typeof(expected):
		TYPE_NIL:
			return true
		TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return expected == actual
		TYPE_FLOAT:
			var expected_float: float = expected
			var actual_same_float: float = actual
			return is_finite(expected_float) and is_finite(actual_same_float) and expected_float == actual_same_float
		TYPE_ARRAY:
			if expected.size() != actual.size(): return false
			for index in range(expected.size()):
				if not file_profile_json_equal_node(expected[index],actual[index],state,depth+1): return false
			return true
		TYPE_DICTIONARY:
			var expected_result: Dictionary = file_profile_json_key_index(expected,state,true)
			if not expected_result.get("ok",false): return false
			var actual_result: Dictionary = file_profile_json_key_index(actual,state,false)
			if not actual_result.get("ok",false): return false
			var expected_keys: Dictionary = expected_result.get("keys", {})
			var actual_keys: Dictionary = actual_result.get("keys", {})
			if expected_keys.size() != actual_keys.size(): return false
			for normalized_key in expected_keys:
				if not actual_keys.has(normalized_key): return false
				var expected_key: Variant = expected_keys[normalized_key]
				var actual_key: Variant = actual_keys[normalized_key]
				if not file_profile_json_equal_node(expected[expected_key],actual[actual_key],state,depth+1): return false
			return true
		_:
			# StringName values and non-JSON Variant types are not normalized.
			return false

func file_profile_json_compare_with_budget(expected: Variant, actual: Variant, operation_budget: int) -> Dictionary:
	var state: Dictionary = {"remaining":operation_budget,"visited":0,"truncated":false}
	var equal: bool = file_profile_json_equal_node(expected,actual,state,0)
	return {"equal":equal and not state.truncated,"visited":state.visited,"truncated":state.truncated}

func file_profile_json_compare(expected: Variant, actual: Variant) -> Dictionary:
	return file_profile_json_compare_with_budget(expected,actual,FILE_PROFILE_JSON_OPERATION_BUDGET)

func file_profile_json_equal(expected: Variant, actual: Variant) -> bool:
	return bool(file_profile_json_compare(expected,actual).equal)

func run_file_profile_json_contract_tests() -> bool:
	var ok: bool = true
	var stringname_keys: Dictionary = {}
	stringname_keys[StringName("quest")] = {"ready":true}
	ok = check(file_profile_json_equal(stringname_keys,{"quest":{"ready":true}}), "JSON profile keys permit StringName-to-String serialization") and ok
	ok = check(not file_profile_json_equal(true,1), "JSON profile contract keeps bool distinct from int") and ok
	ok = check(not file_profile_json_equal({"quest":true},{StringName("quest"):true}), "parsed JSON side rejects StringName keys") and ok
	ok = check(not file_profile_json_equal({"value":1.0},{"value":1}), "JSON profile rejects float-to-int representation changes") and ok
	ok = check(not file_profile_json_equal({"value":true},{"value":1.0}), "JSON profile keeps bool distinct from float") and ok
	# These are direct comparator Variants, not JSON.parse_string inputs.
	var negative_boundary_expected_integer: int = NEGATIVE_JSON_SAFE_BOUNDARY
	var negative_boundary_actual_float: float = float(negative_boundary_expected_integer)
	var negative_boundary_expected: Dictionary = {"value":negative_boundary_expected_integer}
	var negative_boundary_actual: Dictionary = {"value":negative_boundary_actual_float}
	ok = check(typeof(negative_boundary_expected["value"]) == TYPE_INT and negative_boundary_expected["value"] == negative_boundary_expected_integer and str(negative_boundary_expected_integer) == "-9007199254740991" and typeof(negative_boundary_actual["value"]) == TYPE_FLOAT and negative_boundary_actual["value"] == float(negative_boundary_expected_integer) and int(negative_boundary_actual["value"]) == negative_boundary_expected_integer, "negative safe-boundary synthetic comparator input has exact typed values") and ok
	var expected_number: Variant = negative_boundary_expected["value"]
	var actual_number: Variant = negative_boundary_actual["value"]
	var expected_integer: int = expected_number
	var actual_float: float = actual_number
	var expected_as_float: float = float(expected_integer)
	var actual_is_finite: bool = is_finite(actual_float)
	var expected_inclusive_range: bool = expected_integer >= -JSON_EXACT_INTEGER_MAX and expected_integer <= JSON_EXACT_INTEGER_MAX
	var actual_inclusive_range: bool = actual_is_finite and actual_float >= -float(JSON_EXACT_INTEGER_MAX) and actual_float <= float(JSON_EXACT_INTEGER_MAX)
	var floor_result: Variant = floor(actual_float)
	var floorf_result: float = floorf(actual_float)
	var floor_integral_predicate: bool = floor_result == actual_number
	var floorf_integral_predicate: bool = floorf_result == actual_float
	var safe_roundtrip_checked: bool = false
	var safe_int_float_roundtrip_equal: bool = false
	if actual_inclusive_range and floorf_integral_predicate:
		var actual_integer_roundtrip: int = int(actual_float)
		var actual_float_roundtrip: float = float(actual_integer_roundtrip)
		safe_roundtrip_checked = true
		safe_int_float_roundtrip_equal = actual_float_roundtrip == actual_float
	var negative_boundary_result: Dictionary = file_profile_json_compare(negative_boundary_expected,negative_boundary_actual)
	print("WIND42_NEG_SAFE_BOUND_DIAG " + JSON.stringify({
		"expected_type_id":typeof(expected_number),"actual_type_id":typeof(actual_number),
		"floor_type_id":typeof(floor_result),"floorf_type_id":typeof(floorf_result),
		"expected_integer_text":str(expected_integer),"actual_float_text":str(actual_float),
		"expected_float_text":str(expected_as_float),"floor_text":str(floor_result),"floorf_text":str(floorf_result),
		"expected_range":expected_inclusive_range,"actual_finite":actual_is_finite,"actual_range":actual_inclusive_range,
		"floor_integral":floor_integral_predicate,"floorf_integral":floorf_integral_predicate,
		"expected_float_equals_actual":expected_as_float == actual_float,
		"safe_roundtrip_checked":safe_roundtrip_checked,"safe_int_float_roundtrip_equal":safe_int_float_roundtrip_equal,
		"comparator_equal":negative_boundary_result.get("equal",false),"comparator_visited":negative_boundary_result.get("visited",-1),
		"comparator_truncated":negative_boundary_result.get("truncated",true)
	}))
	ok = check(file_profile_json_equal(negative_boundary_expected,negative_boundary_actual), "negative exact-safe integer boundary is accepted") and ok
	var negative_out_of_range_expected_integer: int = NEGATIVE_JSON_OUT_OF_RANGE
	var negative_out_of_range_float_source_integer: int = NEGATIVE_JSON_FLOAT_SOURCE
	var negative_out_of_range_actual_float: float = float(negative_out_of_range_float_source_integer)
	var negative_out_of_range_expected: Dictionary = {"value":negative_out_of_range_expected_integer}
	var negative_out_of_range_actual: Dictionary = {"value":negative_out_of_range_actual_float}
	ok = check(typeof(negative_out_of_range_expected["value"]) == TYPE_INT and negative_out_of_range_expected["value"] == negative_out_of_range_expected_integer and str(negative_out_of_range_expected_integer) == "-9007199254740993" and typeof(negative_out_of_range_actual["value"]) == TYPE_FLOAT and negative_out_of_range_actual["value"] == float(negative_out_of_range_float_source_integer) and int(negative_out_of_range_actual["value"]) == negative_out_of_range_float_source_integer and str(negative_out_of_range_float_source_integer) == "-9007199254740992", "negative out-of-range synthetic comparator input has exact typed values") and ok
	ok = check(not file_profile_json_equal(negative_out_of_range_expected,negative_out_of_range_actual), "negative integer beyond exact-safe range is rejected") and ok
	var same_type_large_integer: int = SAME_TYPE_LARGE_INTEGER
	var same_type_large_expected: Dictionary = {"value":same_type_large_integer}
	var same_type_large_actual: Dictionary = {"value":same_type_large_integer}
	ok = check(typeof(same_type_large_expected["value"]) == TYPE_INT and same_type_large_expected["value"] == same_type_large_integer and str(same_type_large_integer) == "9007199254740993" and typeof(same_type_large_actual["value"]) == TYPE_INT and same_type_large_actual["value"] == same_type_large_integer, "same-type large integer synthetic inputs retain exact int values") and ok
	ok = check(file_profile_json_equal(same_type_large_expected,same_type_large_actual), "same-type integers compare exactly outside the cross-type safe range") and ok
	var budget_result: Dictionary = file_profile_json_compare_with_budget({"outer":{"inner":1}},{"outer":{"inner":1}},2)
	ok = check(not budget_result.equal and budget_result.truncated and budget_result.visited <= 2, "JSON profile comparator fails closed on a small operation budget") and ok
	ok = check(file_profile_json_equal({"count":41},{"count":41.0}), "JSON integer field accepts its exact integral float encoding") and ok
	ok = check(not file_profile_json_equal({"count":41},{"count":41.5}), "JSON integer field rejects fractional encoding") and ok
	ok = check(not file_profile_json_equal({"count":41},{"count":INF}), "JSON integer field rejects non-finite encoding") and ok
	ok = check(file_profile_json_equal({"rate":1.25},{"rate":1.25}), "JSON profile preserves an allowed fractional float") and ok
	ok = check(not file_profile_json_equal({"rate":1.25},{"rate":1.0}), "fractional float is not truncated to an integer") and ok
	var positive_boundary_integer: int = POSITIVE_JSON_SAFE_BOUNDARY
	var positive_boundary_float: float = float(positive_boundary_integer)
	var positive_boundary_expected: Dictionary = {"count":positive_boundary_integer}
	var positive_boundary_actual: Dictionary = {"count":positive_boundary_float}
	ok = check(typeof(positive_boundary_expected["count"]) == TYPE_INT and positive_boundary_expected["count"] == positive_boundary_integer and str(positive_boundary_integer) == "9007199254740991" and typeof(positive_boundary_actual["count"]) == TYPE_FLOAT and positive_boundary_actual["count"] == float(positive_boundary_integer) and int(positive_boundary_actual["count"]) == positive_boundary_integer, "positive safe-boundary synthetic comparator input has exact typed values") and ok
	ok = check(file_profile_json_equal(positive_boundary_expected,positive_boundary_actual), "largest exact JSON integer boundary is accepted") and ok
	var positive_out_of_range_expected_integer: int = POSITIVE_JSON_OUT_OF_RANGE
	var positive_out_of_range_float_source_integer: int = POSITIVE_JSON_FLOAT_SOURCE
	var positive_out_of_range_actual_float: float = float(positive_out_of_range_float_source_integer)
	var positive_out_of_range_expected: Dictionary = {"count":positive_out_of_range_expected_integer}
	var positive_out_of_range_actual: Dictionary = {"count":positive_out_of_range_actual_float}
	ok = check(typeof(positive_out_of_range_expected["count"]) == TYPE_INT and positive_out_of_range_expected["count"] == positive_out_of_range_expected_integer and str(positive_out_of_range_expected_integer) == "9007199254740993" and typeof(positive_out_of_range_actual["count"]) == TYPE_FLOAT and positive_out_of_range_actual["count"] == float(positive_out_of_range_float_source_integer) and int(positive_out_of_range_actual["count"]) == positive_out_of_range_float_source_integer and str(positive_out_of_range_float_source_integer) == "9007199254740992", "positive out-of-range synthetic comparator input has exact typed values") and ok
	ok = check(not file_profile_json_equal(positive_out_of_range_expected,positive_out_of_range_actual), "integer beyond exact JSON range is rejected") and ok
	ok = check(not file_profile_json_equal({"present":1},{}), "JSON profile rejects missing keys") and ok
	ok = check(not file_profile_json_equal({}, {"extra":1}), "JSON profile rejects extra keys") and ok
	ok = check(not file_profile_json_equal([1,2],[1,2,3]), "JSON profile rejects array length differences") and ok
	var collision: Dictionary = {}
	var collision_string_key: String = "same"
	var collision_stringname_key: StringName = StringName("same")
	collision[collision_string_key] = 1
	var collision_after_string_insert_size: int = collision.size()
	collision[collision_stringname_key] = 1
	var collision_after_stringname_insert_size: int = collision.size()
	var collision_same_name_equal: bool = collision_string_key == collision_stringname_key
	var collision_has_string: bool = collision.has(collision_string_key)
	var collision_has_stringname: bool = collision.has(collision_stringname_key)
	var collision_keys: Array = collision.keys()
	var collision_key_type_ids: Array[int] = []
	var collision_key_index: int = 0
	while collision_key_index < collision_keys.size() and collision_key_index < 2:
		var collision_key: Variant = collision_keys[collision_key_index]
		var collision_key_type_id: int = typeof(collision_key)
		collision_key_type_ids.append(collision_key_type_id)
		collision_key_index += 1
	var collision_comparison: Dictionary = file_profile_json_compare_with_budget(collision,{"same":1},16)
	var collision_size_is_one: bool = collision.size() == 1
	var collision_key_type_is_string: bool = false
	if collision_key_type_ids.size() == 1:
		collision_key_type_is_string = collision_key_type_ids[0] == TYPE_STRING
	var collision_budgeted_comparator_accepts: bool = bool(collision_comparison.get("equal",false))
	var collision_full_budget_comparator_accepts: bool = file_profile_json_equal(collision,{"same":1})
	print("WIND42_SYNTHETIC_COLLISION_DIAG " + JSON.stringify({
		"after_string_insert_size":collision_after_string_insert_size,
		"after_stringname_insert_size":collision_after_stringname_insert_size,
		"same_name_equal":collision_same_name_equal,
		"has_string":collision_has_string,"has_stringname":collision_has_stringname,
		"key_type_ids":collision_key_type_ids,"key_type_is_string":collision_key_type_is_string,
		"size_is_one":collision_size_is_one,
		"budget16_comparator_accepts":collision_budgeted_comparator_accepts,
		"full_budget_comparator_accepts":collision_full_budget_comparator_accepts,
		"budget16_visited":int(collision_comparison.get("visited",0)),
		"budget16_truncated":bool(collision_comparison.get("truncated",true))
	}))
	ok = check(collision_after_string_insert_size == 1 and collision_after_stringname_insert_size == 1 and collision_size_is_one and collision_same_name_equal and collision_has_string and collision_has_stringname and collision_key_type_is_string and collision_full_budget_comparator_accepts, "native Dictionary coalesces same-name String/StringName keys into one String entry accepted by the JSON profile") and ok
	var deep_expected: Variant = {"leaf":true}
	var deep_actual: Variant = {"leaf":true}
	for _index in range(FILE_PROFILE_JSON_MAX_DEPTH+2):
		deep_expected = {"nested":deep_expected}
		deep_actual = {"nested":deep_actual}
	var deep_result: Dictionary = file_profile_json_compare(deep_expected,deep_actual)
	ok = check(not deep_result.equal and deep_result.truncated, "JSON profile comparator fails closed at its depth bound") and ok
	ok = check(not file_profile_json_equal(Vector2i(1,2),Vector2i(1,2)), "non-JSON Variant values are rejected") and ok
	return ok

func assert_file_profile(path: String, expected: Dictionary, expected_raw: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	return parsed is Dictionary and file_profile_json_equal(expected,parsed) and raw == expected_raw

func diagnostic_type_supported(value: Variant) -> bool:
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]

func diagnostic_add(sample: Array, state: Dictionary, row: Dictionary, is_diff: bool = false, is_unsupported: bool = false) -> void:
	if is_diff: state.observed_diff_count = int(state.observed_diff_count) + 1
	if is_unsupported: state.unsupported_count = int(state.unsupported_count) + 1
	if sample.size() < 12: sample.append(row)

func diagnostic_path(parent: String, suffix: String, state: Dictionary, budget: Dictionary) -> String:
	var combined: String = parent + suffix
	if combined.length() > 128:
		state.truncated = true
		budget.truncated = true
		return combined.substr(0,128)
	return combined

func diagnostic_consume(state: Dictionary, budget: Dictionary) -> bool:
	if int(budget.remaining) <= 0:
		state.truncated = true
		budget.truncated = true
		return false
	budget.remaining = int(budget.remaining) - 1
	budget.visited = int(budget.visited) + 1
	state.visited = int(state.visited) + 1
	return true

func diagnostic_diff(expected: Variant, actual: Variant, path: String, depth: int, sample: Array, state: Dictionary, budget: Dictionary) -> void:
	if not diagnostic_consume(state,budget): return
	if depth > 6:
		state.truncated = true
		budget.truncated = true
		return
	var expected_type: int = typeof(expected)
	var actual_type: int = typeof(actual)
	if expected_type != actual_type:
		diagnostic_add(sample,state,{"kind":"type_or_value_difference","path":path,"expected_type_id":expected_type,"actual_type_id":actual_type},true)
		return
	if expected is Dictionary:
		if depth >= 6 and (not expected.is_empty() or not actual.is_empty()):
			state.truncated = true
			budget.truncated = true
			return
		var ordinal: int = 0
		for key in expected:
			if not diagnostic_consume(state,budget): break
			if not diagnostic_type_supported(key):
				diagnostic_add(sample,state,{"kind":"unsupported_key","path":path,"ordinal":ordinal,"key_type_id":typeof(key)},false,true)
			elif not actual.has(key):
				diagnostic_add(sample,state,{"kind":"missing_key","path":diagnostic_path(path,".d["+str(ordinal)+"]",state,budget),"key_ordinal":ordinal,"key_type_id":typeof(key),"expected_type_id":typeof(expected[key]),"actual_type_id":-1},true)
			else:
				diagnostic_diff(expected[key],actual[key],diagnostic_path(path,".d["+str(ordinal)+"]",state,budget),depth+1,sample,state,budget)
			ordinal += 1
		var actual_ordinal: int = 0
		for key in actual:
			if not diagnostic_consume(state,budget): break
			if not diagnostic_type_supported(key):
				diagnostic_add(sample,state,{"kind":"unsupported_key","path":path,"ordinal":actual_ordinal,"key_type_id":typeof(key)},false,true)
			elif not expected.has(key):
				diagnostic_add(sample,state,{"kind":"extra_key","path":diagnostic_path(path,".x["+str(actual_ordinal)+"]",state,budget),"key_ordinal":actual_ordinal,"key_type_id":typeof(key),"actual_type_id":typeof(actual[key])},true)
			actual_ordinal += 1
		return
	if expected is Array:
		if expected.size() != actual.size():
			diagnostic_add(sample,state,{"kind":"array_length_difference","path":path,"expected_count":expected.size(),"actual_count":actual.size()},true)
		if depth >= 6 and (not expected.is_empty() or not actual.is_empty()):
			state.truncated = true
			budget.truncated = true
			return
		var shared: int = mini(expected.size(),actual.size())
		for index in range(shared):
			if int(budget.remaining) <= 0:
				state.truncated = true
				budget.truncated = true
				break
			diagnostic_diff(expected[index],actual[index],diagnostic_path(path,"["+str(index)+"]",state,budget),depth+1,sample,state,budget)
		return
	if not diagnostic_type_supported(expected):
		diagnostic_add(sample,state,{"kind":"unsupported_value","path":path,"type_id":expected_type},false,true)
		return
	if expected != actual:
		diagnostic_add(sample,state,{"kind":"scalar_difference","path":path,"expected_type_id":expected_type,"actual_type_id":actual_type},true)

func observe_file_profile(path: String, expected: Dictionary, expected_raw: String, sample: Array, state: Dictionary, budget: Dictionary) -> Dictionary:
	var result: Dictionary = {"exists":FileAccess.file_exists(path),"read_count":0,"parsed_is_dictionary":false,"parsed_equal":false,"parsed_strict_equal":false,"json_compare_visited":0,"json_compare_truncated":false,"raw_exact":false}
	if not result.exists: return result
	# Exactly one primary read. JSON parsing has no profile validator/normalizer callback.
	var raw: String = FileAccess.get_file_as_string(path)
	result.read_count = 1
	var parsed: Variant = JSON.parse_string(raw)
	result.parsed_is_dictionary = parsed is Dictionary
	result.parsed_strict_equal = parsed is Dictionary and parsed == expected
	if parsed is Dictionary:
		var json_comparison: Dictionary = file_profile_json_compare(expected,parsed)
		result.parsed_equal = json_comparison.equal
		result.json_compare_visited = json_comparison.visited
		result.json_compare_truncated = json_comparison.truncated
	# raw_exact is String equality after get_file_as_string, not a byte-level API comparison.
	result.raw_exact = raw == expected_raw
	if parsed is Dictionary:
		diagnostic_diff(expected,parsed,"$",0,sample,state,budget)
	return result

func run() -> void:
	var source: Dictionary = source_table()
	if not check(not source.is_empty(), "immutable original-source fixture hash is exact"):
		finish(); return
	if not run_file_profile_json_contract_tests():
		finish(); return
	var b = fixture_backend("commit")
	if not check(b != null, "commit fixture is fully initialized, migrated, and baseline-saved"):
		finish(); return
	var commit_login_time := int(b.session._profile.player.last_luck_time)
	var baseline: Dictionary = b.session._profile.duplicate(true)
	var baseline_raw := FileAccess.get_file_as_string(b.save_path)
	var baseline_cache: String = b.last_saved_payload
	var baseline_storage_cache: String = b._storage_json
	var baseline_serial: int = b.quest_save_serial
	var before_runtime := {"map": b.automation.position_map, "cell": b.automation.position_cell,
		"scope": b.quest_arrival._scope, "marks": b.quest_arrival._marks.duplicate(true),
		"stages": b.quest_arrival._stages.duplicate(true), "warp": b.quest_arrival._warp.duplicate(true)}
	if not check(b.session._profile.has("original_instances") and b.session._profile.has("original_equipment") and b.session._profile.has("next_original_uid"), "baseline follows native equipment/UID migration"):
		finish(); return
	if not check(not Policy.supports(39, 42), "public production start is intentionally unsupported; facade owns only the test segment"):
		finish(); return
	var npc: Dictionary = b.quest_catalog.active_npc(NPC_ID)
	var branches: Array = npc.get("branches", [])
	var actual: Dictionary = b.original_quests.branch_for(npc, b.session._profile)
	# Independent source oracle: literal source fields and raw branch order, not
	# the Plan.same_source comparator under test.
	if not check(source_value_equal(npc, source.npc) and source_branches_equal(branches, source.npc.branches), "independent raw-source oracle matches the complete NPC and all three full branches in order"):
		finish(); return
	if not check(branches.size() == 3 and branches[0].get("condition") == "LV>0&NOWEV=42" and branches[1].get("event") == 42 and branches[1].get("type") == "REQUEST" and branches[1].get("condition") == "LV>0&NOWEV=41&ENDEV=4" and branches[1].get("actions", {}) == {} and branches[1].get("source_branch_index") == 1 and branches[2].get("condition") == "LV>0", "literal priority oracle confirms branch0/1/2 semantics"):
		finish(); return
	if not check(source_value_equal(actual, source.npc.branches[1]) and actual.get("event") == 42 and actual.get("type") == "REQUEST" and actual.get("condition") == "LV>0&NOWEV=41&ENDEV=4" and actual.get("actions", {}) == {}, "real branch_for equals the independently locked full REQUEST source and wins before commit"):
		finish(); return
	if not check(source_value_equal(1, 1.0) and not source_value_equal(true, 1) and not source_value_equal(1, 1.5), "source numeric normalization accepts finite integral spelling only; bool and fractional values remain distinct"):
		finish(); return
	if not check(source.npc.branches[1].get("source_line") == 15 and source.npc.branches[1].get("actions", {}) == {}, "immutable raw-source fixture confirms branch1 source line/actions"):
		finish(); return
	var Plan = preload("res://server/quest_auto_spirit_wind42_plan.gd")
	var proposal: Dictionary = Plan.request_proposal(b, 39)
	if not check(proposal.get("status") == "step" and proposal.step.id == "spirit_wind42:request:42" and proposal.step.npc_id == NPC_ID and proposal.step.map_id == 100 and proposal.step.cell == [346, 356] and proposal.step.source.branch_index == 1 and proposal.step.source.condition == "LV>0&NOWEV=41&ENDEV=4", "plan proposal matches literal original request contract"):
		finish(); return
	if not check(ArrivalPolicy.scope(100) == "" and b.quest_arrival.has_arrival(b, 100, Vector2i(346, 356)), "map100 public arrival is unscoped without injected proof"):
		finish(); return

	# Cancellation uses only a choice actually returned by the original dialogue.
	var cancel = fixture_backend("cancel")
	if not check(cancel != null, "cancel fixture independently migrated and baseline-saved"):
		finish(); return
	var cancel_login_time := int(cancel.session._profile.player.last_luck_time)
	var cancel_profile: Dictionary = cancel.session._profile.duplicate(true)
	var cancel_raw := FileAccess.get_file_as_string(cancel.save_path)
	var cancel_save_calls: int = cancel.save_calls
	var cancel_source_calls: int = cancel.source_transaction_calls
	var cancel_cache: String = cancel.last_saved_payload
	var cancel_storage_cache: String = cancel._storage_json
	var cancel_serial: int = cancel.quest_save_serial
	var cancel_dialogue: Dictionary = cancel.original_quests.talk(cancel, NPC_ID)
	var no_choice := visible_choice(cancel_dialogue, "no")
	var cancel_choice_ids: Array = no_choice.get("visible_choices", []).map(func(choice): return str(choice.get("id", "")))
	if not check(cancel_dialogue.get("ok", false) and cancel_choice_ids == ["yes", "no"], "actual original REQUEST response offers the exact cancellation choices and token"):
		finish(); return
	var cancel_reply: Dictionary = cancel.original_quests.choose(cancel, str(no_choice.token), str(no_choice.choice))
	if not check(cancel_reply.get("ok", false) and cancel_reply.get("closed", false), "actual original choose accepts the returned no choice"):
		finish(); return
	var diagnostic_budget: Dictionary = {"remaining":4096,"visited":0,"truncated":false}
	var cancel_native_sample: Array = []
	var cancel_native_state: Dictionary = {"visited":0,"observed_diff_count":0,"unsupported_count":0,"truncated":false}
	var cancel_file_sample: Array = []
	var cancel_native_profile_equal: bool = cancel.session._profile == cancel_profile
	diagnostic_diff(cancel_profile,cancel.session._profile,"$",0,cancel_native_sample,cancel_native_state,diagnostic_budget)
	var cancel_file_state: Dictionary = {"visited":0,"observed_diff_count":0,"unsupported_count":0,"truncated":false}
	var cancel_file_observation: Dictionary = observe_file_profile(cancel.save_path,cancel_profile,cancel_raw,cancel_file_sample,cancel_file_state,diagnostic_budget)
	var cancel_tmp_exists: bool = FileAccess.file_exists(cancel.save_path + ".tmp")
	var cancel_bak_exists: bool = FileAccess.file_exists(cancel.save_path + ".bak")
	var cancel_pending_size: int = cancel.original_quests.pending.size()
	var cancel_serial_equal: bool = cancel.quest_save_serial == cancel_serial
	var cancel_save_calls_equal: bool = cancel.save_calls == cancel_save_calls
	var cancel_source_calls_equal: bool = cancel.source_transaction_calls == cancel_source_calls
	var cancel_diagnostic: Dictionary = {
		"native_profile_equal":cancel_native_profile_equal,
		"native_observed_diff_count":cancel_native_state.observed_diff_count,"native_sample":cancel_native_sample,
		"native_visited":cancel_native_state.visited,"native_truncated":cancel_native_state.truncated,"native_unsupported_count":cancel_native_state.unsupported_count,
		"payload_cache_equal":cancel.last_saved_payload == cancel_cache,
		"storage_cache_equal":cancel._storage_json == cancel_storage_cache,
		"serial_equal":cancel_serial_equal,"serial_delta_diagnostic_only":cancel.quest_save_serial-cancel_serial,
		"save_calls_equal":cancel_save_calls_equal,"save_call_delta_diagnostic_only":cancel.save_calls-cancel_save_calls,
		"source_calls_equal":cancel_source_calls_equal,"source_call_delta_diagnostic_only":cancel.source_transaction_calls-cancel_source_calls,
		"primary":cancel_file_observation,"file_observed_diff_count":cancel_file_state.observed_diff_count,"file_sample":cancel_file_sample,
		"file_visited":cancel_file_state.visited,"file_truncated":cancel_file_state.truncated,"file_unsupported_count":cancel_file_state.unsupported_count,
		"shared_node_budget_visited":diagnostic_budget.visited,"shared_node_budget_remaining":diagnostic_budget.remaining,"shared_node_budget_truncated":diagnostic_budget.truncated,
		"tmp_exists":cancel_tmp_exists,"bak_exists":cancel_bak_exists,"pending_empty":cancel_pending_size == 0,"pending_count":cancel_pending_size
	}
	print("WIND42_CANCEL_DIAGNOSTIC " + JSON.stringify(cancel_diagnostic))
	var cancel_compound_ok: bool = cancel_native_profile_equal and cancel.last_saved_payload == cancel_cache and cancel._storage_json == cancel_storage_cache and cancel_serial_equal and cancel_save_calls_equal and cancel_source_calls_equal and cancel_file_observation.exists and cancel_file_observation.parsed_is_dictionary and cancel_file_observation.parsed_equal and cancel_file_observation.raw_exact and not cancel_tmp_exists and not cancel_bak_exists and cancel_pending_size == 0
	if not check(cancel_compound_ok, "cancel preserves entire native profile, exact raw save bytes, caches, callbacks, and file set"):
		finish(); return
	var cancel_reload = Wind42TestBackend.new()
	track_backend(cancel_reload)
	fixed_login_time = cancel_login_time
	cancel_reload.session.login_clock = Callable(self, "fixed_login_clock")
	# Exactly one load call; all diagnostics below are read-only and only run
	# after successful load, preserving the original short-circuit on load failure.
	var cancel_reload_load_return: bool = cancel_reload.load_profile(cancel.save_path)
	var cancel_reload_return_type_id: int = typeof(cancel_reload_load_return)
	var cancel_reload_comparisons_evaluated: bool = false
	var cancel_reload_native_equal: bool = false
	var cancel_reload_payload_cache_equal: bool = false
	var cancel_reload_storage_cache_equal: bool = false
	var cancel_reload_native_sample: Array = []
	var cancel_reload_native_state: Dictionary = {"visited":0,"observed_diff_count":0,"unsupported_count":0,"truncated":false}
	var cancel_reload_diagnostic_budget: Dictionary = {"remaining":4096,"visited":0,"truncated":false}
	if cancel_reload_load_return:
		cancel_reload_comparisons_evaluated = true
		cancel_reload_native_equal = cancel_reload.session._profile == cancel_profile
		cancel_reload_payload_cache_equal = cancel_reload.last_saved_payload == cancel_cache
		cancel_reload_storage_cache_equal = cancel_reload._storage_json == cancel_storage_cache
		diagnostic_diff(cancel_profile,cancel_reload.session._profile,"$",0,cancel_reload_native_sample,cancel_reload_native_state,cancel_reload_diagnostic_budget)
	var cancel_reload_diagnostic: Dictionary = {
		"load_return_type_id":cancel_reload_return_type_id,"load_returned":cancel_reload_load_return,
		"comparisons_evaluated":cancel_reload_comparisons_evaluated,
		"native_profile_equal":cancel_reload_native_equal,
		"last_saved_payload_equal":cancel_reload_payload_cache_equal,
		"storage_json_equal":cancel_reload_storage_cache_equal,
		"native_observed_diff_count":cancel_reload_native_state.observed_diff_count,
		"native_diff_sample":cancel_reload_native_sample,
		"native_visited":cancel_reload_native_state.visited,
		"native_truncated":cancel_reload_native_state.truncated,
		"native_unsupported_count":cancel_reload_native_state.unsupported_count,
		"diagnostic_budget_visited":cancel_reload_diagnostic_budget.visited,
		"diagnostic_budget_remaining":cancel_reload_diagnostic_budget.remaining,
		"diagnostic_budget_truncated":cancel_reload_diagnostic_budget.truncated
	}
	print("WIND42_CANCEL_RELOAD_DIAGNOSTIC " + JSON.stringify(cancel_reload_diagnostic))
	var cancel_reload_ok: bool = cancel_reload_load_return and cancel_reload_native_equal and cancel_reload_payload_cache_equal and cancel_reload_storage_cache_equal
	if not check(cancel_reload_ok, "cancel baseline independently loads with its own fixture login clock and exact profile/caches"):
		finish(); return

	# A test-only selector facade feeds the real QuestAuto strict runner. It does
	# not change QuestAutoPolicy/Registry and does not call the public start path.
	var runner = enable_runner_facade(b)
	if not check(replaced_runner_refs.size() == 1 and replaced_runner_refs[0].get_ref() == null, "replaced backend-owned QuestAuto is released after facade substitution"):
		finish(); return
	runner.quest_id = 38
	if not check(runner.strict_select(b).get("status") == "manual" and runner.strict_select(b, 40).get("status") == "manual", "facade refuses quest_id and selected_id outside job39"):
		finish(); return
	if not check(runner.strict_select(b, 39).get("status") == "step", "explicit selected_id 39 stays within the one-job facade"):
		finish(); return
	runner.quest_id = 39
	var saved_calls_before_request: int = b.save_calls
	var source_calls_before_request: int = b.source_transaction_calls
	runner.tick(b, 0.2)
	var pending: Dictionary = b.original_quests.pending
	if not check(runner.phase == "strict_dialogue" and pending.get("phase") == "REQUEST" and pending.get("branch", {}).get("event") == 42 and runner.dialogue_choices == ["yes", "ok"] and not str(pending.get("token", "")).is_empty(), "tick1 synchronously opens REQUEST; pending/token and validated yes/no choice are exact"):
		finish(); return
	runner.tick(b, 0.2)
	if not check(runner.phase == "strict_dialogue" and b.original_quests.pending.get("phase") == "end" and runner.dialogue_choices == ["ok"], "tick2 synchronously chooses yes, performs one REQUEST save, and reaches actual end acknowledgement"):
		finish(); return
	runner.tick(b, 0.2)
	if not check(runner.phase == "travel" and b.original_quests.pending.is_empty(), "tick3 synchronously chooses returned ok, closes dialogue, and does not save again"):
		finish(); return
	runner.tick(b, 0.2)
	if not check(not runner.running and runner.phase == "manual" and runner.pause_reason.contains("竖琴"), "tick4 handoff calls stop, keeps no resume intent, and halts at the next manual boundary"):
		finish(); return
	if not check(b.save_calls == saved_calls_before_request + 1 and b.source_transaction_calls == source_calls_before_request + 1 and b.quest_save_serial == baseline_serial + 1 and not FileAccess.file_exists(b._resume_file()) and SaveLock.holder_pid(b.save_path) == 0, "one synchronous original transaction yields exactly one save boundary, no resume file, and no SaveLock acquisition"):
		finish(); return

	var expected: Dictionary = baseline.duplicate(true)
	# Independent oracle from original_quests.gd:19–21: event word = event >> 5,
	# bit = 1 << (event % 32); event 42 is word 1, bit 10 in the six-word array.
	var now_words: Array = expected.original_events.now
	var now_index := 42 >> 5
	var now_mask := 1 << (42 % 32)
	if not check(now_words.size() == 6 and (int(now_words[now_index]) & now_mask) == 0, "baseline NOW42 bit is clear in native six-word layout"):
		finish(); return
	now_words[now_index] = int(now_words[now_index]) | now_mask
	if not check(b.session._profile == expected, "complete native profile equals independently derived source transaction expectation"):
		finish(); return
	if not check(b.last_saved_payload == JSON.stringify(expected) and b._storage_json == JSON.stringify(expected.get("pet_storage", [])) and b.quest_save_serial == baseline_serial + 1, "save and storage caches match exact expected state and one durable transaction"):
		finish(); return
	if not check(assert_file_profile(b.save_path, expected, JSON.stringify(expected)) and FileAccess.get_file_as_string(b.save_path + ".bak") == baseline_raw and not FileAccess.file_exists(b.save_path + ".tmp"), "primary exact expected profile, backup exact baseline bytes, and no temp residue"):
		finish(); return
	if not check([b.automation.position_map, b.automation.position_cell] == [before_runtime.map, before_runtime.cell] and b.quest_arrival._scope == before_runtime.scope and b.quest_arrival._marks == before_runtime.marks and b.quest_arrival._stages == before_runtime.stages and b.quest_arrival._warp == before_runtime.warp, "transaction preserves all runtime position/arrival authority caches"):
		finish(); return
	var reloaded = Wind42TestBackend.new()
	track_backend(reloaded)
	fixed_login_time = commit_login_time
	reloaded.session.login_clock = Callable(self, "fixed_login_clock")
	if not check(reloaded.load_profile(b.save_path) and reloaded.session._profile == expected, "independent load equals entire expected native profile"):
		finish(); return
	if not check(reloaded.last_saved_payload == JSON.stringify(expected) and reloaded._storage_json == JSON.stringify(expected.get("pet_storage", [])) and reloaded.quest_arrival._scope.is_empty() and reloaded.quest_arrival._marks.is_empty() and reloaded.quest_arrival._stages.is_empty() and reloaded.quest_arrival._warp.is_empty(), "load caches are exact and nonpersistent arrival state resets (public has_arrival remains unscoped)"):
		finish(); return
	var resumed: Dictionary = Plan.request_proposal(reloaded, 39)
	if not check(resumed.get("status") == "manual" and resumed.get("stage") == "manual_harp_munde" and not resumed.has("step"), "restart does not repeat request and stops for manual next stage"):
		finish(); return
	var post_branch: Dictionary = reloaded.original_quests.branch_for(reloaded.quest_catalog.active_npc(NPC_ID), expected)
	if not check(post_branch.get("type") == "MESSAGE" and post_branch.get("condition") == "LV>0&NOWEV=42", "next real source priority is MESSAGE0; never re-talk to repeat REQUEST"):
		finish(); return
	finish()

func finish() -> void:
	for backend in backends:
		if is_instance_valid(backend): backend.free()
	backends.clear()
	for ref in backend_refs:
		check(not is_instance_valid(ref.get_ref()), "test-owned Backend Node is freed at teardown")
	for ref in replaced_runner_refs:
		check(ref.get_ref() == null, "replaced QuestAuto facade resource is not retained")
	for index in range(owned_save_paths.size()):
		var save_path: String = owned_save_paths[index]
		var resume_path: String = owned_resume_paths[index]
		var holder := SaveLock.holder_pid(save_path)
		if holder != 0: natural_lock_leaks += 1
		check(holder == 0, "natural Backend teardown released test SaveLock before any fallback")
		if holder == OS.get_process_id():
			fallback_lock_releases += 1
			printerr("TEARDOWN FALLBACK ONLY: natural SaveLock leak already recorded as assertion failure; releasing own test lock")
			SaveLock.release(save_path)
			print("TEARDOWN CLEANUP FACT: fallback holder after release=%d" % SaveLock.holder_pid(save_path))
		elif holder != 0:
			printerr("TEARDOWN CLEANUP FACT: leaving non-owned lock untouched; holder=%d" % holder)
		var kept: Array[String] = []
		for path in [save_path, save_path + ".bak", save_path + ".tmp", resume_path, resume_path + ".tmp"]:
			if FileAccess.file_exists(path): kept.append(path)
		preserved_file_count += kept.size()
		print("TEARDOWN CLEANUP FACT: preserved user:// files=%s" % str(kept))
	print("wind42_request_actual_transaction_test: %d assertions, %d failures" % [assertions, failures])
	print("TEARDOWN CLEANUP FACTS: natural_lock_leaks=%d fallback_lock_releases=%d preserved_files=%d" % [natural_lock_leaks, fallback_lock_releases, preserved_file_count])
	quit(1 if failures else 0)
