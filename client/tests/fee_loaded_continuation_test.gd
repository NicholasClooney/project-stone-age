extends "res://tests/support/fee_recovered_close_harness.gd"

func run() -> void:
	for kind: String in ["canonical", "pretty", "loot", "fallback", "known_edge", "closed", "unknown", "attempting"]:
		var c: Dictionary = fixture("mint-" + kind, kind)
		var diagnostic: Dictionary = establish(c)
		diagnostic.ok = false # Outer diagnostics cannot erase a genuine internal success.
		var h: Dictionary = c.b._begin_fee_recovered_close()
		check(not h.is_empty(), "both real success exits mint: " + kind)
		check(c.s._fee_loaded_receipt.used and c.b._begin_fee_loaded_baseline().is_empty(), "used receipt never resurrected")
		check(not c.b.quest_loot.outer_resume_persistent_claims_idle(c.b), "loot sees same close claim")
		check(triple(c.path) == c.baseline_disks, "take never writes")
		verify_live(c, c.expected, c.baseline_serial, c.expected)
		c.b._end_fee_recovered_close(h)
		check(c.b._begin_fee_recovered_close().is_empty() and c.s.writes == 0, "end permanently consumes")
		done(c)
	for mode: String in ["no_write", "after_false", "unknown", "bad_type"]:
		var c: Dictionary = fixture("no-mint-" + mode)
		var h: Dictionary = c.b._begin_fee_loaded_baseline()
		c.s.mode = mode;c.s.at_read = 8
		var diagnostic: Dictionary = c.b._persist_fee_loaded_baseline(h)
		check(not truth(diagnostic.get("ok")), "real failure/partial/unknown")
		diagnostic.ok = true
		check(c.b._begin_fee_recovered_close().is_empty(), "forged success never mints")
		var installed: bool = mode != "no_write"
		verify_live(c, c.expected, 20 if installed else 19, c.expected)
		check(triple(c.path) == ([file_row(c.expected), c.disk_before[0], {"kind": "absent"}] if installed else c.disk_before), "failed baseline complete disk oracle")
		done(c)
	for mode: String in ["claim", "profile_ref", "serial", "cache", "loot_active", "loot_proof", "envelope"]:
		var c: Dictionary = fixture("ready-guard-" + mode)
		establish(c)
		var proof: Dictionary = {"private": RefCounted.new()}
		var claim := RefCounted.new()
		match mode:
			"claim":c.b._fee_attempt_close_call = claim
			"profile_ref":c.s._profile = c.s._profile.duplicate(true)
			"serial":c.b.quest_save_serial += 1
			"cache":c.b.last_saved_payload += " "
			"loot_active":c.s._loot_failure_active = proof
			"loot_proof":c.s._loot_failure_write = proof
			"envelope":c.b._loot_resume_envelope = proof
		check(c.b._begin_fee_recovered_close().is_empty() and c.s.reads == 0 and c.s.writes == 0, "ready CAS/reverse proof refusal")
		check(c.s._profile == c.expected and triple(c.path) == c.baseline_disks, "complete owner and files unchanged")
		if mode == "claim":check(is_same(c.b._fee_attempt_close_call, claim), "foreign claim retained")
		if mode == "loot_active":check(is_same(c.s._loot_failure_active, proof), "active retained")
		if mode == "loot_proof":check(is_same(c.s._loot_failure_write, proof), "proof retained")
		if mode == "envelope":check(is_same(c.b._loot_resume_envelope, proof), "envelope retained")
		done(c)
	var forged: Dictionary = fixture("no-baseline")
	for fake: Variant in [null, {}, {"ok": true}, {"recovered_close_call": RefCounted.new()}, {"load_call": RefCounted.new()}]:
		check(text(forged.b._persist_fee_recovered_close(fake).get("stage"), "invalid_handle"), "diagnostic not capability")
	check(forged.b._begin_fee_recovered_close().is_empty(), "load alone never grants close")
	for consumer: Variant in [null, RefCounted.new(), forged.b._fee_recovered_close_writer]:
		check(forged.b._fee_loaded_baseline_writer.take_close_continuation(forged.b, consumer, RefCounted.new()).is_empty(), "wrong consumer/claim cannot obtain authority")
	verify_live(forged, forged.expected, 19, forged.expected)
	check(triple(forged.path) == forged.disk_before and not forged.s._fee_loaded_receipt.used, "forgery consumes no real receipt")
	done(forged)
	var handles: Dictionary = fixture("handles")
	establish(handles)
	var valid: Dictionary = handles.b._begin_fee_recovered_close()
	for fake: Variant in [null, [], 0, {}, {"recovered_close_call": RefCounted.new()}, {"call": valid.recovered_close_call}, {"recovered_close_call": valid.recovered_close_call, "extra": true}]:
		handles.b._end_fee_recovered_close(fake)
		check(text(handles.b._persist_fee_recovered_close(fake).get("stage"), "invalid_handle"), "wrong end/persist preserves genuine frame")
	check(handles.b._begin_fee_recovered_close().is_empty(), "nested begin refuses")
	check(truth(handles.b._persist_fee_recovered_close(valid).get("ok")), "right capability survives wrong handles")
	var closed: Dictionary = closed_expected(handles)
	verify_live(handles, closed, handles.baseline_serial + 1, closed)
	check(triple(handles.path) == [file_row(closed), file_row(closed), {"kind": "absent"}], "full genuine close triple")
	check(handles.b._begin_fee_recovered_close().is_empty(), "replay refused")
	done(handles)
	var saved: Dictionary = fixture("ordinary-save")
	establish(saved)
	check(saved.b.save(), "real ordinary save")
	check(saved.b._begin_fee_recovered_close().is_empty(), "even unchanged ordinary save invalidates serial")
	verify_live(saved, saved.expected, saved.baseline_serial + 1, saved.expected)
	check(triple(saved.path) == saved.baseline_disks, "same payload save disk oracle")
	done(saved)
	# Two independent backends: original fbba loader body vs candidate's memory-only entry revoke.
	for item: Array in [["pretty", ""], ["loot", ""], ["loot", "after_false"], ["pretty", "load_after_false"]]:
		legacy_loader = true
		var old: Dictionary = fixture("legacy-loader", item[0], item[1])
		legacy_loader = false
		var fresh: Dictionary = fixture("new-loader", item[0], item[1])
		check(old.loaded == fresh.loaded and old.s._profile == fresh.s._profile and old.b.last_saved_payload == fresh.b.last_saved_payload, "original loader return and full live/cache equality")
		check(old.b.quest_save_serial == fresh.b.quest_save_serial and triple(old.path) == triple(fresh.path), "original loader complete disk/serial equality")
		if item[1].is_empty():
			verify_live(fresh, fresh.expected, 19, fresh.expected)
			var want: Array = [file_row(fresh.expected), {"kind": "file", "bytes": fresh.source_bytes}, {"kind": "absent"}] if item[0] == "loot" else [{"kind": "file", "bytes": fresh.source_bytes}, {"kind": "absent"}, {"kind": "absent"}]
			check(triple(fresh.path) == want, "independent success loader triple")
		else:
			check(not fresh.loaded and fresh.b._begin_fee_loaded_baseline().is_empty() and fresh.b._begin_fee_recovered_close().is_empty(), "failed load has no authority")
			check(fresh.s._profile == (fresh.initial_profile if item[1] == "after_false" else fresh.expected) and fresh.b.last_saved_payload == fresh.initial_cache and fresh.b.quest_save_serial == 19, "independent failed loader full memory/cache/serial")
			check(triple(fresh.path) == ([file_row(fresh.expected), {"kind": "file", "bytes": fresh.source_bytes}, {"kind": "absent"}] if item[0] == "loot" else [{"kind": "file", "bytes": fresh.source_bytes}, {"kind": "absent"}, {"kind": "absent"}]), "independent failed loader disk effects")
		done(old);done(fresh)
	var cold: Dictionary = fixture("cold-reload")
	establish(cold)
	var prior_receipt: Dictionary = cold.s._fee_loaded_receipt
	check(cold.b.load_profile(cold.path), "real cold load")
	check(not is_same(prior_receipt, cold.s._fee_loaded_receipt) and prior_receipt.used, "fresh original receipt, old stays used")
	check(cold.b._begin_fee_recovered_close().is_empty(), "cold load does not inherit continuation")
	verify_live(cold, cold.expected, cold.baseline_serial, cold.expected)
	check(triple(cold.path) == cold.baseline_disks, "cold full disk unchanged")
	done(cold)
	var failed: Dictionary = fixture("failed-load-revokes")
	establish(failed)
	var receipt: Dictionary = failed.s._fee_loaded_receipt
	check(not failed.b.load_profile(failed.path + ".missing"), "real missing loader false")
	check(is_same(receipt, failed.s._fee_loaded_receipt) and receipt.used, "Session original receipt retained")
	check(failed.b._begin_fee_recovered_close().is_empty() and failed.b._begin_fee_loaded_baseline().is_empty(), "failed Backend load revokes both authorities")
	verify_live(failed, failed.expected, failed.baseline_serial, failed.expected)
	check(triple(failed.path) == failed.baseline_disks and image_of(failed.path + ".missing").kind == "absent", "failed load disk unchanged")
	done(failed)
	check(ordinal == 32, "exact bounded 32 fixtures")
	summary("FEE LOADED CONTINUATION")
