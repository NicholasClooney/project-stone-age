extends SceneTree
## UNRUN B2a: actual load -> private receipt -> exact baseline only.
## No engine authorization, production caller, close, sidecar consumption or ACK.
const Backend = preload("res://server/backend.gd")
const Session = preload("res://server/game_session.gd")
const Fault = preload("res://tests/support/fee_loaded_baseline_fault_session.gd")
const RUN := "11111111111111111111111111111111"
const OLD := "22222222222222222222222222222222"
const STEP := "jewels:hunt:2760"
const NOW := 1800000000
var failures := 0
var checks := 0
var ordinal := 0
var kept: Array[String] = []

class PublishFault extends "res://server/backend.gd":
	var replace_timer := false
	func _publish() -> void:
		if replace_timer:quest_loot = preload("res://server/quest_auto_loot.gd").new()
		super._publish()

func _initialize() -> void:call_deferred("run")
func clock() -> int:return NOW
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:failures += 1;push_error(label)
func truth(v: Variant) -> bool:
	if not v is bool:return false
	var result: bool = v
	return result
func text(v: Variant, expected: String) -> bool:
	return v is String and v == expected
func put(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	check(f != null, "fixture opens: " + path)
	if f == null:return
	f.store_buffer(bytes);f.flush();check(f.get_error() == OK, "fixture flush")
	f.close()
func image_of(path: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):return {"kind": "directory"}
	if not FileAccess.file_exists(path):return {"kind": "absent"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:return {"kind": "unreadable"}
	var n: int = f.get_length()
	var bytes: PackedByteArray = f.get_buffer(n)
	var ok: bool = bytes.size() == n and f.get_error() == OK
	f.close()
	return {"kind": "file" if ok else "unreadable", "bytes": bytes}
func triple(path: String) -> Array:
	return [image_of(path), image_of(path + ".bak"), image_of(path + ".tmp")]
func journal(run: String = RUN, status: String = "active") -> Dictionary:
	return {"schema": 1, "owner": {"profile_id": "samgir-singleplayer-v1", "character_id": "100000"}, "current": {"run_id": run, "run_status": status, "purchase": {"state": "none"}}, "unresolved_attempt": {}}
func ledger(open_span: bool) -> Dictionary:
	return {"version": 1, "recovery_blocked": false, "entries": {STEP: {
		"budget_id": "33333333333333333333333333333333", "origin_run_id": OLD, "generation": 0, "revision": 5,
		"limit_ms": 1800000, "used_ms": 1200, "existing_items": 0, "saved_battles": 2, "new_items": 1,
		"issued_seq": 3, "settled_seq": 2 if open_span else 3, "open_span": open_span, "recovery_blocked": false}}}

func fixture(tag: String, kind: String = "pretty", load_mode: String = "") -> Dictionary:
	ordinal += 1
	print("B2A_TRACE BEGIN ordinal=%d tag=%s tick_us=%d checks=%d failures=%d" % [ordinal, tag, Time.get_ticks_usec(), checks, failures])
	var rng := RandomNumberGenerator.new();rng.seed = 8317
	var source = Session.new(Callable(self, "clock"), rng)
	var before: Dictionary = source.snapshot()
	before.quest_auto_fee_lifecycle = journal()
	if kind == "loot":before.quest_loot = ledger(true)
	if kind == "closed":before.quest_auto_fee_lifecycle.current.run_status = "closed"
	if kind in ["manual_only", "unknown"]:before.quest_auto_fee_lifecycle.current.purchase = {"state": "manual_only"}
	if kind == "unknown":before.quest_auto_fee_lifecycle.unresolved_attempt = {"origin_run_id": OLD, "attempt_id": "44444444444444444444444444444444", "source_id": "lobby", "offer_id": "ticket", "item_id": 2600, "amount": 100, "balance_before": 500}
	if kind in ["attempting", "ticket_committed", "entry_committed"]:
		before.quest_auto_fee_lifecycle.current.purchase = {"state": kind, "attempt_id": "44444444444444444444444444444444", "source_id": "lobby", "offer_id": "ticket", "item_id": 2600, "amount": 100, "balance_before": 500}
		if kind != "attempting":before.quest_auto_fee_lifecycle.current.purchase.merge({"balance_after": 400, "ticket_uid": 12})
		if kind == "entry_committed":before.quest_auto_fee_lifecycle.current.purchase.consumed_ticket_uid = 12
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
	var path: String = "user://fee-loaded-%d-%03d-%s.json" % [Time.get_ticks_usec(), ordinal, tag]
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
	print("B2A_TRACE SEEDED ordinal=%d path=%s tick_us=%d" % [ordinal, path, Time.get_ticks_usec()])
	var b = PublishFault.new()
	b.set_process(false)
	var load_rng := RandomNumberGenerator.new();load_rng.seed = 8317
	var s = Fault.new(Callable(self, "clock"), load_rng)
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
	print("B2A_TRACE READY ordinal=%d path=%s tick_us=%d checks=%d failures=%d" % [ordinal, path, Time.get_ticks_usec(), checks, failures])
	return result
func done(c: Dictionary) -> void:
	check(image_of(c.b.resume_path).bytes == c.sidecar, "entire sidecar remains untouched")
	c.b.free() # Preserve all successful and failed disk fixtures.
	print("B2A_TRACE END ordinal=%d path=%s tick_us=%d checks=%d failures=%d" % [ordinal, c.path, Time.get_ticks_usec(), checks, failures])

func success_cases() -> void:
	for kind: String in ["pretty", "canonical", "loot", "fallback", "known_edge", "closed", "manual_only", "unknown", "attempting", "ticket_committed", "entry_committed"]:
		var c: Dictionary = fixture(kind, kind)
		var h: Dictionary = c.b._begin_fee_loaded_baseline()
		check(not h.is_empty() and c.s.reads == 3, "real receipt seals frame: " + kind)
		var r: Dictionary = c.b._persist_fee_loaded_baseline(h)
		var no_write: bool = kind in ["canonical", "loot"]
		check(truth(r.get("ok")), "baseline success: " + kind)
		check(c.s.writes == (0 if no_write else 1) and c.s.reads == (6 if no_write else 9), "exact reader/writer counts: " + kind)
		check(c.s._profile == c.expected and c.b.last_saved_payload == JSON.stringify(c.expected) and c.b.quest_save_serial == (19 if no_write else 20), "full memory/cache/serial: " + kind)
		var expected_backup: Dictionary = c.disk_before[1] if no_write or kind == "fallback" else c.disk_before[0]
		check(triple(c.path) == [{"kind": "file", "bytes": JSON.stringify(c.expected).to_utf8_buffer()}, expected_backup, {"kind": "absent"}], "independent entire disk triple: " + kind)
		check(c.b._begin_fee_loaded_baseline().is_empty() and text(c.b._persist_fee_loaded_baseline(h).get("stage"), "invalid_handle"), "consumed receipt and handle never replay")
		done(c)

func fault_cases() -> void:
	for mode: String in ["no_write", "after_false", "tmp_directory", "unknown", "bad_type", "owner", "path", "serial", "timer", "claim", "nested"]:
		var c: Dictionary = fixture(mode)
		var h: Dictionary = c.b._begin_fee_loaded_baseline()
		check(not h.is_empty(), "fault sealed before arming")
		c.s.mode = mode;c.s.handle = h;c.s.at_read = 7
		var r: Dictionary = c.b._persist_fee_loaded_baseline(h)
		check(c.s.writes == 1 and c.s.reads == 9, "all raw writer and consecutive readback calls: " + mode)
		check(truth(r.get("ok")) == (mode == "nested"), "bounded result: " + mode)
		var installed: bool = mode in ["after_false", "nested"]
		check(truth(r.get("installed")) == installed, "observed installation/serial fact: " + mode)
		var expected_live: Dictionary = c.expected.duplicate(true)
		if mode == "owner":expected_live.profile_id = "successor"
		check(c.s._profile == expected_live and c.b.last_saved_payload == JSON.stringify(c.expected), "independent full successor/live/cache: " + mode)
		check(c.b.quest_save_serial == (29 if mode == "serial" else (20 if installed else 19)), "serial unchanged or original-only advance")
		if mode in ["no_write", "tmp_directory"]:
			check(image_of(c.path) == c.disk_before[0] and image_of(c.path + ".bak") == c.disk_before[1], "actual unwritten full pair")
		else:
			check(image_of(c.path).bytes == JSON.stringify(c.expected).to_utf8_buffer() and image_of(c.path + ".bak") == c.disk_before[0], "actual landed full pair despite error")
		check(image_of(c.path + ".tmp").kind == ("directory" if mode == "tmp_directory" else "absent"), "exact retained tmp state")
		if mode == "claim":check(is_same(c.b._fee_attempt_close_call, c.s.claim), "successor claim retained")
		else:check(c.b._fee_attempt_close_call == null, "own claim released")
		if mode == "nested":check(text(c.s.nested.get("stage"), "already_executing"), "nested call did not consume outer frame")
		check(c.b._begin_fee_loaded_baseline().is_empty(), "unknown/failed I/O receipt cannot silently retry")
		done(c)

func guards() -> void:
	for kind: String in ["foreign_run", "foreign_owner", "legacy", "snapshot_migration"]:
		var c: Dictionary = fixture(kind, kind)
		check(c.b._begin_fee_loaded_baseline().is_empty() and c.s.writes == 0 and triple(c.path) == c.disk_before, "foreign/legacy cannot gain authority: " + kind)
		done(c)
	for mode: String in ["fake_load", "load_after_false", "publish_timer"]:
		var c: Dictionary = fixture(mode, "pretty", mode)
		check(c.b._begin_fee_loaded_baseline().is_empty() and c.s.writes == 0, "real successful loader and post-publication owner required: " + mode)
		done(c)
	for mode: String in ["path", "owner", "profile_ref", "serial", "cache", "timer", "loot_active", "loot_proof", "envelope", "outer_call", "heartbeat", "claim"]:
		var c: Dictionary = fixture("guard-" + mode)
		var proof: Dictionary = {"sentinel": RefCounted.new()}
		match mode:
			"path":c.b.save_path += ".foreign"
			"owner":c.s._profile.profile_id = "foreign"
			"profile_ref":c.s._profile = c.s._profile.duplicate(true)
			"serial":c.b.quest_save_serial += 1
			"cache":c.b.last_saved_payload += " "
			"timer":c.b.quest_loot = preload("res://server/quest_auto_loot.gd").new()
			"loot_active":c.s._loot_failure_active = proof
			"loot_proof":c.s._loot_failure_write = proof
			"envelope":c.b._loot_resume_envelope = proof
			"outer_call":c.b._loot_outer_resume_call = RefCounted.new()
			"heartbeat":c.b.quest_loot.heartbeat_call = RefCounted.new()
			"claim":c.b._fee_attempt_close_call = RefCounted.new()
		check(c.b._begin_fee_loaded_baseline().is_empty() and c.s.writes == 0 and c.s.reads == 0, "reverse guard before I/O: " + mode)
		if mode == "loot_active":check(is_same(c.s._loot_failure_active, proof), "loot proof not consumed/cleared")
		if mode == "envelope":check(is_same(c.b._loot_resume_envelope, proof), "loot envelope not borrowed")
		if mode == "loot_proof":check(is_same(c.s._loot_failure_write, proof), "loot retry proof not borrowed")
		check(triple(c.path) == c.disk_before, "guard preserves complete triple")
		done(c)

func read_boundaries() -> void:
	for n: int in [1, 2, 3, 4, 5, 6, 7, 8, 9]:
		var c: Dictionary = fixture("read-owner-%d" % n)
		if n <= 3:
			c.s.mode = "read_owner";c.s.at_read = n
			check(c.b._begin_fee_loaded_baseline().is_empty(), "begin read CAS")
		else:
			var h: Dictionary = c.b._begin_fee_loaded_baseline()
			c.s.mode = "read_owner";c.s.at_read = n
			var r: Dictionary = c.b._persist_fee_loaded_baseline(h)
			check(not truth(r.get("ok")) and not truth(r.get("installed")), "old Session readback never installs successor")
		check(c.s.reads == (n if n <= 6 else 9) and c.s.writes == (0 if n <= 6 else 1), "module per-read CAS vs Session continuous three observations")
		var successor: Dictionary = c.expected.duplicate(true);successor.profile_id = "read-successor"
		check(c.s._profile == successor and c.b.quest_save_serial == 19, "exact read successor retained")
		var wanted: Array = c.disk_before if n <= 6 else [{"kind": "file", "bytes": JSON.stringify(c.expected).to_utf8_buffer()}, c.disk_before[0], {"kind": "absent"}]
		check(triple(c.path) == wanted, "read successor complete physical triple")
		done(c)

func handles() -> void:
	var c: Dictionary = fixture("handles")
	var h: Dictionary = c.b._begin_fee_loaded_baseline()
	for wrong: Variant in [null, [], 0, {}, {"load_call": RefCounted.new()}, {"load_call": h.load_call, "extra": true}, {"call": h.load_call}]:
		check(text(c.b._persist_fee_loaded_baseline(wrong).get("stage"), "invalid_handle"), "wrong handle rejected")
		c.b._end_fee_loaded_baseline(wrong)
	check(not c.b.quest_loot.outer_resume_persistent_claims_idle(c.b), "existing loot sees fee reservation without new loot hook")
	check(c.b._begin_fee_loaded_baseline().is_empty(), "nested begin cannot consume real frame")
	check(truth(c.b._persist_fee_loaded_baseline(h).get("ok")), "real handle survives wrong calls")
	check(c.s.writes == 1 and c.s.reads == 9, "handle exact I/O count")
	done(c)

func additional_boundaries() -> void:
	# Every file observation can fail independently; errors do not erase disk facts.
	for mode: String in ["unknown", "bad_type"]:
		for n: int in range(1, 10):
			var c: Dictionary = fixture("%s-%d" % [mode, n])
			var h: Dictionary = {}
			if n > 3:h = c.b._begin_fee_loaded_baseline()
			c.s.mode = mode;c.s.at_read = n
			if n <= 3:
				check(c.b._begin_fee_loaded_baseline().is_empty(), "unknown admission rejects")
			else:
				var r: Dictionary = c.b._persist_fee_loaded_baseline(h)
				check(not truth(r.get("ok")), "unknown prewrite/postwrite denies success")
			# Only postwrite backup/tmp uncertainty permits known-primary installation.
			var installed: bool = n in [8, 9]
			check(c.s.writes == (1 if n >= 7 else 0), "fault observation writer count")
			check(c.s.reads == (3 if n <= 3 else (6 if n <= 6 else 9)), "fault observation exact reader count")
			check(c.s._profile == c.expected and c.b.last_saved_payload == JSON.stringify(c.expected) and c.b.quest_save_serial == (20 if installed else 19), "unknown full memory oracle")
			var wanted: Array = c.disk_before if n <= 6 else [{"kind": "file", "bytes": JSON.stringify(c.expected).to_utf8_buffer()}, c.disk_before[0], {"kind": "absent"}]
			check(triple(c.path) == wanted, "unknown independent complete actual triple")
			done(c)
	for which: int in range(3):
		var c: Dictionary = fixture("disk-drift-%d" % which)
		var h: Dictionary = c.b._begin_fee_loaded_baseline()
		var suffix: String = ["", ".bak", ".tmp"][which]
		var bytes: PackedByteArray = "external-successor".to_utf8_buffer()
		put(c.path + suffix, bytes)
		var wanted: Array = c.disk_before.duplicate(true);wanted[which] = {"kind": "file", "bytes": bytes}
		check(not truth(c.b._persist_fee_loaded_baseline(h).get("ok")) and c.s.writes == 0, "external disk drift has no write")
		check(triple(c.path) == wanted and c.s._profile == c.expected and c.b.quest_save_serial == 19, "complete external successor preserved")
		done(c)
	var direct: Dictionary = fixture("direct-raw")
	var receipt: Dictionary = direct.s._fee_loaded_receipt
	for fake: Variant in [null, {}, RefCounted.new(), direct.b._fee_loaded_baseline_writer]:
		var denied: Dictionary = direct.s._write_fee_loaded_baseline_once(receipt, direct.path, direct.s._profile, direct.expected, fake, direct.b)
		check(text(denied.get("stage"), "writer_claim_rejected"), "raw bypass lacks executing reservation")
	check(direct.s.reads == 0 and direct.s.writes == 0 and not receipt.used and triple(direct.path) == direct.disk_before, "raw bypass leaves receipt and full disk")
	var handle: Dictionary = direct.b._begin_fee_loaded_baseline()
	check(truth(direct.b._persist_fee_loaded_baseline(handle).get("ok")), "raw bypass never consumed genuine receipt")
	done(direct)
	var prior: Dictionary = fixture("failed-load-retains-receipt")
	var old_receipt: Dictionary = prior.s._fee_loaded_receipt
	var prior_profile: Dictionary = prior.s._profile
	check(not prior.s.load_game(prior.path + ".missing"), "real absent loader fails")
	check(is_same(prior.s._fee_loaded_receipt, old_receipt) and is_same(prior.s._profile, prior_profile) and triple(prior.path) == prior.disk_before, "failed loader preserves original receipt/ref/disks")
	done(prior)
	# Existing loot recovery can physically land then return false: no B2a receipt.
	var landed: Dictionary = fixture("loot-load-false", "loot", "after_false")
	check(not landed.loaded and landed.s._fee_loaded_receipt.is_empty() and landed.b._begin_fee_loaded_baseline().is_empty(), "loader false never grants receipt")
	check(landed.s._profile == landed.initial_profile and landed.b.last_saved_payload == landed.initial_cache and landed.b.quest_save_serial == 19, "failed loader restores original entire live profile/cache/serial only")
	check(triple(landed.path) == [{"kind": "file", "bytes": JSON.stringify(landed.expected).to_utf8_buffer()}, {"kind": "file", "bytes": landed.source_bytes}, {"kind": "absent"}], "actual loot load write remains after false")
	done(landed)

func malformed_journal_owners() -> void:
	for field: String in ["profile_id", "character_id"]:
		for bad: Variant in [null, false, 7, [], {}, "__missing__"]:
			var c: Dictionary = fixture("bad-journal-owner")
			var invalid: Dictionary = c.before.duplicate(true)
			if bad is String:invalid.quest_auto_fee_lifecycle.owner.erase(field)
			else:invalid.quest_auto_fee_lifecycle.owner[field] = bad
			var bytes: PackedByteArray = JSON.stringify(invalid).to_utf8_buffer()
			put(c.path, bytes)
			var old_receipt: Dictionary = c.s._fee_loaded_receipt
			var old_profile: Dictionary = c.s._profile
			check(not c.s.load_game(c.path), "malformed owner load rejected without conversion")
			check(is_same(c.s._fee_loaded_receipt, old_receipt) and is_same(c.s._profile, old_profile) and c.s._profile == c.expected, "bad owner full live and receipt preserved")
			check(triple(c.path) == [{"kind": "file", "bytes": bytes}, {"kind": "absent"}, {"kind": "absent"}], "bad owner full disk preserved")
			done(c)

func run() -> void:
	success_cases();fault_cases();guards();read_boundaries();handles();additional_boundaries();malformed_journal_owners()
	print("FEE LOADED BASELINE SUMMARY checks=%d failures=%d retained_fixtures=%d" % [checks, failures, kept.size()])
	for path: String in kept:print("FEE LOADED BASELINE RETAINED " + path)
	quit(1 if failures else 0)
