extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## Internal closed-retire seam oracle. This test source is prepared only; it has
## not been parsed or run. No Stop caller, RPC, source authorization, or UI path.
const Journal = preload("res://server/fee_attempt_lifecycle.gd")
const FaultSession = preload("res://tests/support/fee_attempt_close_fault_session.gd")
const RUN := "11111111111111111111111111111111"
const OTHER_RUN := "44444444444444444444444444444444"
const ATTEMPT := "22222222222222222222222222222222"
const SOURCE := "closed-retire-test-source"
const OFFER := "closed-retire-test-offer"
const ITEM := 799001
const AMOUNT := 37
var checks:int=0
var failures:int=0
var aborted:bool=false
var serial:int=0
var retained_paths:Array[String]=[]
var setup_io_rows:Array[Dictionary]=[]

class ProbeBackend extends "res://server/backend.gd":
	var read_count:int=0
	var write_count:int=0
	var rename_count:int=0
	var remove_count:int=0
	var read_mutation_at:int=-1
	var read_mutation:String=""
	var read_override_at:int=-1
	var read_override:Dictionary={}
	var force_write_error:bool=false
	var force_rename_error:bool=false
	var force_remove_error:bool=false
	var nested_handle:Dictionary={}
	var nested_result:Dictionary={}
	var nested_on_write:bool=false
	func _fee_resume_io_read(path:String)->Dictionary:
		var result:Dictionary=super._fee_resume_io_read(path)
		read_count+=1
		if read_count==read_mutation_at:
			if read_mutation=="change_path":save_path="user://closed-retire-successor-%d.json" % Clock.ticks_usec()
			elif read_mutation=="change_serial":quest_save_serial+=1
			elif read_mutation=="replace_profile":session._profile=session._profile.duplicate(true)
			elif read_mutation=="change_profile_disk":
				var profile_file:=FileAccess.open(save_path,FileAccess.WRITE)
				if profile_file!=null:profile_file.store_string("test-only injected profile replacement")
				if profile_file!=null:profile_file.close()
		if read_count==read_override_at:return read_override.duplicate(true)
		return result
	func _fee_resume_io_write_tmp(payload:PackedByteArray)->Dictionary:
		write_count+=1
		if force_write_error:return {"ok":false,"stage":"injected_open_tmp","error":ERR_CANT_OPEN}
		var result:Dictionary=super._fee_resume_io_write_tmp(payload)
		if nested_on_write:
			nested_on_write=false
			nested_result=_commit_fee_resume_closed_retire_frame(nested_handle)
		return result
	func _fee_resume_io_rename()->int:
		rename_count+=1
		if force_rename_error:return ERR_CANT_OPEN
		return super._fee_resume_io_rename()
	func _fee_resume_io_remove()->int:
		remove_count+=1
		if force_remove_error:return ERR_CANT_OPEN
		return super._fee_resume_io_remove()

class ProbeSession extends "res://tests/support/fee_attempt_close_fault_session.gd":
	var profile_read_count:int=0
	var mutate_profile_read_at:int=-1
	var mutate_host:WeakRef
	var profile_read_override_at:int=-1
	var profile_read_override:Dictionary={}
	func _read_fee_attempt_file(path:String,expected:PackedByteArray)->Dictionary:
		var result:Dictionary=super._read_fee_attempt_file(path,expected)
		profile_read_count+=1
		if profile_read_count==mutate_profile_read_at:
			var host:Variant=mutate_host.get_ref() if mutate_host!=null else null
			if host is ProbeBackend:
				if host.read_mutation=="profile_change_path":host.save_path="user://closed-retire-profile-successor-%d.json" % Clock.ticks_usec()
				elif host.read_mutation=="profile_change_serial":host.quest_save_serial+=1
				elif host.read_mutation=="profile_change_owner":host.session._profile["profile_id"]="closed-retire-successor-owner"
		if profile_read_count==profile_read_override_at:return profile_read_override.duplicate(true)
		return result

func _initialize()->void:
	call_deferred("run")

func check(value:bool,label:String)->bool:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
	return value

func io_snapshot(host:ProbeBackend)->Dictionary:
	return {"read":host.read_count,"write":host.write_count,"rename":host.rename_count,"remove":host.remove_count}

func io_delta(host:ProbeBackend,before:Dictionary,key:String)->int:
	return int(host.get("%s_count" % key))-int(before.get(key,-999999))

func io_mutations_unchanged(host:ProbeBackend,before:Dictionary)->bool:
	return io_delta(host,before,"write")==0 and io_delta(host,before,"rename")==0 and io_delta(host,before,"remove")==0

func io_all_unchanged(host:ProbeBackend,before:Dictionary)->bool:
	return io_delta(host,before,"read")==0 and io_mutations_unchanged(host,before)

func record_setup_io(stage:String,host:ProbeBackend)->void:
	setup_io_rows.append({"stage":stage,"path":host.save_path,"counters":io_snapshot(host)})

func fail_setup(label:String,host:Node=null)->Dictionary:
	check(false,"fixture setup failed: "+label)
	if host!=null and is_instance_valid(host):host.free()
	aborted=true
	return {}

func raw(path:String)->Dictionary:
	var absolute:String=ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):return {"kind":"directory","bytes":PackedByteArray()}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:
		var open_error:int=FileAccess.get_open_error()
		return {"kind":"missing" if open_error==ERR_FILE_NOT_FOUND else "read_error","error":open_error,"bytes":PackedByteArray()}
	var length:int=file.get_length()
	if length<0 or length>16777216:
		file.close()
		return {"kind":"read_error","bytes":PackedByteArray()}
	var bytes:PackedByteArray=file.get_buffer(length)
	var read_error:int=file.get_error()
	file.close()
	return {"kind":"bytes" if read_error==OK and bytes.size()==length else "read_error","bytes":bytes,"length":length,"error":read_error}

func write_raw(path:String,bytes:PackedByteArray)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(bytes)
	file.flush()
	var ok:bool=file.get_error()==OK
	file.close()
	return ok

func native_bytes(value:Dictionary)->PackedByteArray:
	return JSON.stringify(JSON.from_native(value)).to_utf8_buffer()

func decode_native(path:String,backend:ProbeBackend)->Variant:
	var row:Dictionary=raw(path)
	if row.get("kind","")!="bytes":return null
	var parser:=JSON.new()
	if parser.parse(row.bytes.get_string_from_utf8())!=OK:return null
	var budget:Array=[0]
	if not backend._fee_native_sidecar_dictionary_safe(parser.data,0,budget):return null
	return JSON.to_native(parser.data,false)

func empty_unresolved_record(profile:Dictionary)->Dictionary:
	return Journal.empty_record(str(profile.get("profile_id","")),str(profile.get("character_id","")),RUN,true)

func set_live_identity(host:ProbeBackend)->void:
	host.quest_auto.identity.run_id=RUN
	host.quest_auto.identity.step_id="closed-retire-test"
	host.quest_auto.identity.revision=9

func source_resume_state(host:ProbeBackend)->Dictionary:
	# Use the actual Automation.resume_state and Backend._quest_resume_state
	# builders. hunt_running is a test-local normal resume fixture; cell remains
	# the original builder's untyped [x,y] integer Array, never Vector2i.
	host.automation.hunt_running=true
	host.automation.hunt_map=200
	host.automation.hunt_cell=Vector2i(7,11)
	host.automation.position_map=200
	host.automation.position_cell=Vector2i(7,11)
	var state:Dictionary=host._quest_resume_state(host.automation.resume_state())
	if state.is_empty():return {}
	var typed_probe:Array[String]=["turn:player","turn:pet"]
	state["typed_probe"]=typed_probe
	state[StringName("native_probe")]=["preserve",3]
	# This battle-shaped payload is synthetic and tests opaque-key preservation only;
	# it is not a BattleSession/Backend-generated recoverable battle checkpoint.
	state["battle"]={"test_fixture_only":true,"battle_id":"fixture-battle","cell":[2,5]}
	return state

func start_active_fixture(label:String,write_source_sidecar:bool)->Dictionary:
	serial+=1
	var host:ProbeBackend=ProbeBackend.new()
	if host==null:return fail_setup(label+": Backend subclass construction")
	host.set_process(false)
	host.save_path="user://closed-retire-%d-%03d-%s.json" % [Clock.ticks_usec(),serial,label]
	var session:ProbeSession=ProbeSession.new() as ProbeSession
	if session==null:return fail_setup(label+": session construction",host)
	session.bind_host(host)
	session.mutate_host=weakref(host)
	host.session=session
	session.battle_pets_hook=host._live_battle_pets
	session.capture_entry_hook=host._capture_entry
	var owner:Dictionary={"profile_id":str(session._profile.get("profile_id","")),"character_id":str(session._profile.get("character_id",""))}
	var record:Dictionary=empty_unresolved_record(session._profile)
	if record.is_empty() or not Journal.valid(record):return fail_setup(label+": independent active journal valid",host)
	session._profile["quest_auto_fee_lifecycle"]=record.duplicate(true)
	var absolute:String=ProjectSettings.globalize_path(host.save_path)
	retained_paths.append(absolute)
	for suffix:String in ["",".bak",".tmp",".resume.json",".resume.json.tmp"]:
		if FileAccess.file_exists(absolute+suffix) or DirAccess.dir_exists_absolute(absolute+suffix):return fail_setup(label+": unique profile/sidecar paths absent",host)
	if not session.save_game(host.save_path):return fail_setup(label+": original save_game writes initial profile",host)
	host.last_saved_payload=JSON.stringify(session._profile)
	host.quest_save_serial=71
	host.quest_auto.running=true
	host.quest_auto.internal=true
	set_live_identity(host)
	var source_state:Dictionary=source_resume_state(host)
	var source_cell:Variant=source_state.get("cell",null)
	var source_hunt:Variant=source_state.get("hunt",null)
	var source_quest:Variant=source_state.get("quest_auto",null)
	var source_binding:Variant=source_state.get("fee_attempt_binding",null)
	var source_identity:Variant=source_quest.get("identity",null) if source_quest is Dictionary else null
	var expected_binding:Dictionary={"owner":owner.duplicate(true),"run_id":RUN}
	if source_state.is_empty() or not source_cell is Array:return fail_setup(label+": original resume builder cell is an integer Array",host)
	var source_cell_array:Array=source_cell
	if source_cell_array.size()!=2 or not source_cell_array[0] is int or not source_cell_array[1] is int:return fail_setup(label+": original resume builder cell contains exactly two native integers",host)
	if not source_hunt is Dictionary or not source_quest is Dictionary or not source_identity is Dictionary or source_identity.get("run_id",null)!=RUN or source_binding!=expected_binding:return fail_setup(label+": original builders project hunt, quest identity and authoritative fee binding",host)
	if write_source_sidecar:
		host._write_resume_file(host._resume_file(),source_state)
		var written:Dictionary=raw(host._resume_file())
		if written.get("kind","")!="bytes" or written.bytes!=native_bytes(source_state):return fail_setup(label+": original resume writer stores source state",host)
	host.automation.hunt_running=false
	var source_typed:Variant=source_state.get("typed_probe",null)
	if not source_typed is Array:return fail_setup(label+": typed resume fixture array exists",host)
	record_setup_io("active_fixture_ready",host)
	return {"ready":true,"host":host,"session":session,"owner":owner,"active_record":record.duplicate(true),"source_state":source_state,"run_id":RUN,"path":host.save_path,"sidecar_path":host._resume_file()}

func close_active_fixture(fx:Dictionary)->bool:
	var host:ProbeBackend=fx.host
	var session:ProbeSession=fx.session
	var prior:Dictionary=session._profile.get("quest_auto_fee_lifecycle",{}).duplicate(true)
	var transition:Dictionary=Journal.close_run(prior,RUN)
	var expected:Dictionary=prior.duplicate(true)
	expected.current.run_status="closed"
	if not transition.get("ok",false) or transition.get("candidate",{})!=expected or not Journal.valid(expected):return check(false,"Journal.close_run exact independent closed candidate")
	var candidate:Dictionary=session._profile.duplicate(true)
	candidate["quest_auto_fee_lifecycle"]=expected.duplicate(true)
	var stopped:Dictionary=host.quest_auto.identity.checkpoint()
	host.quest_auto.identity.invalidate()
	host.quest_auto.running=false
	host.quest_auto.internal=false
	host.quest_auto.source_frame=null
	var handle:Dictionary=host._begin_fee_attempt_close_frame(stopped,candidate)
	if handle.is_empty():return check(false,"real close-frame preparation accepted")
	var result:Dictionary=host._persist_fee_attempt_close_pair(handle)
	var p:Dictionary=raw(host.save_path)
	var b:Dictionary=raw(host.save_path+".bak")
	var t:Dictionary=raw(host.save_path+".tmp")
	var ok:bool=result.get("ok",false) is bool and result.get("ok",false) and p.get("kind","")=="bytes" and b.get("kind","")=="bytes" and t.get("kind","")=="missing" and p.bytes==JSON.stringify(candidate).to_utf8_buffer() and b.bytes==p.bytes and session._profile==candidate
	if not check(ok,"original close pair writer creates exact closed profile before retire fixture"):return false
	return true

func prepare_actual_sidecar_frame(fx:Dictionary)->Dictionary:
	var state:Dictionary=fx.source_state.duplicate(true)
	var candidate:Dictionary=state.duplicate(true)
	candidate.erase("quest_auto")
	var prepared:Dictionary=fx.host._begin_fee_resume_sidecar_frame("write_fence",candidate)
	return prepared

func build_attempt_candidate(fx:Dictionary)->Dictionary:
	var session:ProbeSession=fx.session
	var prior:Dictionary=session._profile.get("quest_auto_fee_lifecycle",{}).duplicate(true)
	var transition:Dictionary=Journal.begin_attempt(prior,RUN,ATTEMPT,SOURCE,OFFER,ITEM,AMOUNT,100)
	if not transition.get("ok",false) or not Journal.valid(transition.get("candidate",{})):return {}
	var candidate:Dictionary=session._profile.duplicate(true)
	candidate["quest_auto_fee_lifecycle"]=transition.candidate.duplicate(true)
	return candidate

func build_attempt_candidate_from_record(fx:Dictionary,prior:Dictionary)->Dictionary:
	var transition:Dictionary=Journal.begin_attempt(prior,RUN,ATTEMPT,SOURCE,OFFER,ITEM,AMOUNT,100)
	if not transition.get("ok",false) or not Journal.valid(transition.get("candidate",{})):return {}
	var candidate:Dictionary=fx.session._profile.duplicate(true)
	candidate["quest_auto_fee_lifecycle"]=transition.candidate.duplicate(true)
	return candidate

func prepare_attempt_frame(fx:Dictionary)->Dictionary:
	var host:ProbeBackend=fx.host
	var candidate:Dictionary=build_attempt_candidate(fx)
	if candidate.is_empty():
		check(false,"original pure attempt transition yields valid candidate")
		return {}
	host._depth+=1 # Test-local trusted-dispatch depth; not a route/source authorization.
	var frame:Dictionary=host._begin_fee_attempt_writer_frame(candidate)
	host._depth-=1
	return frame

func prepare_close_frame(fx:Dictionary)->Dictionary:
	var host:ProbeBackend=fx.host
	var session:ProbeSession=fx.session
	var prior:Dictionary=session._profile.get("quest_auto_fee_lifecycle",{}).duplicate(true)
	var transition:Dictionary=Journal.close_run(prior,RUN)
	if not transition.get("ok",false):return {}
	var candidate:Dictionary=session._profile.duplicate(true)
	candidate["quest_auto_fee_lifecycle"]=transition.candidate.duplicate(true)
	var stopped:Dictionary=host.quest_auto.identity.checkpoint()
	host.quest_auto.identity.invalidate()
	host.quest_auto.running=false
	host.quest_auto.internal=false
	host.quest_auto.source_frame=null
	return host._begin_fee_attempt_close_frame(stopped,candidate)

func make_closed_fixture(label:String)->Dictionary:
	var fx:Dictionary=start_active_fixture(label,true)
	if fx.is_empty():return {}
	var source:Dictionary=fx.source_state
	var ordinary:Dictionary=prepare_actual_sidecar_frame(fx)
	if not ordinary.get("ok",false):check(false,label+": actual ordinary sidecar prepare");finish_fixture(fx);return {}
	var committed:Dictionary=fx.host._commit_fee_resume_sidecar_frame({"call":ordinary.get("call")})
	if not committed.get("ok",false):check(false,label+": actual ordinary sidecar write/rename");finish_fixture(fx);return {}
	# The retirement fixture is restored to the original builder output so both
	# quest_auto intent and fee binding are attributable to the closed run.
	fx.host._write_resume_file(fx.sidecar_path,source)
	var sidecar:Dictionary=raw(fx.sidecar_path)
	if sidecar.get("kind","")!="bytes" or sidecar.bytes!=native_bytes(source):check(false,label+": original writer restores source sidecar");finish_fixture(fx);return {}
	if not close_active_fixture(fx):finish_fixture(fx);return {}
	fx.sidecar_state=source.duplicate(true)
	fx.expected_sidecar_candidate=source.duplicate(true)
	fx.expected_sidecar_candidate.erase("quest_auto")
	fx.expected_sidecar_candidate.erase("fee_attempt_binding")
	record_setup_io("closed_fixture_ready",fx.host)
	return fx

func make_closed_no_sidecar_fixture(label:String)->Dictionary:
	var fx:Dictionary=start_active_fixture(label,false)
	if fx.is_empty():return {}
	if raw(fx.sidecar_path).get("kind","")!="missing":check(false,label+": sidecar is initially absent");finish_fixture(fx);return {}
	if not close_active_fixture(fx):finish_fixture(fx);return {}
	record_setup_io("closed_no_sidecar_ready",fx.host)
	return fx

func begin_retire(fx:Dictionary,expected_read_delta:int=4)->Dictionary:
	var before:Dictionary=io_snapshot(fx.host)
	var result:Dictionary=fx.host._begin_fee_resume_closed_retire_frame()
	check(io_delta(fx.host,before,"read")==expected_read_delta and io_mutations_unchanged(fx.host,before),"retire begin has exact %d-read and zero-mutation delta" % expected_read_delta)
	return result

func finish_fixture(fx:Dictionary)->void:
	var host:Variant=fx.get("host",null)
	if host is Node and is_instance_valid(host):host.free()

func case_profile_frame_identity()->void:
	# A prepared frame must retain the live profile identity while freezing an
	# independent, value-equal profile snapshot.
	var valid_fx:Dictionary=make_closed_fixture("frame-identity-valid")
	if valid_fx.is_empty():return
	var valid_begin:Dictionary=begin_retire(valid_fx)
	if not valid_begin.get("ok",false):check(false,"identity fixture prepares a closed-retire frame");finish_fixture(valid_fx);return
	var valid_frame:Dictionary=valid_fx.host._fee_resume_sidecar_frame
	var valid_counts:Dictionary=io_snapshot(valid_fx.host)
	var valid_profile_ref:Variant=valid_frame.get("profile_ref",null)
	var valid_profile_value:Variant=valid_frame.get("profile",null)
	var valid_identity:bool=valid_profile_ref is Dictionary and valid_profile_value is Dictionary and is_same(valid_fx.session._profile,valid_profile_ref) and not is_same(valid_fx.session._profile,valid_profile_value) and valid_fx.session._profile==valid_profile_value
	check(valid_identity and valid_fx.host._fee_resume_closed_retire_frame_current(valid_frame),"prepared frame preserves live profile identity and equal frozen values")
	check(io_all_unchanged(valid_fx.host,valid_counts),"frame-current identity check performs no file IO")
	finish_fixture(valid_fx)

	# Replacing the live profile with an equal-but-distinct Dictionary must fail
	# the identity fence, release only its own claim, and perform no IO.
	var equal_fx:Dictionary=make_closed_fixture("frame-identity-equal-replacement")
	if equal_fx.is_empty():return
	var equal_begin:Dictionary=begin_retire(equal_fx)
	if not equal_begin.get("ok",false):check(false,"equal replacement fixture prepares");finish_fixture(equal_fx);return
	var equal_frame:Dictionary=equal_fx.host._fee_resume_sidecar_frame
	var equal_handle:Dictionary={"call":equal_begin.get("call")}
	var equal_replacement:Dictionary=equal_fx.session._profile.duplicate(true)
	var equal_counts:Dictionary=io_snapshot(equal_fx.host)
	equal_fx.session._profile=equal_replacement
	check(equal_replacement==equal_frame.get("profile",{}) and not is_same(equal_replacement,equal_frame.get("profile_ref")),"replacement is value-equal but a distinct profile object")
	check(not equal_fx.host._fee_resume_closed_retire_frame_current(equal_frame),"equal-but-distinct profile object invalidates the frame")
	var equal_result:Dictionary=equal_fx.host._commit_fee_resume_closed_retire_frame(equal_handle)
	check(not equal_result.get("ok",false) and equal_result.get("stage","")=="stale_before_io_after_claim" and io_all_unchanged(equal_fx.host,equal_counts),"equal replacement is refused before IO")
	check(equal_fx.host._fee_resume_sidecar_call==null and equal_fx.host._fee_resume_sidecar_frame.is_empty(),"stale equal-replacement handle releases only its own claim")
	finish_fixture(equal_fx)

	# Mutating the original Dictionary retains identity but changes its frozen
	# contents; it too must be refused before IO.
	var value_fx:Dictionary=make_closed_fixture("frame-identity-value-mutation")
	if value_fx.is_empty():return
	var value_begin:Dictionary=begin_retire(value_fx)
	if not value_begin.get("ok",false):check(false,"value mutation fixture prepares");finish_fixture(value_fx);return
	var value_frame:Dictionary=value_fx.host._fee_resume_sidecar_frame
	var value_handle:Dictionary={"call":value_begin.get("call")}
	var value_counts:Dictionary=io_snapshot(value_fx.host)
	value_fx.session._profile["profile_id"]="closed-retire-mutated-owner"
	check(is_same(value_fx.session._profile,value_frame.get("profile_ref")) and value_fx.session._profile!=value_frame.get("profile",{}),"original object mutation preserves identity but changes frozen values")
	check(not value_fx.host._fee_resume_closed_retire_frame_current(value_frame),"mutated original profile values invalidate the frame")
	var value_result:Dictionary=value_fx.host._commit_fee_resume_closed_retire_frame(value_handle)
	check(not value_result.get("ok",false) and value_result.get("stage","")=="stale_before_io_after_claim" and io_all_unchanged(value_fx.host,value_counts),"mutated original profile is refused before IO")
	finish_fixture(value_fx)

	# After the old rightful claim has been aborted, its handle must not clear a
	# later successor claim on the same backend.
	var successor_fx:Dictionary=make_closed_fixture("frame-identity-successor-claim")
	if successor_fx.is_empty():return
	var old_begin:Dictionary=begin_retire(successor_fx)
	if not old_begin.get("ok",false):check(false,"old identity handle prepares");finish_fixture(successor_fx);return
	var old_frame:Dictionary=successor_fx.host._fee_resume_sidecar_frame
	var old_handle:Dictionary={"call":old_begin.get("call")}
	var original_profile_ref:Dictionary=successor_fx.session._profile
	successor_fx.session._profile=original_profile_ref.duplicate(true)
	var old_abort_counts:Dictionary=io_snapshot(successor_fx.host)
	var old_abort:Dictionary=successor_fx.host._commit_fee_resume_closed_retire_frame(old_handle)
	check(not old_abort.get("ok",false) and io_all_unchanged(successor_fx.host,old_abort_counts),"old stale identity frame aborts without IO")
	check(successor_fx.host._fee_resume_sidecar_call==null and successor_fx.host._fee_resume_sidecar_frame.is_empty(),"old rightful claim is released")
	successor_fx.session._profile=original_profile_ref
	var successor:Dictionary=begin_retire(successor_fx)
	if not successor.get("ok",false):check(false,"successor retire claim prepares after old abort");finish_fixture(successor_fx);return
	var successor_handle:Dictionary={"call":successor.get("call")}
	var successor_frame:Dictionary=successor_fx.host._fee_resume_sidecar_frame
	var replay_counts:Dictionary=io_snapshot(successor_fx.host)
	var old_replay:Dictionary=successor_fx.host._commit_fee_resume_closed_retire_frame(old_handle)
	check(not old_replay.get("ok",false) and old_replay.get("stage","")=="invalid_handle" and io_all_unchanged(successor_fx.host,replay_counts),"old handle replay cannot read or mutate successor files")
	check(is_same(successor_fx.host._fee_resume_sidecar_call,successor_handle.get("call")) and successor_fx.host._fee_resume_sidecar_frame_current(successor_frame),"old handle cannot clear the successor claim")
	finish_fixture(successor_fx)

func case_success_composite()->void:
	var fx:Dictionary=make_closed_fixture("success-composite")
	if fx.is_empty():return
	var source:Dictionary=fx.sidecar_state
	var old_primary:Dictionary=raw(fx.path)
	var old_backup:Dictionary=raw(fx.path+".bak")
	var old_sidecar:Dictionary=raw(fx.sidecar_path)
	var old_tmp:Dictionary=raw(fx.sidecar_path+".tmp")
	var begin_counts_before:Dictionary=io_snapshot(fx.host)
	var begun:Dictionary=begin_retire(fx)
	if not begun.get("ok",false):check(false,"closed matching source sidecar begins retire");finish_fixture(fx);return
	check(io_delta(fx.host,begin_counts_before,"read")==4 and io_mutations_unchanged(fx.host,begin_counts_before),"retire begin reads target/tmp twice and performs no mutation")
	var fake_counts_before:Dictionary=io_snapshot(fx.host)
	var fake:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({})
	check(not fake.get("ok",false) and io_all_unchanged(fx.host,fake_counts_before),"empty/replayed-shaped handle cannot consume a live retire claim or touch files")
	var wrong_counts_before:Dictionary=io_snapshot(fx.host)
	var wrong:Dictionary=fx.host._commit_fee_resume_sidecar_frame({"call":begun.get("call")})
	check(not wrong.get("ok",false) and io_all_unchanged(fx.host,wrong_counts_before),"ordinary sidecar commit refuses retire action without file IO")
	var result_counts_before:Dictionary=io_snapshot(fx.host)
	var result:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":begun.get("call")})
	var result_counts_after:Dictionary=io_snapshot(fx.host)
	var result_count_delta:Dictionary={
		"read":int(result_counts_after.get("read",-1))-int(result_counts_before.get("read",-1)),
		"write":int(result_counts_after.get("write",-1))-int(result_counts_before.get("write",-1)),
		"rename":int(result_counts_after.get("rename",-1))-int(result_counts_before.get("rename",-1)),
		"remove":int(result_counts_after.get("remove",-1))-int(result_counts_before.get("remove",-1))
	}
	var result_count_checks:Dictionary={
		"read_13":result_count_delta.read==13,
		"write_1":result_count_delta.write==1,
		"rename_1":result_count_delta.rename==1,
		"remove_0":result_count_delta.remove==0
	}
	var result_fields:Dictionary={}
	for result_key:String in ["ok","stage","operation_attempted","operation_completed","operation_error","sidecar_persisted","target_state","sidecar_exists","temporary_clear","profile_pair_state"]:
		var result_value:Variant=result.get(result_key,null)
		if result_value is String:result_fields[result_key]=result_value.substr(0,128)
		elif result_value is bool or result_value is int:result_fields[result_key]=result_value
		else:result_fields[result_key]="<missing-or-nonscalar>"
	print("CLOSED RETIRE COMMIT DIAGNOSTIC: "+JSON.stringify({"before":result_counts_before,"after":result_counts_after,"delta":result_count_delta,"component_checks":result_count_checks,"result":result_fields}))
	check(io_delta(fx.host,result_counts_before,"read")==13 and io_delta(fx.host,result_counts_before,"write")==1 and io_delta(fx.host,result_counts_before,"rename")==1 and io_delta(fx.host,result_counts_before,"remove")==0,"successful rewrite has exact 13-read/1-write/1-rename delta")
	var expected:Dictionary=source.duplicate(true)
	expected.erase("quest_auto")
	expected.erase("fee_attempt_binding")
	var actual:Variant=decode_native(fx.sidecar_path,fx.host)
	var final_primary:Dictionary=raw(fx.path)
	var final_backup:Dictionary=raw(fx.path+".bak")
	var final_sidecar:Dictionary=raw(fx.sidecar_path)
	var final_tmp:Dictionary=raw(fx.sidecar_path+".tmp")
	check(result.get("ok",false) is bool and result.get("ok",false),"retire reports successful operation and target facts")
	check(actual is Dictionary and actual==expected,"all source resume keys/values remain; only quest intent and fee binding removed")
	check(actual is Dictionary and actual.get("cell",null) is Array and actual.get("battle",null)==source.get("battle",null),"original cell array and nested recovery state are retained")
	var typed_value:Variant=actual.get("typed_probe",null) if actual is Dictionary else null
	var typed_ok:bool=false
	if typed_value is Array:
		var typed_array:Array=typed_value
		typed_ok=typed_array.is_typed() and typed_array.get_typed_builtin()==TYPE_STRING and typed_array.get_typed_class_name().is_empty() and typed_array.get_typed_script()==null
	check(actual is Dictionary and typed_ok and actual.has(StringName("native_probe")) and actual[StringName("native_probe")]==source[StringName("native_probe")],"typed Array[String] and StringName key/value survive native decode")
	check(final_primary==old_primary and final_backup==old_backup and final_tmp.get("kind","")=="missing","profile pair and sidecar tmp facts are unchanged/clear")
	check(old_sidecar.get("kind","")=="bytes" and final_sidecar.get("kind","")=="bytes" and old_tmp.get("kind","")=="missing","retirement rewrites nonempty source sidecar rather than deleting profile")
	check(final_sidecar.get("kind","")=="bytes" and final_sidecar.bytes==native_bytes(expected),"independent full native envelope serialization matches the resulting sidecar bytes")
	var replay_counts_before:Dictionary=io_snapshot(fx.host)
	var replay:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":begun.get("call")})
	check(not replay.get("ok",false) and replay.get("stage","")=="invalid_handle" and io_all_unchanged(fx.host,replay_counts_before),"retired handle cannot replay or touch files after rightful commit")
	finish_fixture(fx)

func case_missing_and_foreign()->void:
	var absent_fx:Dictionary=make_closed_no_sidecar_fixture("verified-absence")
	if absent_fx.is_empty():return
	var absent_before:Dictionary=raw(absent_fx.sidecar_path)
	var absent_begin_counts:Dictionary=io_snapshot(absent_fx.host)
	var absent_begin:Dictionary=begin_retire(absent_fx)
	if not absent_begin.get("ok",false):check(false,"physically verified absence is a valid idempotent retire target");finish_fixture(absent_fx);return
	check(io_delta(absent_fx.host,absent_begin_counts,"read")==4 and io_mutations_unchanged(absent_fx.host,absent_begin_counts),"absent fixture begin reads target/tmp twice without mutation")
	var absent_commit_counts:Dictionary=io_snapshot(absent_fx.host)
	var absent_result:Dictionary=absent_fx.host._commit_fee_resume_closed_retire_frame({"call":absent_begin.get("call")})
	check(io_delta(absent_fx.host,absent_commit_counts,"read")==8 and io_mutations_unchanged(absent_fx.host,absent_commit_counts),"verified absent commit performs eight observations and no mutation")
	check(absent_before.get("kind","")=="missing" and absent_result.get("ok",false) is bool and absent_result.get("ok",false),"absent sidecar completes without fabricating a remove")
	check(not absent_result.get("operation_attempted",true) and absent_result.get("operation_completed",false) and raw(absent_fx.sidecar_path).get("kind","")=="missing","verified absence remains absent with operation_attempted=false")
	finish_fixture(absent_fx)
	var standalone_fx:Dictionary=make_closed_fixture("standalone-binding")
	if standalone_fx.is_empty():return
	var exact_binding:Dictionary={"owner":standalone_fx.owner.duplicate(true),"run_id":RUN}
	if not write_raw(standalone_fx.sidecar_path,native_bytes({"fee_attempt_binding":exact_binding})):
		check(false,"standalone binding sidecar written");finish_fixture(standalone_fx);return
	var standalone_before:Dictionary=raw(standalone_fx.sidecar_path)
	var standalone_begin_counts:Dictionary=io_snapshot(standalone_fx.host)
	var standalone_frame:Dictionary=begin_retire(standalone_fx)
	if not standalone_frame.get("ok",false):check(false,"exact standalone binding is attributable");finish_fixture(standalone_fx);return
	check(io_delta(standalone_fx.host,standalone_begin_counts,"read")==4 and io_mutations_unchanged(standalone_fx.host,standalone_begin_counts),"standalone binding begin has exact four-read/no-mutation delta")
	var standalone_counts_before:Dictionary=io_snapshot(standalone_fx.host)
	var standalone_result:Dictionary=standalone_fx.host._commit_fee_resume_closed_retire_frame({"call":standalone_frame.get("call")})
	check(io_delta(standalone_fx.host,standalone_counts_before,"read")==12,"standalone binding remove observes exactly twelve sidecar rows")
	check(standalone_result.get("ok",false) is bool and standalone_result.get("ok",false) and io_delta(standalone_fx.host,standalone_counts_before,"remove")==1 and io_delta(standalone_fx.host,standalone_counts_before,"rename")==0 and io_delta(standalone_fx.host,standalone_counts_before,"write")==0,"binding-only sidecar remove has exact one-call mutation deltas")
	check(standalone_before.get("kind","")=="bytes" and raw(standalone_fx.sidecar_path).get("kind","")=="missing","standalone binding is physically absent after successful remove")
	var repeat_frame:Dictionary=begin_retire(standalone_fx)
	var repeat_counts_before:Dictionary=io_snapshot(standalone_fx.host)
	var repeat_result:Dictionary=standalone_fx.host._commit_fee_resume_closed_retire_frame({"call":repeat_frame.get("call")}) if repeat_frame.get("ok",false) else {}
	check(repeat_frame.get("ok",false) and repeat_result.get("ok",false) is bool and repeat_result.get("ok",false) and not repeat_result.get("operation_attempted",true),"verified post-retire absence is safely idempotent")
	check(io_mutations_unchanged(standalone_fx.host,repeat_counts_before),"idempotent absent commit adds no write/rename/remove")
	finish_fixture(standalone_fx)
	for variant:String in ["markerless","foreign_run","foreign_owner","foreign_quest","malformed","temp"]:
		var fx:Dictionary=make_closed_fixture("reject-"+variant)
		if fx.is_empty():return
		var path:String=fx.sidecar_path
		if variant=="markerless":
			var markerless_state:Dictionary=fx.sidecar_state.duplicate(true)
			markerless_state.erase("quest_auto");markerless_state.erase("fee_attempt_binding")
			if not write_raw(path,native_bytes(markerless_state)):check(false,"markerless fixture written");finish_fixture(fx);return
		elif variant=="foreign_run":
			var foreign_run_state:Dictionary=fx.sidecar_state.duplicate(true)
			foreign_run_state.fee_attempt_binding.run_id=OTHER_RUN
			if not write_raw(path,native_bytes(foreign_run_state)):check(false,"foreign run fixture written");finish_fixture(fx);return
		elif variant=="foreign_owner":
			var foreign_owner_state:Dictionary=fx.sidecar_state.duplicate(true)
			foreign_owner_state.fee_attempt_binding.owner.profile_id="another-profile"
			if not write_raw(path,native_bytes(foreign_owner_state)):check(false,"foreign owner fixture written");finish_fixture(fx);return
		elif variant=="foreign_quest":
			var foreign_quest_state:Dictionary=fx.sidecar_state.duplicate(true)
			foreign_quest_state.quest_auto.identity.run_id=OTHER_RUN
			if not write_raw(path,native_bytes(foreign_quest_state)):check(false,"foreign quest fixture written");finish_fixture(fx);return
		elif variant=="malformed":
			if not write_raw(path,"{}".to_utf8_buffer()):check(false,"malformed fixture written");finish_fixture(fx);return
		elif variant=="temp":
			if not write_raw(path+".tmp","occupied".to_utf8_buffer()):check(false,"occupied tmp fixture written");finish_fixture(fx);return
		var before:Dictionary=raw(path)
		var before_tmp:Dictionary=raw(path+".tmp")
		var counts_before:Dictionary=io_snapshot(fx.host)
		var result:Dictionary=begin_retire(fx)
		check(not result.get("ok",false) and io_delta(fx.host,counts_before,"read")==4,variant+" sidecar state is rejected after four bounded observations")
		check(io_mutations_unchanged(fx.host,counts_before),variant+" begin rejection has zero mutation delta")
		check(raw(path)==before and raw(path+".tmp")==before_tmp,variant+" preserves complete target/tmp facts")
		finish_fixture(fx)

func case_real_claim_pairwise()->void:
	# Ordinary sidecar frame is prepared from Backend's actual resume builders.
	var fx:Dictionary=start_active_fixture("ordinary-claim",true)
	if fx.is_empty():return
	var ordinary_stopped_identity:Dictionary=fx.host.quest_auto.identity.checkpoint()
	fx.host.quest_auto.identity.invalidate()
	fx.host.quest_auto.running=false
	fx.host.quest_auto.internal=false
	fx.host.quest_auto.source_frame=null
	var ordinary_close_transition:Dictionary=Journal.close_run(fx.active_record,RUN)
	if not ordinary_close_transition.get("ok",false):check(false,"ordinary claim fixture has independently valid close transition");finish_fixture(fx);return
	var ordinary_close_candidate:Dictionary=fx.session._profile.duplicate(true)
	ordinary_close_candidate["quest_auto_fee_lifecycle"]=ordinary_close_transition.candidate.duplicate(true)
	var ordinary_begin_counts:Dictionary=io_snapshot(fx.host)
	var ordinary:Dictionary=prepare_actual_sidecar_frame(fx)
	if not ordinary.get("ok",false):check(false,"actual ordinary sidecar frame prepares");finish_fixture(fx);return
	var ordinary_after_counts:Dictionary=io_snapshot(fx.host)
	var ordinary_count_delta:Dictionary={
		"read":int(ordinary_after_counts.get("read",-999999))-int(ordinary_begin_counts.get("read",-999999)),
		"write":int(ordinary_after_counts.get("write",-999999))-int(ordinary_begin_counts.get("write",-999999)),
		"rename":int(ordinary_after_counts.get("rename",-999999))-int(ordinary_begin_counts.get("rename",-999999)),
		"remove":int(ordinary_after_counts.get("remove",-999999))-int(ordinary_begin_counts.get("remove",-999999))
	}
	var ordinary_read_total_ok:bool=ordinary_count_delta.read==3
	var ordinary_mutation_free:bool=ordinary_count_delta.write==0 and ordinary_count_delta.rename==0 and ordinary_count_delta.remove==0
	var ordinary_result_scalars:Dictionary={}
	for ordinary_key:String in ["ok","stage","operation_attempted","operation_completed","operation_error","sidecar_persisted","target_state","sidecar_exists","temporary_clear","temporary_exists"]:
		if not ordinary.has(ordinary_key):continue
		var ordinary_value:Variant=ordinary[ordinary_key]
		if ordinary_value is String:ordinary_result_scalars[ordinary_key]=ordinary_value.substr(0,128)
		elif ordinary_value is bool or ordinary_value is int or ordinary_value is float:ordinary_result_scalars[ordinary_key]=ordinary_value
		else:ordinary_result_scalars[ordinary_key]="<non-scalar>"
	print("ORDINARY SIDECAR BEGIN DIAGNOSTIC: "+JSON.stringify({"before":ordinary_begin_counts,"after":ordinary_after_counts,"delta":ordinary_count_delta,"read_total_ok":ordinary_read_total_ok,"read_accounting":"target pre-read + tmp pre-read + prepared-fact target reread","mutation_free":ordinary_mutation_free,"result":ordinary_result_scalars}))
	check(io_delta(fx.host,ordinary_begin_counts,"read")==3 and io_mutations_unchanged(fx.host,ordinary_begin_counts),"ordinary sidecar begin reads target/tmp plus prepared-fact target once with no mutation")
	var pair_counts_before:Dictionary=io_snapshot(fx.host)
	var retire_while_ordinary:Dictionary=fx.host._begin_fee_resume_closed_retire_frame()
	check(not retire_while_ordinary.get("ok",false) and io_delta(fx.host,pair_counts_before,"read")==0 and io_mutations_unchanged(fx.host,pair_counts_before),"ordinary live claim blocks closed-retire before file IO/mutation")
	var attempt_candidate:Dictionary=build_attempt_candidate(fx)
	if attempt_candidate.is_empty():check(false,"ordinary-claim fixture constructs valid pure attempt transition");finish_fixture(fx);return
	fx.host._depth+=1
	var attempt_call_counts:Dictionary=io_snapshot(fx.host)
	var attempt_while_ordinary:Dictionary=fx.host._begin_fee_attempt_writer_frame(attempt_candidate)
	fx.host._depth-=1
	check(attempt_while_ordinary.is_empty() and io_delta(fx.host,attempt_call_counts,"read")==0 and io_mutations_unchanged(fx.host,attempt_call_counts),"ordinary claim blocks real attempt-frame begin before file IO/mutation")
	var close_call_counts:Dictionary=io_snapshot(fx.host)
	var close_while_ordinary:Dictionary=fx.host._begin_fee_attempt_close_frame(ordinary_stopped_identity,ordinary_close_candidate)
	check(close_while_ordinary.is_empty() and io_delta(fx.host,close_call_counts,"read")==0 and io_mutations_unchanged(fx.host,close_call_counts),"ordinary claim blocks exact close begin before file IO/mutation")
	var ordinary_wrong_counts_before:Dictionary=io_snapshot(fx.host)
	var wrong_close:Dictionary=fx.host._persist_fee_attempt_close_pair({"call":ordinary.get("call")})
	var wrong_retire_commit:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":ordinary.get("call")})
	var wrong_attempt:Dictionary=fx.host._persist_fee_attempt_fence({"call":ordinary.get("call")})
	check(not wrong_close.get("ok",false) and not wrong_retire_commit.get("ok",false) and not wrong_attempt.get("ok",false) and io_all_unchanged(fx.host,ordinary_wrong_counts_before),"close/retire/attempt commits reject ordinary handle without IO")
	var ordinary_counts_before:Dictionary=io_snapshot(fx.host)
	var rightful:Dictionary=fx.host._commit_fee_resume_sidecar_frame({"call":ordinary.get("call")})
	check(rightful.get("ok",false) is bool and rightful.get("ok",false),"failed cross-action starts did not consume rightful ordinary handle")
	check(io_delta(fx.host,ordinary_counts_before,"read")==7 and io_delta(fx.host,ordinary_counts_before,"write")==1 and io_delta(fx.host,ordinary_counts_before,"rename")==1 and io_delta(fx.host,ordinary_counts_before,"remove")==0,"ordinary rightful commit has exact 7-read/1-write/1-rename delta")
	finish_fixture(fx)

	# A real retire frame blocks ordinary, close, and attempt entry points.
	fx=make_closed_fixture("retire-claim")
	if fx.is_empty():return
	var retire:Dictionary=begin_retire(fx)
	if not retire.get("ok",false):check(false,"real retire claim prepares");finish_fixture(fx);return
	var retire_pair_counts:Dictionary=io_snapshot(fx.host)
	var binding_candidate:Dictionary=fx.sidecar_state.duplicate(true);binding_candidate.erase("quest_auto")
	var ordinary_while_retire:Dictionary=fx.host._begin_fee_resume_sidecar_frame("write_fence",binding_candidate)
	check(not ordinary_while_retire.get("ok",false) and io_delta(fx.host,retire_pair_counts,"read")==0 and io_mutations_unchanged(fx.host,retire_pair_counts),"retire claim blocks ordinary sidecar begin without file IO/mutation")
	var closed_attempt_candidate:Dictionary=build_attempt_candidate_from_record(fx,fx.active_record)
	check(not closed_attempt_candidate.is_empty() and Journal.valid(closed_attempt_candidate.quest_auto_fee_lifecycle),"retire case supplies an independently valid attempt transition candidate")
	var closed_attempt_counts:Dictionary=io_snapshot(fx.host)
	fx.host._depth+=1
	var attempt_while_retire:Dictionary=fx.host._begin_fee_attempt_writer_frame(closed_attempt_candidate)
	fx.host._depth-=1
	check(attempt_while_retire.is_empty() and io_delta(fx.host,closed_attempt_counts,"read")==0 and io_mutations_unchanged(fx.host,closed_attempt_counts),"retire claim rejects a pure-valid active candidate before later closed-run checks/file IO")
	var retire_wrong_counts_before:Dictionary=io_snapshot(fx.host)
	var wrong_ordinary:Dictionary=fx.host._commit_fee_resume_sidecar_frame({"call":retire.get("call")})
	var wrong_close_commit:Dictionary=fx.host._persist_fee_attempt_close_pair({"call":retire.get("call")})
	var wrong_attempt_commit:Dictionary=fx.host._persist_fee_attempt_fence({"call":retire.get("call")})
	check(not wrong_ordinary.get("ok",false) and not wrong_close_commit.get("ok",false) and not wrong_attempt_commit.get("ok",false) and io_all_unchanged(fx.host,retire_wrong_counts_before),"ordinary/close/attempt commits reject retire handle without IO")
	var retire_counts_before:Dictionary=io_snapshot(fx.host)
	var rightful_retire:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":retire.get("call")})
	check(rightful_retire.get("ok",false) is bool and rightful_retire.get("ok",false),"cross-claim refusals leave rightful retire handle usable")
	check(io_delta(fx.host,retire_counts_before,"read")==13 and io_delta(fx.host,retire_counts_before,"write")==1 and io_delta(fx.host,retire_counts_before,"rename")==1 and io_delta(fx.host,retire_counts_before,"remove")==0,"retire rewrite has exact 13-read/1-write/1-rename delta")
	finish_fixture(fx)

	# Real attempt claim from the production begin seam blocks other begin paths.
	fx=start_active_fixture("attempt-claim",false)
	if fx.is_empty():return
	var attempt_begin_counts:Dictionary=io_snapshot(fx.host)
	var attempt:Dictionary=prepare_attempt_frame(fx)
	if attempt.is_empty():check(false,"actual attempt writer frame prepares from legal Journal transition");finish_fixture(fx);return
	check(io_all_unchanged(fx.host,attempt_begin_counts),"attempt-frame preparation performs no Probe sidecar IO")
	var attempt_pair_counts:Dictionary=io_snapshot(fx.host)
	var sidecar_while_attempt:Dictionary=fx.host._begin_fee_resume_sidecar_frame("write_fence",{})
	check(not sidecar_while_attempt.get("ok",false) and io_delta(fx.host,attempt_pair_counts,"read")==0 and io_mutations_unchanged(fx.host,attempt_pair_counts),"attempt claim blocks ordinary sidecar begin before file IO/mutation")
	var retire_while_attempt:Dictionary=begin_retire(fx,0)
	check(not retire_while_attempt.get("ok",false) and io_delta(fx.host,attempt_pair_counts,"read")==0 and io_mutations_unchanged(fx.host,attempt_pair_counts),"attempt claim blocks retire begin before profile/sidecar reads or mutation")
	var attempt_stopped_identity:Dictionary=fx.host.quest_auto.identity.checkpoint()
	var attempt_close_candidate:Dictionary=fx.session._profile.duplicate(true)
	var attempt_close_transition:Dictionary=Journal.close_run(attempt_close_candidate.quest_auto_fee_lifecycle,RUN)
	if attempt_close_transition.get("ok",false):attempt_close_candidate.quest_auto_fee_lifecycle=attempt_close_transition.candidate.duplicate(true)
	var close_blocked:Dictionary=fx.host._begin_fee_attempt_close_frame(attempt_stopped_identity,attempt_close_candidate)
	check(close_blocked.is_empty(),"attempt claim blocks close begin")
	var wrong_attempt_counts:Dictionary=io_snapshot(fx.host)
	var wrong_retire:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":attempt.get("call")})
	var wrong_sidecar_attempt:Dictionary=fx.host._commit_fee_resume_sidecar_frame({"call":attempt.get("call")})
	var wrong_close_attempt:Dictionary=fx.host._persist_fee_attempt_close_pair({"call":attempt.get("call")})
	check(not wrong_retire.get("ok",false) and not wrong_sidecar_attempt.get("ok",false) and not wrong_close_attempt.get("ok",false) and is_same(fx.host._fee_attempt_writer_call,attempt.get("call")) and io_all_unchanged(fx.host,wrong_attempt_counts),"wrong retire/sidecar/close commits cannot consume attempt frame or touch files")
	fx.host._end_fee_attempt_writer_frame(attempt)
	check(fx.host._fee_attempt_writer_call==null and fx.host._fee_attempt_writer_snapshot.is_empty(),"correct attempt-frame release clears only the rightful claim")
	finish_fixture(fx)

	# A successful close-frame claim is also obtained through the production
	# close preparation API and excludes all other begin paths until its writer.
	fx=start_active_fixture("close-claim",false)
	if fx.is_empty():return
	var close_begin_counts:Dictionary=io_snapshot(fx.host)
	var close_frame:Dictionary=prepare_close_frame(fx)
	if close_frame.is_empty():check(false,"actual close writer frame prepares before pairwise checks");finish_fixture(fx);return
	check(io_all_unchanged(fx.host,close_begin_counts),"close-frame preparation does not use Probe sidecar IO")
	var close_pair_counts:Dictionary=io_snapshot(fx.host)
	var blocked_attempt:Dictionary=prepare_attempt_frame(fx)
	check(blocked_attempt.is_empty() and io_delta(fx.host,close_pair_counts,"read")==0 and io_mutations_unchanged(fx.host,close_pair_counts),"close claim blocks actual attempt-frame begin without file IO/mutation")
	var blocked_sidecar:Dictionary=fx.host._begin_fee_resume_sidecar_frame("write_fence",{})
	check(not blocked_sidecar.get("ok",false) and io_delta(fx.host,close_pair_counts,"read")==0 and io_mutations_unchanged(fx.host,close_pair_counts),"close claim blocks ordinary sidecar begin without file IO/mutation")
	var blocked_retire:Dictionary=fx.host._begin_fee_resume_closed_retire_frame()
	check(not blocked_retire.get("ok",false) and io_delta(fx.host,close_pair_counts,"read")==0 and io_mutations_unchanged(fx.host,close_pair_counts),"close claim blocks retire begin without file IO/mutation")
	var close_wrong_counts:Dictionary=io_snapshot(fx.host)
	var wrong_sidecar_close:Dictionary=fx.host._commit_fee_resume_sidecar_frame({"call":close_frame.get("call")})
	var wrong_retire_close:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":close_frame.get("call")})
	var wrong_attempt_close:Dictionary=fx.host._persist_fee_attempt_fence({"call":close_frame.get("call")})
	check(not wrong_sidecar_close.get("ok",false) and not wrong_retire_close.get("ok",false) and not wrong_attempt_close.get("ok",false) and io_all_unchanged(fx.host,close_wrong_counts),"sidecar/retire/attempt commits reject close handle without IO")
	var close_commit_counts:Dictionary=io_snapshot(fx.host)
	var close_result:Dictionary=fx.host._persist_fee_attempt_close_pair(close_frame)
	check(close_result.get("ok",false) is bool and close_result.get("ok",false) and io_all_unchanged(fx.host,close_commit_counts),"rightful close handle remains usable without sidecar IO")
	finish_fixture(fx)

func case_begin_read_callback_fences()->void:
	# Each overridable sidecar path read is followed by a frame check before the
	# next path is touched. The checks below mutate only this test Backend owner.
	for mutation:Dictionary in [{"read":1,"kind":"change_path"},{"read":2,"kind":"change_serial"},{"read":3,"kind":"replace_profile"},{"read":4,"kind":"change_path"}]:
		var read_number:int=int(mutation.get("read",-1))
		var mutation_kind:String=str(mutation.get("kind",""))
		var fx_sidecar:Dictionary=make_closed_fixture("begin-read-%d-%s" % [read_number,mutation_kind])
		if fx_sidecar.is_empty():return
		var before:Dictionary=raw(fx_sidecar.sidecar_path)
		fx_sidecar.host.read_count=0
		fx_sidecar.host.read_mutation_at=read_number
		fx_sidecar.host.read_mutation=mutation_kind
		var sidecar_counts_before:Dictionary=io_snapshot(fx_sidecar.host)
		var result_sidecar:Dictionary=begin_retire(fx_sidecar,read_number)
		check(not result_sidecar.get("ok",false) and io_delta(fx_sidecar.host,sidecar_counts_before,"read")==read_number,"begin callback %s invalidates before a later sidecar read" % mutation_kind)
		check(raw(fx_sidecar.sidecar_path)==before and io_mutations_unchanged(fx_sidecar.host,sidecar_counts_before),"begin callback %s leaves original bytes and zero mutation delta" % mutation_kind)
		finish_fixture(fx_sidecar)
	for offset:int in [1,2,3,4,5,6]:
		var fx_profile:Dictionary=make_closed_fixture("begin-profile-read-%d" % offset)
		if fx_profile.is_empty():return
		var profile_before:Dictionary=raw(fx_profile.sidecar_path)
		var profile_base_reads:int=fx_profile.session.profile_read_count
		fx_profile.session.mutate_profile_read_at=profile_base_reads+offset
		fx_profile.host.read_mutation="profile_change_path" if offset in [1,4] else ("profile_change_owner" if offset in [2,5] else "profile_change_serial")
		fx_profile.host.read_count=0
		var profile_counts_before:Dictionary=io_snapshot(fx_profile.host)
		var expected_sidecar_reads:int=0 if offset<=3 else 2
		var result_profile:Dictionary=begin_retire(fx_profile,expected_sidecar_reads)
		check(not result_profile.get("ok",false) and io_delta(fx_profile.host,profile_counts_before,"read")==expected_sidecar_reads,"profile-pair callback offset %d stops before subsequent sidecar reads" % offset)
		check(raw(fx_profile.sidecar_path)==profile_before and io_mutations_unchanged(fx_profile.host,profile_counts_before),"profile callback offset %d preserves complete sidecar bytes" % offset)
		finish_fixture(fx_profile)
	for malformed_read:Dictionary in [{"ok":true,"exists":true},{"ok":true,"exists":false},{"ok":true,"exists":true,"bytes":"not-packed"},{"ok":true,"exists":false,"bytes":PackedByteArray([7])}]:
		var fx_bytes:Dictionary=make_closed_fixture("missing-read-bytes")
		if fx_bytes.is_empty():return
		var before_bytes:Dictionary=raw(fx_bytes.sidecar_path)
		fx_bytes.host.read_count=0
		fx_bytes.host.read_override_at=1
		fx_bytes.host.read_override=malformed_read.duplicate(true)
		var bytes_counts_before:Dictionary=io_snapshot(fx_bytes.host)
		var result_bytes:Dictionary=begin_retire(fx_bytes,4)
		check(not result_bytes.get("ok",false) and io_delta(fx_bytes.host,bytes_counts_before,"read")==4 and io_mutations_unchanged(fx_bytes.host,bytes_counts_before),"malformed target row is rejected after four bounded sidecar observations without mutation")
		check(raw(fx_bytes.sidecar_path)==before_bytes,"missing read bytes does not alter the physical sidecar")
		finish_fixture(fx_bytes)
	for profile_fault:Dictionary in [
		{"offset":1,"row":{"ok":true,"exists":true,"matches":true}},
		{"offset":2,"row":{"ok":true,"exists":true,"matches":true,"bytes":"bad"}},
		{"offset":3,"row":{"ok":true,"exists":false}}
	]:
		var profile_fx:Dictionary=make_closed_fixture("profile-read-bytes")
		if profile_fx.is_empty():return
		var sidecar_before:Dictionary=raw(profile_fx.sidecar_path)
		profile_fx.host.read_count=0
		profile_fx.session.profile_read_override_at=profile_fx.session.profile_read_count+int(profile_fault.get("offset",-1))
		profile_fx.session.profile_read_override=profile_fault.get("row",{}).duplicate(true)
		var malformed_profile_counts_before:Dictionary=io_snapshot(profile_fx.host)
		var profile_result:Dictionary=begin_retire(profile_fx,0)
		check(not profile_result.get("ok",false) and io_delta(profile_fx.host,malformed_profile_counts_before,"read")==0,"profile primary/backup/tmp read missing or wrong bytes is refused before sidecar access")
		check(raw(profile_fx.sidecar_path)==sidecar_before and io_mutations_unchanged(profile_fx.host,malformed_profile_counts_before),"malformed profile read row performs no sidecar mutation")
		finish_fixture(profile_fx)

func case_commit_read_bytes_guards()->void:
	# Each override returns a malformed successful row while the independent raw
	# oracle records the real file bytes. No malformed row may authorize mutation.
	for fault:Dictionary in [
		{"name":"target_pre_missing","read":1,"expected_reads":4,"phase":"preflight","row":{"ok":true,"exists":true}},
		{"name":"tmp_pre_absent_missing_bytes","read":2,"expected_reads":4,"phase":"preflight","row":{"ok":true,"exists":false}},
		{"name":"tmp_written_missing","read":5,"expected_reads":7,"phase":"write_tmp","row":{"ok":true,"exists":true}},
		{"name":"tmp_pre_rename_missing","read":7,"expected_reads":11,"phase":"pre_rename","row":{"ok":true,"exists":true}}
	]:
		var label:String=str(fault.get("name","missing-bytes"))
		var fx:Dictionary=make_closed_fixture(label)
		if fx.is_empty():return
		var target_before:Dictionary=raw(fx.sidecar_path)
		var tmp_before:Dictionary=raw(fx.sidecar_path+".tmp")
		var frame:Dictionary=begin_retire(fx)
		if not frame.get("ok",false):check(false,label+": actual retire frame prepares");finish_fixture(fx);return
		fx.host.read_count=0
		fx.host.read_override_at=int(fault.get("read",-1))
		fx.host.read_override=fault.get("row",{}).duplicate(true)
		var counts_before:Dictionary=io_snapshot(fx.host)
		var result:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":frame.get("call")})
		check(not result.get("ok",false),label+": missing bytes never authorizes a successful operation")
		check(io_delta(fx.host,counts_before,"read")==int(fault.get("expected_reads",-1)),label+": completes the source-defined preflight/error-observation reads")
		check(io_delta(fx.host,counts_before,"rename")==0 and io_delta(fx.host,counts_before,"remove")==0,label+": rename/remove deltas remain zero")
		if fault.get("phase","")=="preflight":
			check(io_delta(fx.host,counts_before,"write")==0,label+": preflight rejection performs no tmp write")
			check(raw(fx.sidecar_path)==target_before and raw(fx.sidecar_path+".tmp")==tmp_before,label+": preflight retains complete target/tmp bytes")
		else:
			var physical_tmp:Dictionary=raw(fx.sidecar_path+".tmp")
			check(io_delta(fx.host,counts_before,"write")==1 and physical_tmp.get("kind","")=="bytes" and physical_tmp.bytes==native_bytes(fx.expected_sidecar_candidate),label+": one tmp candidate is preserved before refusal")
			check(raw(fx.sidecar_path)==target_before,label+": original sidecar target bytes remain unchanged")
			check(result.get("operation_attempted",false) is bool and result.operation_attempted and not result.get("operation_completed",true),label+": operation facts distinguish attempted tmp write from incomplete retirement")
		finish_fixture(fx)

func case_remove_tmp_bytes_guards()->void:
	# A true `exists=false` is insufficient: both actual remove-branch reads
	# must carry explicit, correctly typed empty bytes before deletion is allowed.
	for read_offset:int in [6,8]:
		for malformed:Dictionary in [
			{"label":"missing","row":{"ok":true,"exists":false}},
			{"label":"wrong_type","row":{"ok":true,"exists":false,"bytes":""}},
			{"label":"nonempty","row":{"ok":true,"exists":false,"bytes":PackedByteArray([9])}}
		]:
			var fx:Dictionary=make_closed_fixture("remove-tmp-%d-%s" % [read_offset,str(malformed.get("label","bad"))])
			if fx.is_empty():return
			var binding:Dictionary={"owner":fx.owner.duplicate(true),"run_id":RUN}
			if not write_raw(fx.sidecar_path,native_bytes({"fee_attempt_binding":binding})):
				check(false,"remove tmp guard source written");finish_fixture(fx);return
			var original_target:Dictionary=raw(fx.sidecar_path)
			var original_tmp:Dictionary=raw(fx.sidecar_path+".tmp")
			var frame:Dictionary=begin_retire(fx)
			if not frame.get("ok",false):check(false,"remove tmp guard frame prepares");finish_fixture(fx);return
			fx.host.read_count=0
			fx.host.read_override_at=read_offset
			fx.host.read_override=malformed.get("row",{}).duplicate(true)
			var remove_counts_before:Dictionary=io_snapshot(fx.host)
			var result:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":frame.get("call")})
			check(not result.get("ok",false),"remove read %d %s is rejected" % [read_offset,str(malformed.get("label","bad"))])
			check(io_delta(fx.host,remove_counts_before,"read")==read_offset and io_mutations_unchanged(fx.host,remove_counts_before),"remove read %d %s stops before mutation" % [read_offset,str(malformed.get("label","bad"))])
			check(raw(fx.sidecar_path)==original_target and raw(fx.sidecar_path+".tmp")==original_tmp,"remove read %d %s retains complete target and tmp bytes" % [read_offset,str(malformed.get("label","bad"))])
			check(fx.host._fee_resume_sidecar_call==null and fx.host._fee_resume_sidecar_frame.is_empty(),"remove read %d %s releases its refused frame" % [read_offset,str(malformed.get("label","bad"))])
			finish_fixture(fx)

func case_commit_profile_bytes_guard()->void:
	var fx:Dictionary=make_closed_fixture("commit-profile-missing-bytes")
	if fx.is_empty():return
	var before:Dictionary=raw(fx.sidecar_path)
	var frame:Dictionary=begin_retire(fx)
	if not frame.get("ok",false):check(false,"profile bytes guard frame prepares");finish_fixture(fx);return
	fx.host.read_count=0
	fx.session.profile_read_override_at=fx.session.profile_read_count+1
	fx.session.profile_read_override={"ok":true,"exists":true,"matches":true}
	var counts_before:Dictionary=io_snapshot(fx.host)
	var result:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":frame.get("call")})
	check(not result.get("ok",false) and io_delta(fx.host,counts_before,"read")==4,"unknown initial profile pair still permits four read-only sidecar observations, then blocks mutation")
	check(io_mutations_unchanged(fx.host,counts_before) and raw(fx.sidecar_path)==before,"missing profile bytes preserves sidecar and performs no mutation")
	finish_fixture(fx)

func case_profile_disk_change_after_sidecar_read()->void:
	var fx:Dictionary=make_closed_fixture("profile-disk-change")
	if fx.is_empty():return
	var original_sidecar:Dictionary=raw(fx.sidecar_path)
	var original_profile:Dictionary=raw(fx.host.save_path)
	fx.host.read_count=0
	fx.host.read_mutation_at=1
	fx.host.read_mutation="change_profile_disk"
	var counts_before:Dictionary=io_snapshot(fx.host)
	var result:Dictionary=begin_retire(fx,2)
	var changed_profile:Dictionary=raw(fx.host.save_path)
	check(not result.get("ok",false) and io_delta(fx.host,counts_before,"read")==2 and io_mutations_unchanged(fx.host,counts_before),"profile bytes changed by target callback are detected after two sidecar reads without mutation")
	check(original_profile.get("kind","")=="bytes" and changed_profile.get("kind","")=="bytes" and changed_profile.bytes!=original_profile.bytes,"independent profile oracle records callback mutation")
	check(raw(fx.sidecar_path)==original_sidecar and raw(fx.sidecar_path+".tmp").get("kind","")=="missing","sidecar remains untouched when closed profile pair no longer matches")
	finish_fixture(fx)

func case_io_failures_and_unknown_readback()->void:
	for fault:String in ["write_fail","rename_fail","readback_unknown","remove_fail"]:
		var fx:Dictionary=make_closed_fixture("io-"+fault)
		if fx.is_empty():return
		if fault=="remove_fail":
			var binding:Dictionary={"owner":fx.owner.duplicate(true),"run_id":RUN}
			if not write_raw(fx.sidecar_path,native_bytes({"fee_attempt_binding":binding})):
				check(false,"standalone binding fixture written");finish_fixture(fx);return
		var original:Dictionary=raw(fx.sidecar_path)
		var frame:Dictionary=begin_retire(fx)
		if not frame.get("ok",false):check(false,fault+" retire frame prepares");finish_fixture(fx);return
		fx.host.read_count=0
		fx.host.force_write_error=fault=="write_fail"
		fx.host.force_rename_error=fault=="rename_fail"
		fx.host.force_remove_error=fault=="remove_fail"
		if fault=="readback_unknown":
			fx.host.read_override_at=12
			fx.host.read_override={"ok":true,"exists":true}
		var counts_before:Dictionary=io_snapshot(fx.host)
		var result:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":frame.get("call")})
		var expected_write_delta:int=1 if fault in ["write_fail","rename_fail","readback_unknown"] else 0
		var expected_rename_delta:int=1 if fault in ["rename_fail","readback_unknown"] else 0
		var expected_remove_delta:int=1 if fault=="remove_fail" else 0
		var expected_read_delta:int=13
		if fault=="write_fail":expected_read_delta=7
		elif fault=="remove_fail":expected_read_delta=12
		check(io_delta(fx.host,counts_before,"read")==expected_read_delta and io_delta(fx.host,counts_before,"write")==expected_write_delta and io_delta(fx.host,counts_before,"rename")==expected_rename_delta and io_delta(fx.host,counts_before,"remove")==expected_remove_delta,"%s failure has exact read/write/rename/remove call deltas" % fault)
		if fault=="readback_unknown":
			var physical:Dictionary=raw(fx.sidecar_path)
			check(not result.get("ok",false) and result.get("sidecar_persisted",null) is String and result.sidecar_persisted=="unknown","incomplete final readback remains unknown despite completed rename")
			check(result.get("operation_completed",false) is bool and result.operation_completed and physical.get("kind","")=="bytes","independent raw disk sees completed target while API fact is unknown")
		elif fault=="rename_fail":
			check(not result.get("ok",false) and result.get("operation_attempted",false) and not result.get("operation_completed",true),"rename error reports attempted but incomplete operation")
			check(raw(fx.sidecar_path)==original and raw(fx.sidecar_path+".tmp").get("kind","")=="bytes","rename failure preserves source and leaves candidate tmp evidence")
		elif fault=="remove_fail":
			check(not result.get("ok",false) and result.get("operation_attempted",false) and not result.get("operation_completed",true),"remove error reports attempted but incomplete deletion")
			check(raw(fx.sidecar_path)==original,"failed remove leaves standalone binding bytes intact")
		else:
			check(not result.get("ok",false) and not result.get("operation_completed",true),"tmp open failure is not reported complete")
			check(raw(fx.sidecar_path)==original and raw(fx.sidecar_path+".tmp").get("kind","")=="missing","tmp open failure preserves original and leaves no candidate tmp")
		finish_fixture(fx)

func case_pre_read_and_commit_stale()->void:
	# Mutation from the first sidecar read must stop the begin sequence before a
	# second path read; old/new complete bytes are sampled independently.
	var fx:Dictionary=make_closed_fixture("begin-stale")
	if fx.is_empty():return
	var old_path:String=fx.sidecar_path
	var before:Dictionary=raw(old_path)
	fx.host.read_count=0
	fx.host.read_mutation_at=1
	fx.host.read_mutation="change_path"
	var begin_counts_before:Dictionary=io_snapshot(fx.host)
	var begun:Dictionary=begin_retire(fx,1)
	check(not begun.get("ok",false) and io_delta(fx.host,begin_counts_before,"read")==1 and io_mutations_unchanged(fx.host,begin_counts_before),"owner/path replacement after first target read prevents the next tmp read")
	check(raw(old_path)==before and raw(fx.host._resume_file()).get("kind","")=="missing","old bytes remain and successor path is untouched")
	finish_fixture(fx)

	fx=make_closed_fixture("commit-profile-stale")
	if fx.is_empty():return
	var frame:Dictionary=begin_retire(fx)
	if not frame.get("ok",false):check(false,"profile stale fixture retire frame prepares");finish_fixture(fx);return
	fx.host.read_count=0
	fx.session.mutate_profile_read_at=fx.session.profile_read_count+1
	fx.host.read_mutation="profile_change_path"
	var before_old:Dictionary=raw(fx.sidecar_path)
	var before_profile_reads:int=fx.session.profile_read_count
	var profile_stale_counts_before:Dictionary=io_snapshot(fx.host)
	var result:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":frame.get("call")})
	check(not result.get("ok",false) and io_delta(fx.host,profile_stale_counts_before,"read")==0 and io_mutations_unchanged(fx.host,profile_stale_counts_before),"profile callback owner change is checked before sidecar target read/write")
	check(fx.session.profile_read_count>before_profile_reads and raw(fx.sidecar_path)==before_old,"old sidecar remains exact after profile-read invalidation")
	finish_fixture(fx)

	# Force tmp creation to fail before the error-observation path. The final
	# pair reader then changes owner/path; the observation helper must reject its
	# stale result and issue no further old/new path read.
	fx=make_closed_fixture("observation-profile-stale")
	if fx.is_empty():return
	frame=begin_retire(fx)
	if not frame.get("ok",false):check(false,"observation stale fixture frame prepares");finish_fixture(fx);return
	fx.host.read_count=0
	fx.session.mutate_profile_read_at=fx.session.profile_read_count+10
	fx.host.read_mutation="profile_change_path"
	fx.host.force_write_error=true
	var old_sidecar_before:Dictionary=raw(fx.sidecar_path)
	var profile_reads_before:int=fx.session.profile_read_count
	var observation_counts_before:Dictionary=io_snapshot(fx.host)
	var observation_result:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":frame.get("call")})
	check(not observation_result.get("ok",false) and io_delta(fx.host,observation_counts_before,"read")==7 and io_delta(fx.host,observation_counts_before,"write")==1 and io_delta(fx.host,observation_counts_before,"rename")==0 and io_delta(fx.host,observation_counts_before,"remove")==0,"final observation pair invalidation stops all subsequent sidecar I/O")
	check(fx.session.profile_read_count>profile_reads_before and raw(fx.sidecar_path)==old_sidecar_before,"profile callback invalidation preserves old sidecar bytes")
	finish_fixture(fx)

func case_stale_commit_releases_own_claim()->void:
	for mutation:String in ["path","serial","profile"]:
		var fx:Dictionary=make_closed_fixture("stale-own-claim-"+mutation)
		if fx.is_empty():return
		var old_path:String=fx.sidecar_path
		var old_bytes:Dictionary=raw(old_path)
		var frame:Dictionary=begin_retire(fx)
		if not frame.get("ok",false):check(false,mutation+": retire frame prepares");finish_fixture(fx);return
		var old_handle:Dictionary={"call":frame.get("call")}
		if mutation=="path":fx.host.save_path="user://closed-retire-stale-successor-%d.json" % Clock.ticks_usec()
		elif mutation=="serial":fx.host.quest_save_serial+=1
		else:fx.session._profile=fx.session._profile.duplicate(true)
		fx.host.read_count=0
		var stale_counts_before:Dictionary=io_snapshot(fx.host)
		var stale:Dictionary=fx.host._commit_fee_resume_closed_retire_frame(old_handle)
		check(not stale.get("ok",false) and stale.get("stage","")=="stale_before_io_after_claim","%s stale frame is refused before IO" % mutation)
		check(io_delta(fx.host,stale_counts_before,"read")==0 and io_mutations_unchanged(fx.host,stale_counts_before),"%s stale commit performs no subsequent reads or writes" % mutation)
		check(fx.host._fee_resume_sidecar_call==null and fx.host._fee_resume_sidecar_frame.is_empty() and not fx.host._fee_resume_sidecar_executing,"%s stale rightful call releases its own claim" % mutation)
		check(raw(old_path)==old_bytes,"%s stale commit preserves old sidecar bytes" % mutation)
		var replay_counts_before:Dictionary=io_snapshot(fx.host)
		var replay:Dictionary=fx.host._commit_fee_resume_closed_retire_frame(old_handle)
		check(not replay.get("ok",false) and replay.get("stage","")=="invalid_handle" and io_delta(fx.host,replay_counts_before,"read")==0 and io_mutations_unchanged(fx.host,replay_counts_before),"%s repeated old handle is rejected without IO" % mutation)
		if mutation=="serial":
			var successor:Dictionary=begin_retire(fx)
			if not successor.get("ok",false):check(false,"serial successor frame prepares after old claim release");finish_fixture(fx);return
			var successor_handle:Dictionary={"call":successor.get("call")}
			var stale_again_counts:Dictionary=io_snapshot(fx.host)
			var stale_again:Dictionary=fx.host._commit_fee_resume_closed_retire_frame(old_handle)
			check(not stale_again.get("ok",false) and fx.host._fee_resume_sidecar_call==successor_handle.get("call") and io_all_unchanged(fx.host,stale_again_counts),"old handle cannot clear successor claim or touch files")
			var successor_counts:Dictionary=io_snapshot(fx.host)
			var successor_result:Dictionary=fx.host._commit_fee_resume_closed_retire_frame(successor_handle)
			check(successor_result.get("ok",false) is bool and successor_result.get("ok",false) and io_delta(fx.host,successor_counts,"read")==13 and io_delta(fx.host,successor_counts,"write")==1 and io_delta(fx.host,successor_counts,"rename")==1 and io_delta(fx.host,successor_counts,"remove")==0,"successor handle remains usable with exact rewrite deltas")
		finish_fixture(fx)

func case_reentry_and_strict_bytes()->void:
	var fx:Dictionary=make_closed_fixture("nested-retire")
	if fx.is_empty():return
	var nested_begin_counts:Dictionary=io_snapshot(fx.host)
	var frame:Dictionary=begin_retire(fx)
	if not frame.get("ok",false):check(false,"nested fixture frame prepared");finish_fixture(fx);return
	check(io_delta(fx.host,nested_begin_counts,"read")==4 and io_mutations_unchanged(fx.host,nested_begin_counts),"nested fixture begin has exact four-read/no-mutation delta")
	fx.host.nested_handle={"call":frame.get("call")}
	fx.host.nested_on_write=true
	var nested_commit_counts:Dictionary=io_snapshot(fx.host)
	var result:Dictionary=fx.host._commit_fee_resume_closed_retire_frame({"call":frame.get("call")})
	check(io_delta(fx.host,nested_commit_counts,"read")==13 and io_delta(fx.host,nested_commit_counts,"write")==1 and io_delta(fx.host,nested_commit_counts,"rename")==1 and io_delta(fx.host,nested_commit_counts,"remove")==0,"nested rightful outer commit has exact operation deltas; nested call contributes none")
	check(not fx.host.nested_result.get("ok",false) and fx.host.nested_result.get("stage","")=="already_executing","same-handle nested commit is refused")
	check(result.get("ok",false) is bool and result.get("ok",false),"outer retire owns and completes the single write")
	var frame_value:Dictionary={"remove_target":false,"payload":"candidate".to_utf8_buffer()}
	for malformed:Dictionary in [{"ok":true,"exists":true},{"ok":true,"exists":true,"bytes":"candidate"},{"ok":"true","exists":true,"bytes":PackedByteArray()}]:
		var fact:Dictionary=fx.host._fee_resume_retire_fact_from_read(frame_value,malformed)
		check(fact.get("sidecar_persisted",null) is String and fact.sidecar_persisted=="unknown","missing/wrong-type bytes or ok remain unknown")
	check(fx.host._fee_resume_retire_tmp_clear_fact({"ok":true,"exists":false})=="unknown","absent tmp without an explicit byte row is unknown")
	check(fx.host._fee_resume_retire_tmp_clear_fact({"ok":true,"exists":false,"bytes":PackedByteArray()}) is bool and fx.host._fee_resume_retire_tmp_clear_fact({"ok":true,"exists":false,"bytes":PackedByteArray()}),"absent tmp with empty typed bytes is positively clear")
	finish_fixture(fx)

func finish_run()->void:
	print("FEE CLOSED RETIRE FIXTURE PATHS: "+JSON.stringify(retained_paths))
	print("FEE CLOSED RETIRE SETUP IO COUNTS: "+JSON.stringify(setup_io_rows))
	print("FEE CLOSED RETIRE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func run()->void:
	case_profile_frame_identity()
	if aborted:finish_run();return
	case_success_composite()
	if aborted:finish_run();return
	case_missing_and_foreign()
	if aborted:finish_run();return
	case_begin_read_callback_fences()
	if aborted:finish_run();return
	case_profile_disk_change_after_sidecar_read()
	if aborted:finish_run();return
	case_commit_read_bytes_guards()
	if aborted:finish_run();return
	case_remove_tmp_bytes_guards()
	if aborted:finish_run();return
	case_commit_profile_bytes_guard()
	if aborted:finish_run();return
	case_real_claim_pairwise()
	if aborted:finish_run();return
	case_io_failures_and_unknown_readback()
	if aborted:finish_run();return
	case_pre_read_and_commit_stale()
	if aborted:finish_run();return
	case_stale_commit_releases_own_claim()
	if aborted:finish_run();return
	case_reentry_and_strict_bytes()
	finish_run()
