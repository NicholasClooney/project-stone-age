extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## UNRUN: real QuestAuto.start/tick/strict_advance from the canonical public save spawn
## to the original Saton REQUEST, through only original ordinary portals.
## no_random_encounters is a route-compatibility fixture, not natural-play evidence.
const Backend = preload("res://server/backend.gd")
const Runner = preload("res://tests/support/quest_auto_saton_request_candidate_runner.gd")
const Plan = preload("res://server/quest_auto_saton_plan.gd")
const Rules = preload("res://server/original_quests.gd")
const Session = preload("res://server/game_session.gd")
const Auto = preload("res://server/quest_auto.gd")
const Policy = preload("res://scripts/quest_auto_policy.gd")
const Registry = preload("res://server/quest_auto_registry.gd")
const Motion = preload("res://server/quest_auto_motion.gd")
const Passage = preload("res://scripts/passage_rules.gd")
const ArrivalPolicy = preload("res://server/quest_arrival_policy.gd")
const Wait = preload("res://tests/support/wait.gd")

const WAIT_SECONDS := 150.0
const MAX_LOGICAL_POINTS := 6000
const EXTERNAL_HARD_SECONDS := 300.0
const CLIENT := "saton-public-spawn-candidate"
const CONNECTION := 101013
const MANIFEST_SHA := "5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639"
const QUEST_CATALOG_SHA := "c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92"
const EVENT_SOURCE_SHA := "9a5eb18fa325f7dad0e9b25114e196c6c2b971cbff2c4662ec0c799a99eb09ac"
const CREATE_SOURCE_SHA := "c3c3d1962cb8f618860d47593117b959e6633673cd990ce33b56d68e85794aa8"
const MAP_1000_SHA := "d8a418bd5c77dfece89dc9cc13e395d2385f25417a76b6530dbc31c8f6051271"
const MAP_100_SHA := "8ff703bdb192c52298b7abe4f4700292776c864f149d4f8cea93ec7e2da461bd"
const MAP_1100_SHA := "8a1c854b9788b021128bb56d676a16f959308673002628a0662d0736ce255345"
const MAP_1112_SHA := "c7fe32a654fb8804ee66008ab9f4248217cff473e00ca78d4224f38e61d41fed"

## These are the complete five-field manifest rows that can form the native A
## route: public village 1000→outdoor 1000, outdoor 100→Kao 1100, then home 1112.
## The test observes which original A door is actually used; it does not select one.
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
	{"source":"100warp.create:313","from_map":100,"cell":[470,631],"to_map":1100,"target":[63,35]},
	{"source":"100warp.create:322","from_map":100,"cell":[471,631],"to_map":1100,"target":[64,35]},
	{"source":"100warp.create:331","from_map":100,"cell":[472,631],"to_map":1100,"target":[65,35]},
	{"source":"100warp.create:340","from_map":100,"cell":[473,631],"to_map":1100,"target":[66,35]},
	{"source":"100warp.create:349","from_map":100,"cell":[474,631],"to_map":1100,"target":[67,35]},
	{"source":"warp_y.create:664","from_map":1100,"cell":[82,112],"to_map":1112,"target":[10,15]},
	{"source":"warp_y.create:682","from_map":1100,"cell":[82,113],"to_map":1112,"target":[10,16]}
]

class DiagnosticBackend extends "res://server/backend.gd":
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
var wait_deadline_msec: int = 0
var logical_points: int = 0
var ordinary_walks: int = 0
var portals: int = 0
var portal_sequence: Array[String] = []
var transaction_open: bool = false
var transaction_before: Dictionary = {}
var transaction_save_serial: int = 0
var trace: Array[Dictionary] = []
var first_failure: Dictionary = {}
var trace_path: String = ""
var trace_io_error: String = ""

func _initialize() -> void:
	call_deferred("run")

func runner() -> Variant:
	return backend.quest_auto

func navigation():
	return runner().navigation

func check(ok: bool, label: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		failed = true
		if first_failure.is_empty():
			first_failure = {"label":label,"map":backend.automation.position_map if backend != null else -1,"cell":str(backend.automation.position_cell) if backend != null else "","phase":runner().phase if backend != null else ""}
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

func reviewed_portal(link: Dictionary, from_map: int, to_map: int) -> bool:
	if link.size() != 5:return false
	for expected in REVIEWED_PORTALS:
		if int(expected.from_map) == from_map and int(expected.to_map) == to_map and saved_equal(link, expected):return true
	return false

func source_hash(path: String, expected: String, label: String) -> bool:
	if not FileAccess.file_exists(path):return check(false, label + " source missing")
	var raw: String = FileAccess.get_file_as_string(path)
	return check(not raw.is_empty() and raw.sha256_text() == expected, label + " source SHA matches frozen input")

func binary_source_hash(path: String, expected: String, label: String) -> bool:
	if not FileAccess.file_exists(path):return check(false, label + " map missing")
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if not check(not raw.is_empty(), label + " map bytes are nonempty"):return false
	var context: HashingContext = HashingContext.new()
	var start_error: Error = context.start(HashingContext.HASH_SHA256)
	if not check(start_error == OK, label + " map SHA context starts"):return false
	var update_error: Error = context.update(raw)
	if not check(update_error == OK, label + " map SHA context accepts full raw bytes"):return false
	var digest: PackedByteArray = context.finish()
	if not check(digest.size() == 32, label + " map SHA digest is exactly 32 bytes"):return false
	return check(digest.hex_encode() == expected, label + " map SHA matches frozen packed source")

func run() -> void:
	started_msec = Clock.ticks_msec()
	var unique: String = str(Clock.ticks_usec())
	trace_path = "user://saton-public-spawn-request-" + unique + "-trace.json"
	if not check(not FileAccess.file_exists(trace_path), "diagnostic trace is not reused from a prior run"):finish();return
	if not source_hash("res://assets/legacy/world/manifest.json", MANIFEST_SHA, "world manifest"):finish();return
	if not source_hash("res://assets/legacy/quests/catalog.json", QUEST_CATALOG_SHA, "quest catalog"):finish();return
	if not binary_source_hash("res://assets/legacy/world/1000.map", MAP_1000_SHA, "map 1000"):finish();return
	if not binary_source_hash("res://assets/legacy/world/100.map", MAP_100_SHA, "map 100"):finish();return
	if not binary_source_hash("res://assets/legacy/world/1100.map", MAP_1100_SHA, "map 1100"):finish();return
	if not binary_source_hash("res://assets/legacy/world/1112.map", MAP_1112_SHA, "map 1112"):finish();return
	var sources: Dictionary = Plan.source_table()
	var source_records_value: Variant = sources.get("sources", {})
	if not check(source_records_value is Dictionary, "Saton source table keeps raw records under its sources object"):finish();return
	var source_records: Dictionary = source_records_value
	var event_source_value: Variant = source_records.get("sainasu/event/event13_1", {})
	if not check(event_source_value is Dictionary, "Saton event13_1 raw-source record exists at the nested key"):finish();return
	var event_source_record: Dictionary = event_source_value
	var create_source_value: Variant = source_records.get("sainasu/event/event13n.create", {})
	if not check(create_source_value is Dictionary, "Saton event13n.create raw-source record exists at the nested key"):finish();return
	var create_source_record: Dictionary = create_source_value
	if not check(not sources.is_empty() and event_source_record.get("sha256", "") == EVENT_SOURCE_SHA and create_source_record.get("sha256", "") == CREATE_SOURCE_SHA, "Saton complete raw-source lock remains exact"):finish();return
	if not prepare_backend(unique):finish();return
	if not check(backend.quest_catalog.jobs.any(func(job):return job.get("id") == 10 and job.get("event") == 13) and 13 in backend.quest_catalog.enabled_events, "real catalog retains job10/event13 and original event enablement"):finish();return
	if not check(not Policy.supports(10,13) and not Registry.supports(10), "production Policy and Registry remain closed for Saton job10"):finish();return
	var default_runner: Auto = Auto.new()
	if not check(not default_runner._supports_automatic_start(10,13) and default_runner._supports_automatic_start(2,44) == Policy.supports(2,44), "unmodified production admission remains Policy-equivalent"):finish();return
	if not check(runner()._supports_automatic_start(10,13) and not runner()._supports_automatic_start(10,14) and not runner()._supports_automatic_start(9,13), "test runner admission is limited to job10/event13"):finish();return
	if not check(runner().selected_mode(backend) == "A", "isolated native preference resolves to original mode A without rewriting route choices"):finish();return
	var original_arrival: bool = backend.quest_arrival.has_arrival(backend,1000,Vector2i(80,90))
	if not check(original_arrival and ArrivalPolicy.scope(1000).is_empty() and ArrivalPolicy.scope(100).is_empty() and ArrivalPolicy.scope(1100).is_empty() and ArrivalPolicy.scope(1112).is_empty(), "canonical public origin and source-only route maps have no protected-scope bridge"):finish();return
	if not start_candidate():finish();return
	var actual_step: Dictionary = runner().step.duplicate(true)
	var table: Dictionary = Plan.source_table()
	var locked_npc: Dictionary = {}
	for candidate_npc in table.get("npcs",[]):
		if candidate_npc.get("id","") == "sainasu/event/event13_1@1112:16:15":locked_npc = candidate_npc
	var locked_branch: Dictionary = locked_npc.get("branches",[])[2] if locked_npc.get("branches",[]).size() == 4 else {}
	if not check(actual_step.get("id","") == "saton:request" and actual_step.get("npc_id","") == "sainasu/event/event13_1@1112:16:15" and actual_step.source.type == "REQUEST" and actual_step.source.branch == 2 and actual_step.source.source_line == 28 and actual_step.source.source_sha == EVENT_SOURCE_SHA and actual_step.source.actions == {"GetItem":"2431*1"} and actual_step.auto_choices == ["yes","ok"] and not locked_branch.is_empty() and Plan.same_source(actual_step.source.branch_data,locked_branch), "real start's branch_for priority resolved exact full original branch2 REQUEST, never earlier ACCEPT/MESSAGE"):finish();return
	if not check(Auto.new().safe_step(actual_step,10,false), "existing strict ordinary REQUEST allowlist accepts this exact source action"):finish();return
	wait_deadline_msec = Clock.ticks_msec() + int(WAIT_SECONDS * 1000.0)
	var reached: bool = await Wait.until(self, drive_until_stop, WAIT_SECONDS)
	if failed:finish();return
	if not check(reached and done and runner().phase == "manual" and not runner().running, "actual QuestAuto lifecycle stops at the post-REQUEST manual boundary within one global Wait 150"):finish();return
	if not check(runner().step.get("id", "") == "saton:request" and portal_sequence.size() == 3, "one exact REQUEST and exactly three original map transitions were observed"):finish();return
	if not check(portal_sequence[0] in ["100warp.create:43","100warp.create:52","100warp.create:61","100warp.create:70","100warp.create:124","100warp.create:133","100warp.create:142","100warp.create:151","100warp.create:160"] and portal_sequence[1] in ["100warp.create:313","100warp.create:322","100warp.create:331","100warp.create:340","100warp.create:349"] and portal_sequence[2] in ["warp_y.create:664","warp_y.create:682"], "all three committed doors are the actual A-selected source-locked original chain"):finish();return
	if not check(logical_points <= MAX_LOGICAL_POINTS and ordinary_walks > 0 and backend.candidate_field_calls == ordinary_walks, "logical movement stays within 6000 points and every ordinary step has one original field_step"):finish();return
	if not check(not backend.battle_open and backend.original_quests.pending.is_empty() and backend.session._pending.is_empty() and not runner().owns_battle, "no battle or pending dialogue is left open at the manual stop"):finish();return
	if not check(backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty(), "no protected authority, arrival mark or stage was injected"):finish();return
	var observed = navigation()
	print("SATON PUBLIC REQUEST candidate: points=%d walks=%d portals=%d fields=%d route=%s next=%d plans=%d local_path=%d rebuilds=%d cells=%d elapsed_ms=%d stop=NOW13_manual" % [logical_points,ordinary_walks,portals,backend.candidate_field_calls,str(portal_sequence),observed.next_calls,observed.plan_calls,observed.local_path_calls,observed.grid_rebuilds,observed.grid_rebuild_cells,Clock.ticks_msec()-started_msec])
	finish()

func prepare_backend(unique: String) -> bool:
	backend = DiagnosticBackend.new()
	backend.set_process(false)
	backend.quest_auto = Runner.new()
	backend.save_path = "user://saton-public-request-" + unique + ".json"
	for suffix in ["", ".bak", ".tmp", ".resume.json"]:
		var path: String = backend.save_path + suffix
		if not check(not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)), "isolated save and sidecar path is unused: " + suffix):return false
	var location_value: Variant = backend.session._profile.get("location", {})
	if not check(location_value is Dictionary and saved_equal(location_value,{"map_id":1000,"x":80,"y":90}), "native canonical public saved start is 1000(80,90), distinct from manifest placement spawn"):return false
	if not check(backend.automation.position_map == -1, "Backend begins without a live position or fabricated arrival"):return false
	var profile: Dictionary = backend.session._profile
	profile.player.level = 16
	if not check(not Rules.flag(profile,"now",13) and not Rules.flag(profile,"ended",13) and not Rules.flag(profile,"ended",14) and not 2431 in profile.original_items and not 2450 in profile.original_items, "only disclosed LV16 eligibility; no quest flags, footprint or reward injected"):return false
	var hello: Dictionary = backend.handle({"type":"report_position","map_id":1000,"cell":[80,90],"client":CLIENT})
	if not check(hello.get("ok",false) and backend.automation.position_map == 1000 and backend.automation.position_cell == Vector2i(80,90), "normal initial client report establishes the canonical public saved start"):return false
	if not check(backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty(), "public handshake creates no protected proof"):return false
	if not check(backend.handle({"type":"no_random_encounters","enabled":true}).get("ok",false), "no_random_encounters is enabled only as the declared route-verification fixture"):return false
	if not check(backend.save(), "isolated baseline is saved normally before runner start"):return false
	return true

func start_candidate() -> bool:
	var default_closed: bool = not Policy.supports(10,13) and not Registry.supports(10)
	if not check(default_closed and 13 in backend.quest_catalog.enabled_events, "test starts against the real enabled catalog while product opening stays false"):return false
	var reply: Dictionary = backend.handle({"type":"quest_auto_start","quest_id":10,"client":CLIENT,"_quest_connection":CONNECTION})
	if not check(reply.get("ok",false) and runner().running and runner().strict_walk and runner().phase == "travel", "production QuestAuto.start admits only through the test subclass seam and keeps strict_walk"):return false
	if not check(runner().step.get("id", "") == "saton:request" and runner().step.source.actions == {"GetItem":"2431*1"}, "actual runner start captures the source-locked REQUEST proposal"):return false
	return true

func ack_for(receipt: Dictionary) -> Dictionary:
	var cell: Array = Motion.cell(receipt.get("cell",[]))
	var result: Dictionary = {"type":"report_position","map_id":receipt.get("map_id",-1),"cell":cell,"quest_position_seq":receipt.get("quest_position_seq",-1),"client":CLIENT,"_quest_connection":CONNECTION}
	for field in Motion.IDENTITY_FIELDS:
		if receipt.has(field):result[field] = receipt[field]
	return result

func drive_until_stop() -> bool:
	if failed or done:return true	
	if float(Clock.ticks_msec() - started_msec) / 1000.0 >= EXTERNAL_HARD_SECONDS:
		check(false, "300 second fallback check; an external monitor must terminate a blocked synchronous AStar call")
		return true
	if Clock.ticks_msec() >= wait_deadline_msec:
		check(false, "single global Wait 150 deadline reached; no next runner/AStar call")
		return true
	if not runner().running and runner().phase != "manual":
		check(false, "QuestAuto stopped before the source-derived manual boundary")
		return true
	if runner().phase == "landing":
		var issued: Array = runner().issued
		if not check(not issued.is_empty(), "portal landing has one server-issued receipt"):return true
		var value: Variant = issued[-1]
		if not check(value is Dictionary, "issued portal receipt preserves its native Dictionary shape"):return true
		var receipt: Dictionary = value.duplicate(true)
		var before_phase: String = runner().phase
		var ack: Dictionary = backend.handle(ack_for(receipt))
		if not check(ack.get("ok",false) and runner().phase == "travel" and before_phase == "landing", "real report_position ACK completes each ordinary original portal step"):return true
		trace.append({"kind":"portal_ack","receipt":receipt,"map":backend.automation.position_map,"cell":str(backend.automation.position_cell)})
		return false
	if logical_points >= MAX_LOGICAL_POINTS and runner().phase == "travel":
		var capped_npc: Dictionary = backend.original_quests.npc_by_id(str(runner().step.get("npc_id", "")))
		var cap_delta: Vector2i = backend.automation.position_cell - Vector2i(int(capped_npc.get("cell", [999999,999999])[0]),int(capped_npc.get("cell", [999999,999999])[1]))
		if int(capped_npc.get("map_id", -1)) != backend.automation.position_map or maxi(absi(cap_delta.x),absi(cap_delta.y)) > 2:
			check(false, "6000 global logical point cap prevents another runner travel tick")
			return true
	var before_map: int = backend.automation.position_map
	var before_cell: Vector2i = backend.automation.position_cell
	var before_phase: String = runner().phase
	var before_pending: Dictionary = backend.original_quests.pending.duplicate(true)
	var before_profile: Dictionary = backend.session.snapshot()
	var before_save: int = backend.quest_save_serial
	var fields_before: int = backend.candidate_field_calls
	runner().tick(backend,0.21)
	var after_map: int = backend.automation.position_map
	var after_cell: Vector2i = backend.automation.position_cell
	if before_map != after_map or before_cell != after_cell:
		logical_points += 1
		var point: Dictionary = navigation().last_point.duplicate(true)
		if after_map != before_map:
			var live: Dictionary = backend.quest_helper.places.links(before_map).get(before_cell,{})
			var point_link: Dictionary = point.get("portal",{})
			var exact_point_link: bool = saved_equal(point_link,live)
			var exact_reviewed_link: bool = reviewed_portal(live,before_map,after_map)
			var point_target_map: bool = Motion.same_integer(point.get("map_id"),after_map)
			var point_target_cell: bool = Motion.cell(point.get("cell",[])) == [after_cell.x,after_cell.y]
			var active_link: bool = not bool(live.get("disabled",false)) and not live.has("gate_source")
			var unpaid: bool = not bool(live.get("requires_travel_pass",false)) and not Passage.requires_permit(before_map,after_map)
			var public_scopes: bool = ArrivalPolicy.scope(before_map).is_empty() and ArrivalPolicy.scope(after_map).is_empty()
			var arrival: bool = backend.quest_arrival.has_arrival(backend,after_map,after_cell)
			if not check(exact_point_link and exact_reviewed_link and point_target_map and point_target_cell and active_link and unpaid and public_scopes and arrival, "real A-selected portal matches full original identity, has no disabled/gate/payment rule, and native arrival succeeds"):return true
			portal_sequence.append(str(live.get("source","")))
			portals += 1
			trace.append({"kind":"portal_commit","origin":[before_map,before_cell.x,before_cell.y],"destination":[after_map,after_cell.x,after_cell.y],"live_link":live.duplicate(true),"point":point.duplicate(true),"checks":{"exact_point_link":exact_point_link,"exact_reviewed_link":exact_reviewed_link,"point_target_map":point_target_map,"point_target_cell":point_target_cell,"active_link":active_link,"unpaid":unpaid,"public_scopes":public_scopes,"arrival":arrival}})
		else:
			var delta: Vector2i = after_cell - before_cell
			if not check(absi(delta.x)+absi(delta.y)==1 and not point.has("portal") and not point.has("gate"), "ordinary runner movement is one cardinal cell"):return true
			ordinary_walks += 1
			if not check(backend.candidate_field_calls == fields_before + 1, "one original field_step follows each ordinary committed cell"):return true
			if not check(logical_points <= MAX_LOGICAL_POINTS, "global logical movement cap is not exceeded"):return true
			trace.append({"kind":"walk","from":[before_map,before_cell.x,before_cell.y],"to":[after_map,after_cell.x,after_cell.y],"field_calls":backend.candidate_field_calls})
	if before_phase == "travel" and before_pending.is_empty() and runner().phase == "strict_dialogue" and not backend.original_quests.pending.is_empty():
		var talk_npc: Dictionary = backend.original_quests.npc_by_id(str(runner().step.get("npc_id", "")))
		var talk_offset: Vector2i = backend.automation.position_cell - Vector2i(int(talk_npc.get("cell", [999999,999999])[0]),int(talk_npc.get("cell", [999999,999999])[1]))
		if not check(int(talk_npc.get("map_id", -1)) == 1112 and maxi(absi(talk_offset.x),absi(talk_offset.y)) <= 2 and runner().step.source.branch_data.source_branch_index == 2, "runner opens the locked request only inside original Saton talk range"):return true
		if not check(not transaction_open, "only the first REQUEST transaction opens in this candidate"):return true
		transaction_open = true
		transaction_before = before_profile
		transaction_save_serial = before_save
	if transaction_open and backend.original_quests.pending.is_empty() and runner().phase == "travel" and backend.quest_save_serial > transaction_save_serial:
		if not record_request_transaction():return true
	if not runner().running and runner().phase == "manual":
		var post: Dictionary = Plan.select(backend,10)
		done = transaction_open == false and post.get("status") == "manual" and post.get("stage") == "wait_boss" and not post.has("step")
		var reached_npc: Dictionary = backend.original_quests.npc_by_id("sainasu/event/event13_1@1112:16:15")
		if not check(not reached_npc.is_empty(), "the frozen Saton NPC remains available at the final authority"):return true
		var final_delta: Vector2i = backend.automation.position_cell - Vector2i(int(reached_npc.cell[0]),int(reached_npc.cell[1]))
		if not check(done and Rules.flag(backend.session._profile,"now",13) and backend.automation.position_map == 1112 and maxi(absi(final_delta.x),absi(final_delta.y)) <= 2, "native REQUEST completes at the naturally reached Saton talk range and selector stops at manual wait_boss"):return true
		trace.append({"kind":"manual_stop","proposal":post.duplicate(true),"profile":backend.session.snapshot()})
	return failed or done

func record_request_transaction() -> bool:
	var earned: Dictionary = backend.session.snapshot()
	var expected: Dictionary = transaction_before.duplicate(true)
	var next_uid_value: Variant = transaction_before.get("next_original_uid", -1)
	if not check(next_uid_value is int and next_uid_value > 0, "frozen pre-REQUEST next_original_uid is a positive native integer"):return false
	var received_uid: int = next_uid_value
	var expected_instance: Dictionary = {"uid":received_uid,"item_id":2431,"durability":0}
	if not check(not 2431 in transaction_before.original_items and not transaction_before.original_instances.any(func(instance):return instance.get("item_id",-1) == 2431) and not transaction_before.original_instances.any(func(instance):return instance.get("uid",-1) == received_uid), "frozen pre-REQUEST inventory has no footprint or reused instance UID"):return false
	Rules.set_flag(expected,"now",13,true)
	expected.original_items.append(2431)
	expected.original_instances.append(expected_instance.duplicate(true))
	expected.next_original_uid = received_uid + 1
	var matching_instances: Array = []
	var received_uid_count: int = 0
	for instance_value in earned.original_instances:
		if not instance_value is Dictionary:continue
		if instance_value.get("item_id",-1) == 2431:matching_instances.append(instance_value)
		if instance_value.get("uid",-1) == received_uid:received_uid_count += 1
	if not check(matching_instances.size() == 1 and received_uid_count == 1, "REQUEST adds exactly one footprint instance with the frozen unused UID"):return false
	var actual_instance: Dictionary = matching_instances[0]
	if not check(saved_equal(actual_instance,expected_instance), "2431 instance preserves item_id, frozen UID, and original zero durability"):return false
	if not check(earned.next_original_uid is int and earned.next_original_uid == received_uid + 1, "original instance allocation advances next_original_uid exactly once"):return false
	var items_without_received: Array = earned.original_items.duplicate()
	var received_item_index: int = items_without_received.find(2431)
	if not check(earned.original_items.count(2431) == 1 and received_item_index >= 0, "REQUEST yields exactly one original item 2431"):return false
	items_without_received.remove_at(received_item_index)
	var instances_without_received: Array = earned.original_instances.duplicate(true)
	var received_instance_index: int = -1
	for index in range(instances_without_received.size()):
		var instance_value: Variant = instances_without_received[index]
		if instance_value is Dictionary and instance_value.get("uid",-1) == received_uid:
			received_instance_index = index
			break
	if not check(received_instance_index >= 0, "the sole new original instance is present for full before/after comparison"):return false
	instances_without_received.remove_at(received_instance_index)
	if not check(saved_equal(items_without_received,transaction_before.original_items) and saved_equal(instances_without_received,transaction_before.original_instances) and saved_equal(earned.original_equipment,transaction_before.original_equipment) and saved_equal(earned.equipment,transaction_before.equipment), "all other original items/instances and both equipment views remain unchanged"):return false
	if not check(saved_equal(earned,expected), "full native profile diff is exactly NOW13 plus original footprint item, instance, and next UID"):return false
	if not check(not Rules.flag(earned,"ended",13) and not Rules.flag(earned,"ended",14) and not 2450 in earned.original_items and not 2428 in earned.original_items and not 2429 in earned.original_items and not 2430 in earned.original_items, "REQUEST does not complete either END or grant treasures/medicine"):return false
	var disk = Session.new()
	if not check(disk.load_game(backend.save_path) and saved_equal(disk.snapshot(),earned), "normal original transaction save reads back the complete profile without moving the endpoint"):return false
	if not check(backend.automation.position_map == 1112, "transaction leaves live authority in the naturally reached NPC map; saved location is not rewritten to the endpoint"):return false
	var following: Dictionary = Plan.select(backend,10)
	if not check(following.get("status") == "manual" and following.get("stage") == "wait_boss" and not following.has("step"), "saved NOW13 immediately yields the intended manual boss boundary"):return false
	trace.append({"kind":"request13_transaction","before":transaction_before.duplicate(true),"earned":earned.duplicate(true),"disk":disk.snapshot(),"disk_location":disk.snapshot().get("location"),"next":following.duplicate(true),"save_serial_before":transaction_save_serial,"save_serial_after":backend.quest_save_serial})
	transaction_open = false
	transaction_before = {}
	return true

func finish() -> void:
	write_trace()
	if not trace_io_error.is_empty():
		failures += 1
		failed = true
		push_error(trace_io_error)
	if backend != null:backend.free()
	print("quest_auto_saton_public_spawn_request_route_candidate_test: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)

func write_trace() -> void:
	var nav_trace: Dictionary = {}
	if backend != null:
		var observed = navigation()
		nav_trace = {"next_calls":observed.next_calls,"plan_calls":observed.plan_calls,"local_path_calls":observed.local_path_calls,"grid_rebuilds":observed.grid_rebuilds,"grid_rebuild_cells":observed.grid_rebuild_cells}
	var out: FileAccess = FileAccess.open(trace_path,FileAccess.WRITE)
	if out == null:
		trace_io_error = "cannot create isolated candidate trace: " + trace_path
		return
	var serialized: String = JSON.stringify({"trace":trace,"first_failure":first_failure,"points":logical_points,"walks":ordinary_walks,"portals":portal_sequence,"field_calls":backend.candidate_field_calls if backend != null else 0,"navigation":nav_trace,"elapsed_ms":Clock.ticks_msec()-started_msec},"  ")
	out.store_string(serialized)
	out.flush()
	var write_error: Error = out.get_error()
	out.close()
	if write_error != OK:
		trace_io_error = "candidate trace write failed: " + str(write_error)
		return
	var verify: FileAccess = FileAccess.open(trace_path,FileAccess.READ)
	if verify == null:
		trace_io_error = "candidate trace readback failed: " + trace_path
		return
	var written_length: int = verify.get_length()
	verify.close()
	if written_length != serialized.to_utf8_buffer().size():trace_io_error = "candidate trace byte-length mismatch"
