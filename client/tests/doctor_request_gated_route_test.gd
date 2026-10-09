extends SceneTree
## UNRUN 6a product route. Navigation instrumentation only; admission and selector are production.
## no_random_encounters is only a disclosed route fixture, not natural-play evidence.
const Backend = preload("res://server/backend.gd")
const Plan = preload("res://server/quest_auto_doctor_plan.gd")
const Rules = preload("res://server/original_quests.gd")
const Session = preload("res://server/game_session.gd")
const Auto = preload("res://server/quest_auto.gd")
const Runner = preload("res://tests/support/doctor_request_observed_runner.gd")
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
const CLIENT: String = "doctor-public-spawn-request-candidate"
const CONNECTION: int = 61515
const MANIFEST_SHA: String = "5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639"
const CATALOG_SHA: String = "c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92"
const MAP_SHA: Dictionary = {
	1000: "d8a418bd5c77dfece89dc9cc13e395d2385f25417a76b6530dbc31c8f6051271",
	100: "8ff703bdb192c52298b7abe4f4700292776c864f149d4f8cea93ec7e2da461bd",
	11001: "10d3ccfec79b16398de03f3a7e9d45b6a3f3717aeb7796b6b9d7fd4921d591eb",
	11002: "d390edd7da32418988d4ad212e41e23d3d7ca067a77875fb945cf948eb1caa3a",
	11003: "182c938e7088108ea415070d187a9de25f20409019b93272507b7a1f5d788674",
	11004: "23ab975e8e263dffc10b5e4b2bf29d78cef6da11b645d3428ab13a9dcc9bb7d6",
	11005: "ca7a8ed2ed485d68e5f85f5e95ddc238e605e61e1570c1bebed2a590df47e441",
	11006: "6aa2a645bb4e7c56ac764442fe4cd33973115db65aa2a36f59f137006d15bec7"
}
## Complete active manifest links from the public village to outdoor map 100.
## These are accepted only if this is the link actually returned by original A.
const PUBLIC_ROADS: Array[Dictionary] = [
	{"source":"100warp.create:43","from_map":1000,"cell":[49,116],"to_map":100,"target":[637,491]},
	{"source":"100warp.create:52","from_map":1000,"cell":[49,117],"to_map":100,"target":[637,492]},
	{"source":"100warp.create:61","from_map":1000,"cell":[49,118],"to_map":100,"target":[637,493]},
	{"source":"100warp.create:70","from_map":1000,"cell":[49,119],"to_map":100,"target":[637,494]},
	{"source":"100warp.create:124","from_map":1000,"cell":[117,112],"to_map":100,"target":[706,488]},
	{"source":"100warp.create:133","from_map":1000,"cell":[118,112],"to_map":100,"target":[707,488]},
	{"source":"100warp.create:142","from_map":1000,"cell":[119,112],"to_map":100,"target":[708,488]},
	{"source":"100warp.create:151","from_map":1000,"cell":[120,112],"to_map":100,"target":[709,488]},
	{"source":"100warp.create:160","from_map":1000,"cell":[121,112],"to_map":100,"target":[710,488]}
]
const DOCTOR_CHAIN: Array[String] = [
	"dungeon00.create:1204", "dungeon00.create:1240", "dungeon00.create:1258",
	"dungeon00.create:1276", "dungeon00.create:1294", "dungeon00.create:1312"
]

class DiagnosticBackend extends "res://server/backend.gd":
	func _doctor_request_enabled()->bool:return true
	var candidate_field_calls: int = 0
	func _cmd_field_step(command: Dictionary) -> Dictionary:
		candidate_field_calls += 1
		return super._cmd_field_step(command)

var backend: Variant
var assertions: int = 0
var failures: int = 0
var failed: bool = false
var done: bool = false
var started_msec: int = 0
var logical_points: int = 0
var ordinary_walks: int = 0
var portal_sequence: Array[String] = []
var target: Dictionary = {}
var transaction_open: bool = false
var transaction_before: Dictionary = {}
var transaction_save_serial: int = 0
var transaction_rows: Array = []
var trace: Array[Dictionary] = []
var first_failure: Dictionary = {}
var trace_path: String = ""
var trace_error: String = ""
var wait_deadline_msec: int = 0

func _initialize() -> void:
	call_deferred("run")

func runner() -> Variant:
	return backend.quest_auto

func navigation():
	return runner().navigation

func state() -> Dictionary:
	if backend == null: return {}
	return {"map": backend.automation.position_map, "cell": [backend.automation.position_cell.x, backend.automation.position_cell.y], "scope": backend.quest_arrival._scope, "marks": backend.quest_arrival._marks.duplicate(true), "stages": backend.quest_arrival._stages.duplicate(true), "running": runner().running, "phase": runner().phase, "step": runner().step.get("id", "")}

func check(ok: bool, label: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		failed = true
		if first_failure.is_empty(): first_failure = {"label": label, "state": state(), "target": target.duplicate(true)}
		write_trace()
		push_error(label)
	return ok

func same_source(a: Variant, b: Variant) -> bool:
	return Plan.same_source(a, b)

func raw_optional_migration_fields(profile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field in ["original_instances", "original_equipment", "next_original_uid"]:
		var present: bool = profile.has(field)
		var value: Variant = profile.get(field) if present else null
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		result[field] = {"present": present, "value": value}
	return result

func zero_original_equipment_slots(value: Variant) -> bool:
	if not value is Dictionary: return false
	var slots: Dictionary = value
	var required: Array[String] = ["arm", "bracelet", "amulet", "head", "body"]
	if slots.size() != required.size(): return false
	for key in required:
		var slot_value: Variant = slots.get(key, null)
		if not slot_value is int or slot_value != 0: return false
	return true

func zero_raw_original_events(value: Variant) -> bool:
	if not value is Dictionary: return false
	var events: Dictionary = value
	if events.size() != 2: return false
	for kind in ["now", "ended"]:
		var words_value: Variant = events.get(kind, null)
		if not words_value is Array: return false
		var words: Array = words_value
		if words.size() != 6: return false
		for word in words:
			if not word is int or word != 0: return false
	return true

func migrated_empty_original_fields_valid(profile: Dictionary) -> bool:
	var items_value: Variant = profile.get("original_items", null)
	var instances_value: Variant = profile.get("original_instances", null)
	var slots_value: Variant = profile.get("original_equipment", null)
	var next_uid_value: Variant = profile.get("next_original_uid", null)
	var equipment_value: Variant = profile.get("equipment", null)
	if not profile.has("original_items") or not items_value is Array: return false
	if not profile.has("original_instances") or not instances_value is Array: return false
	if not profile.has("original_equipment") or not zero_original_equipment_slots(slots_value): return false
	if not profile.has("next_original_uid") or not next_uid_value is int or next_uid_value != 1: return false
	if not profile.has("equipment") or not equipment_value is Dictionary: return false
	var items: Array = items_value
	var instances: Array = instances_value
	if not items.is_empty() or not instances.is_empty() or instances.size() != items.size(): return false
	return same_source(equipment_value, {"body": "", "amulet": ""})

func source_hash(path: String, expected: String, label: String) -> bool:
	if not FileAccess.file_exists(path): return check(false, label + " missing")
	var raw: String = FileAccess.get_file_as_string(path)
	return check(not raw.is_empty() and raw.sha256_text() == expected, label + " SHA")

func binary_hash(path: String, expected: String, label: String) -> bool:
	if not FileAccess.file_exists(path): return check(false, label + " missing")
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if not check(not raw.is_empty(), label + " nonempty raw map"): return false
	var context: HashingContext = HashingContext.new()
	if not check(context.start(HashingContext.HASH_SHA256) == OK, label + " SHA context starts"): return false
	if not check(context.update(raw) == OK, label + " hashes complete raw bytes"): return false
	var digest: PackedByteArray = context.finish()
	if not check(digest.size() == 32, label + " SHA digest length"): return false
	return check(digest.hex_encode() == expected, label + " frozen SHA")

func reviewed_portal(link: Dictionary, from_map: int, to_map: int) -> bool:
	if bool(link.get("disabled", false)) or link.has("gate_source"): return false
	if Motion.same_integer(from_map, 1000) and Motion.same_integer(to_map, 100):
		for expected in PUBLIC_ROADS:
			if same_source(link, expected): return true
		return false
	var table_value: Variant = Plan.source_table()
	if not table_value is Dictionary: return false
	var table: Dictionary = table_value
	var doors_value: Variant = table.get("doors", null)
	if not doors_value is Array: return false
	var doors: Array = doors_value
	for expected_value in doors:
		if not expected_value is Dictionary: return false
		var expected: Dictionary = expected_value
		if Motion.same_integer(expected.get("from_map", -1), from_map) and Motion.same_integer(expected.get("to_map", -1), to_map) and same_source(link, expected): return true
	return false

func ack_for(receipt: Dictionary) -> Dictionary:
	var cell: Array = Motion.cell(receipt.get("cell", []))
	var ack: Dictionary = {"type": "report_position", "map_id": receipt.get("map_id", -1), "cell": cell, "quest_position_seq": receipt.get("quest_position_seq", -1), "client": CLIENT, "_quest_connection": CONNECTION}
	for field in Motion.IDENTITY_FIELDS:
		if receipt.has(field): ack[field] = receipt[field]
	return ack

func run() -> void:
	started_msec = Time.get_ticks_msec()
	var unique: String = str(Time.get_ticks_usec())
	trace_path = "user://doctor-public-request-" + unique + "-trace.json"
	backend = DiagnosticBackend.new()
	backend.set_process(false)
	backend.quest_auto = Runner.new()
	backend.fee_attach(CONNECTION)
	backend.save_path = "user://doctor-public-request-" + unique + ".json"
	for suffix in ["", ".bak", ".tmp", ".resume.json"]:
		var path: String = backend.save_path + suffix
		if not check(not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)), "new save/sidecar path is unused " + suffix): finish(); return
	if not check(not FileAccess.file_exists(trace_path) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(trace_path)), "trace path is not reused"): finish(); return
	if not source_hash("res://assets/legacy/world/manifest.json", MANIFEST_SHA, "complete world manifest"): finish(); return
	if not source_hash("res://assets/legacy/quests/catalog.json", CATALOG_SHA, "full quest catalog"): finish(); return
	for map_value in MAP_SHA:
		var map_id: int = int(map_value)
		if not binary_hash("res://assets/legacy/world/%d.map" % map_id, str(MAP_SHA[map_value]), "map %d" % map_id): finish(); return
	var table: Dictionary = Plan.source_table()
	if not check(not table.is_empty(), "source table exists after the plan's frozen raw SHA check"): finish(); return
	var doors_value: Variant = table.get("doors", null)
	var request_value: Variant = table.get("request", null)
	var npc_value: Variant = table.get("npc", null)
	var sources_value: Variant = table.get("sources", null)
	if not check(doors_value is Array and request_value is Dictionary and npc_value is Dictionary and sources_value is Dictionary, "source table doors/request/npc/sources have their required container types"): finish(); return
	var doors: Array = doors_value
	var request: Dictionary = request_value
	var raw_npc: Dictionary = npc_value
	var source_records: Dictionary = sources_value
	var branches_value: Variant = raw_npc.get("branches", null)
	if not check(doors.size() == 14 and branches_value is Array, "full 14-door lock and ordered raw branch array exist"): finish(); return
	var raw_branches: Array = branches_value
	if not check(raw_branches.size() == 7, "complete seven-branch raw NPC array is preserved"): finish(); return
	for branch_value in raw_branches:
		if not check(branch_value is Dictionary, "each original NPC branch is a full Dictionary"): finish(); return
	if not check(Motion.same_integer(request.get("job", null), 6) and Motion.same_integer(request.get("event", null), 15) and Motion.same_integer(request.get("branch_index", null), 2), "locked request metadata is exactly job6/event15/branch2 with finite integer values"): finish(); return
	var disabled_count: int = 0
	for door_value in doors:
		if not check(door_value is Dictionary, "every locked portal row retains its Dictionary type"): finish(); return
		var door: Dictionary = door_value
		if bool(door.get("disabled", false)):
			disabled_count += 1
			if not check(not reviewed_portal(door, int(door.get("from_map", -1)), int(door.get("to_map", -1))), "disabled source door remains rejected"): finish(); return
	if not check(disabled_count == 1, "only the reviewed root alternate is disabled"): finish(); return
	if not check(backend.quest_catalog.jobs.any(func(row): return row.get("id") == 6 and row.get("event") == 15) and backend.quest_catalog.jobs.any(func(row): return row.get("id") == 7 and row.get("event") == 16) and 15 in backend.quest_catalog.enabled_events, "live catalog keeps Doctor job/event mapping and event15 enabled"): finish(); return
	if not check(not Policy.supports(6, 15) and not Registry.supports(6), "production Policy/Registry stay closed"): finish(); return
	if not check(Settings.effective(backend.session.automation_settings()).mode == "A", "untouched default mode is original A"): finish(); return
	var default_auto: Auto = Auto.new()
	if not check(not default_auto._supports_automatic_start(6, 15) and not runner()._supports_automatic_start(6, 15) and backend._doctor_request_enabled() and not runner()._supports_automatic_start(7, 15), "Policy stays closed; gated product prepare_start alone admits Doctor"): finish(); return
	var profile: Dictionary = backend.session._profile
	var location_value: Variant = profile.get("location", {})
	if not check(location_value is Dictionary and same_source(location_value, {"map_id": 1000, "x": 80, "y": 90}) and backend.automation.position_map == -1, "fresh native save spawn is 1000(80,90), distinct from manifest placement spawn, with no live position"): finish(); return
	var raw_player_value: Variant = profile.get("player", null)
	if not check(raw_player_value is Dictionary, "raw constructor player retains its Dictionary type before fixture change"): finish(); return
	var raw_player: Dictionary = raw_player_value
	var raw_level_value: Variant = raw_player.get("level", null)
	if not check(raw_player.has("level") and raw_level_value is int and raw_level_value == 1, "raw constructor level is the original int 1 before the eligibility fixture"): finish(); return
	raw_player["level"] = 10 # Eligibility fixture only; no original quest/item/arrival state is seeded.
	var raw_events_value: Variant = profile.get("original_events", null)
	var raw_items_value: Variant = profile.get("original_items", null)
	var raw_equipment_value: Variant = profile.get("equipment", null)
	var raw_migration_fields: Dictionary = raw_optional_migration_fields(profile)
	trace.append({"kind": "raw_profile_migration_fields", "fields": raw_migration_fields})
	if not check(profile.has("original_events") and zero_raw_original_events(raw_events_value), "raw constructor original_events has exact empty now/ended arrays before Rules.flag reads"): finish(); return
	if not check(profile.has("original_items") and raw_items_value is Array and raw_items_value.is_empty(), "raw constructor has an explicitly present empty original_items Array"): finish(); return
	if not check(profile.has("equipment") and raw_equipment_value is Dictionary and same_source(raw_equipment_value, {"body": "", "amulet": ""}), "raw constructor retains its exact empty spirit equipment Dictionary"): finish(); return
	var raw_instances_state: Dictionary = raw_migration_fields["original_instances"]
	var raw_slots_state: Dictionary = raw_migration_fields["original_equipment"]
	var raw_uid_state: Dictionary = raw_migration_fields["next_original_uid"]
	var raw_instances: Variant = raw_instances_state["value"]
	var raw_slots: Variant = raw_slots_state["value"]
	var raw_uid: Variant = raw_uid_state["value"]
	var raw_optional_types_valid: bool = (not bool(raw_instances_state["present"]) or (raw_instances is Array and raw_instances.is_empty())) and (not bool(raw_slots_state["present"]) or zero_original_equipment_slots(raw_slots)) and (not bool(raw_uid_state["present"]) or (raw_uid is int and raw_uid == 1))
	if not check(raw_optional_types_valid, "any already-present raw instance/equipment/UID fields retain their exact types and empty-profile values"): finish(); return
	if not check(not bool(raw_instances_state["present"]) and not bool(raw_slots_state["present"]) and not bool(raw_uid_state["present"]), "fresh GameSession raw profile preserves the source-defined absence of migration-only equipment fields"): finish(); return
	if not check(not Rules.flag(profile, "now", 15) and not Rules.flag(profile, "now", 16) and not Rules.flag(profile, "ended", 15) and not Rules.flag(profile, "ended", 16), "fresh raw quest flags remain unset; only LV10 eligibility is set"): finish(); return
	var start_cell: Array = [int(location_value.x), int(location_value.y)]
	var handshake: Dictionary = backend.handle({"type": "report_position", "map_id": 1000, "cell": start_cell, "client": CLIENT})
	if not check(handshake.get("ok", false) and backend.automation.position_map == 1000 and backend.automation.position_cell == Vector2i(start_cell[0], start_cell[1]) and backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty() and backend.quest_arrival.has_arrival(backend, 1000, Vector2i(start_cell[0], start_cell[1])), "ordinary public-spawn handshake establishes authority without proof"): finish(); return
	if not check(backend.handle({"type": "no_random_encounters", "enabled": true}).get("ok", false) and backend.save(), "disclosed route-only encounter compatibility fixture saved normally"): finish(); return
	var before_start: Dictionary = backend.session.snapshot()
	if not check(migrated_empty_original_fields_valid(before_start), "first normal save/snapshot migrates original items, instances, slot map, UID and equipment with strict complete types"): finish(); return
	var candidate_value: Variant = Plan.request_proposal(backend, 6)
	if not check(candidate_value is Dictionary, "selector returns a proposal Dictionary"): finish(); return
	var candidate: Dictionary = candidate_value
	var raw_sources: Dictionary = source_records
	var expected_source_shas: Dictionary = {
		"jobdaily.txt": "0c073ce1cc455cc65a3e3118e5db25985441d433ef4745e7ea752e3235358612",
		"npc/genout/dungeon00.create": "1b3d189ea8ae5e42de4321efce19d3fb9517f0b25b6130ff0cb73761cd62514b",
		"npc/sainasu/event/event15.create": "1c4cbcc3c51fe33393f13712eb3754214605807ededf8892057069a0d9b51c64",
		"npc/sainasu/event/event15_1": "bdd68415498806f66ea795da05ac52f9c5122ade98df21581e63859515e77042"
	}
	for source_key in expected_source_shas:
		var record_value: Variant = raw_sources.get(source_key, null)
		if not check(record_value is Dictionary, "nested raw source record is a Dictionary " + str(source_key)): finish(); return
		var source_record: Dictionary = record_value
		if not check(source_record.get("sha256", "") == expected_source_shas[source_key], "nested raw source SHA " + str(source_key)): finish(); return
	var request_step_value: Variant = candidate.get("step", null)
	if not check(request_step_value is Dictionary, "REQUEST proposal contains a step Dictionary"): finish(); return
	var request_step: Dictionary = request_step_value
	var step_source_value: Variant = request_step.get("source", null)
	if not check(step_source_value is Dictionary, "REQUEST step source retains its Dictionary type"): finish(); return
	var step_source: Dictionary = step_source_value
	var step_actions_value: Variant = step_source.get("actions", null)
	if not check(step_actions_value is Dictionary, "REQUEST source actions retain their Dictionary type"): finish(); return
	var step_actions: Dictionary = step_actions_value
	var step_branch_value: Variant = step_source.get("branch_data", null)
	if not check(candidate.get("status") == "step" and request_step.get("id") == "doctor:request:15" and step_actions.is_empty() and Motion.same_integer(step_source.get("source_line", null), 26) and step_source.get("source_sha") == expected_source_shas["npc/sainasu/event/event15_1"] and same_source(step_branch_value, raw_branches[2]), "highest matching complete original REQUEST15 branch2 proposal"): finish(); return
	var active_npc_value: Variant = backend.quest_catalog.active_npc("sainasu/event/event15_1")
	if not check(active_npc_value is Dictionary, "active NPC projection retains its Dictionary type"): finish(); return
	var active_npc: Dictionary = active_npc_value
	var highest_value: Variant = backend.original_quests.branch_for(active_npc, before_start)
	if not check(highest_value is Dictionary, "original branch_for result retains its Dictionary type"): finish(); return
	var highest: Dictionary = highest_value
	if not check(not Rules.matches(before_start, str(raw_branches[0].get("condition", ""))) and not Rules.matches(before_start, str(raw_branches[1].get("condition", ""))) and Rules.matches(before_start, str(raw_branches[2].get("condition", ""))), "complete ordered raw branches show earlier pet/flag ACCEPT predicates false and branch2 REQUEST true"): finish(); return
	var highest_actions_value: Variant = highest.get("actions", null)
	if not check(highest_actions_value is Dictionary, "selected branch action container retains its Dictionary type"): finish(); return
	var highest_actions: Dictionary = highest_actions_value
	if not check(same_source(active_npc, raw_npc) and same_source(highest, raw_branches[2]) and highest.get("type") == "REQUEST" and highest.get("condition") == "LV>9" and highest_actions.is_empty(), "live branch_for priority selects exact frozen branch2 after earlier ACCEPT branches fail their original predicates"): finish(); return
	if not check(Auto.new().safe_step(request_step, 6, false), "existing strict runner step guard accepts only the source-locked empty-action REQUEST"): finish(); return
	target = request_step.duplicate(true)
	var admission: Dictionary = backend.handle({"type": "quest_auto_start", "quest_id": 6, "client": CLIENT, "_quest_connection": CONNECTION})
	if not check(admission.get("ok", false) and runner().running and runner().strict_walk and runner().phase == "travel" and same_source(runner().step, request_step), "real QuestAuto.start captures the same proposal through gated production admission"): finish(); return
	wait_deadline_msec = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	var started: bool = await Wait.until(self, drive, WAIT_SECONDS)
	if failed: finish(); return
	if not check(started and done and not runner().running and runner().phase == "manual", "real runner reaches its post-REQUEST manual stop within Wait 150"): finish(); return
	if not check(portal_sequence.size() == 7 and portal_sequence[0] in ["100warp.create:43", "100warp.create:52", "100warp.create:61", "100warp.create:70", "100warp.create:124", "100warp.create:133", "100warp.create:142", "100warp.create:151", "100warp.create:160"], "public spawn route uses one actual original 1000-to-100 A-selected portal"): finish(); return
	for index in range(DOCTOR_CHAIN.size()):
		if not check(portal_sequence[index + 1] == DOCTOR_CHAIN[index], "actual Doctor source portal order %d" % index): finish(); return
	if not check(logical_points <= MAX_LOGICAL_POINTS and ordinary_walks > 0 and backend.candidate_field_calls == ordinary_walks, "all ordinary moves have exactly one field step and remain under 6000 points"): finish(); return
	if not check(not backend.battle_open and backend.original_quests.pending.is_empty() and backend.session._pending.is_empty(), "no battle/dialogue/pet transaction remains open"): finish(); return
	print("DOCTOR RUNNER REQUEST15: points=%d walks=%d portals=%s fields=%d elapsed_ms=%d manual=manual_uid" % [logical_points, ordinary_walks, str(portal_sequence), backend.candidate_field_calls, Time.get_ticks_msec() - started_msec])
	finish()

func drive() -> bool:
	if failed or done: return true
	if Time.get_ticks_msec() >= wait_deadline_msec:
		check(false, "single Wait 150-second absolute deadline reached before another ACK/tick/AStar call")
		return true
	if Time.get_ticks_msec() - started_msec >= int(HARD_EXTERNAL_SECONDS * 1000.0):
		check(false, "external hard 300-second budget reached between synchronous runner calls")
		return true
	if logical_points >= MAX_LOGICAL_POINTS and runner().phase == "travel":
		check(false, "6000 global logical point cap reached before another runner tick"); return true
	if runner().phase == "landing":
		var issued: Array = runner().issued
		if not check(not issued.is_empty(), "cross-map landing has an issued server receipt"): return true
		var receipt_value: Variant = issued[-1]
		if not check(receipt_value is Dictionary, "portal receipt retains its original Dictionary type"): return true
		var receipt: Dictionary = receipt_value.duplicate(true)
		var ack: Dictionary = backend.handle(ack_for(receipt))
		if not check(ack.get("ok", false) and runner().phase == "travel", "native Backend accepts the full-identity portal ACK"): return true
		trace.append({"kind": "portal_ack", "receipt": receipt, "state": state()})
		return false
	var before_map: int = backend.automation.position_map
	var before_cell: Vector2i = backend.automation.position_cell
	var before_phase: String = runner().phase
	var before_pending: Dictionary = backend.original_quests.pending.duplicate(true)
	var before_profile: Dictionary = backend.session.snapshot()
	var before_serial: int = backend.quest_save_serial
	var fields_before: int = backend.candidate_field_calls
	runner().tick(backend, 0.21)
	if Time.get_ticks_msec() >= wait_deadline_msec:
		check(false, "single Wait 150-second absolute deadline elapsed during synchronous runner/AStar call; preserve its resulting state")
		return true
	var after_map: int = backend.automation.position_map
	var after_cell: Vector2i = backend.automation.position_cell
	if before_map != after_map or before_cell != after_cell:
		logical_points += 1
		var point: Dictionary = navigation().last_point.duplicate(true)
		var destination_matches: bool = not point.is_empty() and Motion.same_integer(point.get("map_id", -1), after_map) and Motion.cell(point.get("cell", [])) == [after_cell.x, after_cell.y]
		if before_map != after_map:
			var live_value: Variant = backend.quest_helper.places.links(before_map).get(before_cell, {})
			var live: Dictionary = live_value if live_value is Dictionary else {}
			var point_portal_value: Variant = point.get("portal", null)
			var point_has_portal: bool = point.has("portal") and point_portal_value is Dictionary
			var point_portal_matches_live: bool = point_has_portal and same_source(point_portal_value, live)
			var live_disabled: bool = bool(live.get("disabled", false))
			var live_has_gate_source: bool = live.has("gate_source")
			var live_ordinary: bool = not live_disabled and not live_has_gate_source
			var reviewed_identity: bool = live_ordinary and reviewed_portal(live, before_map, after_map)
			var exact: bool = point_has_portal and point_portal_matches_live and reviewed_identity
			var has_live_fee: bool = bool(live.get("requires_travel_pass", false))
			var pair_requires_permit: bool = Passage.requires_permit(before_map, after_map)
			var unpaid: bool = not has_live_fee and not pair_requires_permit
			trace.append({"kind":"portal_check","from_map":before_map,"from_cell":[before_cell.x,before_cell.y],"to_map":after_map,"to_cell":[after_cell.x,after_cell.y],"destination_matches_authority":destination_matches,"live_link":live.duplicate(true),"point":point.duplicate(true),"point_has_portal":point_has_portal,"point_portal_matches_live":point_portal_matches_live,"live_disabled":live_disabled,"live_has_gate_source":live_has_gate_source,"live_ordinary":live_ordinary,"reviewed_identity":reviewed_identity,"live_requires_travel_pass":has_live_fee,"pair_requires_permit":pair_requires_permit,"exact_source_identity":exact,"arrival_called":false})
			if not check(destination_matches, "actual strict_advance output equals authority destination"): return true
			if not check(point_has_portal, "portal result carries a Dictionary source identity"): return true
			if not check(point_portal_matches_live, "portal result source identity equals the exact live link"): return true
			if not check(reviewed_identity, "live portal matches one complete active reviewed source tuple"): return true
			if not check(unpaid, "portal live link and map pair require no travel fee"): return true
			var arrived: bool = backend.quest_arrival.has_arrival(backend, after_map, after_cell)
			trace[-1]["arrival_called"] = true
			trace[-1]["native_arrival"] = arrived
			if not check(arrived, "portal destination passes one native arrival check"): return true
			if before_map == 100 and after_map == 11001:
				if not check(backend.quest_arrival._scope == "doctor", "original root portal naturally establishes Doctor scope"): return true
			portal_sequence.append(str(live.get("source", "")))
		else:
			var delta: Vector2i = after_cell - before_cell
			if not check(absi(delta.x) + absi(delta.y) == 1 and not point.has("portal") and not point.has("gate"), "strict runner makes one cardinal field step"): return true
			ordinary_walks += 1
			if not check(backend.candidate_field_calls == fields_before + 1, "ordinary authority step runs exactly one native field_step"): return true
			if not check(backend.quest_arrival.has_arrival(backend, after_map, after_cell), "each ordinary point retains original arrival qualification"): return true
		trace.append({"from": [before_map, before_cell.x, before_cell.y], "to": [after_map, after_cell.x, after_cell.y], "point": point, "scope": backend.quest_arrival._scope, "marks": backend.quest_arrival._marks.duplicate(true), "stages": backend.quest_arrival._stages.duplicate(true), "phase": runner().phase})
	if before_phase == "travel" and before_pending.is_empty() and runner().phase == "strict_dialogue" and not backend.original_quests.pending.is_empty():
		if not check(not transaction_open, "only the first REQUEST15 transaction begins"): return true
		if not check(migrated_empty_original_fields_valid(before_profile), "pre-REQUEST full snapshot contains the complete migrated empty equipment identity"): return true
		transaction_open = true
		transaction_before = before_profile
		transaction_save_serial = before_serial
		transaction_rows = disk_rows(backend.save_path)
	if transaction_open and backend.original_quests.pending.is_empty() and runner().phase == "travel" and backend.quest_save_serial > transaction_save_serial:
		if not record_request_transaction(): return true
	if not runner().running and runner().phase == "manual":
		var next_value: Variant = Plan.request_proposal(backend, 6)
		if not check(next_value is Dictionary, "post-REQUEST selector returns a manual Dictionary"): return true
		var next: Dictionary = next_value
		done = not transaction_open and next.get("status") == "manual" and next.get("stage") == "manual_uid" and Rules.flag(backend.session._profile, "now", 15) and not Rules.flag(backend.session._profile, "ended", 15)
		if not check(done, "runner's real stopped state is the source-derived manual UID boundary"): return true
		trace.append({"kind": "manual_stop", "next": next, "state": state()})
	return failed or done

func record_request_transaction() -> bool:
	var earned: Dictionary = backend.session.snapshot()
	if not check(migrated_empty_original_fields_valid(transaction_before), "transaction-before snapshot retains complete migrated equipment fields"): return false
	if not check(migrated_empty_original_fields_valid(earned), "post-REQUEST snapshot retains complete migrated equipment fields"): return false
	var expected: Dictionary = transaction_before.duplicate(true)
	expected.original_events.now[0] = int(expected.original_events.now[0]) | (1 << 15)
	var expected_rows:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},transaction_rows[0],{"exists":false,"bytes":PackedByteArray()}]
	if not check(disk_rows(backend.save_path)==expected_rows and backend.last_saved_payload==JSON.stringify(expected) and backend.quest_save_serial==transaction_save_serial+1,"independent main/bak/tmp/cache/serial exact original REQUEST"):return false
	if not check(same_source(earned, expected), "complete profile diff is exactly the original NOW15 transaction"): return false
	if not check(same_source(earned.original_items, transaction_before.original_items) and same_source(earned.original_instances, transaction_before.original_instances) and earned.next_original_uid is int and earned.next_original_uid == transaction_before.next_original_uid and same_source(earned.original_equipment, transaction_before.original_equipment) and same_source(earned.equipment, transaction_before.equipment), "empty-action request creates no item/instance/UID/equipment change"): return false
	var disk: Session = Session.new()
	if not check(disk.load_game(backend.save_path), "native transaction save reloads"): return false
	var reloaded: Dictionary = disk.snapshot()
	if not check(migrated_empty_original_fields_valid(reloaded), "independent Session.load_game plus snapshot restores the complete migrated empty equipment fields"): return false
	if not check(same_source(reloaded, earned), "Session.load_game full profile exactly equals earned transaction"): return false
	if not check(Rules.flag(earned, "now", 15) and not Rules.flag(earned, "now", 16) and not Rules.flag(earned, "ended", 15) and not Rules.flag(earned, "ended", 16), "REQUEST creates only NOW15, without job7/END completion"): return false
	var expected_location: Dictionary = {"map_id": 1000, "x": 80, "y": 90}
	if not check(same_source(reloaded.get("location", null), expected_location), "save location remains exactly the canonical spawn with finite integral numeric fields; no endpoint save was fabricated"): return false
	var next_value: Variant = Plan.request_proposal(backend, 6)
	if not check(next_value is Dictionary, "post-REQUEST selector returns a manual Dictionary"): return false
	var next: Dictionary = next_value
	if not check(next.get("status") == "manual" and next.get("stage") == "manual_uid" and not next.has("step"), "next proposal stops for player UID decision"): return false
	trace.append({"kind": "request15", "before": transaction_before.duplicate(true), "earned": earned.duplicate(true), "reloaded": reloaded.duplicate(true), "next": next.duplicate(true), "save_serial_before": transaction_save_serial, "save_serial_after": backend.quest_save_serial})
	transaction_open = false
	transaction_before = {}
	return true

func finish() -> void:
	write_trace()
	if not trace_error.is_empty():
		failures += 1
		failed = true
		push_error(trace_error)
	if backend != null: backend.free()
	print("DOCTOR 6A ROUTE: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func write_trace() -> void:
	if trace_path.is_empty(): return
	var file: FileAccess = FileAccess.open(trace_path, FileAccess.WRITE)
	if file == null:
		trace_error = "cannot write unique route trace"
		return
	var serialized: String = JSON.stringify({"trace": trace, "first_failure": first_failure, "state": state(), "points": logical_points, "walks": ordinary_walks, "portals": portal_sequence, "field_calls": backend.candidate_field_calls if backend != null else 0, "next_calls": navigation().next_calls if backend != null else 0, "plan_calls": navigation().plan_calls if backend != null else 0, "local_path_calls": navigation().local_path_calls if backend != null else 0, "elapsed_ms": Time.get_ticks_msec() - started_msec}, "  ")
	file.store_string(serialized)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		trace_error = "route trace write error " + str(write_error)
		return
	var verify: FileAccess = FileAccess.open(trace_path, FileAccess.READ)
	if verify == null:
		trace_error = "route trace cannot be read back"
		return
	var length: int = verify.get_length()
	verify.close()
	if length != serialized.to_utf8_buffer().size(): trace_error = "route trace readback length mismatch"

func disk_rows(path:String)->Array:
	var result:Array=[]
	for suffix in ["", ".bak", ".tmp"]:
		var exists:bool=FileAccess.file_exists(path+suffix)
		result.append({"exists":exists,"bytes":FileAccess.get_file_as_bytes(path+suffix) if exists else PackedByteArray()})
	return result
