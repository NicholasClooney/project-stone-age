extends "res://tests/support/fee_recovered_close_harness.gd"
const ColdBackend = preload("res://tests/support/fee_cold_backend.gd")
func fixture(tag: String, kind: String = "pretty", load_mode: String = "") -> Dictionary:
	ordinal += 1
	print("B3A_TRACE BEGIN ordinal=%d tag=%s tick_us=%d checks=%d failures=%d" % [ordinal, tag, Time.get_ticks_usec(), checks, failures])
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
	var path: String = "user://fee-cold-%d-%03d-%s.json" % [Time.get_ticks_usec(), ordinal, tag]
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
	print("B3A_TRACE SEEDED ordinal=%d path=%s tick_us=%d" % [ordinal, path, Time.get_ticks_usec()])
	var b = ColdBackend.new()
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
	print("B3A_TRACE READY ordinal=%d path=%s tick_us=%d checks=%d failures=%d" % [ordinal, path, Time.get_ticks_usec(), checks, failures])
	return result
func done(c: Dictionary) -> void:
	check(image_of(c.b.resume_path).bytes == c.sidecar, "entire sidecar remains untouched")
	c.b.free() # Preserve all successful and failed disk fixtures.
	print("B3A_TRACE END ordinal=%d path=%s tick_us=%d checks=%d failures=%d" % [ordinal, c.path, Time.get_ticks_usec(), checks, failures])



func marker(run: String = RUN) -> Dictionary:
	return {"quest_auto": {"identity": {"run_id": run, "step_id": "fee:test", "revision": 3}},
		"fee_attempt_binding": {"owner": {"profile_id": "samgir-singleplayer-v1", "character_id": "100000"}, "run_id": RUN}}
func set_sidecar(c: Dictionary, kind: String) -> Dictionary:
	var state: Dictionary = marker(OLD if kind == "foreign" else RUN)
	if kind == "residual":state["sentinel"] = {"keep": [1, "x"]}
	if kind == "mixed":state.quest_auto.identity.step_id = "jewels:hunt:2760"
	if kind == "absent":
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(c.path + ".sidecar")) == OK, "prepare absent sidecar")
		c.sidecar_absent = true
		return {}
	c.sidecar = JSON.stringify(JSON.from_native(state)).to_utf8_buffer()
	put(c.path + ".sidecar", c.sidecar)
	return state
func end_cold(c: Dictionary) -> void:
	c.b.free()
	print("B3A_TRACE END ordinal=%d path=%s" % [ordinal,c.path])
func side_pair(c: Dictionary) -> Array:return [image_of(c.path + ".sidecar"), image_of(c.path + ".sidecar.tmp")]
func preserved_side(c: Dictionary) -> Array:return [{"kind":"file","bytes":c.sidecar},{"kind":"absent"}]
func closed_pair(c: Dictionary) -> Array:
	var profile: Dictionary = closed_expected(c)
	return [file_row(profile),file_row(profile),{"kind":"absent"}]
