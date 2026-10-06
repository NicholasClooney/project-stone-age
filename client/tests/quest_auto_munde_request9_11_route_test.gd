extends SceneTree
## UNRUN: real QuestAuto.start/tick/strict_advance candidate acceptance.
## Policy/Registry files and their normal job-8 closure remain unchanged.
const Backend = preload("res://server/backend.gd")
const Candidate = preload("res://server/quest_auto_munde_request11_candidate.gd")
const Plan = preload("res://server/quest_auto_munde_plan.gd")
const Auto = preload("res://server/quest_auto.gd")
const Runner = preload("res://tests/support/quest_auto_munde_candidate_runner.gd")
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
const HARD_EXTERNAL_PROPOSAL := 300.0
const CLIENT_ID := "munde-request9-11-runner-candidate"
const CONNECTION_ID := 91008
const WORLD_MANIFEST_SHA := "5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639"

class DiagnosticBackend extends "res://server/backend.gd":
	var candidate_field_calls := 0
	func _cmd_field_step(command: Dictionary) -> Dictionary:
		candidate_field_calls += 1
		return super._cmd_field_step(command)

## Exact original public road/village/cave doors needed by this candidate.
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
	{"source":"100warp.create:592","from_map":1400,"cell":[72,116],"to_map":100,"target":[260,171]}
]

var backend: Variant
var assertions := 0
var failures := 0
var failed := false
var done := false
var target: Dictionary = {}
var trace: Array = []
var first_failure: Dictionary = {}
var logical_points := 0
var ordinary_walks := 0
var portals := 0
var portal_sequence: Array[String] = []
var phase := "request9"
var started_msec := 0
var wait_deadline_msec := 0
var first_live_receipt: Dictionary = {}
var inrun_stale_checked := false
var cancel_probe_done := false
var cancel_old_receipt: Dictionary = {}
var second_step_checked := false
var transaction_open := false
var transaction_before: Dictionary = {}
var transaction_step_id := ""
var transaction_serial_before := 0
var recorded_transactions: Array[int] = []

func _initialize() -> void:
	call_deferred("run")

func runner() -> Variant:
	return backend.quest_auto

func navigation():
	return runner().navigation

func state() -> Dictionary:
	if backend == null:return {}
	var result: Dictionary = {"map_id":backend.automation.position_map,"cell":[backend.automation.position_cell.x,backend.automation.position_cell.y],"location":backend.session._profile.get("location",{}),"scope":backend.quest_arrival._scope,"marks":backend.quest_arrival._marks,"stages":backend.quest_arrival._stages,"npc_version":backend.original_quests.npc_state.version,"running":runner().running,"phase":runner().phase,"run_id":runner().identity.run_id,"step_id":runner().identity.step_id,"revision":runner().identity.revision,"position_serial":runner().position_serial}
	return result.duplicate(true)

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
		write_trace()
		push_error(label)
	return ok

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
	for expected in REVIEWED_PORTALS:
		if str(link.get("source", "")) == str(expected.source):return saved_equal(link, expected)
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

func source_sequence_matches(start: int, expected: Array[String]) -> bool:
	if portal_sequence.size() != start + expected.size():return false
	for index in range(expected.size()):
		if portal_sequence[start + index] != expected[index]:return false
	return true

func write_trace() -> void:
	var nav_trace: Dictionary = {}
	if backend != null:
		var observed = navigation()
		nav_trace = {"next_calls":observed.next_calls,"plan_calls":observed.plan_calls,"local_path_calls":observed.local_path_calls,"grid_rebuilds":observed.grid_rebuilds,"grid_rebuild_cells":observed.grid_rebuild_cells}
	var f = FileAccess.open("user://munde-request9-11-runner-candidate-trace.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"trace":trace,"first_failure":first_failure,"state":state(),"logical_points":logical_points,"ordinary_walks":ordinary_walks,"portals":portals,"portal_sequence":portal_sequence,"field_calls":backend.candidate_field_calls if backend != null else 0,"navigation":nav_trace,"phase":phase,"done":done}, "  "))
		f.close()

func prepare_backend(save_name: String) -> bool:
	backend = DiagnosticBackend.new()
	backend.set_process(false)
	backend.quest_auto = Runner.new()
	backend.save_path = "user://" + save_name
	var saved_location_value: Variant = backend.session._profile.get("location", {})
	if not check(saved_location_value is Dictionary, "fresh native profile location has its required Dictionary type"):return false
	var saved_location: Dictionary = saved_location_value.duplicate(true)
	if not check(saved_location == {"map_id":1000,"x":80,"y":90}, "fresh native default save location is the public 1000(80,90) spawn"):return false
	if not check(backend.automation.position_map == -1, "backend starts without a fabricated live position"):return false
	backend.session._profile.player.level = 30
	Rules.set_flag(backend.session._profile, "ended", 4, true)
	if not check(not Rules.flag(backend.session._profile,"now",9) and not Rules.flag(backend.session._profile,"now",11) and not Rules.flag(backend.session._profile,"ended",9) and not Rules.flag(backend.session._profile,"ended",10) and not Rules.flag(backend.session._profile,"ended",11) and not Rules.flag(backend.session._profile,"ended",12), "only explicit LV30/END4 eligibility; no NOW/END completion injected"):return false
	var handshake: Dictionary = backend.handle({"type":"report_position","map_id":int(saved_location.map_id),"cell":[int(saved_location.x),int(saved_location.y)],"client":CLIENT_ID})
	if not check(handshake.get("ok",false) and backend.automation.position_map == 1000 and backend.automation.position_cell == Vector2i(80,90), "normal initial client position report establishes saved public spawn"):return false
	if not check(backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty(), "initial handshake gives no protected scope/mark/stage"):return false
	if not check(backend.handle({"type":"no_random_encounters","enabled":true}).get("ok",false), "original no-random compatibility setting saves; not natural-encounter evidence"):return false
	if not check(backend.save(), "isolated candidate save initialized"):return false
	return true

func start_candidate() -> bool:
	var row: Dictionary = runner().row(backend, 8)
	var event_id := int(row.get("event", -1))
	if not check(event_id == 9 and 9 in backend.quest_catalog.enabled_events, "catalog maps job 8 to enabled original event 9"):return false
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
	var before_state: Dictionary = state()
	var before_profile: Dictionary = backend.session.snapshot()
	var before_serial: int = runner().position_serial
	var before_save: int = backend.quest_save_serial
	var reply: Dictionary = backend.handle(ack_for(receipt))
	return check(reply.get("ok",false) and state() == before_state and saved_equal(backend.session.snapshot(),before_profile) and runner().position_serial == before_serial and backend.quest_save_serial == before_save and runner().running == expect_running, label)

func start_snapshot_check() -> bool:
	if not numeric_container_contract_checks():return false
	var manifest_path := "res://assets/legacy/world/manifest.json"
	var manifest: String = FileAccess.get_file_as_string(manifest_path) if FileAccess.file_exists(manifest_path) else ""
	return check(not manifest.is_empty() and manifest.sha256_text() == WORLD_MANIFEST_SHA, "complete original world manifest matches the reviewed portal identity set")

func run() -> void:
	started_msec = Time.get_ticks_msec()
	if not start_snapshot_check():finish();return
	if not prepare_backend("munde-request9-11-runner-candidate.json"):finish();return
	var first: Dictionary = Candidate.select(backend, 8)
	if not check(first.get("status") == "step" and first.step.id == "munde:request:9" and first.step.npc_id == Plan.REQUEST_NPC and first.step.map_id == 1200 and first.step.cell == [97,75], "exact original REQUEST9 candidate selected from current stage"):finish();return
	if not check(first.step.source.type == "REQUEST" and first.step.source.branch_index == 1 and first.step.source.source_line == 14 and first.step.source.source_sha == "7d201e34ea3b230dc9deac43556e6cc50c43647fae01d1a35a6df4cc114618e7" and first.step.source.actions.is_empty() and first.step.auto_choices == ["yes","ok"], "complete locked event09 REQUEST source, empty actions only"):finish();return
	if not check(Auto.new().safe_step(first.step, 8), "the existing strict REQUEST guard accepts the reviewed candidate shape"):finish();return
	target = first.step.duplicate(true)
	if not start_candidate():finish();return
	if not check(runner().step.id == first.step.id and runner().step.source == first.step.source, "actual QuestAuto.start selected the same full source-locked REQUEST9 step"):finish();return
	wait_deadline_msec = Time.get_ticks_msec() + int(WAIT_PER_REQUEST * 1000)
	var reached: bool = await Wait.until(self, drive_request11, WAIT_PER_REQUEST)
	if failed:finish();return
	if not check(reached and phase == "request11" and runner().step.id == "munde:request11", "runner's first native transaction advances to the selected REQUEST11 step within Wait 150"):finish();return
	var first_route_ok := portal_sequence.size() == 5 and str(portal_sequence[0]) in ["100warp.create:43","100warp.create:52","100warp.create:61","100warp.create:70","100warp.create:124","100warp.create:133","100warp.create:142","100warp.create:151","100warp.create:160"] and source_sequence_matches(1, ["dungeon00.create:142","dungeon00.create:160","dungeon00.create:178","dungeon00.create:196"])
	if not check(first_route_ok, "runner's accepted route uses only the original road floors 10101→10102→10103→1200"):finish();return
	var second: Dictionary = Candidate.select(backend, 8)
	if not check(second.get("status") == "step" and second.step.id == "munde:request11" and second.step.npc_id == Plan.REQUEST11_NPC and second.step.map_id == 1400 and Motion.cell(second.step.cell) == [71,76], "earned NOW9 selects exact original Katan REQUEST11"):finish();return
	if not check(second.step.source.type == "REQUEST" and second.step.source.branch_index == 3 and second.step.source.source_line == 41 and second.step.source.source_sha == "e6b9230968cbd1669bcade7223c0fc7c4d7b6213320fc0311db0f1394a0540f3" and second.step.source.actions.is_empty() and second.step.auto_choices == ["yes","ok"], "full selected REQUEST11 branch3 source and empty actions"):finish();return
	if not check(Auto.new().safe_step(second.step, 8), "the existing strict REQUEST guard accepts the earned next step"):finish();return
	target = second.step.duplicate(true)
	wait_deadline_msec = Time.get_ticks_msec() + int(WAIT_PER_REQUEST * 1000)
	reached = await Wait.until(self, drive_request11_manual, WAIT_PER_REQUEST)
	if failed:finish();return
	if not check(reached and done and phase == "manual" and not runner().running, "second original transaction reaches the candidate manual stop boundary within Wait 150"):finish();return
	if not check(recorded_transactions == [9, 11], "both original transactions were recorded with full profile and native save readback"):finish();return
	var second_route_ok := portal_sequence.size() == 10 and str(portal_sequence[9]) in ["100warp.create:547","100warp.create:556","100warp.create:565"]
	if second_route_ok:second_route_ok = source_sequence_matches(5, ["dungeon00.create:205","dungeon00.create:187","dungeon00.create:169","dungeon00.create:151",str(portal_sequence[9])])
	if not check(second_route_ok, "runner's accepted return follows the original road and a source-locked Katan portal"):finish();return
	if not check(logical_points <= MAX_LOGICAL_POINTS and backend.candidate_field_calls == ordinary_walks and portals > 0, "all ordinary runner movements executed one original field step; total logical points stay <= 6000"):finish();return
	if not check(not backend.battle_open and backend.original_quests.pending.is_empty() and backend.session._pending.is_empty() and backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty(), "no open transaction/battle or fabricated protected proof"):finish();return
	var observed = navigation()
	print("MUNDE RUNNER REQUEST9->11: points=%d walks=%d portals=%d fields=%d sources=%s next=%d plans=%d local_path=%d grid_rebuilds=%d grid_cells=%d elapsed_ms=%d stop=request10_manual" % [logical_points,ordinary_walks,portals,backend.candidate_field_calls,str(portal_sequence),observed.next_calls,observed.plan_calls,observed.local_path_calls,observed.grid_rebuilds,observed.grid_rebuild_cells,Time.get_ticks_msec()-started_msec])
	finish()

func drive_request11() -> bool:
	if failed:return true
	if phase == "request11" and runner().step.get("id", "") == "munde:request11":return true
	if Time.get_ticks_msec() >= wait_deadline_msec:
		check(false, "REQUEST9 Wait 150 deadline; do not begin another synchronous runner/AStar call")
		return true
	if not runner().running:
		check(false, "runner stopped before the committed REQUEST9 advanced to REQUEST11")
		return true
	return runner_frame()

func drive_request11_manual() -> bool:
	if failed:return true
	if done:return true
	if Time.get_ticks_msec() >= wait_deadline_msec:
		check(false, "REQUEST11 Wait 150 deadline; do not begin another synchronous runner/AStar call")
		return true
	if not runner().running and runner().phase != "manual":
		check(false, "runner stopped outside the reviewed manual boundary")
		return true
	return runner_frame()

func runner_frame() -> bool:
	if failed or done:return true
	if Time.get_ticks_msec() - started_msec > int(HARD_EXTERNAL_PROPOSAL * 1000):
		check(false, "300 second hard external wall limit (checked between synchronous runner calls only)")
		return true
	if runner().phase == "landing":
		var receipts: Array = runner().issued
		if not check(not receipts.is_empty(), "cross-map landing has a server-issued receipt"):return true
		var latest_receipt: Variant = receipts[-1]
		if not check(latest_receipt is Dictionary, "server-issued landing receipt retains its native Dictionary type"):return true
		var receipt_source: Dictionary = latest_receipt
		var receipt: Dictionary = receipt_source.duplicate(true)
		var before_phase: String = runner().phase
		var ack: Dictionary = backend.handle(ack_for(receipt))
		if not check(ack.get("ok",false) and runner().phase == "travel" and before_phase == "landing", "real Backend report_position dispatch accepts the current full-identity portal ACK"):return true
		trace.append({"kind":"portal_ack","receipt":receipt,"state":state()})
		return false
	if logical_points >= MAX_LOGICAL_POINTS and runner().phase == "travel":
		var npc: Dictionary = backend.original_quests.npc_by_id(str(runner().step.get("npc_id", "")))
		var offset: Vector2i = backend.automation.position_cell - Vector2i(int(npc.get("cell", [999999,999999])[0]),int(npc.get("cell", [999999,999999])[1]))
		if int(npc.get("map_id", -1)) != backend.automation.position_map or maxi(absi(offset.x),absi(offset.y)) > 2:
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
	runner().tick(backend, 0.21)
	var after_map: int = backend.automation.position_map
	var after_cell: Vector2i = backend.automation.position_cell
	if before_map != after_map or before_cell != after_cell:
		logical_points += 1
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
			var origin_scope_public: bool = origin_scope.is_empty()
			var destination_scope_public: bool = destination_scope.is_empty()
			var ordinary: bool = has_portal and point_portal_matches_live and live_matches_reviewed_source and point_map_matches and point_cell_matches and link_enabled and no_gate_source and no_travel_pass and no_permit and origin_scope_public and destination_scope_public
			var arrival_checked: bool = ordinary
			var arrival_observed: bool = false
			if arrival_checked:arrival_observed = backend.quest_arrival.has_arrival(backend,after_map,after_cell)
			if not ordinary or not arrival_observed:
				first_failure = {"kind":"portal_rejected" if not ordinary else "arrival_rejected","origin":[before_map,before_cell.x,before_cell.y],"point":point,"live_link":live.duplicate(true),"conjuncts":{"has_portal":has_portal,"point_portal_matches_live":point_portal_matches_live,"live_matches_reviewed_source":live_matches_reviewed_source,"point_map_matches":point_map_matches,"point_cell_matches":point_cell_matches,"link_enabled":link_enabled,"no_gate_source":no_gate_source,"no_travel_pass":no_travel_pass,"no_permit":no_permit,"origin_scope_public":origin_scope_public,"destination_scope_public":destination_scope_public,"arrival_checked":arrival_checked,"arrival_observed":arrival_observed},"raw":{"point_map_id":point.get("map_id"),"expected_map_id":after_map,"point_cell":point.get("cell"),"normalized_point_cell":point_cell_value,"expected_cell":[after_cell.x,after_cell.y],"origin_scope":origin_scope,"destination_scope":destination_scope,"live_link_size":live.size()}}
			if not check(ordinary and arrival_observed, "runner crosses only a source-locked ordinary portal and destination arrival is observed"):return true
			portal_sequence.append(str(live.get("source", "")))
			portals += 1
		else:
			var delta := after_cell - before_cell
			if not check(absi(delta.x) + absi(delta.y) == 1 and not point.has("portal") and not point.has("gate"), "runner movement remains one original cardinal field cell"):return true
			ordinary_walks += 1
			if not check(backend.candidate_field_calls == fields_before + 1, "each committed ordinary cell receives exactly one original field_step call"):return true
			if first_live_receipt.is_empty():
				var current_receipts: Array = runner().issued
				if not check(not current_receipts.is_empty(), "ordinary committed move appended its server receipt"):return true
				var latest_live_receipt: Variant = current_receipts[-1]
				if not check(latest_live_receipt is Dictionary, "ordinary server receipt retains its native Dictionary type"):return true
				var live_receipt_source: Dictionary = latest_live_receipt
				first_live_receipt = live_receipt_source.duplicate(true)
		trace.append({"map":after_map,"from":[before_map,before_cell.x,before_cell.y],"to":[after_map,after_cell.x,after_cell.y],"portal":str(point.get("portal",{}).get("source","")),"field_calls":backend.candidate_field_calls,"runner_phase":runner().phase,"step":runner().identity.step_id,"position_serial":runner().position_serial})
		if not inrun_stale_checked and logical_points >= 2 and not first_live_receipt.is_empty():
			inrun_stale_checked = true
			if not replay_stale(first_live_receipt, "an older real-run position ACK is consumed without moving authority, saving, changing sequence, or stopping the current run", true):return true
	if before_phase == "travel" and before_pending.is_empty() and runner().phase == "strict_dialogue" and not backend.original_quests.pending.is_empty():
		if before_step == "munde:request11" and not cancel_probe_done:
			if not cancel_mid_dialogue_and_restart():return true
		else:
			transaction_open = true
			transaction_before = before_profile
			transaction_step_id = before_step
			transaction_serial_before = before_save_serial
	if transaction_open and backend.original_quests.pending.is_empty() and runner().phase == "travel" and backend.quest_save_serial > transaction_serial_before:
		if not record_transaction():return true
	if phase == "request11" and runner().step.get("id", "") == "munde:request11" and not second_step_checked:
		second_step_checked = true
		var selected: Dictionary = runner().step
		if not check(selected.npc_id == Plan.REQUEST11_NPC and selected.source.type == "REQUEST" and selected.source.branch_index == 3 and selected.source.source_line == 41 and selected.source.source_sha == "e6b9230968cbd1669bcade7223c0fc7c4d7b6213320fc0311db0f1394a0540f3" and selected.source.actions.is_empty(), "actual runner strict selection consumes the exact complete REQUEST11 candidate"):return true
	if not runner().running and runner().phase == "manual":
		phase = "manual"
		done = Rules.flag(backend.session._profile,"now",11)
		if not done:check(false, "runner reached manual handoff before the actual NOW11 transaction")
		trace.append({"kind":"runner_manual_stop","state":state(),"selection":Candidate.select(backend,8)})
	return failed or done

func cancel_mid_dialogue_and_restart() -> bool:
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
	var stop_reply: Dictionary = backend.handle({"type":"quest_auto_stop"})
	if not check(stop_reply.get("ok",false) and not runner().running and runner().phase == "stopped" and backend.original_quests.pending.is_empty(), "real quest_auto_stop cancels the live runner and clears its pending dialogue"):return false
	if not check(saved_equal(backend.session.snapshot(),profile_before) and backend.quest_save_serial == serial_before and backend.automation.position_map == current_map and backend.automation.position_cell == current_cell, "cancellation before REQUEST11 choice changes neither saved profile nor authority"):return false
	if not replay_stale(old_receipt, "cancelled-run old ACK is consumed and cannot restore an earlier authority position", false):return false
	cancel_probe_done = true
	transaction_open = false
	if not start_candidate():return false
	if not check(runner().identity.run_id != old_run and runner().running and backend.automation.position_map == current_map and backend.automation.position_cell == current_cell, "a new admitted run has a fresh identity at the actual current arrival"):return false
	if not replay_stale(old_receipt, "prior-run ACK remains inert after a new run starts", true):return false
	trace.append({"kind":"cancel_restart","old_run":old_run,"new_run":runner().identity.run_id,"old_receipt":old_receipt})
	return true

func record_transaction() -> bool:
	var event_id := 9 if transaction_step_id == "munde:request:9" else 11
	var earned: Dictionary = backend.session.snapshot()
	var expected: Dictionary = transaction_before.duplicate(true)
	Rules.set_flag(expected, "now", event_id, true)
	if not check(saved_equal(earned, expected), "full profile diff is exactly the runner-earned NOW%d flag" % event_id):return false
	var disk = Session.new()
	if not check(disk.load_game(backend.save_path) and saved_equal(disk.snapshot(), earned), "normal native transaction save reads back the complete profile"):return false
	var following: Dictionary = Candidate.select(backend, 8)
	if event_id == 9:
		if not check(following.get("status") == "step" and following.step.id == "munde:request11" and Rules.flag(earned,"now",9), "only actually committed NOW9 enables the next source REQUEST"):return false
		phase = "request11"
	else:
		if not check(following.get("status") == "manual" and following.get("stage") == "candidate_boundary" and not following.has("step"), "stop after NOW11 before REQUEST10/Charm/keyword/Boss/reward"):return false
	recorded_transactions.append(event_id)
	trace.append({"transaction":"request%d" % event_id,"before":transaction_before,"earned":earned,"disk":disk.snapshot(),"disk_location":disk.snapshot().get("location",{}),"next":following.duplicate(true),"state":state()})
	transaction_open = false
	transaction_before = {}
	transaction_step_id = ""
	return true

func finish() -> void:
	write_trace()
	if backend != null:backend.free()
	print("quest_auto_munde_request9_11_route_test: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
