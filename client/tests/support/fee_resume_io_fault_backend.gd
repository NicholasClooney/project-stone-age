extends "res://server/backend.gd"

## Faults are injected only at the private sidecar OS-call seams. Every mode is
## explicit; there is no client/RPC path to this subclass or these switches.
var io_mode := ""
var nested_handle: Variant
var nested_result: Dictionary = {}
var write_calls := 0
var rename_calls := 0
var remove_calls := 0
var target_reads_after_tmp := 0
var fail_target_read_once := false
var preflight_read_count:=0
var preflight_read_facts:Array[Dictionary]=[]
var successor_snapshot:Dictionary={}

func _fee_resume_io_read(path:String)->Dictionary:
	var result:Dictionary=super._fee_resume_io_read(path)
	if fail_target_read_once and path==_resume_file():
		fail_target_read_once=false
		return {"ok":false,"exists":true,"error":ERR_FILE_CANT_READ,"bytes":PackedByteArray()}
	if write_calls==0 and rename_calls==0 and io_mode.begins_with("mutate_on_preflight_") and (path==_resume_file() or path==_resume_file()+".tmp"):
		preflight_read_count+=1
		preflight_read_facts.append({"path":path,"ok":result.get("ok",false),"exists":result.get("exists",false),"bytes":result.get("bytes",PackedByteArray())})
		if preflight_read_count==2:
			_apply_frame_mutation(io_mode.trim_prefix("mutate_on_preflight_"))
			successor_snapshot={"profile":session._profile.duplicate(true),"serial":quest_save_serial,"save_path":save_path,"resume_path":resume_path}
	if write_calls>0 and rename_calls==0 and path==_resume_file():
		target_reads_after_tmp+=1
		if target_reads_after_tmp==1 and io_mode.begins_with("mutate_on_target_pre_"):
			_apply_frame_mutation(io_mode.trim_prefix("mutate_on_target_pre_"))
	elif write_calls>0 and rename_calls==0 and path==_resume_file()+".tmp":
		if target_reads_after_tmp>=1 and io_mode.begins_with("mutate_on_tmp_pre_"):
			_apply_frame_mutation(io_mode.trim_prefix("mutate_on_tmp_pre_"))
	return result

func _apply_frame_mutation(kind:String)->void:
	io_mode="mutated"
	if kind=="serial":quest_save_serial+=1
	elif kind=="path":save_path+=".successor"
	elif kind=="resume_path":resume_path+=".successor"
	elif kind=="profile":session._profile=session._profile.duplicate(true)
	elif kind=="owner":session._profile.profile_id+="-successor"

func _fee_resume_io_write_tmp(payload:PackedByteArray)->Dictionary:
	write_calls+=1
	if io_mode=="open_tmp_failure":return {"ok":false,"stage":"injected_open_tmp_failure","error":ERR_CANT_CREATE}
	return super._fee_resume_io_write_tmp(payload)

func _fee_resume_io_rename()->int:
	rename_calls+=1
	if io_mode=="rename_before":return ERR_CANT_CREATE
	if io_mode=="rename_os_failure":
		var absolute:String=ProjectSettings.globalize_path(_resume_file())
		var made:int=DirAccess.make_dir_absolute(absolute)
		if made!=OK:return made
		return super._fee_resume_io_rename()
	var result:int=super._fee_resume_io_rename()
	if io_mode=="rename_after":return ERR_CANT_CREATE
	if io_mode=="owner_nested_after_rename":quest_save_serial+=1
	if io_mode=="profile_after_rename":session._profile=session._profile.duplicate(true)
	if io_mode=="owner_nested_after_rename":nested_result=_commit_fee_resume_sidecar_frame(nested_handle)
	if io_mode=="readback_after_rename":fail_target_read_once=true
	return result

func _fee_resume_io_remove()->int:
	remove_calls+=1
	if io_mode=="remove_before":return ERR_CANT_CREATE
	var result:int=super._fee_resume_io_remove()
	if io_mode=="remove_after":return ERR_CANT_CREATE
	return result
