extends "res://tests/fee_loaded_baseline_test.gd"
const StorageFault = preload("res://tests/support/fee_loaded_storage_fault_session.gd")
class OriginalLoadBackend extends "res://server/backend.gd":
	func load_profile(path: String) -> bool:
		_fee_loaded_baseline_writer.revoke_loaded_authority()
		var load_owner=session
		var load_scope_path:String=save_path
		stationary.stop(self,"载入存档停止了原地遇敌。")
		var stop_result:Dictionary=quest_auto.stop(self,"载入存档停止了自动任务。")
		if not stop_result.get("ok",false):return false
		original_quests.pending={}
		if not is_same(session,load_owner) or save_path!=load_scope_path:return false
		var previous_fee_receipt:Dictionary=load_owner._fee_loaded_receipt
		if not load_owner.load_game(path):return false
		if not is_same(session,load_owner) or save_path!=load_scope_path:return false
		# Successful cold load retires old in-memory loot authority only.
		quest_loot = preload("res://server/quest_auto_loot.gd").new()
		quest_arrival.reset()
		transmigration.reset()
		last_saved_payload = JSON.stringify(session.snapshot())
		var fee_load_token:RefCounted=_fee_loaded_baseline_writer.bind_loaded(self,load_owner,path,previous_fee_receipt)
		_publish()
		_fee_loaded_baseline_writer.finish_load_publication(self,fee_load_token)
		return true

func make_case(shape: String, mutation: String = "", old_loader: bool = false, load_fault: String = "") -> Dictionary:
	ordinal += 1
	print("N_TRACE BEGIN ordinal=%d shape=%s mode=%s" % [ordinal, shape, mutation])
	var rng := RandomNumberGenerator.new();rng.seed = 8317
	var source = Session.new(Callable(self, "clock"), rng)
	var before: Dictionary = source.snapshot()
	before.quest_auto_fee_lifecycle = journal()
	before.player.gold = 4321
	before.inventory.potion = 37
	before.travel_pass = true
	if shape in ["absent", "loot_absent", "fallback_absent"]:
		for key: String in ["item_storage", "legacy_item_storage", "item_storage_revision"]:before.erase(key)
	if shape == "nonempty":
		before.legacy_item_storage = {"potion": 7}
		before.item_storage_revision = 3
		before.item_storage = [{"uid": 1, "item_id": 2605, "durability": 2500000}]
		before.next_original_uid = 2
	if shape.begins_with("missing_"):before.erase(shape.trim_prefix("missing_"))
	if shape.begins_with("only_"):
		for key: String in ["item_storage", "legacy_item_storage", "item_storage_revision"]:
			if key != shape.trim_prefix("only_"):before.erase(key)
	if shape == "loot_absent":before.quest_loot = ledger(true)
	if shape == "fallback_absent":before.quest_loot = {"version": 1, "recovery_blocked": true, "entries": {}}
	var partial: bool = shape.begins_with("missing_") or shape.begins_with("only_")
	check(source._valid_profile(before) == (not partial), "independent original source validity")
	var loaded: Dictionary = before.duplicate(true)
	if shape == "loot_absent":
		loaded.quest_loot.entries[STEP].open_span = false
		loaded.quest_loot.entries[STEP].settled_seq = 3
		loaded.quest_loot.entries[STEP].revision = 6
	var expected: Dictionary = loaded.duplicate(true)
	if shape in ["absent", "loot_absent", "fallback_absent"]:expected.merge({"item_storage": [], "legacy_item_storage": {}, "item_storage_revision": 0})
	var path: String = "user://fee-storage-%d-%03d.json" % [Clock.ticks_usec(), ordinal]
	kept.append(ProjectSettings.globalize_path(path))
	var bytes: PackedByteArray = JSON.stringify(before, "\t").to_utf8_buffer()
	put(path, "bad-json".to_utf8_buffer() if shape == "fallback_absent" else bytes)
	if shape == "fallback_absent":put(path + ".bak", bytes)
	var sidecar: PackedByteArray = "fee-storage-sidecar-unchanged".to_utf8_buffer()
	put(path + ".sidecar", sidecar)
	var initial_disks: Array = triple(path)
	print("N_TRACE SEEDED ordinal=%d path=%s" % [ordinal, path])
	var b = OriginalLoadBackend.new() if old_loader else Backend.new()
	b.set_process(false)
	var luck := RandomNumberGenerator.new();luck.seed = 8317
	var s = StorageFault.new(Callable(self, "clock"), luck)
	s.host = weakref(b);s.snapshot_mode = mutation;s.mode = load_fault
	b.session = s;s.battle_pets_hook = b._live_battle_pets;s.capture_entry_hook = b._capture_entry
	b.resume_path = path + ".sidecar";b.quest_save_serial = 19
	var initial: Dictionary = s._profile.duplicate(true)
	var cache: String = b.last_saved_payload
	var ok: bool = b.load_profile(path)
	b.save_path = path if mutation != "path" else path + ".next"
	s.mode = "";s.writes = 0;s.reads = 0
	print("N_TRACE READY ordinal=%d path=%s loaded=%s" % [ordinal, path, ok])
	return {"b": b, "s": s, "path": path, "before": before, "loaded": loaded, "expected": expected,
		"bytes": bytes, "sidecar": sidecar, "ok": ok, "initial": initial, "cache": cache,
		"initial_disks": initial_disks, "shape": shape, "mutation": mutation, "partial": partial}

func finish_case(c: Dictionary) -> void:
	check(image_of(c.path + ".sidecar").bytes == c.sidecar, "complete sidecar untouched")
	c.b.free()
	print("N_TRACE END path=%s" % c.path)

func row_of(value: Dictionary) -> Dictionary:return {"kind": "file", "bytes": JSON.stringify(value).to_utf8_buffer()}
func post_load_disks(c: Dictionary) -> Array:
	if c.shape == "loot_absent":return [row_of(c.loaded), {"kind": "file", "bytes": c.bytes}, {"kind": "absent"}]
	return c.initial_disks

func deny(c: Dictionary) -> void:
	check(c.b._begin_fee_loaded_baseline().is_empty() and c.b._begin_fee_recovered_close().is_empty(), "normalization refusal grants neither baseline nor close")
	check(c.s.writes == 0 and c.s.reads == 0, "refusal no fee IO")
	check(triple(c.path) == post_load_disks(c), "independent entire original load disk behavior")

func run() -> void:
	for shape: String in ["absent", "present", "nonempty", "loot_absent", "fallback_absent"]:
		var c: Dictionary = make_case(shape)
		check(c.ok and c.s._profile == c.expected and c.b.last_saved_payload == JSON.stringify(c.expected), "entire successful normalized live/cache")
		check(triple(c.path) == post_load_disks(c), "original loader physical images before baseline")
		var receipt: Dictionary = c.s._fee_loaded_receipt
		check(receipt.loader_profile_bytes == JSON.stringify(c.loaded).to_utf8_buffer() and receipt.loaded_bytes == JSON.stringify(c.expected).to_utf8_buffer(), "independent loader bytes and target bytes")
		check(c.s._begin_fee_loaded_storage_normalization(receipt, c.b) == null, "normalization receipt cannot replay")
		var h: Dictionary = c.b._begin_fee_loaded_baseline()
		check(not h.is_empty(), "normalization permits exact baseline")
		var r: Dictionary = c.b._persist_fee_loaded_baseline(h)
		check(truth(r.get("ok")) and c.s.writes == 1 and c.b.quest_save_serial == 20, "baseline independently writes full target")
		var backup: Dictionary = c.initial_disks[1] if shape == "fallback_absent" else post_load_disks(c)[0]
		check(triple(c.path) == [row_of(c.expected), backup, {"kind": "absent"}], "entire normalized baseline primary/backup/tmp")
		var close: Dictionary = c.b._begin_fee_recovered_close()
		check(not close.is_empty() and receipt.used, "real B2b continuation after baseline only")
		c.b._end_fee_recovered_close(close)
		check(c.s._begin_fee_loaded_storage_normalization(receipt, c.b) == null and c.b._begin_fee_recovered_close().is_empty(), "used receipt never resurrects continuation")
		finish_case(c)
	for prefix: String in ["missing_", "only_"]:
		for key: String in ["item_storage", "legacy_item_storage", "item_storage_revision"]:
			var c: Dictionary = make_case(prefix + key)
			check(not c.ok and c.s._profile == c.initial and c.b.last_saved_payload == c.cache and c.b.quest_save_serial == 19, "real partial source load behavior unchanged")
			check(c.s._fee_loaded_receipt.is_empty() and c.s.snapshot_faults == 0, "invalid source never reaches receipt/snapshot")
			deny(c);finish_case(c)
	for mutation: String in ["gold", "gold_type", "revision_type", "ref", "receipt_copy", "token", "used", "serial", "path", "timer", "nested_failure", "drop_item", "drop_legacy", "drop_revision"]:
		var c: Dictionary = make_case("absent", mutation)
		check(c.ok and c.s.snapshot_faults == 1, "real load remains successful; snapshot fault reached once")
		var expected: Dictionary = c.expected.duplicate(true)
		if mutation == "gold":expected.player.gold += 1
		if mutation == "gold_type":expected.player.gold = float(expected.player.gold)
		if mutation == "revision_type":expected.item_storage_revision = 0.0
		if mutation == "drop_legacy":expected.erase("legacy_item_storage")
		if mutation == "drop_revision":expected.erase("item_storage_revision")
		check(c.s._profile == expected and typeof(c.s._profile.player.gold) == typeof(expected.player.gold), "complete snapshot effects preserved on refusal")
		var cache_expected: Dictionary = expected.duplicate(true)
		if mutation == "drop_item":cache_expected.erase("item_storage")
		check(c.b.last_saved_payload == JSON.stringify(cache_expected) and c.b.quest_save_serial == (20 if mutation == "serial" else 19), "original cache/serial effects preserved")
		if mutation == "nested_failure":check(not c.s.nested_loaded, "real nested failed load reached")
		deny(c);finish_case(c)
	# Exact original load body in independent backends, plus independent full expected.
	for spec: Array in [["absent", ""], ["loot_absent", ""], ["loot_absent", "after_false"]]:
		var a: Dictionary = make_case(spec[0], "", true, spec[1])
		var z: Dictionary = make_case(spec[0], "", false, spec[1])
		check(a.ok == z.ok and a.s._profile == z.s._profile and a.b.last_saved_payload == z.b.last_saved_payload and a.b.quest_save_serial == z.b.quest_save_serial, "old/new loader full live and return parity")
		check(triple(a.path) == triple(z.path), "old/new physical disk parity")
		check(z.s._profile == (z.expected if spec[1].is_empty() else z.initial), "independent load full profile oracle")
		check(triple(z.path) == post_load_disks(z), "independent load entire disk oracle including false-after")
		if not spec[1].is_empty():deny(z)
		finish_case(a);finish_case(z)
	var wrong: Dictionary = make_case("absent", "wrong_handle")
	check(wrong.ok and wrong.s.wrong_denied, "wrong calls during real frame preserve genuine owner")
	for token: RefCounted in [null, RefCounted.new()]:
		check(not wrong.s._finish_fee_loaded_storage_normalization(token, wrong.b), "wrong/replay finish cannot authorize")
	check(wrong.s._begin_fee_loaded_storage_normalization(wrong.s._fee_loaded_receipt.duplicate(true), wrong.b) == null, "copied receipt denied")
	check(not wrong.s._fee_loaded_receipt.used and triple(wrong.path) == post_load_disks(wrong), "wrong calls keep original receipt/disks")
	var real: Dictionary = wrong.b._begin_fee_loaded_baseline()
	check(not real.is_empty() and truth(wrong.b._persist_fee_loaded_baseline(real).get("ok")), "real normalized receipt survives wrong calls")
	check(triple(wrong.path) == [row_of(wrong.expected), wrong.initial_disks[0], {"kind": "absent"}] and wrong.s._profile == wrong.expected and wrong.b.quest_save_serial == 20, "full independent post-wrong-call baseline oracle")
	finish_case(wrong)
	check(ordinal == 32, "exact 32 bounded fixtures")
	print("FEE LOADED STORAGE NORMALIZATION SUMMARY checks=%d failures=%d retained_fixtures=%d" % [checks, failures, kept.size()])
	quit(1 if failures else 0)
