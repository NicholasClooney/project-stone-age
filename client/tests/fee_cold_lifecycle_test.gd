extends "res://tests/support/fee_cold_harness.gd"
## UNRUN complete profile + three profile files + two sidecar files oracles.
func run() -> void:
	for kind: String in ["absent","same","residual","foreign","mixed","orphan"]:
		var c: Dictionary = fixture("route-"+kind,"legacy" if kind=="orphan" else "pretty")
		set_sidecar(c,kind)
		check(c.b._prepare_fee_cold_open(),"fee routes away from legacy deletion")
		if kind=="orphan":
			check(c.s._profile==c.expected and triple(c.path)==c.disk_before and c.b.quest_save_serial==19,"orphan never creates profile journal")
		else:
			verify_live(c,closed_expected(c),21,closed_expected(c))
			check(triple(c.path)==closed_pair(c),"complete closed pair independent oracle")
		var expected: Array = preserved_side(c)
		if kind in ["absent","same"]:expected=[{"kind":"absent"},{"kind":"absent"}]
		if kind=="residual":expected=[{"kind":"file","bytes":JSON.stringify(JSON.from_native({"sentinel":{"keep":[1,"x"]}})).to_utf8_buffer()},{"kind":"absent"}]
		check(side_pair(c)==expected,"independent entire sidecar pair")
		check(c.b._fee_cold_lifecycle.protects_resume(c.b)==(kind not in ["absent","same"]),"pending distinct from profile completion")
		c.b.load_resume()
		check(side_pair(c)==expected and not c.b.quest_auto.running and c.b.automation.pending_resume.is_empty(),"no fee/mixed/orphan automatic execution or legacy delete")
		if kind=="foreign":
			var original: Dictionary=c.s._profile
			for key: String in ["owner","run","path","session"]:
				match key:
					"owner":c.s._profile=original.duplicate(true);c.s._profile.profile_id="successor"
					"run":c.s._profile=original.duplicate(true);c.s._profile.quest_auto_fee_lifecycle.current.run_id=OLD
					"path":c.b.save_path=c.path+".successor"
					"session":c.b.session=Session.new()
				check(not c.b._fee_cold_lifecycle.protects_resume(c.b),"file hold never transfers to a successor: "+key)
				c.b.session=c.s;c.s._profile=original;c.b.save_path=c.path
			check(c.b._fee_cold_lifecycle.protects_resume(c.b) and side_pair(c)==expected,"original scope remains independently protected")
		end_cold(c)
	for mode: String in ["baseline_no_write","baseline_after_false","close_after_false:1","close_after_false:2","close_owner:1","close_serial:2","closed_hold","profile_ref"]:
		var c: Dictionary = fixture(mode,"closed_attempting" if mode=="closed_hold" else "pretty")
		set_sidecar(c,"same")
		c.b.mode=mode
		if mode.begins_with("baseline_"):c.s.mode=mode.trim_prefix("baseline_")
		if mode=="profile_ref":c.s._profile=c.s._profile.duplicate(true)
		check(c.b._prepare_fee_cold_open(),"failure still routes without blocking login")
		var live: Dictionary=c.expected.duplicate(true)
		var cache: Dictionary=c.expected.duplicate(true)
		var serial: int=19
		var disk: Array=c.disk_before
		if mode not in ["baseline_no_write","profile_ref"]:
			serial=20;disk=[file_row(c.expected),c.disk_before[0],{"kind":"absent"}]
		if mode.begins_with("close_"):
			var closed: Dictionary=closed_expected(c)
			disk=[file_row(closed),file_row(closed if mode.ends_with(":2") else c.expected),{"kind":"absent"}]
			if mode=="close_owner:1":live.profile_id="read-successor"
			else:live=closed;cache=closed;serial=31 if mode=="close_serial:2" else 21
		verify_live(c,live,serial,cache)
		check(triple(c.path)==disk and side_pair(c)==preserved_side(c),"false/partial/owner full five-file oracle")
		check(c.b.side_writes==0 and c.b.side_removes==0,"no retire without genuine close capability")
		end_cold(c)
	for mode: String in ["remove_fail","remove_after_false","write_tmp_false","rename_fail","rename_after_false","read_unknown","read_owner","loot_callback","marker_successor","load_failed"]:
		var c: Dictionary=fixture(mode)
		var residual: bool=mode in ["write_tmp_false","rename_fail","rename_after_false"]
		set_sidecar(c,"residual" if residual else "same");c.b.mode=mode
		if mode=="load_failed":put(c.path+".bad","not-json".to_utf8_buffer())
		check(c.b._prepare_fee_cold_open(),"retire failure never blocks cold routing")
		var closed: Dictionary=closed_expected(c)
		var live: Dictionary=closed.duplicate(true)
		if mode=="read_owner":live.profile_id="read-successor"
		verify_live(c,live,21,closed)
		check(triple(c.path)==closed_pair(c),"retire errors never undo closed profile pair")
		var expected: Array=preserved_side(c)
		var bytes: PackedByteArray=JSON.stringify(JSON.from_native({"sentinel":{"keep":[1,"x"]}})).to_utf8_buffer()
		if mode=="marker_successor":
			var successor:Dictionary=marker();successor.quest_auto.identity.step_id="jewels:hunt:2760"
			expected=[{"kind":"file","bytes":JSON.stringify(JSON.from_native(successor)).to_utf8_buffer()},{"kind":"absent"}]
		if mode=="load_failed":check(c.b.failed_load_called and not c.b.failed_load_result and c.b.side_removes==0,"real failed reload revokes cold frame before delete without requiring owner mutation")
		if mode=="remove_after_false":expected=[{"kind":"absent"},{"kind":"absent"}]
		if mode=="rename_fail":expected[1]={"kind":"file","bytes":bytes}
		if mode=="rename_after_false":expected=[{"kind":"file","bytes":bytes},{"kind":"absent"}]
		check(side_pair(c)==expected,"actual write/remove and returned failure distinguished")
		if mode=="loot_callback":check(not c.s._loot_failure_active.is_empty() and c.b.side_removes==0,"mid-reader loot proof is retained and stops writer")
		if mode=="read_owner":check(c.b.side_removes==0,"mid-reader successor stops writer")
		end_cold(c)
	for mode: String in ["baseline_wrapper_false","close_wrapper_false","retire_wrapper_false","forge_baseline_ok","forge_close_ok","forge_retire_ok","nested"]:
		var c: Dictionary=fixture(mode);set_sidecar(c,"same");c.b.mode=mode
		check(c.b._prepare_fee_cold_open(),"private provenance routing")
		var forged: bool=mode.begins_with("forge_")
		var expected: Dictionary=c.expected if mode in ["forge_baseline_ok","forge_close_ok"] else closed_expected(c)
		var serial: int=19 if mode=="forge_baseline_ok" else (20 if mode=="forge_close_ok" else 21)
		verify_live(c,expected,serial,expected)
		var disk: Array=c.disk_before if mode=="forge_baseline_ok" else ([file_row(c.expected),c.disk_before[0],{"kind":"absent"}] if mode=="forge_close_ok" else closed_pair(c))
		check(triple(c.path)==disk,"independent wrapper full profile triple")
		check(side_pair(c)==(preserved_side(c) if forged else [{"kind":"absent"},{"kind":"absent"}]),"diagnostic cannot create or erase internal authorization")
		check(c.b._fee_attempt_close_call==null and c.b._fee_resume_sidecar_call==null and c.b._fee_attempt_writer_call==null,"skipped/forged wrapper releases only actual own handles")
		if not forged:
			check(c.b.wrong_retire_denied,"wrong consumer/call does not consume real retire authority")
			check(not c.b._fee_recovered_close_writer.retire_current(c.b,c.b._fee_cold_lifecycle,c.b.observed_retire) and c.b._fee_recovered_close_writer._retire.is_empty(),"ended private record cannot replay")
			check(c.b._begin_fee_recovered_close().is_empty(),"used baseline continuation cannot mint another close")
		if mode=="nested":check(c.b.nested_routed,"nested open refuses extra transaction")
		end_cold(c)
	for branch: String in ["periodic","shutdown_empty","shutdown_nonempty"]:
		var c: Dictionary=fixture(branch);set_sidecar(c,"foreign")
		check(c.b._prepare_fee_cold_open(),"foreign marker scoped hold")
		var before: Array=side_pair(c)
		if branch=="periodic":
			c.b.keep_resume_file()
			c.b._write_resume_file(c.path+".sidecar",{"overwrite":"forbidden"})
			c.b._remove_resume_file(c.path+".sidecar")
		else:
			if branch=="shutdown_nonempty":c.b.automation.pending_resume={"kind":"training","map_id":1000,"cell":[80,90]}
			c.b.record_shutdown()
		check(side_pair(c)==before,"real periodic/shutdown generic file branch preserves complete marker bytes")
		if branch=="shutdown_empty":check(c.b.generic_removes==1,"real shutdown delete branch reached")
		if branch=="shutdown_nonempty":check(c.b.generic_writes==1,"real shutdown write branch reached")
		var expected: Dictionary=closed_expected(c);expected.player.gold+=1
		c.s._profile.player.gold+=1
		check(c.b.save(),"manual profile save remains available")
		verify_live(c,expected,22,expected)
		check(triple(c.path)==[file_row(expected),file_row(closed_expected(c)),{"kind":"absent"}] and side_pair(c)==before,"manual save preserves anchor and unrelated sidecar")
		end_cold(c)
	check(ordinal==34,"exact 34 cold fixtures and one additional failed reload")
	summary("FEE COLD LIFECYCLE")
