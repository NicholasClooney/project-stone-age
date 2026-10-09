extends SceneTree
## UNRUN candidate: native fresh-save location -> original A Runner -> exact first Jan ACCEPT.
## The test-only runner admits only job27/event20; no NOW/item/arrival is seeded.
const Backend = preload("res://server/backend.gd")
const Plan = preload("res://server/quest_auto_jan_plan.gd")
const Rules = preload("res://server/original_quests.gd")
const Session = preload("res://server/game_session.gd")
const Auto = preload("res://server/quest_auto.gd")
const Runner = preload("res://tests/support/quest_auto_jan_public_spawn_runner_candidate.gd")
const Policy = preload("res://scripts/quest_auto_policy.gd")
const Registry = preload("res://server/quest_auto_registry.gd")
const Motion = preload("res://server/quest_auto_motion.gd")
const ArrivalPolicy = preload("res://server/quest_arrival_policy.gd")
const Passage = preload("res://scripts/passage_rules.gd")
const Settings = preload("res://server/quest_auto_settings_rules.gd")
const Wait = preload("res://tests/support/wait.gd")

const WAIT_SECONDS: float = 150.0
const MAX_LOGICAL_POINTS: int = 6000
const HARD_EXTERNAL_SECONDS: float = 300.0
const CLIENT: String = "jan-public-spawn-route-candidate"
const CONNECTION: int = 62027
const MANIFEST_SHA: String = "5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639"
const CATALOG_SHA: String = "c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92"
const PLAN_SOURCE_SHA: String = "c1b4ae1e6b03275977c371b33f3bd3ccb33982ba2c328536f124a466941e9c51"
const ROUTE_LOCK_PATH: String = "res://server/quest_auto_jan_public_spawn_sources.json"
const ROUTE_LOCK_SHA: String = "3890ee27783b8fc7b2f57c24855c65c6b02188e286bb417d3e515cb00b9e8c0b"
const EDGE_CHAIN: Array = [[1000,100],[100,1100],[1100,10201],[10201,10202],[10202,10203],[10203,200],[200,3400]]
const REQUIRED_MAPS: Array[int] = [1000,100,1100,10201,10202,10203,200,3400]

class DiagnosticBackend extends "res://server/backend.gd":
	var candidate_field_calls: int = 0
	func _cmd_field_step(command: Dictionary) -> Dictionary:
		candidate_field_calls += 1
		return super._cmd_field_step(command)

var backend: Variant
var assertions: int = 0
var failures: int = 0
var failed: bool = false
var finished: bool = false
var started_msec: int = 0
var wait_deadline_msec: int = 0
var logical_points: int = 0
var ordinary_walks: int = 0
var portals: int = 0
var valid_acks: int = 0
var portal_sequence: Array[String] = []
var portal_maps: Array = []
var trace: Array[Dictionary] = []
var first_failure: Dictionary = {}
var target: Dictionary = {}
var transaction_open: bool = false
var transaction_before: Dictionary = {}
var transaction_save_serial: int = 0
var transaction_step: Dictionary = {}
var transaction_count: int = 0
var done: bool = false
var trace_path: String = ""
var trace_path_refused: bool = false
var trace_attempted: bool = false
var trace_write_error: String = ""
var route_lock: Dictionary = {}
var start_call_count: int = 0
var start_response_snapshot: Dictionary = {}
var start_selections_snapshot: Variant = null
var start_step_snapshot: Variant = null

func _initialize() -> void:
	call_deferred("run")

func runner() -> Variant:
	return backend.quest_auto

func navigation() -> Variant:
	return runner().navigation

func state() -> Dictionary:
	if backend == null: return {}
	var result: Dictionary = {
		"map_id": backend.automation.position_map,
		"cell": [backend.automation.position_cell.x, backend.automation.position_cell.y],
		"saved_location": backend.session._profile.get("location", null),
		"scope": backend.quest_arrival._scope,
		"marks": backend.quest_arrival._marks.duplicate(true),
		"stages": backend.quest_arrival._stages.duplicate(true),
		"running": runner().running,
		"phase": runner().phase,
		"step_id": runner().step.get("id", ""),
		"logical_points": logical_points,
		"portals": portal_sequence.duplicate()
	}
	return result.duplicate(true)

func check(ok: bool, label: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		failed = true
		if first_failure.is_empty():
			var remaining: Array = []
			if backend != null:
				var route_value: Variant = navigation().route
				if route_value is Array: remaining = route_value.duplicate(true)
			first_failure = {"label": label, "state": state(), "target": target.duplicate(true), "remaining": remaining}
		write_trace()
		push_error(label)
	return ok

func same_source(a: Variant, b: Variant) -> bool:
	return Plan.same_source(a, b)

func positive_finite_integer(value: Variant) -> bool:
	if value is bool or not (value is int or value is float): return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number) and number > 0

func metadata_dimension_matches(metadata: Dictionary, key: String, expected: int) -> bool:
	if not metadata.has(key): return false
	var value: Variant = metadata.get(key, null)
	return positive_finite_integer(value) and same_source(value, expected)

func metadata_value_matches(metadata: Dictionary, key: String, expected: Variant) -> bool:
	return metadata.has(key) and same_source(metadata.get(key, null), expected)

func bounded_metadata_value(value: Variant) -> Dictionary:
	var result: Dictionary = {"type": type_string(typeof(value))}
	if value is Array:
		var array_value: Array = value
		result["size"] = array_value.size()
		var prefix: Array = []
		for index in range(min(array_value.size(), 4)):
			var child: Variant = array_value[index]
			var child_summary: Dictionary = {"type": type_string(typeof(child))}
			if child is Array:
				child_summary["size"] = (child as Array).size()
			elif child is Dictionary:
				child_summary["size"] = (child as Dictionary).size()
			else:
				var child_text: String = str(child)
				child_summary["value_prefix"] = child_text.substr(0, 80)
				child_summary["value_length"] = child_text.length()
			prefix.append(child_summary)
		result["prefix"] = prefix
	elif value is Dictionary:
		var dictionary_value: Dictionary = value
		result["size"] = dictionary_value.size()
		var key_prefix: Array = []
		for key in dictionary_value.keys():
			if key_prefix.size() >= 8: break
			var key_text: String = str(key)
			key_prefix.append({"type": type_string(typeof(key)), "value_prefix": key_text.substr(0, 80), "value_length": key_text.length()})
		result["key_prefix"] = key_prefix
	else:
		var scalar_text: String = str(value)
		result["value_prefix"] = scalar_text.substr(0, 160)
		result["value_length"] = scalar_text.length()
	return result

func observe_manifest_metadata(label: String, metadata: Dictionary, expected: Dictionary) -> void:
	var keys: Array = ["path", "width", "height", "spawn", "kind"]
	for key in expected.keys():
		if not keys.has(key): keys.append(key)
	var fields: Dictionary = {}
	for key in keys:
		if not metadata.has(key) and not expected.has(key): continue
		var actual: Variant = metadata.get(key, null)
		var field: Dictionary = {"present": metadata.has(key), "actual": bounded_metadata_value(actual)}
		if expected.has(key): field["same_source_expected"] = metadata.has(key) and same_source(actual, expected[key])
		if key == "width" or key == "height": field["positive_finite_integer"] = positive_finite_integer(actual)
		fields[key] = field
	print("MANIFEST_METADATA_OBSERVATION ", label, " ", JSON.stringify(fields))

func saved_equal(a: Variant, b: Variant) -> bool:
	if a is bool or b is bool: return a is bool and b is bool and a == b
	if a is int or a is float:
		return (b is int or b is float) and is_finite(float(a)) and is_finite(float(b)) and a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not saved_equal(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not saved_equal(a[index], b[index]): return false
		return true
	return typeof(a) == typeof(b) and a == b

func source_hash(path: String, expected: String, label: String) -> bool:
	if not FileAccess.file_exists(path): return check(false, label + " missing")
	var raw: String = FileAccess.get_file_as_string(path)
	return check(not raw.is_empty() and raw.sha256_text() == expected, label + " exact source SHA")

func binary_hash(path: String, expected: String, label: String) -> bool:
	if not FileAccess.file_exists(path): return check(false, label + " missing")
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if not check(not raw.is_empty(), label + " nonempty raw map bytes"): return false
	var context: HashingContext = HashingContext.new()
	if not check(context.start(HashingContext.HASH_SHA256) == OK, label + " HashingContext start"): return false
	if not check(context.update(raw) == OK, label + " HashingContext raw update"): return false
	var digest: PackedByteArray = context.finish()
	if not check(digest.size() == 32, label + " SHA-256 digest length"): return false
	return check(digest.hex_encode() == expected, label + " exact map SHA")

func empty_raw_events(profile: Dictionary) -> bool:
	var events_value: Variant = profile.get("original_events", null)
	if not events_value is Dictionary: return false
	var events: Dictionary = events_value
	if events.size() != 2: return false
	for kind in ["now", "ended"]:
		var words_value: Variant = events.get(kind, null)
		if not words_value is Array: return false
		var words: Array = words_value
		if words.size() != 6: return false
		for word in words:
			if not word is int or word != 0: return false
	return true

func raw_migration_fields(profile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["original_instances", "original_equipment", "next_original_uid"]:
		var present: bool = profile.has(key)
		var value: Variant = profile.get(key) if present else null
		if value is Dictionary or value is Array: value = value.duplicate(true)
		result[key] = {"present": present, "value": value}
	return result

func zero_equipment_slots(value: Variant) -> bool:
	if not value is Dictionary: return false
	var slots: Dictionary = value
	if slots.size() != 5: return false
	for key in ["arm", "bracelet", "amulet", "head", "body"]:
		var item: Variant = slots.get(key, null)
		if not item is int or item != 0: return false
	return true

func migrated_empty_inventory(profile: Dictionary) -> bool:
	var items_value: Variant = profile.get("original_items", null)
	var instances_value: Variant = profile.get("original_instances", null)
	var equipment_value: Variant = profile.get("original_equipment", null)
	var uid_value: Variant = profile.get("next_original_uid", null)
	var spirit_equipment_value: Variant = profile.get("equipment", null)
	if not profile.has("original_items") or not items_value is Array: return false
	if not profile.has("original_instances") or not instances_value is Array: return false
	if not profile.has("original_equipment") or not zero_equipment_slots(equipment_value): return false
	if not profile.has("next_original_uid") or not uid_value is int or uid_value != 1: return false
	if not profile.has("equipment") or not spirit_equipment_value is Dictionary: return false
	var items: Array = items_value
	var instances: Array = instances_value
	return items.is_empty() and instances.is_empty() and same_source(spirit_equipment_value, {"body":"", "amulet":""})

func load_route_lock() -> bool:
	if not FileAccess.file_exists(ROUTE_LOCK_PATH): return check(false, "candidate route source lock exists")
	var raw: String = FileAccess.get_file_as_string(ROUTE_LOCK_PATH)
	if not check(not raw.is_empty() and raw.sha256_text() == ROUTE_LOCK_SHA, "candidate route source lock exact SHA"): return false
	var parsed: Variant = JSON.parse_string(raw)
	if not check(parsed is Dictionary, "candidate route source lock JSON is Dictionary"): return false
	route_lock = parsed
	var lock_chain_value: Variant = route_lock.get("portal_chain", null)
	var portals_value: Variant = route_lock.get("portals", null)
	if not check(lock_chain_value is Array and portals_value is Array, "route lock chain and complete portal rows retain Array shape"): return false
	var lock_chain: Array = lock_chain_value
	var locked_portals: Array = portals_value
	if not check(lock_chain.size() == EDGE_CHAIN.size() and locked_portals.size() == 23, "seven map transitions and all 23 parallel original tuples are locked"): return false
	for index in range(EDGE_CHAIN.size()):
		if not check(same_source(lock_chain[index], EDGE_CHAIN[index]), "locked map edge order %d" % index): return false
	return true

func reviewed_portal(link: Dictionary, from_map: int, to_map: int) -> bool:
	if link.has("disabled") and bool(link.disabled): return false
	if link.has("gate_source") or bool(link.get("requires_travel_pass", false)): return false
	var locked_portals: Array = route_lock.get("portals", [])
	for expected_value in locked_portals:
		if not expected_value is Dictionary: return false
		var expected: Dictionary = expected_value
		if Motion.same_integer(expected.get("from_map", null), from_map) and Motion.same_integer(expected.get("to_map", null), to_map) and same_source(link, expected): return true
	return false

func ack_for(receipt: Dictionary) -> Dictionary:
	var cell: Array = Motion.cell(receipt.get("cell", []))
	var packet: Dictionary = {
		"type": "report_position",
		"map_id": receipt.get("map_id", -1),
		"cell": cell,
		"quest_position_seq": receipt.get("quest_position_seq", -1),
		"client": CLIENT,
		"_quest_connection": CONNECTION
	}
	for field in Motion.IDENTITY_FIELDS:
		if receipt.has(field): packet[field] = receipt[field]
	return packet

func run() -> void:
	started_msec = Time.get_ticks_msec()
	var unique: String = str(Time.get_ticks_usec())
	trace_path = "user://jan-public-spawn-route-" + unique + "-trace.json"
	var backend_path: String = "user://jan-public-spawn-route-" + unique + ".json"
	if FileAccess.file_exists(trace_path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(trace_path)):
		trace_path_refused = true
		check(false, "trace path collision is refused without opening or overwriting it")
		finish()
		return
	backend = DiagnosticBackend.new()
	backend.set_process(false)
	backend.quest_auto = Runner.new()
	backend.save_path = backend_path
	for suffix in ["", ".bak", ".tmp", ".resume.json"]:
		var candidate_path: String = backend_path + suffix
		if not check(not FileAccess.file_exists(candidate_path) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate_path)), "fresh isolated save/sidecar path is unused " + suffix): finish(); return
	if not load_route_lock(): finish(); return
	if not source_hash("res://assets/legacy/world/manifest.json", MANIFEST_SHA, "complete world manifest"): finish(); return
	if not source_hash("res://assets/legacy/quests/catalog.json", CATALOG_SHA, "complete quest catalog"): finish(); return
	if not source_hash("res://server/quest_auto_jan_sources.json", PLAN_SOURCE_SHA, "existing Jan selector source lock"): finish(); return
	var map_lock_value: Variant = route_lock.get("maps", null)
	if not check(map_lock_value is Dictionary, "route lock map metadata is Dictionary"): finish(); return
	var map_lock: Dictionary = map_lock_value
	for map_id in REQUIRED_MAPS:
		var row_value: Variant = map_lock.get(str(map_id), null)
		if not check(row_value is Dictionary, "full source map row exists %d" % map_id): finish(); return
		var row: Dictionary = row_value
		var metadata_value: Variant = row.get("metadata", null)
		if not check(metadata_value is Dictionary, "full source map metadata is Dictionary %d" % map_id): finish(); return
		var metadata: Dictionary = metadata_value
		if not binary_hash("res://assets/legacy/world/%d.map" % map_id, str(row.get("sha256", "")), "map %d" % map_id): finish(); return
		var expected_path: String = "world/%d.map" % map_id
		observe_manifest_metadata("map %d identity/dimensions" % map_id, metadata, {"path": expected_path})
		var path_value: Variant = metadata.get("path", null)
		var map_path_matches: bool = metadata.has("path") and path_value is String and path_value == expected_path
		var width_is_positive_integer: bool = metadata.has("width") and positive_finite_integer(metadata.get("width", null))
		var height_is_positive_integer: bool = metadata.has("height") and positive_finite_integer(metadata.get("height", null))
		if not check(map_path_matches and width_is_positive_integer and height_is_positive_integer, "manifest identity/dimensions remain present for map %d" % map_id): finish(); return
	var metadata_1000: Dictionary = map_lock["1000"].get("metadata", {})
	observe_manifest_metadata("map 1000 exact dimensions/spawn", metadata_1000, {"width": 160, "height": 160, "spawn": [89,73]})
	var map_1000_matches: bool = metadata_dimension_matches(metadata_1000, "width", 160) and metadata_dimension_matches(metadata_1000, "height", 160) and metadata_value_matches(metadata_1000, "spawn", [89,73])
	if not check(map_1000_matches, "1000 manifest spawn metadata stays distinct from native saved location"): finish(); return
	var metadata_3400: Dictionary = map_lock["3400"].get("metadata", {})
	observe_manifest_metadata("map 3400 exact dimensions/kind/spawn", metadata_3400, {"width": 120, "height": 120, "kind": "village", "spawn": [60,41]})
	var map_3400_matches: bool = metadata_dimension_matches(metadata_3400, "width", 120) and metadata_dimension_matches(metadata_3400, "height", 120) and metadata_value_matches(metadata_3400, "kind", "village") and metadata_value_matches(metadata_3400, "spawn", [60,41])
	if not check(map_3400_matches, "3400 manifest spawn is the original incoming-door landing, not the native starting authority"): finish(); return
	var raw_sources_value: Variant = route_lock.get("raw_reference_sha256", null)
	if not check(raw_sources_value is Dictionary, "raw original event/portal source SHA table is Dictionary"): finish(); return
	var source_table_value: Variant = Plan.source_table()
	if not check(source_table_value is Dictionary, "existing Plan source table stays a Dictionary"): finish(); return
	var source_table: Dictionary = source_table_value
	var source_catalog_value: Variant = route_lock.get("source_catalog", null)
	if not check(source_catalog_value is Dictionary, "route-lock source_catalog remains a Dictionary"): finish(); return
	var source_catalog: Dictionary = source_catalog_value
	var locked_table_value: Variant = source_catalog.get("source_table", null)
	if not check(locked_table_value is Dictionary and same_source(source_table, locked_table_value), "route lock embeds the exact existing full Jan source table"): finish(); return
	var npc_value: Variant = source_table.get("npc", null)
	var jobs_value: Variant = source_table.get("jobs", null)
	var source_rows_value: Variant = source_table.get("sources", null)
	if not check(npc_value is Dictionary and jobs_value is Array and source_rows_value is Dictionary, "Jan source table npc/jobs/sources shapes are preserved"): finish(); return
	var expected_npc: Dictionary = npc_value
	var expected_jobs: Array = jobs_value
	var source_rows: Dictionary = source_rows_value
	var branch_rows_value: Variant = expected_npc.get("branches", null)
	if not check(branch_rows_value is Array, "complete raw five-branch array exists"): finish(); return
	var branch_rows: Array = branch_rows_value
	if not check(branch_rows.size() == 5, "all five ordered Kai branches remain locked"): finish(); return
	var expected_branch_value: Variant = branch_rows[2]
	if not check(expected_branch_value is Dictionary, "original branch2 source row is Dictionary"): finish(); return
	var expected_branch: Dictionary = expected_branch_value
	var branch_index_value: Variant = expected_branch.get("source_branch_index", null)
	var branch_line_value: Variant = expected_branch.get("source_line", null)
	var branch_event_value: Variant = expected_branch.get("event", null)
	var branch_type_value: Variant = expected_branch.get("type", null)
	var branch_condition_value: Variant = expected_branch.get("condition", null)
	var branch_actions_value: Variant = expected_branch.get("actions", null)
	var branch_index_matches: bool = Motion.same_integer(branch_index_value, 2)
	var branch_line_matches: bool = Motion.same_integer(branch_line_value, 23)
	var branch_event_matches: bool = same_source(branch_event_value, -1)
	var branch_type_matches: bool = branch_type_value == "ACCEPT"
	var branch_condition_matches: bool = branch_condition_value == "ITEM!=2486"
	var branch_actions_matches: bool = same_source(branch_actions_value, {"GetItem":"2486"})
	var branch_get_item_value: Variant = null
	if branch_actions_value is Dictionary:
		branch_get_item_value = (branch_actions_value as Dictionary).get("GetItem", null)
	var branch_predicates: Dictionary = {"source_branch_index":branch_index_matches,"source_line":branch_line_matches,"event":branch_event_matches,"type":branch_type_matches,"condition":branch_condition_matches,"actions":branch_actions_matches}
	var branch_values: Dictionary = {"source_branch_index":bounded_metadata_value(branch_index_value),"source_line":bounded_metadata_value(branch_line_value),"event":bounded_metadata_value(branch_event_value),"type":bounded_metadata_value(branch_type_value),"condition":bounded_metadata_value(branch_condition_value),"actions":bounded_metadata_value(branch_actions_value),"actions.GetItem":bounded_metadata_value(branch_get_item_value)}
	print("JAN BRANCH2 SOURCE OBS ", JSON.stringify({"predicates":branch_predicates,"values":branch_values,"branch":bounded_metadata_value(expected_branch)}))
	if not check(branch_index_matches and branch_line_matches and branch_event_matches and branch_type_matches and branch_condition_matches and branch_actions_matches, "job27 first eligible original transaction is exact branch2 ACCEPT/GetItem2486"): finish(); return
	if not check(source_rows.get("npc/jaruga/event/event20.create", {}).get("sha256") == "9a09b6d45ce7ce027d855f51090a53c09a6e6fec4436786dbfd8cd42a15e0b41" and source_rows.get("npc/jaruga/event/event20_1", {}).get("sha256") == "ffc45d76c829aee8dd880058dea568b8f60e6c59d0a66fb3eea9ff5e33c94335", "original Kaeyi create/event20_1 bytes stay pinned"): finish(); return
	if not check(source_rows.get("jobdaily.txt", {}).get("sha256") == "0c073ce1cc455cc65a3e3118e5db25985441d433ef4745e7ea752e3235358612", "original jobdaily 27/event20 mapping stays pinned"): finish(); return
	for locked_job_value in expected_jobs:
		if not check(locked_job_value is Dictionary, "each locked Jan job record is Dictionary"): finish(); return
		var locked_job: Dictionary = locked_job_value
		var matches: int = 0
		for actual_value in backend.quest_catalog.jobs:
			if not actual_value is Dictionary: continue
			var actual_job: Dictionary = actual_value
			if Motion.same_integer(actual_job.get("id", null), locked_job.get("id", -1)):
				matches += 1
				if not check(same_source(actual_job, locked_job), "complete live job row equals source lock %s" % str(locked_job.get("id"))): finish(); return
		if not check(matches == 1, "each locked job has one live catalog row"): finish(); return
	var live_quest: Dictionary = runner().row(backend,27)
	if not check(Motion.same_integer(live_quest.get("event", -1), 20) and 20 in backend.quest_catalog.enabled_events, "live catalog retains enabled original job27/event20"): finish(); return
	if not check(not Policy.supports(27,20) and not Registry.supports(27), "production Policy/Registry stay closed for job27"): finish(); return
	var default_auto: Auto = Auto.new()
	if not check(not default_auto._supports_automatic_start(27,20) and default_auto._supports_automatic_start(2,44) == Policy.supports(2,44), "unmodified production start wrapper remains Policy-equivalent"): finish(); return
	if not check(runner()._supports_automatic_start(27,20) and not runner()._supports_automatic_start(27,21) and not runner()._supports_automatic_start(28,21), "test subclass admission is limited to the exact job/event pair"): finish(); return
	if not check(Settings.effective(backend.session.automation_settings()).mode == "A", "untouched isolated settings select original A mode"): finish(); return
	if not prepare_native_public_start(unique): finish(); return
	var start_profile: Dictionary = backend.session.snapshot()
	if not check(migrated_empty_inventory(start_profile), "normal initial save/snapshot creates complete empty original inventory+UID contract"): finish(); return
	if not check(empty_raw_events(start_profile) and start_profile.original_items.is_empty(), "fresh pre-run profile has zero task flags and no original items"): finish(); return
	var before_start: Dictionary = backend.session.snapshot()
	var first_condition: bool = Rules.matches(before_start, str(branch_rows[0].get("condition", "")))
	var second_condition: bool = Rules.matches(before_start, str(branch_rows[1].get("condition", "")))
	var selected_condition: bool = Rules.matches(before_start, str(branch_rows[2].get("condition", "")))
	if not check(not first_condition and not second_condition and selected_condition, "source ordered earlier branches0/1 are false and branch2 is first matching source condition"): finish(); return
	if not start_candidate(): finish(); return
	var selection_value: Variant = start_selections_snapshot
	if not check(selection_value is Array and not (selection_value as Array).is_empty(), "actual QuestAuto.start made one captured selector proposal"): finish(); return
	var selections: Array = selection_value
	var first_selection_value: Variant = selections[0]
	if not check(first_selection_value is Dictionary and first_selection_value.get("status") == "step" and first_selection_value.get("step", {}).get("id") == "jan:flower:2486", "actual start selector returns the source-derived first flower proposal without injected item/NOW/END"): finish(); return
	var step_value: Variant = start_step_snapshot
	if not check(step_value is Dictionary, "real start step remains a Dictionary"): finish(); return
	var actual_step: Dictionary = step_value
	if not check(actual_step.get("id") == "jan:flower:2486" and actual_step.get("npc_id") == "jaruga/event/event20_1@3400:59:66" and Motion.same_integer(actual_step.get("map_id", null), 3400), "QuestAuto.start captures original Kaeyi target"): finish(); return
	var target_cell: Array = Motion.cell(actual_step.get("cell", null))
	if not check(target_cell == [59,66], "captured target cell is a valid two-integer source coordinate"): finish(); return
	var actual_source_value: Variant = actual_step.get("source", null)
	if not check(actual_source_value is Dictionary, "captured flower source remains Dictionary"): finish(); return
	var actual_source: Dictionary = actual_source_value
	var actual_branch_value: Variant = actual_source.get("branch_data", null)
	if not check(actual_branch_value is Dictionary, "runner carries complete source branch Dictionary"): finish(); return
	var actual_branch: Dictionary = actual_branch_value
	if not check(same_source(actual_branch, expected_branch) and Motion.same_integer(actual_source.get("branch_index", null), 2) and Motion.same_integer(actual_source.get("source_line", null), 23) and actual_source.get("source_sha") == "ffc45d76c829aee8dd880058dea568b8f60e6c59d0a66fb3eea9ff5e33c94335" and same_source(actual_source.get("actions", null), {"GetItem":"2486"}) and actual_step.get("auto_choices") == ["yes","ok"], "runner proposal matches all raw branch identity/action fields and native yes/ok"): finish(); return
	if not check(Auto.new().safe_step(actual_step, 27, false), "existing strict runner allowlist accepts only this locked original ACCEPT/GetItem step"): finish(); return
	var reached: bool = await Wait.until(self, drive_until_manual, WAIT_SECONDS)
	if failed: finish(); return
	if not check(reached and done and not runner().running and runner().phase == "manual", "real QuestAuto lifecycle stops after earned first transaction at manual request20"): finish(); return
	if not check(transaction_count == 1 and transaction_open == false and runner().step.get("id") == "jan:flower:2486", "exactly one flower transaction completes; no request20 or delete-flower revisit starts"): finish(); return
	if not check(logical_points <= MAX_LOGICAL_POINTS and ordinary_walks > 0 and backend.candidate_field_calls == ordinary_walks, "actual ordinary field steps remain paired and under the global 6000 point cap"): finish(); return
	if not check(portal_sequence.size() == EDGE_CHAIN.size() and valid_acks == EDGE_CHAIN.size() and portal_maps.size() == EDGE_CHAIN.size(), "all seven original map edges were executed and valid-ACKed"): finish(); return
	if not check(portal_maps == EDGE_CHAIN, "actual source-matched portal map sequence equals 1000→100→1100→10201→10202→10203→200→3400"): finish(); return
	if not check(backend.automation.position_map == 3400 and near_target() and ArrivalPolicy.scope(backend.automation.position_map).is_empty(), "actual live authority ends within original Kai talk range in public map3400"): finish(); return
	if not check(backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty(), "no protected arrival scope/mark/stage was injected or granted by public corridor doors"): finish(); return
	if not check(not backend.battle_open and backend.original_quests.pending.is_empty() and backend.session._pending.is_empty() and not runner().owns_battle, "first transaction ends without an open battle or pending dialogue"): finish(); return
	if not check(backend.session._profile.get("location", null) == {"map_id":1000,"x":80,"y":90}, "live runtime movement does not silently rewrite the saved profile location"): finish(); return
	var observed_value: Variant = navigation()
	var observed: Variant = observed_value
	print("JAN PUBLIC-SPAWN FLOWER: points=%d walks=%d portals=%d ACKs=%d fields=%d route=%s next=%d plans=%d local_path=%d validate=%d elapsed_ms=%d stop=manual_request20" % [logical_points,ordinary_walks,portals,valid_acks,str(portal_sequence),observed.next_calls,observed.plan_calls,observed.local_path_calls,observed.validate_calls,Time.get_ticks_msec()-started_msec])
	finish()

func raw_optional_migration_fields_valid(fields: Dictionary) -> bool:
	var instances: Dictionary = fields.get("original_instances", {})
	var slots: Dictionary = fields.get("original_equipment", {})
	var uid: Dictionary = fields.get("next_original_uid", {})
	if bool(instances.get("present", false)) and (not instances.get("value") is Array or not (instances.get("value") as Array).is_empty()): return false
	if bool(slots.get("present", false)) and not zero_equipment_slots(slots.get("value")): return false
	if bool(uid.get("present", false)) and (not uid.get("value") is int or uid.get("value") != 1): return false
	return true

func prepare_native_public_start(unique: String) -> bool:
	var profile_value: Variant = backend.session._profile
	if not check(profile_value is Dictionary, "fresh GameSession raw profile is Dictionary"): return false
	var profile: Dictionary = profile_value
	var location_value: Variant = profile.get("location", null)
	if not check(location_value is Dictionary and same_source(location_value, {"map_id":1000,"x":80,"y":90}), "native fresh saved location is exact public 1000(80,90), not manifest spawn"): return false
	var raw_optional: Dictionary = raw_migration_fields(profile)
	trace.append({"kind":"raw_pre_migration","location":location_value.duplicate(true),"optional_equipment_fields":raw_optional})
	if not check(raw_optional_migration_fields_valid(raw_optional), "any already-present raw equipment migration fields retain their exact empty types/values"): return false
	if not check(empty_raw_events(profile), "raw profile begins with exact zero now/ended words before snapshot migration"): return false
	var items_value: Variant = profile.get("original_items", null)
	if not check(profile.has("original_items") and items_value is Array and (items_value as Array).is_empty(), "raw profile explicitly has empty original_items"): return false
	var level_value: Variant = profile.get("player", {}).get("level", null)
	if not check(level_value is int and level_value > 0, "native default character level has a valid integer type; no level convenience is added"): return false
	if not check(backend.automation.position_map == -1, "new Backend has no live actor position before ordinary public handshake"): return false
	var hello: Dictionary = backend.handle({"type":"report_position","map_id":1000,"cell":[80,90],"client":CLIENT})
	if not check(hello.get("ok", false) and backend.automation.position_map == 1000 and backend.automation.position_cell == Vector2i(80,90), "normal same-cell client handshake establishes authority at the saved start"): return false
	if not check(backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty() and backend.quest_arrival.has_arrival(backend,1000,Vector2i(80,90)), "public handshake does not inject protected proof"): return false
	if not check(backend.handle({"type":"no_random_encounters","enabled":true}).get("ok", false), "no_random_encounters is disclosed only as the route-measurement fixture"): return false
	if not check(backend.save(), "save new default profile normally before Runner.start"): return false
	var baseline: Dictionary = backend.session.snapshot()
	if not check(migrated_empty_inventory(baseline), "normal baseline save/snapshot performs supported equipment migration"): return false
	var baseline_disk: Session = Session.new()
	if not check(baseline_disk.load_game(backend.save_path), "normal baseline save has an independent Session.load_game readback"): return false
	var baseline_reloaded: Dictionary = baseline_disk.snapshot()
	if not check(saved_equal(baseline_reloaded, baseline), "complete baseline profile reads back exactly before route execution"): return false
	if not check(Rules.flag(baseline,"now",20) == false and Rules.flag(baseline,"ended",20) == false and Rules.flag(baseline,"now",21) == false and Rules.flag(baseline,"ended",21) == false and Rules.flag(baseline,"now",22) == false and Rules.flag(baseline,"ended",22) == false, "job27/28/29 original flags remain clear in fresh profile"): return false
	if not check(baseline.original_items.is_empty() and baseline.original_instances.is_empty() and baseline.next_original_uid == 1, "no original item or instance/UID is seeded before start"): return false
	return true

func start_candidate() -> bool:
	if start_call_count != 0:
		check(false, "real QuestAuto.start is invoked exactly once")
		return false
	start_call_count += 1
	wait_deadline_msec = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	var response: Dictionary = backend.handle({"type":"quest_auto_start","quest_id":27,"client":CLIENT,"_quest_connection":CONNECTION})
	start_response_snapshot = response.duplicate(true)
	var selection_value: Variant = runner().selections
	start_selections_snapshot = (selection_value as Array).duplicate(true) if selection_value is Array else selection_value
	var step_value: Variant = runner().step
	start_step_snapshot = (step_value as Dictionary).duplicate(true) if step_value is Dictionary else step_value
	var selection_count: int = (start_selections_snapshot as Array).size() if start_selections_snapshot is Array else -1
	var response_values: Dictionary = {"ok":bounded_metadata_value(start_response_snapshot.get("ok", null)),"error":bounded_metadata_value(start_response_snapshot.get("error", null)),"reason":bounded_metadata_value(start_response_snapshot.get("reason", null)),"response_shape":bounded_metadata_value(start_response_snapshot)}
	var runner_values: Dictionary = {"running":bounded_metadata_value(runner().running),"strict_walk":bounded_metadata_value(runner().strict_walk),"phase":bounded_metadata_value(runner().phase),"step":bounded_metadata_value(start_step_snapshot)}
	print("JAN START OBS ", JSON.stringify({"start_call_count":start_call_count,"response":response_values,"runner":runner_values,"selection_count":selection_count,"selections":bounded_metadata_value(start_selections_snapshot)}))
	if not check(start_call_count == 1 and start_response_snapshot.get("ok", false) and runner().running and runner().strict_walk and runner().phase == "travel", "real QuestAuto.start accepts through only the test-only wrapper and uses strict walk"): return false
	var started_step_value: Variant = start_step_snapshot
	if not check(started_step_value is Dictionary, "Runner start step is a Dictionary before target fields are read"): return false
	var started_step: Dictionary = started_step_value
	var started_cell: Array = Motion.cell(started_step.get("cell", null))
	if not check(started_step.get("id") == "jan:flower:2486" and started_cell == [59,66] and Motion.same_integer(started_step.get("map_id", null), 3400), "Runner captured the original first-stage proposal and complete target"): return false
	target = {"id":started_step.get("npc_id",""),"map_id":started_step.get("map_id",-1),"cell":started_cell.duplicate()}
	return true

func near_target() -> bool:
	if backend == null or not Motion.same_integer(backend.automation.position_map,3400): return false
	var map_value: Variant = Motion.integer(target.get("map_id",null))
	var goal: Array = Motion.cell(target.get("cell",null))
	if map_value == null or int(map_value) != 3400 or goal.size() != 2: return false
	var delta: Vector2i = backend.automation.position_cell - Vector2i(int(goal[0]),int(goal[1]))
	return maxi(absi(delta.x),absi(delta.y)) <= 2

func requirement_level_ok(link: Dictionary) -> bool:
	var level_value: Variant = Motion.integer(backend.session._profile.get("player", {}).get("level", null))
	if level_value == null: return false
	if not link.has("requires_level"): return true
	var required_value: Variant = Motion.integer(link.get("requires_level", null))
	return required_value != null and int(required_value) <= int(level_value)

func edge_link_matches(link: Dictionary, from_map: int, to_map: int) -> bool:
	var index: int = portal_maps.size()
	if index >= EDGE_CHAIN.size() or not same_source(EDGE_CHAIN[index], [from_map,to_map]): return false
	if link.has("disabled") and bool(link.disabled): return false
	if link.has("gate_source") or bool(link.get("requires_travel_pass", false)): return false
	if Passage.requires_permit(from_map,to_map): return false
	if not ArrivalPolicy.scope(from_map).is_empty() or not ArrivalPolicy.scope(to_map).is_empty(): return false
	if not requirement_level_ok(link): return false
	return reviewed_portal(link,from_map,to_map)

func drive_until_manual() -> bool:
	if failed or done: return true
	if Time.get_ticks_msec() >= wait_deadline_msec:
		check(false, "single absolute Wait 150 deadline reached before another ACK or Runner tick")
		return true
	if Time.get_ticks_msec() - started_msec >= int(HARD_EXTERNAL_SECONDS * 1000.0):
		check(false, "external hard 300-second budget reached between synchronous Runner calls; preserve state")
		return true
	if not runner().running and runner().phase != "manual":
		check(false, "runner stopped before source-derived manual request20 boundary")
		return true
	if runner().phase == "landing":
		var issued_value: Variant = runner().issued
		if not check(issued_value is Array and not (issued_value as Array).is_empty(), "original portal landing carries server-issued ACK receipt"): return true
		var issued: Array = issued_value
		var receipt_value: Variant = issued[-1]
		if not check(receipt_value is Dictionary, "portal receipt preserves Dictionary identity"): return true
		var receipt: Dictionary = receipt_value.duplicate(true)
		var ack: Dictionary = backend.handle(ack_for(receipt))
		if not check(ack.get("ok", false) and runner().running and runner().phase == "travel", "full original receipt ACK commits each source portal and continues the same run"): return true
		valid_acks += 1
		trace.append({"kind":"valid_portal_ack","receipt":receipt,"state":state()})
		return false
	if logical_points >= MAX_LOGICAL_POINTS and not near_target():
		check(false, "global 6000 logical point cap stops before an additional synchronous Runner/AStar call")
		return true
	var before_map: int = backend.automation.position_map
	var before_cell: Vector2i = backend.automation.position_cell
	var before_phase: String = runner().phase
	var arrival_scope_before: String = backend.quest_arrival._scope
	var map_scope_before: String = ArrivalPolicy.scope(before_map)
	var pending_before: Dictionary = backend.original_quests.pending.duplicate(true)
	var profile_before: Dictionary = backend.session.snapshot()
	var save_before: int = backend.quest_save_serial
	var fields_before: int = backend.candidate_field_calls
	runner().tick(backend,0.21)
	if Time.get_ticks_msec() >= wait_deadline_msec:
		check(false, "Wait 150 elapsed during synchronous Runner/AStar call; keep resulting authority and trace")
		return true
	var after_map: int = backend.automation.position_map
	var after_cell: Vector2i = backend.automation.position_cell
	var after_phase: String = runner().phase
	if before_map != after_map or before_cell != after_cell:
		logical_points += 1
		var point_value: Variant = navigation().last_point
		if not check(point_value is Dictionary and not (point_value as Dictionary).is_empty(), "actual original A next point was passively captured"): return true
		var point: Dictionary = point_value.duplicate(true)
		if before_map != after_map:
			var edge_index: int = portal_maps.size()
			var edge_index_in_range: bool = edge_index >= 0 and edge_index < EDGE_CHAIN.size()
			var expected_edge: Array = EDGE_CHAIN[edge_index] if edge_index_in_range else []
			var actual_edge: Array = [before_map,after_map]
			var edge_order: bool = edge_index_in_range and same_source(expected_edge,actual_edge)
			var live_value: Variant = backend.quest_helper.places.links(before_map).get(before_cell,{})
			if not check(live_value is Dictionary, "real moved portal has a live original link Dictionary"): return true
			var live: Dictionary = live_value
			var point_link_value: Variant = point.get("portal", null)
			var point_link_matches: bool = point_link_value is Dictionary and same_source(point_link_value,live)
			var source_identity: bool = edge_link_matches(live,before_map,after_map)
			var target_map_matches: bool = Motion.same_integer(point.get("map_id",null),after_map)
			var target_cell_matches: bool = Motion.cell(point.get("cell",[])) == [after_cell.x,after_cell.y]
			var no_level_failure: bool = requirement_level_ok(live)
			var no_permit_required: bool = not Passage.requires_permit(before_map,after_map) and not bool(live.get("requires_travel_pass",false))
			var origin_scope: String = ArrivalPolicy.scope(before_map)
			var destination_scope: String = ArrivalPolicy.scope(after_map)
			var scope_unchanged: bool = arrival_scope_before == backend.quest_arrival._scope and arrival_scope_before.is_empty() and origin_scope.is_empty() and destination_scope.is_empty()
			var arrival_preconditions: bool = edge_order and point_link_matches and source_identity and target_map_matches and target_cell_matches and no_level_failure and no_permit_required and scope_unchanged
			var arrival_checked: bool = false
			var arrival_result: bool = false
			if arrival_preconditions:
				arrival_checked = true
				arrival_result = backend.quest_arrival.has_arrival(backend,after_map,after_cell)
			var portal_observation: Dictionary = {"kind":"portal_commit","edge_index":edge_index,"edge_index_in_range":edge_index_in_range,"expected_edge":expected_edge,"actual_edge":actual_edge,"origin":[before_map,before_cell.x,before_cell.y],"destination":[after_map,after_cell.x,after_cell.y],"live_link":live.duplicate(true),"point":point.duplicate(true),"predicates":{"edge_order":edge_order,"point_link_matches":point_link_matches,"source_identity":source_identity,"target_map_matches":target_map_matches,"target_cell_matches":target_cell_matches,"no_level_failure":no_level_failure,"no_permit_required":no_permit_required,"arrival_scope_before":arrival_scope_before,"arrival_scope_after":backend.quest_arrival._scope,"origin_scope":origin_scope,"destination_scope":destination_scope,"scope_unchanged":scope_unchanged,"arrival_checked":arrival_checked,"has_arrival":arrival_result}}
			trace.append(portal_observation)
			if not check(arrival_preconditions and arrival_checked and arrival_result, "actual A-selected portal has exact source/landing and one read-only public arrival check before ACK"): return true
			portal_maps.append([before_map,after_map])
			portal_sequence.append(str(live.get("source","")))
			portals += 1
		else:
			var delta: Vector2i = after_cell - before_cell
			var cardinal_step: bool = absi(delta.x)+absi(delta.y)==1
			var point_map_matches: bool = Motion.same_integer(point.get("map_id",null),after_map)
			var point_cell_matches: bool = Motion.cell(point.get("cell",[])) == [after_cell.x,after_cell.y]
			var map_scope_after: String = ArrivalPolicy.scope(after_map)
			var scope_unchanged: bool = before_map == after_map and map_scope_before == map_scope_after and map_scope_before.is_empty() and arrival_scope_before == backend.quest_arrival._scope and arrival_scope_before.is_empty()
			var ordinary_preconditions: bool = cardinal_step and point_map_matches and point_cell_matches and not point.has("portal") and not point.has("gate") and scope_unchanged
			var arrival_checked: bool = false
			var arrival_result: bool = false
			if ordinary_preconditions:
				arrival_checked = true
				arrival_result = backend.quest_arrival.has_arrival(backend,after_map,after_cell)
			var walk_observation: Dictionary = {"kind":"ordinary_walk","from":[before_map,before_cell.x,before_cell.y],"to":[after_map,after_cell.x,after_cell.y],"point":point.duplicate(true),"predicates":{"cardinal_step":cardinal_step,"point_map_matches":point_map_matches,"point_cell_matches":point_cell_matches,"scope_before":map_scope_before,"scope_after":map_scope_after,"arrival_scope_before":arrival_scope_before,"arrival_scope_after":backend.quest_arrival._scope,"scope_unchanged":scope_unchanged,"arrival_checked":arrival_checked,"has_arrival":arrival_result}}
			trace.append(walk_observation)
			if not check(ordinary_preconditions and arrival_checked and arrival_result, "ordinary move preserves public map/arrival scope and passes one read-only arrival check"): return true
			ordinary_walks += 1
			if not check(backend.candidate_field_calls == fields_before + 1, "each ordinary authoritative cell performs exactly one original field_step"): return true
			if not check(not backend.battle_open, "declared no-random route fixture produces no battle during ordinary movement"): return true
		trace.append({"kind":"authority_step","from":[before_map,before_cell.x,before_cell.y],"to":[after_map,after_cell.x,after_cell.y],"point":point.duplicate(true),"phase_before":before_phase,"phase_after":after_phase,"field_calls":backend.candidate_field_calls,"scope":backend.quest_arrival._scope,"marks":backend.quest_arrival._marks.duplicate(true),"stages":backend.quest_arrival._stages.duplicate(true)})
	if before_phase == "travel" and pending_before.is_empty() and runner().phase == "strict_dialogue" and not backend.original_quests.pending.is_empty():
		if not check(not transaction_open, "only the original flower transaction begins"): return true
		var pending_value: Variant = backend.original_quests.pending.get("branch", null)
		if not check(pending_value is Dictionary and same_source(pending_value,runner().step.source.branch_data), "pending dialogue carries the exact proposed source branch"): return true
		transaction_open = true
		transaction_before = profile_before.duplicate(true)
		transaction_step = runner().step.duplicate(true)
		transaction_save_serial = save_before
		trace.append({"kind":"flower_transaction_open","before":transaction_before.duplicate(true),"step":transaction_step.duplicate(true)})
	if transaction_open and backend.original_quests.pending.is_empty() and runner().phase == "travel" and backend.quest_save_serial > transaction_save_serial:
		if not record_flower_transaction(): return true
	if not runner().running and runner().phase == "manual":
		var next_value: Variant = Plan.flower_proposal(backend,27)
		if not check(next_value is Dictionary, "post-transaction selector returns a result Dictionary"): return true
		var next: Dictionary = next_value
		done = not transaction_open and transaction_count == 1 and next.get("status") == "manual" and next.get("stage") == "request20" and not next.has("step") and Rules.flag(backend.session._profile,"now",20) == false
		if not check(done, "runner stopped at the first manual boundary, original Gide REQUEST20; no job flag was added"): return true
		trace.append({"kind":"manual_boundary","next":next.duplicate(true),"state":state()})
	return failed or done

func record_flower_transaction() -> bool:
	var earned: Dictionary = backend.session.snapshot()
	var before: Dictionary = transaction_before.duplicate(true)
	var items_value: Variant = before.get("original_items", null)
	var instances_value: Variant = before.get("original_instances", null)
	var uid_value: Variant = before.get("next_original_uid", null)
	if not check(items_value is Array and instances_value is Array and uid_value is int and uid_value > 0, "transaction-before inventory/instance/UID types are complete and native"): return false
	var before_items: Array = items_value
	var before_instances: Array = instances_value
	var new_uid: int = uid_value
	if not check(before_items.is_empty() and before_instances.is_empty() and before.next_original_uid == 1 and not before_instances.any(func(row): return row is Dictionary and row.get("uid", -1) == new_uid), "fresh flower pre-transaction has no item or reused UID"): return false
	# OriginalEquipment.instance returns exactly uid/item_id/durability. Item2486
	# has no equipment durability override, so the original value is zero.
	var expected_instance: Dictionary = {"uid":new_uid,"item_id":2486,"durability":0}
	var expected: Dictionary = before.duplicate(true)
	expected.original_items.append(2486)
	expected.original_instances.append(expected_instance.duplicate(true))
	expected.next_original_uid = new_uid + 1
	var earned_items_value: Variant = earned.get("original_items", null)
	var earned_instances_value: Variant = earned.get("original_instances", null)
	var earned_uid_value: Variant = earned.get("next_original_uid", null)
	if not check(earned_items_value is Array and earned_instances_value is Array and earned_uid_value is int, "earned item/instance/UID fields have complete strict types"): return false
	var earned_items: Array = earned_items_value
	var earned_instances: Array = earned_instances_value
	var flower_instances: Array = []
	var uid_count: int = 0
	for value in earned_instances:
		if not value is Dictionary: continue
		var instance_row: Dictionary = value
		if Motion.same_integer(instance_row.get("item_id",null),2486): flower_instances.append(instance_row)
		if Motion.same_integer(instance_row.get("uid",null),new_uid): uid_count += 1
	if not check(earned_items.size() == 1 and earned_items.count(2486) == 1 and flower_instances.size() == 1 and uid_count == 1 and same_source(flower_instances[0],expected_instance), "exactly one original 2486 instance uses the independently frozen next UID and zero durability"): return false
	if not check(earned.next_original_uid == new_uid + 1, "original next_original_uid advances once"): return false
	if not check(saved_equal(earned,expected), "complete earned profile differs only by independently expected 2486 item/instance/UID"): return false
	if not check(same_source(earned.original_events,before.original_events) and same_source(earned.original_equipment,before.original_equipment) and same_source(earned.equipment,before.equipment), "flower event-1 transaction changes no flags or equipped items"): return false
	var disk: Session = Session.new()
	if not check(disk.load_game(backend.save_path), "native ACCEPT transaction save loads through an independent Session.load_game"): return false
	var persisted: Dictionary = disk.snapshot()
	if not check(saved_equal(persisted,earned), "complete post-transaction profile and every instance field exactly read back"): return false
	if not check(saved_equal(persisted.get("location",null),before.get("location",null)) and same_source(persisted.get("location",null),{"map_id":1000,"x":80,"y":90}), "disk location stays at original save spawn; no endpoint write/save is fabricated"): return false
	var next_value: Variant = Plan.flower_proposal(backend,27)
	if not check(next_value is Dictionary, "post-flower selector result remains Dictionary"): return false
	var next: Dictionary = next_value
	if not check(next.get("status") == "manual" and next.get("stage") == "request20" and not next.has("step"), "source selector hands off at manual original REQUEST20"): return false
	transaction_count += 1
	trace.append({"kind":"flower_transaction_complete","before":before,"expected":expected,"earned":earned.duplicate(true),"persisted":persisted.duplicate(true),"next":next.duplicate(true),"save_serial_before":transaction_save_serial,"save_serial_after":backend.quest_save_serial})
	transaction_open = false
	transaction_before = {}
	transaction_step = {}
	return true

func write_trace() -> void:
	if trace_path_refused or trace_attempted: return
	trace_attempted = true
	var absolute_path: String = ProjectSettings.globalize_path(trace_path)
	if FileAccess.file_exists(trace_path) or DirAccess.dir_exists_absolute(absolute_path):
		trace_write_error = "trace target unexpectedly exists; refusing overwrite"
		return
	var file: FileAccess = FileAccess.open(trace_path, FileAccess.WRITE)
	if file == null:
		trace_write_error = "FileAccess.open failed: %s" % str(FileAccess.get_open_error())
		return
	var payload: String = JSON.stringify({"trace":trace,"first_failure":first_failure,"state":state(),"logical_points":logical_points,"ordinary_walks":ordinary_walks,"portals":portals,"valid_acks":valid_acks,"portal_sequence":portal_sequence,"portal_maps":portal_maps,"navigation":navigation().calls if backend != null else [],"transaction_count":transaction_count,"trace_write_error":trace_write_error}, "  ")
	file.store_string(payload)
	file.close()
	var check_file: FileAccess = FileAccess.open(trace_path, FileAccess.READ)
	if check_file == null:
		trace_write_error = "trace readback failed: %s" % str(FileAccess.get_open_error())
		return
	var length: int = check_file.get_length()
	var bytes: PackedByteArray = check_file.get_buffer(length)
	var read_error: Error = check_file.get_error()
	check_file.close()
	if read_error != OK or bytes.size() != length or bytes.get_string_from_utf8() != payload:
		trace_write_error = "trace readback length/content mismatch"

func finish() -> void:
	if not finished:
		finished = true
		write_trace()
	if not trace_write_error.is_empty():
		failures += 1
		failed = true
		push_error(trace_write_error)
	if backend != null: backend.free()
	print("quest_auto_jan_public_spawn_route_test: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
