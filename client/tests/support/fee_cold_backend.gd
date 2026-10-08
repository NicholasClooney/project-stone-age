extends "res://server/backend.gd"
## UNRUN static candidate. Faults are armed only after genuine load.
var enabled := true
var mode := ""
var side_reads := 0
var side_writes := 0
var side_removes := 0
var generic_writes := 0
var generic_removes := 0
var nested_routed := false
var wrong_retire_denied := false
var failed_load_called := false
var failed_load_result := true
var observed_retire: Dictionary = {}
func _fee_cold_lifecycle_enabled()->bool:return enabled
func _persist_fee_loaded_baseline(handle:Variant)->Dictionary:
	if mode == "forge_baseline_ok":return {"ok":true}
	var result:Dictionary=super._persist_fee_loaded_baseline(handle)
	if mode == "baseline_wrapper_false":result.ok=false
	if mode.begins_with("close_"):
		session.close_mode=mode.trim_prefix("close_").get_slice(":",0)
		session.fault_write=int(mode.get_slice(":",1))
	if mode == "nested":nested_routed=_prepare_fee_cold_open()
	return result
func _persist_fee_recovered_close(handle:Variant)->Dictionary:
	if mode == "forge_close_ok":return {"ok":true}
	var result:Dictionary=super._persist_fee_recovered_close(handle)
	observed_retire=_fee_recovered_close_writer._retire
	wrong_retire_denied=_fee_recovered_close_writer.take_retire(self,RefCounted.new(),RefCounted.new()).is_empty() and _fee_recovered_close_writer.take_retire(self,_fee_cold_lifecycle,RefCounted.new()).is_empty()
	if mode == "close_wrapper_false":result.ok=false
	return result
func _commit_fee_resume_closed_retire_frame(handle:Variant)->Dictionary:
	if mode == "forge_retire_ok":return {"ok":true}
	var result:Dictionary=super._commit_fee_resume_closed_retire_frame(handle)
	if mode == "retire_wrapper_false":result.ok=false
	return result
func _fee_resume_io_read(path:String)->Dictionary:
	side_reads+=1
	var result:Dictionary=super._fee_resume_io_read(path)
	if side_reads==2 and mode=="marker_successor":
		var state:Dictionary=JSON.to_native(JSON.parse_string(result.bytes.get_string_from_utf8()),false)
		state.quest_auto.identity.step_id="jewels:hunt:2760"
		var file:=FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(JSON.stringify(JSON.from_native(state)).to_utf8_buffer());file.close()
	if side_reads==7 and mode=="load_failed":
		failed_load_called=true
		failed_load_result=load_profile(save_path+".bad")
	if side_reads==3:
		if mode == "read_unknown":return {"ok":false,"exists":true}
		if mode == "read_owner":session._profile=session._profile.duplicate(true);session._profile.profile_id="read-successor"
		if mode == "loot_callback":session._loot_failure_active={"private":RefCounted.new()}
	return result
func _fee_resume_io_remove()->int:
	side_removes+=1
	if mode == "remove_fail":return ERR_CANT_CREATE
	var result:int=super._fee_resume_io_remove()
	return ERR_CANT_CREATE if mode == "remove_after_false" else result
func _fee_resume_io_write_tmp(payload:PackedByteArray)->Dictionary:
	side_writes+=1
	if mode == "write_tmp_false":return {"ok":false,"error":ERR_CANT_CREATE}
	return super._fee_resume_io_write_tmp(payload)
func _fee_resume_io_rename()->int:
	if mode == "rename_fail":return ERR_CANT_CREATE
	var result:int=super._fee_resume_io_rename()
	return ERR_CANT_CREATE if mode == "rename_after_false" else result
func _write_resume_file(path:String,state:Dictionary)->void:
	generic_writes+=1
	super._write_resume_file(path,state)
func _remove_resume_file(path:String)->void:
	generic_removes+=1
	super._remove_resume_file(path)
