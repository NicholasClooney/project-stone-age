extends SceneTree
## Independent disk oracle for the private verified sidecar I/O seam.
## Not registered or run in this static candidate.
const Probe=preload("res://tests/support/fee_resume_io_fault_backend.gd")
const Journal=preload("res://server/fee_attempt_lifecycle.gd")
const AdultCheckpoint=preload("res://server/adult_battle_checkpoint.gd")
const OriginalEquipment=preload("res://server/original_equipment.gd")
const RUN="11111111111111111111111111111111"
const OWNER={"profile_id":"samgir-singleplayer-v1","character_id":"100000"}
var checks:=0
var failures:=0
var run_tag:=""

func _initialize()->void:
	run_tag=Crypto.new().generate_random_bytes(8).hex_encode()
	call_deferred("run")

func check(value:bool,label:String)->bool:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
	return value

func tri_state_is(actual:Variant,expected:Variant)->bool:
	if expected is bool:
		if not (actual is bool):return false
		var actual_bool:bool=actual
		var expected_bool:bool=expected
		return actual_bool==expected_bool
	if expected is String:
		if not (actual is String):return false
		var actual_string:String=actual
		var expected_string:String=expected
		return actual_string==expected_string
	return false

func raw(path:String)->Dictionary:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):return {"ok":false,"exists":true,"directory":true,"bytes":PackedByteArray()}
	var f:=FileAccess.open(path,FileAccess.READ)
	if f==null:
		var open_error:int=FileAccess.get_open_error()
		return {"ok":open_error==ERR_FILE_NOT_FOUND,"exists":false,"error":open_error,"bytes":PackedByteArray()}
	var n:int=f.get_length()
	if n<0 or n>16777216:f.close();return {"ok":false,"exists":true,"bytes":PackedByteArray()}
	var bytes:PackedByteArray=f.get_buffer(n)
	var e:int=f.get_error();f.close()
	return {"ok":e==OK and bytes.size()==n,"exists":true,"length":n,"error":e,"bytes":bytes}

func same_file_fact(left:Dictionary,right:Dictionary)->bool:
	return left.get("ok",false)==right.get("ok",false) and left.get("exists",false)==right.get("exists",false) and left.get("bytes",PackedByteArray())==right.get("bytes",PackedByteArray())

func put_fixture(path:String,bytes:PackedByteArray)->bool:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f==null:return false
	f.store_buffer(bytes);f.flush();var e:int=f.get_error();f.close()
	var read:Dictionary=raw(path)
	return e==OK and read.get("ok",false) and read.get("bytes",PackedByteArray())==bytes

func native_bytes(value:Variant)->PackedByteArray:
	return JSON.stringify(JSON.from_native(value)).to_utf8_buffer()

func verify_native_key_roundtrip(label:String,input_key:Variant,expected_key_type:int)->bool:
	var probe:Probe=new_backend("native-key-"+label.replace(" ","-"))
	var original:Dictionary={}
	var expected_value:Dictionary={"count":17,"labels":["a:b",""]}
	original[input_key]=expected_value.duplicate(true)
	var original_keys:Array=original.keys()
	var original_key_type_ok:bool=original_keys.size()==1 and typeof(original_keys[0])==expected_key_type
	var envelope:Variant=JSON.from_native(original)
	var budget:Array=[0]
	var envelope_valid:bool=envelope is Dictionary and probe._fee_native_sidecar_dictionary_safe(envelope,0,budget)
	var envelope_bytes:PackedByteArray=JSON.stringify(envelope).to_utf8_buffer() if envelope is Dictionary else PackedByteArray()
	var decoded:Variant=JSON.to_native(envelope,false) if envelope_valid else null
	var decoded_keys:Array=decoded.keys() if decoded is Dictionary else []
	var decoded_key_type_ok:bool=decoded_keys.size()==1 and typeof(decoded_keys[0])==expected_key_type
	var decoded_value:Variant=decoded.get(decoded_keys[0],null) if decoded_key_type_ok else null
	var roundtrip_bytes:PackedByteArray=JSON.stringify(JSON.from_native(decoded)).to_utf8_buffer() if decoded is Dictionary else PackedByteArray()
	var ok:bool=check(original_key_type_ok,"Input dictionary retains expected native key Variant type: "+label)
	ok=check(envelope_valid,"JSON.from_native key envelope is accepted by the bounded validator: "+label) and ok
	ok=check(decoded_key_type_ok,"JSON.to_native(false) restores the exact key Variant type: "+label) and ok
	ok=check(decoded_value==expected_value,"Nested value is fully preserved for native key: "+label) and ok
	ok=check(roundtrip_bytes==envelope_bytes,"Native key envelope bytes round-trip exactly: "+label) and ok
	probe.free()
	return ok

func verify_string_integer_key_coexistence()->bool:
	var probe:Probe=new_backend("string-integer-key-coexistence")
	var original:Dictionary={}
	original["7"]={"kind":"string"}
	original[7]={"kind":"integer"}
	var envelope:Variant=JSON.from_native(original)
	var budget:Array=[0]
	var envelope_valid:bool=envelope is Dictionary and probe._fee_native_sidecar_dictionary_safe(envelope,0,budget)
	var decoded:Variant=JSON.to_native(envelope,false) if envelope_valid else null
	var string_key_seen:bool=false
	var integer_key_seen:bool=false
	if decoded is Dictionary:
		for key:Variant in decoded.keys():
			if typeof(key)==TYPE_STRING:string_key_seen=true
			elif typeof(key)==TYPE_INT:integer_key_seen=true
	var value_match:bool=decoded is Dictionary and decoded.size()==2 and decoded.get("7",{})=={"kind":"string"} and decoded.get(7,{})=={"kind":"integer"}
	var original_bytes:PackedByteArray=JSON.stringify(envelope).to_utf8_buffer() if envelope is Dictionary else PackedByteArray()
	var roundtrip_bytes:PackedByteArray=JSON.stringify(JSON.from_native(decoded)).to_utf8_buffer() if decoded is Dictionary else PackedByteArray()
	var ok:bool=check(envelope_valid and decoded is Dictionary and decoded.size()==2,"String key s:7 and integer key i:7 coexist in the bounded native envelope")
	ok=check(string_key_seen and integer_key_seen and value_match,"Distinct native String/int key types and values survive s:7 plus i:7 decoding") and ok
	ok=check(roundtrip_bytes==original_bytes,"s:7/i:7 coexistence preserves exact encoded bytes") and ok
	probe.free()
	return ok

func new_backend(tag:String,run_id:String=RUN) -> Probe:
	var b:Probe=Probe.new()
	b.save_path="user://fee-resume-seam-"+run_tag+"-"+tag+".profile.json"
	b.resume_path=b.save_path.get_basename()+".resume.json"
	var rec:Dictionary=Journal.empty_record(OWNER.profile_id,OWNER.character_id,run_id)
	b.session._profile["quest_auto_fee_lifecycle"]=rec
	b.last_saved_payload=JSON.stringify(b.session._profile)
	b.quest_save_serial=40
	return b

func binding_for(b:Probe)->Dictionary:
	return {"owner":OWNER.duplicate(true),"run_id":b.session._profile.quest_auto_fee_lifecycle.current.run_id}

func fence_from(old:Dictionary,b:Probe)->Dictionary:
	var candidate:Dictionary=old.duplicate(true)
	candidate.erase("quest_auto")
	candidate["fee_attempt_binding"]=binding_for(b)
	return candidate

func only_binding(b:Probe)->Dictionary:
	return {"fee_attempt_binding":binding_for(b)}

func diagnostic_scalar(value:Variant)->String:
	var kind:int=typeof(value)
	if kind==TYPE_NIL:return "null"
	if kind==TYPE_BOOL or kind==TYPE_INT or kind==TYPE_FLOAT:return type_string(kind)+":"+str(value)
	if kind==TYPE_STRING:
		var text:String=value
		return "String(len="+str(text.length())+"):"+text.substr(0,80).replace("\n"," ").replace("\r"," ")
	return "type:"+type_string(kind)

func diagnostic_field(row:Dictionary,key:String)->String:
	if not row.has(key):return "missing"
	var value:Variant=row.get(key)
	return type_string(typeof(value))+"="+diagnostic_scalar(value)

func diagnostic_disk_fact(row:Dictionary)->String:
	var bytes_value:Variant=row.get("bytes",null)
	var byte_count:int=-1
	if bytes_value is PackedByteArray:byte_count=bytes_value.size()
	return "ok{"+diagnostic_field(row,"ok")+"} exists{"+diagnostic_field(row,"exists")+"} directory{"+diagnostic_field(row,"directory")+"} length{"+diagnostic_field(row,"length")+"} bytes_size="+str(byte_count)+" error{"+diagnostic_field(row,"error")+"}"

func diagnose_prepare_failure(b:Probe,candidate:Dictionary,prepared:Dictionary)->void:
	var target:Dictionary=raw(b.resume_path)
	var temporary:Dictionary=raw(b.resume_path+".tmp")
	var profile_cache:String=JSON.stringify(b.session._profile)
	var lifecycle_value:Variant=b.session._profile.get("quest_auto_fee_lifecycle",null)
	var owner_value:Variant=null
	var current_value:Variant=null
	if lifecycle_value is Dictionary:
		owner_value=lifecycle_value.get("owner",null)
		current_value=lifecycle_value.get("current",null)
	var run_status:Variant=null
	var run_id:Variant=null
	if current_value is Dictionary:
		run_status=current_value.get("run_status",null)
		run_id=current_value.get("run_id",null)
	var expected_owner:Dictionary={"profile_id":str(b.session._profile.get("profile_id","")),"character_id":str(b.session._profile.get("character_id",""))}
	var owner_matches:bool=owner_value is Dictionary and owner_value==expected_owner
	var profile_id:Variant=b.session._profile.get("profile_id",null)
	var character_id:Variant=b.session._profile.get("character_id",null)
	print("FEE_PREPARE_DIAG tag=",b.resume_path.get_file()," result_ok{",diagnostic_field(prepared,"ok"),"} stage{",diagnostic_field(prepared,"stage"),"} reason{",diagnostic_field(prepared,"reason"),"} attempted{",diagnostic_field(prepared,"operation_attempted"),"} completed{",diagnostic_field(prepared,"operation_completed"),"} persisted{",diagnostic_field(prepared,"sidecar_persisted"),"} target_state{",diagnostic_field(prepared,"target_state"),"} exists{",diagnostic_field(prepared,"sidecar_exists"),"} has_call=",prepared.has("call"))
	print("FEE_PREPARE_DIAG context candidate_type=",type_string(typeof(candidate))," candidate_keys=",candidate.size()," candidate_has_quest_auto=",candidate.has("quest_auto")," candidate_has_binding=",candidate.has("fee_attempt_binding")," profile_cache_match=",profile_cache==b.last_saved_payload," profile_cache_bytes=",profile_cache.to_utf8_buffer().size()," owner_match=",owner_matches," profile_id{",diagnostic_scalar(profile_id),"} character_id{",diagnostic_scalar(character_id),"} run_status{",diagnostic_scalar(run_status),"} run_id{",diagnostic_scalar(run_id),"} frame_claimed=",b._fee_resume_sidecar_call!=null)
	print("FEE_PREPARE_DIAG target{",diagnostic_disk_fact(target),"} temporary{",diagnostic_disk_fact(temporary),"}")

func prepare_frame(b:Probe,action:String,candidate:Dictionary)->Dictionary:
	var prepared:Dictionary=b._begin_fee_resume_sidecar_frame(action,candidate)
	if not prepared.get("ok",false):diagnose_prepare_failure(b,candidate,prepared)
	return prepared

func write_frame(b:Probe,candidate:Dictionary)->Dictionary:
	return prepare_frame(b,"write_fence",candidate)

func remove_frame(b:Probe)->Dictionary:
	return prepare_frame(b,"remove_fence",{})

func full_disk_snapshot(b:Probe)->Dictionary:
	var primary:Dictionary=raw(b.resume_path)
	var tmp:Dictionary=raw(b.resume_path+".tmp")
	return {"primary_exists":primary.get("exists",false),"primary_bytes":primary.get("bytes",PackedByteArray()),"tmp_exists":tmp.get("exists",false),"tmp_bytes":tmp.get("bytes",PackedByteArray())}

func typed_string_array(value:Variant)->bool:
	if not value is Array:return false
	var typed:Array=value
	return typed.is_typed() and typed.get_typed_builtin()==TYPE_STRING and typed.get_typed_class_name().is_empty() and typed.get_typed_script()==null

func real_checkpoint_sidecar(tag:String,map_id:int,cell:Vector2i,area_id:int,group_id:int,enemy_id:int,checkpoint_key:String)->Dictionary:
	var b:Probe=new_backend(tag)
	b.automation.hunt_running=true
	b.automation.hunt_map=map_id
	b.automation.hunt_cell=cell
	b.automation.position_map=map_id
	b.automation.position_cell=cell
	b.quest_auto.quest_id=1 if checkpoint_key=="adult_battle" else -1
	b.quest_auto.shutdown_intent={"version":3,"identity":{"run_id":RUN,"step_id":"static-source-checkpoint","revision":0},"phase":"fixture"}
	if checkpoint_key=="wood_battle":
		# The real source group is gated by original item 2478. Build only that
		# legal fixture prerequisite through the original item-instance API;
		# this does not test the quest that awards it.
		OriginalEquipment.add(b.session._profile,2478)
	if not b.automation.resume_wanted():b.free();return {"ok":false,"reason":"resume setting is disabled"}
	var area:Dictionary=b.encounter_catalog.area_at(map_id,cell)
	var area_empty:bool=area.is_empty()
	var actual_area_id:Variant=area.get("id",null)
	var actual_area_rect:Variant=area.get("rect",null)
	var actual_area_priority:Variant=area.get("priority",null)
	var area_groups:Variant=area.get("groups",[])
	var locked_group_present:bool=false
	if area_groups is Array:
		for group:Variant in area_groups:
			if group is Dictionary and int(group.get("id",-1))==group_id:
				locked_group_present=true
	var area_matches:bool=not area_empty and int(area.get("id",-1))==area_id
	print("FEE_SOURCE_AREA_SETUP tag=",tag," map=",map_id," cell=",cell," expected_id=",area_id," empty=",area_empty," actual_id=",actual_area_id," rect=",actual_area_rect," priority=",actual_area_priority," expected_group=",group_id," group_present=",locked_group_present," matches=",area_matches)
	if not area_matches:b.free();return {"ok":false,"reason":"source area mismatch"}
	var rng:=RandomNumberGenerator.new()
	rng.seed=0x51de0000+group_id
	var held:Variant=b.session._profile.get("original_items",[])
	if not held is Array:b.free();return {"ok":false,"reason":"profile item field is not Array"}
	var troop:Dictionary=b.encounter_catalog.roll_group(area,group_id,rng,held)
	var troop_enemies:Variant=troop.get("enemies",[])
	var source_ids_match:bool=troop_enemies is Array and not troop_enemies.is_empty()
	if source_ids_match:
		for actor:Variant in troop_enemies:
			if not actor is Dictionary or int(actor.get("source_enemy_id",-1))!=enemy_id:source_ids_match=false;break
	if not source_ids_match:b.free();return {"ok":false,"reason":"pinned source group did not produce only its locked source actor id"}
	var config:Dictionary=b.session.start_wild_battle_config(troop)
	if config.is_empty():b.free();return {"ok":false,"reason":"original wild battle validation refused source troop"}
	var opened:Dictionary=b.open_battle(config)
	if not b.battle_open or not bool(opened.get("active",false)) or not b.battle._state.get("turn_order",null) is Array:b.free();return {"ok":false,"reason":"BattleSession did not open an active battle"}
	if int(b.battle._state.get("turn",-1))!=0 or not b.battle._state.turn_order.is_empty():b.free();return {"ok":false,"reason":"battle fixture advanced before checkpoint capture"}
	var checkpoint:Dictionary={}
	if checkpoint_key=="adult_battle":checkpoint=AdultCheckpoint.snapshot(b)
	elif checkpoint_key=="wood_battle":checkpoint=b._wood_battle_resume()
	if checkpoint.is_empty() or not checkpoint.get("state",{}).get("active",false):b.free();return {"ok":false,"reason":"original checkpoint boundary refused battle"}
	var raw_order:Variant=b.battle._state.get("turn_order",null)
	var view_order:Variant=checkpoint.get("state",{}).get("turn_order",null)
	if not typed_string_array(raw_order) or not typed_string_array(view_order):b.free();return {"ok":false,"reason":"source checkpoint lost Array[String] metadata"}
	var hunt:Dictionary=b.automation.resume_state()
	if hunt.is_empty() or hunt.get("kind","")!="hunt":b.free();return {"ok":false,"reason":"test-local hunt resume state was not constructed"}
	hunt[checkpoint_key]=checkpoint
	var sidecar:Dictionary=b._quest_resume_state(hunt)
	var expected_binding:Dictionary=binding_for(b)
	if not sidecar.has("quest_auto") or sidecar.get("fee_attempt_binding",{})!=expected_binding:b.free();return {"ok":false,"reason":"production quest projection did not attach expected run binding"}
	# The seam requires a current cached profile. This test-local assignment is
	# only a precondition; it is not evidence that profile persistence occurred.
	b.last_saved_payload=JSON.stringify(b.session._profile)
	return {"ok":true,"backend":b,"checkpoint":checkpoint,"sidecar":sidecar,"binding":expected_binding}

func verify_real_typed_checkpoint(tag:String,map_id:int,cell:Vector2i,area_id:int,group_id:int,enemy_id:int,checkpoint_key:String)->bool:
	var fixture:Dictionary=real_checkpoint_sidecar(tag,map_id,cell,area_id,group_id,enemy_id,checkpoint_key)
	if not check(fixture.get("ok",false),"Actual source/config/BattleSession/checkpoint setup: "+tag+" "+str(fixture.get("reason",""))):return false
	var b:Probe=fixture.backend
	var old_sidecar:Dictionary=fixture.sidecar
	var checkpoint:Dictionary=fixture.checkpoint
	var old_order:Variant=checkpoint.get("state",{}).get("turn_order",null)
	if not check(typed_string_array(old_order),"Checkpoint contains real typed turn_order before encoding: "+tag):b.free();return false
	var old_order_array:Array=[]
	if old_order is Array:old_order_array=old_order
	var before_typed_size:int=old_order_array.size()
	var old_bytes:PackedByteArray=native_bytes(old_sidecar)
	if not check(put_fixture(b.resume_path,old_bytes),"Complete source checkpoint sidecar seeded as native envelope: "+tag):b.free();return false
	var before_primary:Dictionary=raw(b.resume_path)
	var before_tmp:Dictionary=raw(b.resume_path+".tmp")
	var expected_binding:Dictionary=fixture.binding
	var independent_expected:Dictionary=old_sidecar.duplicate(true)
	independent_expected.erase("quest_auto")
	independent_expected["fee_attempt_binding"]=expected_binding.duplicate(true)
	var candidate:Dictionary=fence_from(old_sidecar,b)
	if not check(candidate==independent_expected,"Independent expected state is exactly old sidecar minus quest_auto plus authoritative binding: "+tag):b.free();return false
	var prepared:Dictionary=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Exact fence candidate prepares with typed checkpoint: "+tag):b.free();return false
	var result:Dictionary=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	var after_primary:Dictionary=raw(b.resume_path)
	var after_tmp:Dictionary=raw(b.resume_path+".tmp")
	var decoded:Variant=null
	var decode_ok:bool=false
	if after_primary.get("ok",false):
		var parser:=JSON.new()
		decode_ok=parser.parse(after_primary.bytes.get_string_from_utf8())==OK
		if decode_ok:decoded=JSON.to_native(parser.data,false)
	var decoded_checkpoint:Dictionary=decoded.get(checkpoint_key,{}) if decoded is Dictionary else {}
	var decoded_order:Variant=decoded_checkpoint.get("state",{}).get("turn_order",null)
	var bytes_expected:PackedByteArray=native_bytes(independent_expected)
	var exact_preservation:bool=decoded is Dictionary and decoded==independent_expected and decoded.get("hunt",null)==old_sidecar.get("hunt",null) and decoded.get(checkpoint_key,null)==checkpoint and not decoded.has("quest_auto") and decoded.get("fee_attempt_binding",null)==expected_binding
	var source_actor_ids:Array=[]
	for enemy:Dictionary in checkpoint.get("pending",{}).get("enemies",[]):source_actor_ids.append(int(enemy.get("source_enemy_id",-1)))
	var full_io_ok:bool=result.get("ok",false) and tri_state_is(result.get("sidecar_persisted",null),true) and before_primary.get("ok",false) and before_primary.get("bytes",PackedByteArray())==old_bytes and not before_tmp.get("exists",true) and after_primary.get("ok",false) and after_primary.get("bytes",PackedByteArray())==bytes_expected and same_file_fact(before_tmp,after_tmp) and not after_tmp.get("exists",true)
	var decoded_order_array:Array=[]
	if decoded_order is Array:decoded_order_array=decoded_order
	var type_metadata_ok:bool=typed_string_array(decoded_order) and decoded_order_array.size()==before_typed_size
	var original_type_metadata_ok:bool=false
	var old_checkpoint_value:Variant=old_sidecar.get(checkpoint_key,null)
	if old_checkpoint_value is Dictionary:
		var old_state_value:Variant=old_checkpoint_value.get("state",null)
		if old_state_value is Dictionary:original_type_metadata_ok=typed_string_array(old_state_value.get("turn_order",null))
	var source_ids_match:bool=not source_actor_ids.is_empty()
	for source_id:int in source_actor_ids:
		if source_id!=enemy_id:source_ids_match=false;break
	var ok:bool=check(full_io_ok,"Real source checkpoint native bytes and tmp oracle preserved: "+tag) and check(decode_ok and exact_preservation,"Whole decoded hunt/battle/checkpoint matches independent candidate, with quest_auto removed and fee binding added: "+tag) and check(original_type_metadata_ok and type_metadata_ok,"Array[String] metadata survives source checkpoint -> JSON.from_native -> validated write -> JSON.to_native(false): "+tag) and check(source_ids_match,"Checkpoint retains only the pinned original source actor id: "+tag)
	b.free()
	return ok

func run()->void:
	if not verify_native_key_roundtrip("string same-display","same",TYPE_STRING):quit(1);return
	if not verify_native_key_roundtrip("StringName same-display",StringName("same"),TYPE_STRING_NAME):quit(1);return
	if not verify_native_key_roundtrip("StringName empty",StringName(""),TYPE_STRING_NAME):quit(1);return
	if not verify_native_key_roundtrip("StringName colon",StringName("namespace:field"),TYPE_STRING_NAME):quit(1);return
	if not verify_string_integer_key_coexistence():quit(1);return
	if not check(not tri_state_is("unknown",true) and not tri_state_is(false,"unknown"),"Tri-state assertion rejects cross-type boolean/string values safely"):
		quit(1);return
	var token_probe_backend:Probe=new_backend("typed-string-token-contract")
	var token_probe:Array[String]=["turn:player","turn:pet"]
	var token_envelope:Variant=JSON.from_native(token_probe)
	var expected_token_envelope:Dictionary={"type":"Array","elem_type":"String","args":["s:turn:player","s:turn:pet"]}
	var token_budget:Array=[0]
	check(token_envelope is Dictionary and token_envelope==expected_token_envelope and token_probe_backend._fee_native_typed_string_array_safe(token_envelope,0,token_budget),"Nonempty Array[String] encoder tag/token probe; supplemental to real source checkpoint cases")
	token_probe_backend.free()
	if failures:quit(1);return
	var delete_frame:Dictionary={}
	var old:Dictionary={"kind":"hunt","queue":[1,2],"map_id":1000,"cell":[80,90],"quest_auto":{"version":3,"identity":{"run_id":RUN,"step_id":"x","revision":2}}}
	var b:Probe=new_backend("success")
	var candidate:Dictionary=only_binding(b)
	var prepared:Dictionary=write_frame(b,candidate)
	check(prepared.get("ok",false),"Absent sidecar accepts exact fence candidate")
	if failures:b.free();quit(1);return
	var valid_handle:Dictionary={"call":prepared.call}
	var invalid_handles:Array=[null,"",{}, {"call":RefCounted.new()}, {"call":prepared.call,"extra":true}]
	for invalid_handle:Variant in invalid_handles:
		var rejected:Dictionary=b._commit_fee_resume_sidecar_frame(invalid_handle)
		check(not rejected.get("ok",true) and rejected.get("stage","")=="invalid_handle" and not rejected.get("operation_attempted",true),"Null/empty/fake/extra handle is rejected without consuming the live frame")
	if failures:b.free();quit(1);return
	var result:Dictionary=b._commit_fee_resume_sidecar_frame(valid_handle)
	var expected_bytes:PackedByteArray=JSON.stringify(JSON.from_native(candidate)).to_utf8_buffer()
	var saved:Dictionary=raw(b.resume_path)
	var tmp:Dictionary=raw(b.resume_path+".tmp")
	check(result.get("ok",false) and tri_state_is(result.get("sidecar_persisted",null),true) and tri_state_is(result.get("sidecar_exists",null),true) and result.get("target_state","")=="matches" and result.get("operation_attempted",false) and result.get("operation_completed",false),"Actual write reports target fact separately from attempted/completed operation")
	check(saved.get("ok",false) and saved.get("bytes",PackedByteArray())==expected_bytes and not tmp.get("exists",true),"Full independent bytes oracle for successful write; no tmp remains")
	var replay:Dictionary=b._commit_fee_resume_sidecar_frame(valid_handle)
	check(not replay.get("ok",true) and replay.get("stage","")=="invalid_handle" and not replay.get("operation_attempted",true) and raw(b.resume_path).get("bytes",PackedByteArray())==expected_bytes,"Replayed handle is rejected after retirement without changing bytes")
	if failures:b.free();quit(1);return
	var original:PackedByteArray=saved.bytes
	var same_candidate:Dictionary=candidate.duplicate(true)
	prepared=write_frame(b,same_candidate)
	check(prepared.get("ok",false),"Same byte candidate is admitted from exact existing fence")
	if failures:b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	saved=raw(b.resume_path)
	check(result.get("ok",false) and tri_state_is(result.get("sidecar_persisted",null),true) and saved.get("bytes",PackedByteArray())==original and b.write_calls==2 and b.rename_calls==2,"Same bytes still traverse exact tmp/rename/readback")
	if failures:b.free();quit(1);return
	prepared=write_frame(b,same_candidate)
	if not check(prepared.get("ok",false),"Existing exact target prepares for CAS refusal"):b.free();quit(1);return
	b.quest_save_serial+=1
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	check(not result.get("ok",true) and not result.get("operation_attempted",true) and tri_state_is(result.get("sidecar_persisted",null),true) and result.get("target_state","")=="matches" and raw(b.resume_path).get("bytes",PackedByteArray())==original,"CAS rejection before new I/O still reports already-matching target bytes")
	if failures:b.free();quit(1);return
	prepared=write_frame(b,same_candidate)
	if not check(prepared.get("ok",false),"Existing exact target prepares for injected write failure"):b.free();quit(1);return
	b.io_mode="open_tmp_failure"
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	saved=raw(b.resume_path)
	check(not result.get("ok",true) and result.get("operation_attempted",false) and not result.get("operation_completed",true) and tri_state_is(result.get("sidecar_persisted",null),true) and result.get("target_state","")=="matches" and saved.get("bytes",PackedByteArray())==original,"Failed new I/O is distinct from already-matching target bytes")
	if failures:b.free();quit(1);return
	b.free()

	b=new_backend("preserve-existing")
	var existing:Dictionary=old.duplicate(true);existing["other_resume"]={"keep":true}
	var existing_bytes:PackedByteArray=native_bytes(existing)
	check(put_fixture(b.resume_path,existing_bytes),"Independent seed writes complete existing sidecar bytes")
	if failures:b.free();quit(1);return
	candidate=fence_from(existing,b)
	prepared=write_frame(b,candidate)
	check(prepared.get("ok",false),"Existing normal sidecar permits only removal of quest intent plus matching fence")
	if failures:b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	saved=raw(b.resume_path)
	var parsed:Variant=JSON.to_native(JSON.parse_string(saved.bytes.get_string_from_utf8()))
	check(result.get("ok",false) and parsed==candidate and parsed.get("other_resume",{})=={"keep":true} and not parsed.has("quest_auto"),"Fence preserves unrelated sidecar payload byte-semantics exactly")
	b.free()

	# Real production source boundaries: no battle actions are submitted.
	# Area 208/group 324 yields one to five actors, all from original source enemy
	# 450; area 88/group 414 yields original source enemy 563.
	if not verify_real_typed_checkpoint("adult-source-checkpoint",10204,Vector2i(20,20),208,324,450,"adult_battle"):
		quit(1);return
	if failures:quit(1);return
	if not verify_real_typed_checkpoint("wood-source-checkpoint",200,Vector2i(700,345),88,414,563,"wood_battle"):
		quit(1);return
	if failures:quit(1);return

	# Existing sidecars are accepted only in the bounded JSON.from_native
	# envelope subset. Plain JSON and malformed nested envelopes fail before
	# JSON.to_native (which emits engine ERRORs for malformed type tags).
	var malformed_cases:Array[Dictionary]=[
		{"label":"plain-json-dictionary","json":{"kind":"hunt","queue":[1]}},
		{"label":"root-missing-type","json":{"args":[]}},
		{"label":"root-invalid-type","json":{"type":"Object","args":[]}},
		{"label":"root-invalid-shape","json":{"type":"Dictionary","args":"not-an-array"}},
		{"label":"root-odd-args","json":{"type":"Dictionary","args":["s:unpaired"]}},
		{"label":"string-stringname-same-name","json":{"type":"Dictionary","args":["s:alias","s:string","sn:alias","s:name"]}},
		{"label":"stringname-string-same-name-reversed","json":{"type":"Dictionary","args":["sn:alias","s:name","s:alias","s:string"]}},
		{"label":"duplicate-stringname-raw-token","json":{"type":"Dictionary","args":["sn:repeat","s:first","sn:repeat","s:second"]}},
		{"label":"dictionary-unknown-key-prefix","json":{"type":"Dictionary","args":["unknown:key","s:value"]}},
		{"label":"nested-missing-type","json":{"type":"Dictionary","args":["s:nested",{}]}},
		{"label":"nested-invalid-type","json":{"type":"Dictionary","args":["s:nested",{"type":"Object","args":[]}]}},
		{"label":"nested-invalid-shape","json":{"type":"Dictionary","args":["s:nested",{"type":"Dictionary","args":["s:unpaired"]}]}},
		{"label":"nested-raw-number","json":{"type":"Dictionary","args":["s:number",1]}},
		{"label":"typed-string-array-stringname-tag","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":"StringName","args":["sn:attack"]}]}},
		{"label":"typed-string-array-type-bool","json":{"type":"Dictionary","args":["s:turn_order",{"type":false,"elem_type":"String","args":[]}]}},
		{"label":"typed-string-array-type-number","json":{"type":"Dictionary","args":["s:turn_order",{"type":1,"elem_type":"String","args":[]}]}},
		{"label":"typed-string-array-type-array","json":{"type":"Dictionary","args":["s:turn_order",{"type":[],"elem_type":"String","args":[]}]}},
		{"label":"typed-string-array-element-type-bool","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":false,"args":[]}]}},
		{"label":"typed-string-array-element-type-number","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":1,"args":[]}]}},
		{"label":"typed-string-array-element-type-array","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":[],"args":[]}]}},
		{"label":"typed-string-array-args-bool","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":"String","args":false}]}},
		{"label":"typed-string-array-args-number","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":"String","args":1}]}},
		{"label":"typed-string-array-args-string","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":"String","args":"not-array"}]}},
		{"label":"typed-string-array-wrong-element-type","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":"String","args":[7]}]}},
		{"label":"typed-string-array-wrong-element-token","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":"String","args":["plain"]}]}},
		{"label":"typed-array-unknown-element-tag","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":"UnknownTyped","args":[]}]}},
		{"label":"typed-array-missing-element-tag","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","args":[]}]}},
		{"label":"typed-array-extra-envelope-key","json":{"type":"Dictionary","args":["s:turn_order",{"type":"Array","elem_type":"String","args":[],"extra":"rejected"}]}},
		{"label":"object-envelope","json":{"type":"Dictionary","args":["s:checkpoint",{"type":"Object","class":"Resource","props":[]}]}},
		{"label":"invalid-json-syntax","raw":"{\"type\":\"Dictionary\",\"args\":["}
	]
	for malformed_case:Dictionary in malformed_cases:
		b=new_backend("malformed-"+str(malformed_case.label))
		var malformed_bytes:PackedByteArray=str(malformed_case.raw).to_utf8_buffer() if malformed_case.has("raw") else JSON.stringify(malformed_case.json).to_utf8_buffer()
		if not check(put_fixture(b.resume_path,malformed_bytes),"Malformed envelope fixture is independently written for "+str(malformed_case.label)):b.free();quit(1);return
		var malformed_target_before:Dictionary=raw(b.resume_path)
		var malformed_tmp_before:Dictionary=raw(b.resume_path+".tmp")
		candidate=only_binding(b)
		prepared=write_frame(b,candidate)
		var expected_malformed_stage:String="existing_sidecar_invalid_json" if malformed_case.label=="invalid-json-syntax" else "existing_sidecar_invalid_native_envelope"
		var malformed_target_after:Dictionary=raw(b.resume_path)
		var malformed_tmp_after:Dictionary=raw(b.resume_path+".tmp")
		check(not prepared.get("ok",true) and prepared.get("stage","")==expected_malformed_stage and not prepared.get("operation_attempted",true) and not prepared.get("operation_completed",true) and same_file_fact(malformed_target_before,malformed_target_after) and same_file_fact(malformed_tmp_before,malformed_tmp_after) and b.write_calls==0 and b.rename_calls==0 and b.remove_calls==0,"Malformed native envelope is rejected before decode and disk mutation: "+str(malformed_case.label))
		b.free()
	if failures:quit(1);return

	b=new_backend("open-failure")
	b.save_path="user://missing-fee-resume-parent-"+run_tag+"/profile.json"
	b.resume_path=b.save_path.get_basename()+".resume.json"
	candidate=fence_from({},b)
	prepared=write_frame(b,candidate)
	check(prepared.get("ok",false),"Missing parent can be prepared without touching disk")
	if failures:b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	check(not result.get("ok",true) and result.get("operation_attempted",false) and not result.get("operation_completed",true) and tri_state_is(result.get("sidecar_persisted",null),false) and result.get("target_state","")=="differs" and result.get("stage","")=="tmp_write_or_readback_failed","Actual FileAccess.open failure reports attempted I/O separately from target mismatch")
	b.free()

	b=new_backend("rename-before")
	b.io_mode="rename_before"
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Rename-failure fixture prepares"):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	var snapshot:=full_disk_snapshot(b)
	check(not result.get("ok",true) and result.get("operation_attempted",false) and not result.get("operation_completed",true) and tri_state_is(result.get("sidecar_persisted",null),false) and result.get("target_state","")=="differs" and snapshot.primary_exists==false and snapshot.tmp_exists and snapshot.tmp_bytes==JSON.stringify(JSON.from_native(candidate)).to_utf8_buffer(),"Injected rename failure leaves exact tmp evidence and reports target mismatch independently")
	b.free()

	b=new_backend("rename-os-failure")
	b.io_mode="rename_os_failure"
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Real rename failure fixture prepares"):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	snapshot=full_disk_snapshot(b)
	check(not result.get("ok",true) and result.get("operation_attempted",false) and not result.get("operation_completed",true) and tri_state_is(result.get("sidecar_persisted",null),"unknown") and result.get("target_state","")=="unknown" and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(b.resume_path)) and snapshot.tmp_exists and snapshot.tmp_bytes==JSON.stringify(JSON.from_native(candidate)).to_utf8_buffer(),"Actual rename against a target directory is UNKNOWN and preserves tmp evidence")
	b.free()

	b=new_backend("rename-after")
	b.io_mode="rename_after"
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Post-rename wrapper fixture prepares"):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	saved=raw(b.resume_path)
	check(not result.get("ok",true) and not result.get("operation_completed",true) and tri_state_is(result.get("sidecar_persisted",null),true) and saved.get("bytes",PackedByteArray())==JSON.stringify(JSON.from_native(candidate)).to_utf8_buffer(),"Wrapper reports rename error after physical rename: target fact is true while operation completion is false")
	b.free()

	b=new_backend("readback-unknown")
	b.io_mode="readback_after_rename"
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Readback fault fixture prepares"):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	saved=raw(b.resume_path)
	check(not result.get("ok",true) and result.get("stage","")=="readback_unknown" and result.get("operation_attempted",false) and result.get("operation_completed",false) and result.get("operation_error",-1)==OK and tri_state_is(result.get("sidecar_persisted",null),"unknown") and tri_state_is(result.get("target_state",null),"unknown") and tri_state_is(result.get("sidecar_exists",null),"unknown") and tri_state_is(result.get("temporary_clear",null),true) and tri_state_is(result.get("temporary_exists",null),false) and saved.get("ok",false) and saved.get("bytes",PackedByteArray())==JSON.stringify(JSON.from_native(candidate)).to_utf8_buffer(),"Readback error keeps API facts unknown, reports completed rename, and independent raw oracle confirms exact disk bytes")
	b.free()

	b=new_backend("serial-before")
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Serial CAS fixture prepares"):b.free();quit(1);return
	b.quest_save_serial+=1
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	snapshot=full_disk_snapshot(b)
	check(not result.get("ok",true) and result.get("operation_attempted",true)==false and tri_state_is(result.get("sidecar_persisted",null),false) and result.get("target_state","")=="differs" and not snapshot.primary_exists and not snapshot.tmp_exists,"Serial successor before I/O reports target mismatch separately from no attempted write")
	b.free()

	for mutation:String in ["resume_path","serial","owner"]:
		b=new_backend("preflight-read-"+mutation)
		var original_resume_path:String=b.resume_path
		var successor_resume_path:String=original_resume_path+".successor" if mutation=="resume_path" else original_resume_path
		var preflight_existing:Dictionary={"kind":"hunt","queue":[3],"map_id":1001}
		var original_target_bytes:PackedByteArray=native_bytes(preflight_existing)
		if not check(put_fixture(original_resume_path,original_target_bytes),"Preflight-read fixture writes original target bytes for "+mutation):b.free();quit(1);return
		var preflight_candidate:Dictionary=fence_from(preflight_existing,b)
		prepared=write_frame(b,preflight_candidate)
		if not check(prepared.get("ok",false),"Preflight-read successor fixture prepares for "+mutation):b.free();quit(1);return
		var old_target_before:Dictionary=raw(original_resume_path)
		var old_tmp_before:Dictionary=raw(original_resume_path+".tmp")
		var new_target_before:Dictionary=raw(successor_resume_path)
		var new_tmp_before:Dictionary=raw(successor_resume_path+".tmp")
		b.io_mode="mutate_on_preflight_"+mutation
		result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
		var old_target_after:Dictionary=raw(original_resume_path)
		var old_tmp_after:Dictionary=raw(original_resume_path+".tmp")
		var new_target_after:Dictionary=raw(successor_resume_path)
		var new_tmp_after:Dictionary=raw(successor_resume_path+".tmp")
		var successor_unchanged:bool=not b.successor_snapshot.is_empty() and b.successor_snapshot.get("profile",{})==b.session._profile and b.successor_snapshot.get("serial",-1)==b.quest_save_serial and b.successor_snapshot.get("save_path","")==b.save_path and b.successor_snapshot.get("resume_path","")==b.resume_path
		var both_preflight_reads_old:bool=false
		if b.preflight_read_facts.size()==2:
			var returned_target:Dictionary=b.preflight_read_facts[0]
			var returned_tmp:Dictionary=b.preflight_read_facts[1]
			both_preflight_reads_old=returned_target.get("path","")==original_resume_path and returned_tmp.get("path","")==original_resume_path+".tmp" and same_file_fact(returned_target,old_target_before) and same_file_fact(returned_tmp,old_tmp_before)
		var same_resume_path:bool=successor_resume_path==original_resume_path
		var expected_target_state:String="differs" if same_resume_path else "unknown"
		var expected_sidecar_exists:Variant=true if same_resume_path else "unknown"
		check(not result.get("ok",true) and result.get("stage","")=="owner_or_cas_after_preflight_reads_before_io" and not result.get("operation_attempted",true) and not result.get("operation_completed",true) and result.get("target_state","")==expected_target_state and tri_state_is(result.get("sidecar_exists",null),expected_sidecar_exists) and b.preflight_read_count==2 and both_preflight_reads_old and b.write_calls==0 and b.rename_calls==0 and b.remove_calls==0,"Both target/tmp preflight callbacks return the old disk facts, then "+mutation+" mutation is rejected before any mutating I/O with path-aware API facts")
		var target_at_current_path_unchanged:bool=false
		if same_resume_path:
			target_at_current_path_unchanged=new_target_after.get("exists",false) and new_target_after.get("bytes",PackedByteArray())==original_target_bytes
		else:
			target_at_current_path_unchanged=not new_target_after.get("exists",true)
		check(same_file_fact(old_target_before,old_target_after) and same_file_fact(old_tmp_before,old_tmp_after) and same_file_fact(new_target_before,new_target_after) and same_file_fact(new_tmp_before,new_tmp_after) and old_target_after.get("bytes",PackedByteArray())==original_target_bytes and target_at_current_path_unchanged and not old_tmp_after.get("exists",true) and not new_tmp_after.get("exists",true),"Old/new target and tmp full byte/existence facts stay unchanged after "+mutation+" pre-write rejection")
		check(successor_unchanged,"Injected successor profile/serial/path remains unchanged after stale "+mutation+" frame returns")
		b.free()

	b=new_backend("owner-after")
	b.io_mode="owner_nested_after_rename";candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Post-write owner fixture prepares"):b.free();quit(1);return
	b.nested_handle={"call":prepared.call}
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	saved=raw(b.resume_path)
	check(not result.get("ok",true) and tri_state_is(result.get("sidecar_persisted",null),true) and result.get("stage","")=="owner_changed_after_io" and b.nested_result.get("stage","")=="already_executing" and b.rename_calls==1,"Post-write owner change reports landed bytes and nested same-handle commit performs no second write")
	b.free()

	for mutation:String in ["serial","path","resume_path","owner"]:
		b=new_backend("before-rename-"+mutation)
		var frozen_path:String=b.resume_path
		candidate=only_binding(b);prepared=write_frame(b,candidate)
		if not check(prepared.get("ok",false),"Before-rename mutation fixture prepares"):b.free();quit(1);return
		b.io_mode="mutate_on_tmp_pre_"+mutation
		result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
		var frozen_target:Dictionary=raw(frozen_path)
		var frozen_tmp:Dictionary=raw(frozen_path+".tmp")
		var current_target:Dictionary=raw(b.resume_path)
		var no_new_target:bool=not current_target.get("exists",false)
		if b.resume_path!=frozen_path:
			var current_tmp:Dictionary=raw(b.resume_path+".tmp")
			no_new_target=no_new_target and not current_tmp.get("exists",false)
		check(not result.get("ok",true) and not result.get("operation_completed",true) and b.rename_calls==0 and no_new_target and not frozen_target.get("exists",false) and frozen_tmp.get("exists",false) and frozen_tmp.get("bytes",PackedByteArray())==JSON.stringify(JSON.from_native(candidate)).to_utf8_buffer(),""+mutation+" change at final tmp-read callback is fenced before rename and old/new paths remain inspectable")
		b.free()

	b=new_backend("target-read-cas")
	candidate=only_binding(b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Target-read CAS fixture prepares"):b.free();quit(1);return
	b.io_mode="mutate_on_target_pre_serial"
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	var target_read_snapshot:=full_disk_snapshot(b)
	check(not result.get("ok",true) and b.rename_calls==0 and not target_read_snapshot.primary_exists and target_read_snapshot.tmp_exists,"Owner/serial mutation during target_pre read is rechecked before rename")
	b.free()

	b=new_backend("profile-successor")
	b.io_mode="profile_after_rename"
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Profile-object successor fixture prepares"):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	saved=raw(b.resume_path)
	check(not result.get("ok",true) and tri_state_is(result.get("sidecar_persisted",null),true) and result.get("stage","")=="owner_changed_after_io" and saved.get("bytes",PackedByteArray())==JSON.stringify(JSON.from_native(candidate)).to_utf8_buffer(),"Same-value profile object replacement fences old completion but reports bytes already landed")
	b.free()

	b=new_backend("disk-successor")
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Disk-successor fixture prepares"):b.free();quit(1);return
	var successor_bytes:PackedByteArray=native_bytes({"external":"newer bytes"})
	check(put_fixture(b.resume_path,successor_bytes),"Independent actor replaces target after prepare")
	if failures:b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	saved=raw(b.resume_path);snapshot=full_disk_snapshot(b)
	check(not result.get("ok",true) and result.get("operation_attempted",true)==false and tri_state_is(result.get("sidecar_persisted",null),false) and result.get("target_state","")=="differs" and tri_state_is(result.get("sidecar_exists",null),true) and saved.get("bytes",PackedByteArray())==successor_bytes and not snapshot.tmp_exists,"Known external disk successor differs from expected target and is preserved byte-exactly")
	b.free()

	b=new_backend("path-successor")
	var path_before_successor:String=b.resume_path
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Path-successor fixture prepares"):b.free();quit(1);return
	b.save_path+=".moved"
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	var old_path_target:Dictionary=raw(path_before_successor)
	var old_path_tmp:Dictionary=raw(path_before_successor+".tmp")
	check(not result.get("ok",true) and tri_state_is(result.get("sidecar_persisted",null),false) and tri_state_is(result.get("sidecar_exists",null),false) and not old_path_target.get("exists",false) and not old_path_tmp.get("exists",false),"Save-path change refuses I/O while the still-bound resume target is independently observed absent")
	b.free()

	b=new_backend("profile-before")
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Profile-object prewrite fixture prepares"):b.free();quit(1);return
	b.session._profile=b.session._profile.duplicate(true)
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	snapshot=full_disk_snapshot(b)
	check(not result.get("ok",true) and tri_state_is(result.get("sidecar_persisted",null),false) and not snapshot.primary_exists and not snapshot.tmp_exists,"Profile-object replacement before I/O writes no bytes")
	b.free()

	b=new_backend("stale-temp")
	# Deliberately malformed obstruction bytes: an existing .tmp is refused by
	# existence before the sidecar envelope decoder is reached.
	var stale:=PackedByteArray([1,2,3])
	check(put_fixture(b.resume_path+".tmp",stale),"Stale tmp fixture bytes captured")
	if failures:b.free();quit(1);return
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	check(not prepared.get("ok",true) and prepared.get("stage","")=="temporary_already_exists" and raw(b.resume_path+".tmp").bytes==stale,"Preexisting temp is refused and preserved byte-exactly")
	b.free()

	b=new_backend("remove-absent")
	var absent_close:=Journal.close_run(b.session._profile.quest_auto_fee_lifecycle,RUN)
	if not check(absent_close.get("ok",false),"Absent-remove close transition is available"):b.free();quit(1);return
	b.session._profile["quest_auto_fee_lifecycle"]=absent_close.candidate
	b.last_saved_payload=JSON.stringify(b.session._profile);b.quest_save_serial+=1
	delete_frame=remove_frame(b)
	check(delete_frame.get("ok",false),"Closed profile can verify already-absent fence without a delete")
	if not delete_frame.get("ok",false):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":delete_frame.call})
	check(result.get("ok",false) and tri_state_is(result.get("sidecar_persisted",null),true) and tri_state_is(result.get("sidecar_exists",null),false) and b.remove_calls==0,"Already-absent sidecar is verified idempotently without broad deletion")
	b.free()

	b=new_backend("remove-absent-cas")
	var absent_cas:=Journal.close_run(b.session._profile.quest_auto_fee_lifecycle,RUN)
	if not check(absent_cas.get("ok",false),"Absent-remove CAS close transition is available"):b.free();quit(1);return
	b.session._profile["quest_auto_fee_lifecycle"]=absent_cas.candidate
	b.last_saved_payload=JSON.stringify(b.session._profile);b.quest_save_serial+=1
	delete_frame=remove_frame(b)
	if not check(delete_frame.get("ok",false),"Absent-remove CAS fixture prepares"):b.free();quit(1);return
	b.quest_save_serial+=1
	result=b._commit_fee_resume_sidecar_frame({"call":delete_frame.call})
	check(not result.get("ok",true) and not result.get("operation_attempted",true) and tri_state_is(result.get("sidecar_persisted",null),true) and tri_state_is(result.get("sidecar_exists",null),false),"CAS refusal with already-absent remove target reports verified absence, not false persistence")
	b.free()

	b=new_backend("remove")
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Delete setup fence frame prepares"):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	if not check(result.get("ok",false),"Delete setup writes verified fence"):b.free();quit(1);return
	var close:=Journal.close_run(b.session._profile.quest_auto_fee_lifecycle,RUN)
	if not check(close.get("ok",false) and Journal.valid(close.get("candidate",{})),"Independent pure close transition validates"):b.free();quit(1);return
	b.session._profile["quest_auto_fee_lifecycle"]=close.candidate
	b.last_saved_payload=JSON.stringify(b.session._profile);b.quest_save_serial+=1
	delete_frame=remove_frame(b)
	check(delete_frame.get("ok",false),"Only exact closed-run fence can prepare removal")
	if not delete_frame.get("ok",false):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":delete_frame.call})
	saved=raw(b.resume_path)
	check(result.get("ok",false) and tri_state_is(result.get("sidecar_persisted",null),true) and tri_state_is(result.get("sidecar_exists",null),false) and saved.get("ok",false) and not saved.get("exists",true),"Exact fence delete verifies target absence")
	b.free()

	b=new_backend("remove-unrelated")
	var close_unrelated:=Journal.close_run(b.session._profile.quest_auto_fee_lifecycle,RUN)
	if not check(close_unrelated.get("ok",false),"Unrelated-key removal close transition is available"):b.free();quit(1);return
	b.session._profile["quest_auto_fee_lifecycle"]=close_unrelated.candidate
	b.last_saved_payload=JSON.stringify(b.session._profile);b.quest_save_serial+=1
	var unrelated:Dictionary={"fee_attempt_binding":binding_for(b),"kind":"hunt","battle":{"battle_id":"keep"},"map_id":1000}
	var unrelated_bytes:PackedByteArray=JSON.stringify(JSON.from_native(unrelated)).to_utf8_buffer()
	check(put_fixture(b.resume_path,unrelated_bytes),"Unrelated hunt/battle sidecar fixture written exactly")
	if failures:b.free();quit(1);return
	delete_frame=remove_frame(b)
	var unrelated_after:Dictionary=raw(b.resume_path)
	check(not delete_frame.get("ok",true) and delete_frame.get("stage","")=="fence_not_standalone" and unrelated_after.get("bytes",PackedByteArray())==unrelated_bytes,"Remove rejects unrelated hunt/battle keys and preserves every byte")
	b.free()

	b=new_backend("remove-before")
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Remove-before setup frame prepares"):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	if not check(result.get("ok",false),"Remove-before setup fence lands"):b.free();quit(1);return
	var closed_before_remove:=Journal.close_run(b.session._profile.quest_auto_fee_lifecycle,RUN)
	if not check(closed_before_remove.get("ok",false),"Remove-before close transition is available"):b.free();quit(1);return
	b.session._profile["quest_auto_fee_lifecycle"]=closed_before_remove.candidate
	b.last_saved_payload=JSON.stringify(b.session._profile);b.quest_save_serial+=1
	delete_frame=remove_frame(b)
	if not check(delete_frame.get("ok",false),"Remove-before frame prepares"):b.free();quit(1);return
	var fence_before_failed_remove:PackedByteArray=raw(b.resume_path).bytes
	b.io_mode="remove_before"
	result=b._commit_fee_resume_sidecar_frame({"call":delete_frame.call})
	saved=raw(b.resume_path)
	check(not result.get("ok",true) and result.get("operation_attempted",false) and not result.get("operation_completed",true) and tri_state_is(result.get("sidecar_persisted",null),false) and result.get("target_state","")=="differs" and saved.get("bytes",PackedByteArray())==fence_before_failed_remove,"Delete error before removal preserves exact prior fence bytes")
	b.free()

	b=new_backend("remove-after")
	candidate=fence_from({},b);prepared=write_frame(b,candidate)
	if not check(prepared.get("ok",false),"Remove-after setup frame prepares"):b.free();quit(1);return
	result=b._commit_fee_resume_sidecar_frame({"call":prepared.call})
	if not check(result.get("ok",false),"Remove-after setup fence lands"):b.free();quit(1);return
	var closed_remove:=Journal.close_run(b.session._profile.quest_auto_fee_lifecycle,RUN)
	if not check(closed_remove.get("ok",false),"Remove-after close transition is available"):b.free();quit(1);return
	b.session._profile["quest_auto_fee_lifecycle"]=closed_remove.candidate
	b.last_saved_payload=JSON.stringify(b.session._profile);b.quest_save_serial+=1
	delete_frame=remove_frame(b)
	if not check(delete_frame.get("ok",false),"Post-remove-wrapper fixture prepares"):b.free();quit(1);return
	var fence_before_remove:PackedByteArray=raw(b.resume_path).bytes
	b.io_mode="remove_after"
	result=b._commit_fee_resume_sidecar_frame({"call":delete_frame.call})
	saved=raw(b.resume_path)
	check(not result.get("ok",true) and result.get("operation_attempted",false) and not result.get("operation_completed",true) and tri_state_is(result.get("sidecar_persisted",null),true) and result.get("target_state","")=="matches" and tri_state_is(result.get("sidecar_exists",null),false) and not saved.get("exists",true) and fence_before_remove.size()>0,"Remove wrapper error after actual deletion reports verified absence, not rollback")
	b.free()

	print("FEE_RESUME_SIDECAR checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
