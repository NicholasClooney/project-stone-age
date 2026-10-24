extends "res://tests/fee_loaded_baseline_test.gd"
const Clock=preload("res://scripts/clock.gd")
const RecoveryFault = preload("res://tests/support/fee_recovered_close_fault_session.gd")
var legacy_loader := false
class LegacyLoadBackend extends "res://server/backend.gd":
	var replace_timer := false
	func load_profile(path: String) -> bool:
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

func fixture(tag: String, kind: String = "pretty", load_mode: String = "") -> Dictionary:
	ordinal += 1
	print("B2B_TRACE BEGIN ordinal=%d tag=%s tick_us=%d checks=%d failures=%d" % [ordinal, tag, Clock.ticks_usec(), checks, failures])
	var rng := RandomNumberGenerator.new();rng.seed = 8317
	var source = Session.new(Callable(self, "clock"), rng)
	var before: Dictionary = source.snapshot()
	before.quest_auto_fee_lifecycle = journal()
	if kind == "loot":before.quest_loot = ledger(true)
	if kind == "closed":before.quest_auto_fee_lifecycle.current.run_status = "closed"
	if kind in ["manual_only", "unknown"]:before.quest_auto_fee_lifecycle.current.purchase = {"state": "manual_only"}
	if kind == "unknown":before.quest_auto_fee_lifecycle.unresolved_attempt = {"origin_run_id": OLD, "attempt_id": "44444444444444444444444444444444", "source_id": "lobby", "offer_id": "ticket", "item_id": 2600, "amount": 100, "balance_before": 500}
	if kind in ["attempting", "ticket_committed", "entry_committed", "closed_attempting"]:
		before.quest_auto_fee_lifecycle.current.purchase = {"state": "attempting" if kind == "closed_attempting" else kind, "attempt_id": "44444444444444444444444444444444", "source_id": "lobby", "offer_id": "ticket", "item_id": 2600, "amount": 100, "balance_before": 500}
		if kind not in ["attempting", "closed_attempting"]:before.quest_auto_fee_lifecycle.current.purchase.merge({"balance_after": 400, "ticket_uid": 12})
		if kind == "entry_committed":before.quest_auto_fee_lifecycle.current.purchase.consumed_ticket_uid = 12
	if kind == "closed_attempting":before.quest_auto_fee_lifecycle.current.run_status = "closed"
	if kind == "fallback":before.quest_loot = {"version": 1, "recovery_blocked": true, "entries": {}}
	if kind == "legacy":before.erase("quest_auto_fee_lifecycle")
	if kind == "snapshot_migration":
		for field: String in ["item_storage", "legacy_item_storage", "item_storage_revision"]:before.erase(field)
	var expected: Dictionary = before.duplicate(true)
	if kind == "snapshot_migration":expected.merge({"item_storage": [], "legacy_item_storage": {}, "item_storage_revision": 0})
	if kind == "loot":
		expected.quest_loot.entries[STEP].open_span = false
		expected.quest_loot.entries[STEP].settled_seq = 3
		expected.quest_loot.entries[STEP].revision = 6
	var path: String = "user://fee-recovered-%d-%03d-%s.json" % [Clock.ticks_usec(), ordinal, tag]
	kept.append(ProjectSettings.globalize_path(path))
	var source_bytes: PackedByteArray = JSON.stringify(before, "" if kind == "canonical" else "\t").to_utf8_buffer()
	put(path, "not-json".to_utf8_buffer() if kind == "fallback" else source_bytes)
	if kind == "fallback":put(path + ".bak", source_bytes)
	if kind in ["known_edge", "foreign_run", "foreign_owner"]:
		var backup: Dictionary = before.duplicate(true)
		backup.quest_auto_fee_lifecycle = journal(OLD, "closed" if kind == "known_edge" else "active")
		if kind == "foreign_owner":backup.profile_id = "foreign";backup.quest_auto_fee_lifecycle.owner.profile_id = "foreign"
		put(path + ".bak", JSON.stringify(backup).to_utf8_buffer())
	var sidecar: PackedByteArray = "{\"sentinel\":\"fee-loot-mixed-untouched\"}".to_utf8_buffer()
	put(path + ".sidecar", sidecar)
	print("B2B_TRACE SEEDED ordinal=%d path=%s tick_us=%d" % [ordinal, path, Clock.ticks_usec()])
	var b = LegacyLoadBackend.new() if legacy_loader else PublishFault.new()
	b.set_process(false)
	var load_rng := RandomNumberGenerator.new();load_rng.seed = 8317
	var s = RecoveryFault.new(Callable(self, "clock"), load_rng)
	s.host = weakref(b)
	b.session = s
	s.battle_pets_hook = b._live_battle_pets
	s.capture_entry_hook = b._capture_entry
	b.resume_path = path + ".sidecar"
	b.quest_save_serial = 19
	s.mode = load_mode
	if load_mode == "publish_timer":b.replace_timer = true;s.mode = ""
	var initial_profile: Dictionary = s._profile.duplicate(true)
	var initial_cache: String = b.last_saved_payload
	var old_timer = b.quest_loot
	var loaded: bool = b.load_profile(path) # Real empty-save_path Hub ordering.
	b.save_path = path
	if load_mode.is_empty():
		check(loaded and not is_same(b.quest_loot, old_timer), "real load rebuilds timer")
		check(s._profile == expected and b.last_saved_payload == JSON.stringify(expected), "independent entire loaded profile/cache")
		if kind != "legacy":check(not s._fee_loaded_receipt.is_empty(), "original successful load receipt")
	check(image_of(b.resume_path).bytes == sidecar, "load leaves complete sidecar bytes")
	var result: Dictionary = {"b": b, "s": s, "path": path, "before": before, "expected": expected, "source_bytes": source_bytes,
		"disk_before": triple(path), "sidecar": sidecar, "loaded": loaded, "kind": kind, "initial_profile": initial_profile, "initial_cache": initial_cache}
	s.mode = "";s.writes = 0;s.reads = 0
	print("B2B_TRACE READY ordinal=%d path=%s tick_us=%d checks=%d failures=%d" % [ordinal, path, Clock.ticks_usec(), checks, failures])
	return result
func done(c: Dictionary) -> void:
	check(image_of(c.b.resume_path).bytes == c.sidecar, "entire sidecar remains untouched")
	c.b.free() # Preserve all successful and failed disk fixtures.
	print("B2B_TRACE END ordinal=%d path=%s tick_us=%d checks=%d failures=%d" % [ordinal, c.path, Clock.ticks_usec(), checks, failures])


func establish(c: Dictionary) -> Dictionary:
	var h: Dictionary = c.b._begin_fee_loaded_baseline()
	check(not h.is_empty(), "real baseline handle")
	var result: Dictionary = c.b._persist_fee_loaded_baseline(h)
	check(truth(result.get("ok")), "real baseline succeeds")
	c.baseline_serial = c.b.quest_save_serial
	c.baseline_disks = triple(c.path)
	c.s.reads = 0;c.s.writes = 0;c.s.close_calls = 0
	return result

## Independent full expected profile; never calls close_run or a writer helper.
func closed_expected(c: Dictionary) -> Dictionary:
	var expected: Dictionary = c.expected.duplicate(true)
	var j: Dictionary = expected.quest_auto_fee_lifecycle
	j.current.run_status = "closed"
	if j.current.purchase.state == "attempting":
		var p: Dictionary = j.current.purchase
		j.unresolved_attempt = {"origin_run_id": j.current.run_id, "attempt_id": p.attempt_id,
			"source_id": p.source_id, "offer_id": p.offer_id, "item_id": p.item_id,
			"amount": p.amount, "balance_before": p.balance_before}
		j.current.purchase = {"state": "manual_only"}
	return expected

func file_row(profile: Dictionary) -> Dictionary:
	return {"kind": "file", "bytes": JSON.stringify(profile).to_utf8_buffer()}

func verify_live(c: Dictionary, expected: Dictionary, serial: int, cache: Dictionary) -> void:
	check(c.s._profile == expected, "independent entire live profile incl rewards/gold/items/UID/ledger")
	check(c.b.last_saved_payload == JSON.stringify(cache) and c.b.quest_save_serial == serial, "entire cache and exact serial")

func summary(label: String) -> void:
	print(label + " SUMMARY checks=%d failures=%d retained_fixtures=%d" % [checks, failures, kept.size()])
	for path: String in kept:print(label + " RETAINED " + path)
	quit(1 if failures else 0)
