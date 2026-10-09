extends SceneTree
## UNRUN: real QuestAuto.start/tick/strict_advance from the canonical public save spawn
## to the original Munde REQUEST, through only original ordinary portals.
## no_random_encounters is a route-compatibility fixture, not natural-play evidence.
const Backend = preload("res://server/backend.gd")
const Runner = preload("res://tests/support/munde_request_observed_runner.gd")
const Diff = preload("res://tests/support/munde_request_compare.gd")
const Plan = preload("res://server/quest_auto_munde_plan.gd")
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
const CLIENT := "munde-public-spawn-candidate"
const CONNECTION := 80909
const MANIFEST_SHA := "5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639"
const QUEST_CATALOG_SHA := "c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92"
const EVENT_SOURCE_SHA := "7d201e34ea3b230dc9deac43556e6cc50c43647fae01d1a35a6df4cc114618e7"
const MAP_1000_SHA := "d8a418bd5c77dfece89dc9cc13e395d2385f25417a76b6530dbc31c8f6051271"
const MAP_100_SHA := "8ff703bdb192c52298b7abe4f4700292776c864f149d4f8cea93ec7e2da461bd"

const MAP_10101_SHA := "1a4b746318a4d7525ee3aded351316b9f54b5b62a97be4ea4bd73c491f5f5c16"

const MAP_10102_SHA := "0dd06f24af5f1a5c8bebb779b0b106cb1f212fb8c83054c0250104aaf3daaf49"

const MAP_10103_SHA := "f78c82345a2b1621e777082016998c67a33fa3a4b63b93ea13ec78c35acb5cba"

const MAP_1200_SHA := "c2a650d49a92a4de91ba35c3bb763ff3e2e52c4ab8f79981402a63a703004d32"

## These are the complete five-field manifest rows that can form the native A
## route: public village 1000→100→10101→10102→10103→1200 (first REQUEST only).
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
]

class DiagnosticBackend extends "res://server/backend.gd":
	func _munde_request_enabled()->bool:return true
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
var transaction_disks:Array=[]
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

func saved_equal(a:Variant,b:Variant)->bool:
	return Diff.first(a,b).is_empty()
func reviewed_portal(link:Dictionary,from_map:int,to_map:int)->bool:
	if link.size()!=5:return false
	for key in link:
		if not key is String:return false
	for expected in REVIEWED_PORTALS:
		# Only manifest map/cell/target numeric fields are JSON-origin integers.
		if link.get("source")!=expected.source or not link.get("source") is String:continue
		if not Motion.same_integer(link.get("from_map"),from_map) or not Motion.same_integer(link.get("to_map"),to_map):continue
		if not Motion.same_integer(expected.from_map,from_map) or not Motion.same_integer(expected.to_map,to_map):continue
		if not link.get("cell") is Array or not link.get("target") is Array or link.cell.size()!=2 or link.target.size()!=2:continue
		if Motion.cell(link.cell)==expected.cell and Motion.cell(link.target)==expected.target:return true
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
	started_msec = Time.get_ticks_msec()
	var unique: String = str(Time.get_ticks_usec())
	trace_path = "user://munde-public-spawn-request-" + unique + "-trace.json"
	if not check(not FileAccess.file_exists(trace_path), "diagnostic trace is not reused from a prior run"):finish();return
	if not source_hash("res://assets/legacy/world/manifest.json", MANIFEST_SHA, "world manifest"):finish();return
	if not source_hash("res://assets/legacy/quests/catalog.json", QUEST_CATALOG_SHA, "quest catalog"):finish();return
	if not binary_source_hash("res://assets/legacy/world/1000.map", MAP_1000_SHA, "map 1000"):finish();return
	if not binary_source_hash("res://assets/legacy/world/100.map", MAP_100_SHA, "map 100"):finish();return
	if not binary_source_hash("res://assets/legacy/world/10101.map", MAP_10101_SHA, "map 10101"):finish();return
	if not binary_source_hash("res://assets/legacy/world/10102.map", MAP_10102_SHA, "map 10102"):finish();return
	if not binary_source_hash("res://assets/legacy/world/10103.map", MAP_10103_SHA, "map 10103"):finish();return
	if not binary_source_hash("res://assets/legacy/world/1200.map", MAP_1200_SHA, "map 1200"):finish();return
	var sources:Dictionary=Plan.source_table()
	if not check(not sources.is_empty() and sources.sources["npc/sainasu/event/event09"].sha256==EVENT_SOURCE_SHA,"complete original first REQUEST raw source lock"):finish();return
	if not prepare_backend(unique):finish();return
	if not check(backend.quest_catalog.jobs.any(func(job):return job.get("id") == 8 and job.get("event") == 9) and 9 in backend.quest_catalog.enabled_events, "real catalog retains job8/event9 and original event enablement"):finish();return
	if not check(not Policy.supports(8,9) and not Registry.supports(8), "production Policy and Registry remain closed for Munde job8"):finish();return
	var default_runner: Auto = Auto.new()
	if not check(not default_runner._supports_automatic_start(8,9) and default_runner._supports_automatic_start(2,44) == Policy.supports(2,44), "unmodified production admission remains Policy-equivalent"):finish();return
	if not check(runner()._supports_automatic_start(8,9)==Policy.supports(8,9) and not runner()._supports_automatic_start(8,9) and not runner()._supports_automatic_start(8,10) and not runner()._supports_automatic_start(7,9),"real helper remains Policy-equivalent and closed for job8 and wrong job/event"):finish();return
	if not prepare_oracle():finish();return
	if not check(runner().selected_mode(backend) == "A", "isolated native preference resolves to original mode A without rewriting route choices"):finish();return
	var original_arrival: bool = backend.quest_arrival.has_arrival(backend,1000,Vector2i(80,90))
	if not check(original_arrival and ArrivalPolicy.scope(1000).is_empty() and ArrivalPolicy.scope(100).is_empty() and ArrivalPolicy.scope(10101).is_empty() and ArrivalPolicy.scope(10102).is_empty() and ArrivalPolicy.scope(10103).is_empty() and ArrivalPolicy.scope(1200).is_empty(), "canonical public origin and source-only route maps have no protected-scope bridge"):finish();return
	if not start_candidate():finish();return
	var actual_step: Dictionary = runner().step.duplicate(true)
	var table: Dictionary = Plan.source_table()
	var locked_branch:Dictionary=table.npc.branches[1]
	if not check(actual_step.id=="munde:request:9" and actual_step.source.type=="REQUEST" and actual_step.source.branch_index==1 and actual_step.source.source_line==14 and actual_step.source.source_sha==EVENT_SOURCE_SHA and actual_step.source.actions.is_empty() and Diff.first(actual_step.source.branch_data,locked_branch).is_empty(),"real first source selected; no 11/10 or reward branch"):finish();return
	if not check(Auto.new().safe_step(actual_step,10,false), "existing strict ordinary REQUEST allowlist accepts this exact source action"):finish();return
	wait_deadline_msec = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	var reached: bool = await Wait.until(self, drive_until_stop, WAIT_SECONDS)
	if failed:finish();return
	if not check(reached and done and runner().phase == "manual" and not runner().running, "actual QuestAuto lifecycle stops at the post-REQUEST manual boundary within one global Wait 150"):finish();return
	if not check(runner().step.get("id", "") == "munde:request:9" and portal_sequence.size() == 5, "one exact REQUEST and exactly five original map transitions were observed"):finish();return
	if not check(portal_sequence[0].begins_with("100warp.create:") and portal_sequence.slice(1)==["dungeon00.create:142","dungeon00.create:160","dungeon00.create:178","dungeon00.create:196"],"five actually observed source-locked original map transitions"):finish();return
	if not check(logical_points <= MAX_LOGICAL_POINTS and ordinary_walks > 0 and backend.candidate_field_calls == ordinary_walks, "logical movement stays within 6000 points and every ordinary step has one original field_step"):finish();return
	if not check(not backend.battle_open and backend.original_quests.pending.is_empty() and backend.session._pending.is_empty() and not runner().owns_battle, "no battle or pending dialogue is left open at the manual stop"):finish();return
	if not check(backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty(), "no protected authority, arrival mark or stage was injected"):finish();return
	var observed = navigation()
	print("MUNDE PUBLIC REQUEST candidate: points=%d walks=%d portals=%d fields=%d route=%s next=%d plans=%d local_path=%d rebuilds=%d cells=%d elapsed_ms=%d stop=NOW9_manual" % [logical_points,ordinary_walks,portals,backend.candidate_field_calls,str(portal_sequence),observed.next_calls,observed.plan_calls,observed.local_path_calls,observed.grid_rebuilds,observed.grid_rebuild_cells,Time.get_ticks_msec()-started_msec])
	finish()

func prepare_backend(unique: String) -> bool:
	backend = DiagnosticBackend.new()
	backend.set_process(false)
	backend.quest_auto = Runner.new()
	backend.fee_attach(CONNECTION)
	backend.save_path = "user://munde-public-request-" + unique + ".json"
	for suffix in ["", ".bak", ".tmp", ".resume.json"]:
		var path: String = backend.save_path + suffix
		if not check(not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)), "isolated save and sidecar path is unused: " + suffix):return false
	var location_value: Variant = backend.session._profile.get("location", {})
	if not check(location_value is Dictionary and saved_equal(location_value,{"map_id":1000,"x":80,"y":90}), "native canonical public saved start is 1000(80,90), distinct from manifest placement spawn"):return false
	if not check(backend.automation.position_map == -1, "Backend begins without a live position or fabricated arrival"):return false
	var profile: Dictionary = backend.session._profile
	profile.player.level = 30
	Rules.set_flag(profile,"ended",4,true)
	if not check(Rules.flag(profile,"ended",4) and not Rules.flag(profile,"now",9) and not Rules.flag(profile,"now",10) and not Rules.flag(profile,"now",11),"explicit LV30/END4 eligibility only; no Munde progress injected"):return false
	var hello: Dictionary = backend.handle({"type":"report_position","map_id":1000,"cell":[80,90],"client":CLIENT})
	if not check(hello.get("ok",false) and backend.automation.position_map == 1000 and backend.automation.position_cell == Vector2i(80,90), "normal initial client report establishes the canonical public saved start"):return false
	if not check(backend.quest_arrival._scope.is_empty() and backend.quest_arrival._marks.is_empty() and backend.quest_arrival._stages.is_empty(), "public handshake creates no protected proof"):return false
	if not check(backend.handle({"type":"no_random_encounters","enabled":true}).get("ok",false), "no_random_encounters is enabled only as the declared route-verification fixture"):return false
	if not check(backend.save(), "isolated baseline is saved normally before runner start"):return false
	return true

func admission_state()->Dictionary:
	var arrival:Dictionary={}
	for row in backend.quest_arrival.get_property_list():
		if (int(row.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE)!=0:
			var value:Variant=backend.quest_arrival.get(row.name)
			arrival[row.name]=value.duplicate(true) if value is Dictionary or value is Array else value
	return {"profile":backend.session._profile.duplicate(true),"disks":disk_rows(),"cache":backend.last_saved_payload,"serial":backend.quest_save_serial,"pending":backend.session._pending.duplicate(true),"dialogue":backend.original_quests.pending.duplicate(true),"arrival":arrival,"runner":{"checkpoint":runner().identity.checkpoint(),"running":runner().running,"internal":runner().internal,"phase":runner().phase,"step":runner().step.duplicate(true),"connection":runner().connection},"munde_scope":runner()._munde_scope.duplicate(true),"doctor_scope":runner()._doctor_scope.duplicate(true),"saton_scope":runner()._saton_scope.duplicate(true),"munde_call":backend._munde_request_call.duplicate(true),"doctor_call":backend._doctor_request_call.duplicate(true),"saton_call":backend._saton_request_call.duplicate(true)}
func prepare_oracle()->bool:
	# Lock-source data only, never the selector or prepare method's result.
	var table:Dictionary=Plan.source_table()
	if not check(not table.is_empty(),"independent locked source exists"):return false
	var branch:Dictionary=table.npc.branches[1].duplicate(true)
	var first:Dictionary={"id":"munde:request:9","npc_id":"sainasu/event/event09@1200:97:75","map_id":1200,"cell":[97,75],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":"sainasu/event/event09@1200:97:75","type":"REQUEST","condition":"LV>29&ENDEV=4","actions":{},"branch_index":1,"branch_data":branch,"source_line":14,"source_sha":EVENT_SOURCE_SHA,"audit_policy":"munde_request9_v1"}}
	var expected:Dictionary={"ok":true,"source":false,"quest_id":8,"client":CLIENT,"connection":CONNECTION,"clean":false,"first":first}
	var before:Dictionary=admission_state()
	var session_ref=backend.session
	var runner_ref=backend.quest_auto
	var profile_ref:Dictionary=backend.session._profile
	var binding_ref=backend._fee_bindings.get(CONNECTION)
	var scope_ref:Dictionary=runner()._munde_scope
	var call_ref:Dictionary=backend._munde_request_call
	var actual:Dictionary=runner().prepare_start(backend,{"type":"quest_auto_start","quest_id":8,"client":CLIENT,"_quest_connection":CONNECTION})
	var difference:Dictionary=Diff.first(actual,expected)
	if not difference.is_empty():Diff.print_first(difference)
	if not check(difference.is_empty(),"real gated prepare matches complete independently constructed proposal"):return false
	return check(admission_state()==before and is_same(backend.session,session_ref) and is_same(backend.quest_auto,runner_ref) and is_same(backend.session._profile,profile_ref) and is_same(backend._fee_bindings.get(CONNECTION),binding_ref) and is_same(runner()._munde_scope,scope_ref) and is_same(backend._munde_request_call,call_ref),"prepare preserves complete profile/disks/cache/serial/pending/arrival/scope and identity refs; no run or item minted")

func start_candidate() -> bool:
	var default_closed: bool = not Policy.supports(8,9) and not Registry.supports(8)
	if not check(default_closed and 9 in backend.quest_catalog.enabled_events, "test starts against the real enabled catalog while product opening stays false"):return false
	var before:Dictionary=admission_state()
	var binding_ref=backend._fee_bindings.get(CONNECTION)
	var reply: Dictionary = backend.handle({"type":"quest_auto_start","quest_id":8,"client":CLIENT,"_quest_connection":CONNECTION})
	if not check(reply.get("ok",false) and runner().running and runner().strict_walk and runner().phase == "travel", "production gated QuestAuto.start installs the real explicit-Start run and keeps strict_walk"):return false
	if not check(runner().step.get("id", "") == "munde:request:9" and runner().step.source.actions.is_empty(), "actual runner start captures the source-locked REQUEST proposal"):return false
	if not check(backend.session._profile==before.profile and disk_rows()==before.disks and backend.last_saved_payload==before.cache and backend.quest_save_serial==before.serial and runner().connection==CONNECTION and is_same(backend._fee_bindings.get(CONNECTION),binding_ref) and not runner()._munde_scope.is_empty() and runner()._doctor_scope.is_empty() and runner()._saton_scope.is_empty() and backend._saton_request_call.is_empty() and backend._munde_request_call.is_empty() and backend._doctor_request_call.is_empty() and backend._required_fee_runner_authority==null,"real Start changes only runner intent, not profile/UID/money/disks/cache/serial or Doctor/D authority"):return false
	return true

func ack_for(receipt: Dictionary) -> Dictionary:
	var cell: Array = Motion.cell(receipt.get("cell",[]))
	var result: Dictionary = {"type":"report_position","map_id":receipt.get("map_id",-1),"cell":cell,"quest_position_seq":receipt.get("quest_position_seq",-1),"client":CLIENT,"_quest_connection":CONNECTION}
	for field in Motion.IDENTITY_FIELDS:
		if receipt.has(field):result[field] = receipt[field]
	return result

func drive_until_stop() -> bool:
	if failed or done:return true
	if float(Time.get_ticks_msec() - started_msec) / 1000.0 >= EXTERNAL_HARD_SECONDS:
		check(false, "300 second fallback check; an external monitor must terminate a blocked synchronous AStar call")
		return true
	if Time.get_ticks_msec() >= wait_deadline_msec:
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
		if not check(int(talk_npc.get("map_id", -1)) == 1200 and maxi(absi(talk_offset.x),absi(talk_offset.y)) <= 2 and runner().step.source.branch_data.source_branch_index == 1, "runner opens the locked request only inside original Munde talk range"):return true
		if not check(not transaction_open, "only the first REQUEST transaction opens in this candidate"):return true
		transaction_open = true
		transaction_before = before_profile
		transaction_save_serial = before_save
		transaction_disks=disk_rows()
	if transaction_open and backend.original_quests.pending.is_empty() and runner().phase == "travel" and backend.quest_save_serial > transaction_save_serial:
		if not record_request_transaction():return true
	if not runner().running and runner().phase == "manual":
		var post: Dictionary = Registry.munde_request(backend,8)
		done = transaction_open == false and post.get("status") == "manual" and post.get("stage") == "request9_complete" and not post.has("step")
		var reached_npc: Dictionary = backend.original_quests.npc_by_id("sainasu/event/event09@1200:97:75")
		if not check(not reached_npc.is_empty(), "the frozen Munde NPC remains available at the final authority"):return true
		var final_delta: Vector2i = backend.automation.position_cell - Vector2i(int(reached_npc.cell[0]),int(reached_npc.cell[1]))
		if not check(done and Rules.flag(backend.session._profile,"now",9) and backend.automation.position_map == 1200 and maxi(absi(final_delta.x),absi(final_delta.y)) <= 2, "native REQUEST completes at the naturally reached Munde talk range and selector stops at manual first-request boundary"):return true
		trace.append({"kind":"manual_stop","proposal":post.duplicate(true),"profile":backend.session.snapshot()})
	return failed or done

func disk_rows()->Array:
	var rows:Array=[]
	for suffix in ["", ".bak", ".tmp"]:
		var path:String=backend.save_path+suffix
		var present:bool=FileAccess.file_exists(path)
		rows.append({"exists":present,"bytes":FileAccess.get_file_as_bytes(path) if present else PackedByteArray()})
	return rows
func record_request_transaction()->bool:
	var earned:Dictionary=backend.session.snapshot()
	var expected:Dictionary=transaction_before.duplicate(true)
	expected.original_events.now[0]=int(expected.original_events.now[0]) | (1 << 9)
	var difference:Dictionary=Diff.first(earned,expected,"profile")
	if not difference.is_empty():Diff.print_first(difference)
	if not check(difference.is_empty(),"whole native profile differs only by NOW9: all money/items/pet UIDs/next UID retained"):return false
	if not check(not Rules.flag(earned,"now",10) and not Rules.flag(earned,"now",11) and not Rules.flag(earned,"ended",9),"no follow-up or reward flags"):return false
	var expected_disks:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},transaction_disks[0],{"exists":false,"bytes":PackedByteArray()}]
	if not check(disk_rows()==expected_disks and backend.last_saved_payload==JSON.stringify(expected) and backend.quest_save_serial==transaction_save_serial+1,"entire independent main/bak/tmp/cache/serial after true REQUEST writer"):return false
	var disk=Session.new()
	# This is the JSON persistence boundary, separate from strict live native equality above.
	# Compare complete encoded profile, never normalize live proposal or key types.
	if not check(disk.load_game(backend.save_path) and JSON.stringify(disk.snapshot())==JSON.stringify(expected),"real load preserves the complete JSON profile and unchanged endpoint"):return false
	if not check(backend.automation.position_map==1200,"transaction does not rewrite live endpoint"):return false
	var following:Dictionary=Registry.munde_request(backend,8)
	if not check(following=={"status":"manual","stage":"request9_complete","reason":"梦德首委托已处理；后续任务请手动进行。"},"independent exact manual boundary after NOW9"):return false
	trace.append({"kind":"request9_transaction","before":transaction_before.duplicate(true),"earned":earned.duplicate(true),"disk":disk.snapshot(),"next":following.duplicate(true)})
	transaction_open=false
	transaction_before={}
	return true

func finish() -> void:
	write_trace()
	if not trace_io_error.is_empty():
		failures += 1
		failed = true
		push_error(trace_io_error)
	if backend != null:backend.free()
	print("MUNDE 6C ROUTE: %d assertions, %d failures" % [assertions,failures])
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
	var serialized: String = JSON.stringify({"trace":trace,"first_failure":first_failure,"points":logical_points,"walks":ordinary_walks,"portals":portal_sequence,"field_calls":backend.candidate_field_calls if backend != null else 0,"navigation":nav_trace,"elapsed_ms":Time.get_ticks_msec()-started_msec},"  ")
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
