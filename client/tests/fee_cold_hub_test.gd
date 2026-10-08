extends "res://tests/support/fee_cold_harness.gd"
## UNRUN actual Accounts/ProfileHub open/login/logout/failed-target path.
const ProfileHub = preload("res://server/profile_hub.gd")
const SaveLock = preload("res://server/save_lock.gd")
class TestHub extends "res://server/profile_hub.gd":
	var gate := true
	var fail_baseline := false
	var loads := 0
	func fixed_clock()->int:return 1800000000
	func _new_profile_backend()->Backend:
		loads+=1
		var b=preload("res://tests/support/fee_cold_backend.gd").new()
		b.enabled=gate
		var rng:=RandomNumberGenerator.new();rng.seed=8317
		var s=preload("res://tests/support/fee_recovered_close_fault_session.gd").new(Callable(self,"fixed_clock"),rng)
		s.host=weakref(b);b.session=s
		s.battle_pets_hook=b._live_battle_pets;s.capture_entry_hook=b._capture_entry
		if fail_baseline:s.mode="no_write"
		return b
func run()->void:
	var production=Backend.new()
	check(not production._fee_cold_lifecycle_enabled(),"actual production default gate is false")
	production.free()
	var total_loads:=0
	for kind:String in ["default_off","fee_failure","foreign","legacy","loot","bad_target"]:
		ordinal+=1
		var dir:String="user://fee-cold-hub-%d-%d"%[Time.get_ticks_usec(),ordinal]
		check(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated Hub directory")
		var hub:=TestHub.new(dir+"/accounts.json")
		hub.tick=false;hub.backups=false;hub.share_dir=""
		hub.gate=kind!="default_off";hub.fail_baseline=kind=="fee_failure"
		check(hub.accounts.load_file(),"real accounts load")
		var created:Dictionary=hub.accounts.create("Owner","1234")
		check(truth(created.get("ok")),"real account creation")
		var path:String=hub.accounts.save_path(created.entry)
		kept.append(ProjectSettings.globalize_path(path))
		var rng:=RandomNumberGenerator.new();rng.seed=8317
		var source=Session.new(Callable(self,"clock"),rng)
		var before:Dictionary=source.snapshot()
		if kind not in ["legacy","loot"]:before.quest_auto_fee_lifecycle=journal()
		if kind=="loot":before.quest_loot=ledger(true)
		var loaded:Dictionary=before.duplicate(true)
		if kind=="loot":
			loaded.quest_loot.entries[STEP].open_span=false
			loaded.quest_loot.entries[STEP].settled_seq=3
			loaded.quest_loot.entries[STEP].revision=6
		var initial:PackedByteArray=JSON.stringify(before,"\t").to_utf8_buffer()
		put(path,initial)
		var state:Dictionary=marker(OLD) if kind in ["foreign","bad_target"] else marker()
		if kind in ["default_off","legacy"]:state={"sentinel":"legacy"}
		if kind=="loot":state={"quest_auto":{"identity":{"step_id":STEP}},"kind":"training","map_id":1000,"cell":[80,90]}
		var side:PackedByteArray=JSON.stringify(JSON.from_native(state)).to_utf8_buffer()
		var resume:String=ProfileHub.resume_file(path)
		put(resume,side)
		print("B3A_HUB BEGIN kind=%s path=%s"%[kind,path])
		var reply:Dictionary=hub.handle(71,{"type":"login","name":"Owner","pin":"1234"})
		check(truth(reply.get("ok")) and hub.profile_of(71)==created.entry.id,"fee failure cannot block actual login")
		var b=hub.backend_of(71)
		var expected:Dictionary=loaded.duplicate(true)
		if kind in ["foreign","bad_target"]:expected.quest_auto_fee_lifecycle.current.run_status="closed"
		check(b.session._profile==expected and b.last_saved_payload==JSON.stringify(expected),"independent full Hub live/cache")
		var wanted:Array=[{"kind":"file","bytes":initial},{"kind":"absent"},{"kind":"absent"}]
		if kind=="loot":wanted=[file_row(loaded),{"kind":"file","bytes":initial},{"kind":"absent"}]
		if kind in ["foreign","bad_target"]:wanted=[file_row(expected),file_row(expected),{"kind":"absent"}]
		check(triple(path)==wanted,"full Hub profile triple")
		var keep:bool=kind in ["fee_failure","foreign","bad_target"]
		check(image_of(resume)==({"kind":"file","bytes":side} if keep else {"kind":"absent"}) and image_of(resume+".tmp").kind=="absent","complete Hub sidecar pair")
		check(not b.quest_auto.running and b.automation.pending_resume.is_empty(),"legacy sentinel and loot companion do not execute")
		check(b.quest_save_serial==(0 if kind=="fee_failure" else (2 if kind in ["foreign","bad_target"] else 1)),"path-before-baseline vs original ordinary save serial")
		var same=b
		check(hub.open_profile(str(created.entry.id)).is_empty() and is_same(hub.backend_of(71),same) and hub.loads==1,"warm open has no new cold load/authority")
		if kind=="bad_target":
			var other:Dictionary=hub.accounts.create("Broken","4321")
			var bad_path:String=hub.accounts.save_path(other.entry)
			put(bad_path,"not-json".to_utf8_buffer())
			var binding:RefCounted=b._fee_bindings.get(71)
			var rejected:Dictionary=hub.handle(71,{"type":"login","name":"Broken","pin":"4321"})
			check(not truth(rejected.get("ok")) and is_same(hub.backend_of(71),same) and is_same(b._fee_bindings.get(71),binding),"original target-open failure preserves old connection and binding")
			check(image_of(bad_path).bytes=="not-json".to_utf8_buffer(),"bad target disk untouched")
		var logout:Dictionary=hub.handle(71,{"type":"logout"})
		check(truth(logout.get("ok")) and hub.profile_of(71).is_empty() and not b._fee_bindings.has(71),"existing logout remains unblocked and revokes connection")
		check(b.session._profile==expected and triple(path)==wanted,"logout does not erase pending anchor")
		if keep:check(image_of(resume).bytes==side,"logout preserves pending foreign marker")
		total_loads+=hub.loads
		for opened in hub.backends.values():SaveLock.release(opened.save_path)
		hub.free() # Disk artifacts remain, including malformed target and account files.
		print("B3A_HUB END kind=%s path=%s"%[kind,path])
	check(ordinal==6 and total_loads==7,"six independent hubs and seven actual loader attempts")
	summary("FEE COLD HUB")
