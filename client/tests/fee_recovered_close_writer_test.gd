extends "res://tests/support/fee_recovered_close_harness.gd"

func run() -> void:
	for kind: String in ["pretty", "loot", "fallback", "known_edge", "closed", "manual_only", "unknown", "attempting", "ticket_committed", "entry_committed"]:
		var c: Dictionary = fixture("close-" + kind, kind)
		establish(c)
		var h: Dictionary = c.b._begin_fee_recovered_close()
		check(not h.is_empty(), "private continuation accepted")
		var result: Dictionary = c.b._persist_fee_recovered_close(h)
		var expected: Dictionary = closed_expected(c)
		check(truth(result.get("ok")) and text(result.get("stage"), "pair_verified"), "full pair verified")
		check(c.s.writes == 2 and c.s.close_calls == 2 and c.s.reads == 15, "two forced writes fifteen reads")
		verify_live(c, expected, c.baseline_serial + 1, expected)
		check(triple(c.path) == [file_row(expected), file_row(expected), {"kind": "absent"}], "full independent pair/tmp")
		check(c.b._begin_fee_recovered_close().is_empty() and text(c.b._persist_fee_recovered_close(h).get("stage"), "invalid_handle"), "single use after success")
		done(c)
	for mode: String in ["no_write", "after_false", "raw_type", "owner", "nested"]:
		for at: int in [1, 2]:
			var c: Dictionary = fixture("write-%s-%d" % [mode, at], "attempting")
			establish(c)
			var h: Dictionary = c.b._begin_fee_recovered_close()
			c.s.close_mode = mode;c.s.fault_write = at;c.s.close_handle = h
			var result: Dictionary = c.b._persist_fee_recovered_close(h)
			var closed: Dictionary = closed_expected(c)
			var installed: bool = at == 2 or mode in ["after_false", "raw_type", "nested"]
			var live: Dictionary = (closed if installed else c.expected).duplicate(true)
			if mode == "owner":live.profile_id = "read-successor"
			check(truth(result.get("ok")) == (mode == "nested"), "raw return independent of physical facts")
			check(truth(result.get("installed")) == installed, "first installation retained even second failure")
			verify_live(c, live, c.baseline_serial + (1 if installed else 0), closed if installed else c.expected)
			var want: Array
			if mode == "no_write" and at == 1:want = c.baseline_disks
			elif (at == 1 and mode != "nested") or (at == 2 and mode == "no_write"):want = [file_row(closed), file_row(c.expected), {"kind": "absent"}]
			else:want = [file_row(closed), file_row(closed), {"kind": "absent"}]
			check(triple(c.path) == want, "full actual disks independent of wrapper")
			check(c.s.close_calls == (2 if mode == "nested" else at) and c.s.writes == c.s.close_calls, "actual raw phase counts")
			if mode == "nested":check(text(c.s.inner.get("stage"), "already_executing") and c.s.inner.begin.is_empty(), "nested persist/end/begin cannot consume real frame")
			check(c.b._begin_fee_recovered_close().is_empty(), "fault/end never remints")
			done(c)
	for mode: String in ["unknown", "read_owner"]:
		for at: int in range(1, 16):
			var c: Dictionary = fixture("read-%s-%d" % [mode, at], "attempting")
			establish(c)
			c.s.close_mode = mode;c.s.fault_read = at
			var h: Dictionary = c.b._begin_fee_recovered_close()
			var result: Dictionary = {} if h.is_empty() else c.b._persist_fee_recovered_close(h)
			check(not truth(result.get("ok")), "every unknown/CAS phase refuses")
			var closed: Dictionary = closed_expected(c)
			var installed: bool = at >= 10 or (mode == "unknown" and at in [8, 9])
			var live: Dictionary = (closed if installed else c.expected).duplicate(true)
			if mode == "read_owner":live.profile_id = "read-successor"
			verify_live(c, live, c.baseline_serial + (1 if installed else 0), closed if installed else c.expected)
			var want: Array = c.baseline_disks if at <= 6 else [file_row(closed), file_row(c.expected if at <= 12 else closed), {"kind": "absent"}]
			check(triple(c.path) == want, "all read positions full disk oracle")
			var expected_reads: int = at if mode == "read_owner" and (at <= 6 or at in [10, 11, 12]) else (3 if at <= 3 else (6 if at <= 6 else (9 if at <= 9 else (12 if at <= 12 else 15))))
			check(c.s.reads == expected_reads and c.s.writes == (0 if at <= 6 else (1 if at <= 12 else 2)), "per-read CAS vs raw Session consecutive three")
			check(c.b._begin_fee_recovered_close().is_empty(), "unknown/owner never recreates continuation")
			done(c)
	for mode: String in ["path", "serial", "claim", "timer"]:
		for at: int in [1, 2]:
			var c: Dictionary = fixture("successor-%s-%d" % [mode, at])
			establish(c)
			var h: Dictionary = c.b._begin_fee_recovered_close()
			c.s.close_mode = mode;c.s.fault_write = at
			var result: Dictionary = c.b._persist_fee_recovered_close(h)
			var closed: Dictionary = closed_expected(c)
			check(not truth(result.get("ok")) and c.s.close_calls == at, "callback successor reached and stops continuation")
			verify_live(c, closed if at == 2 else c.expected, c.baseline_serial + (1 if at == 2 else 0) + (10 if mode == "serial" else 0), closed if at == 2 else c.expected)
			check(triple(c.path) == [file_row(closed), file_row(c.expected if at == 1 else closed), {"kind": "absent"}], "successor actual landed disk retained")
			if mode == "claim":check(is_same(c.b._fee_attempt_close_call, c.s.close_claim), "foreign claim not cleared")
			else:check(c.b._fee_attempt_close_call == null, "own stale claim released")
			done(c)
	for mode: String in ["loot_active", "envelope"]:
		var c: Dictionary = fixture("taken-proof-" + mode)
		establish(c)
		var h: Dictionary = c.b._begin_fee_recovered_close()
		var proof: Dictionary = {"private": RefCounted.new()}
		if mode == "loot_active":c.s._loot_failure_active = proof
		else:c.b._loot_resume_envelope = proof
		check(not truth(c.b._persist_fee_recovered_close(h).get("ok")) and c.s.writes == 0, "taken continuation also rejects loot")
		check(is_same(c.s._loot_failure_active if mode == "loot_active" else c.b._loot_resume_envelope, proof), "foreign loot proof retained")
		verify_live(c, c.expected, c.baseline_serial, c.expected)
		check(triple(c.path) == c.baseline_disks, "taken proof complete disk unchanged")
		done(c)
	for which: int in range(3):
		var c: Dictionary = fixture("disk-drift-%d" % which)
		establish(c)
		var h: Dictionary = c.b._begin_fee_recovered_close()
		var bytes: PackedByteArray = "foreign-disk-successor".to_utf8_buffer()
		put(c.path + ["", ".bak", ".tmp"][which], bytes)
		check(not truth(c.b._persist_fee_recovered_close(h).get("ok")) and c.s.writes == 0, "sealed disk drift refuses")
		var want: Array = c.baseline_disks.duplicate(true);want[which] = {"kind": "file", "bytes": bytes}
		check(triple(c.path) == want, "complete foreign disk preserved")
		verify_live(c, c.expected, c.baseline_serial, c.expected)
		done(c)
	var held: Dictionary = fixture("closed-nonidempotent", "closed_attempting")
	establish(held)
	check(held.b._begin_fee_recovered_close().is_empty() and held.s.writes == 0 and held.s.reads == 0, "closed attempting hold without raw Session migration")
	verify_live(held, held.expected, held.baseline_serial, held.expected)
	check(triple(held.path) == held.baseline_disks, "nonidempotent complete disk held")
	done(held)
	check(ordinal == 64, "exact bounded 64 fixtures")
	summary("FEE RECOVERED CLOSE")
