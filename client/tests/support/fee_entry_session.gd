extends "res://tests/support/fee_lobby_ticket_fault_session.gd"
var entry_read_mode:String=""
var entry_reads:int=0
var entry_unknown_observations:Array=[]
func _read_fee_attempt_file(path:String,bytes:PackedByteArray)->Dictionary:
	var result:Dictionary=super._read_fee_attempt_file(path,bytes)
	var b=host.get_ref() if host!=null else null
	if b==null or b._fee_lobby_ticket_entry._op.is_empty():return result
	entry_reads+=1
	if entry_read_mode=="pre_unknown" and b.entry_writes==0:return {"ok":false,"exists":true}
	if entry_read_mode=="writer_pre_unknown" and b.entry_writes>0 and not b._fee_lobby_ticket_entry._op.io_entered:
		entry_unknown_observations.append({"read":entry_reads,"path":path,"io_entered":b._fee_lobby_ticket_entry._op.io_entered,"physical_ran":b._fee_lobby_ticket_entry._op.physical_ran})
		return {"ok":false,"exists":true}
	if entry_read_mode=="post_unknown" and b._fee_lobby_ticket_entry._op.io_entered:return {"ok":false,"exists":true}
	if entry_read_mode=="read_owner" and b._fee_lobby_ticket_entry._op.io_entered:b.replace_owner()
	return result

# Exact d6691c7f shared writer body; renamed only for test comparison.
func _parent_physical_writer(candidate:Dictionary,path:String)->bool:
	if _fee_purchase_write_refused(candidate,path):return false
	var proof:Dictionary=_loot_failure_active
	if not proof.is_empty():
		proof.entries+=1
		if proof.entries!=1 or path!=proof.path or candidate!=proof.candidate or not _loot_failure_scope_current(proof):return false
		var ready:bool=_loot_failure_pre_io_ready()
		# The seam can reenter or replace owner; no old write follows it.
		if proof.entries!=1 or not is_same(_loot_failure_active,proof) or not _loot_failure_scope_current(proof):return false
		if not ready:
			proof.pre_io_refused=true
			return false
		proof.io_entered=true # From here ANY failure is partial/unknown.
	var file := FileAccess.open(path + ".tmp",FileAccess.WRITE)
	if file == null:
		last_error = "Cannot create save."
		return false
	file.store_string(JSON.stringify(candidate))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) and _valid_profile(_parse_save(FileAccess.get_file_as_string(path))):
		if DirAccess.copy_absolute(absolute,absolute + ".bak") != OK:
			return false
	return DirAccess.rename_absolute(absolute + ".tmp",absolute) == OK

## One forced physical fee-fence write. This deliberately bypasses Backend.save()'s
## same-payload fast path, but does not install/normalize profile state. The
