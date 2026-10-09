extends "res://server/game_session.gd"
## Read/return faults never manufacture successful physical IO.
var host:WeakRef
var mode:String=""
var reads:int=0
var trace:Array=[]
var snapshots:int=0
var shared_calls:int=0
var parent_body:bool=false
var loader_fault:String=""
var nested_loader_rejected:bool=false
func snapshot()->Dictionary:
	snapshots+=1
	return super.snapshot()
func _read_fee_attempt_file(path:String,bytes:PackedByteArray)->Dictionary:
	reads+=1
	var row:Dictionary=super._read_fee_attempt_file(path,bytes)
	var b=host.get_ref()
	var io:bool=is_instance_valid(b) and b._required_fee_runner._op.get("io_entered",false)
	trace.append({"read":reads,"path":path,"io_entered":io,"actual":row.duplicate(true)})
	if mode=="pre_unknown" and reads<=3:return {"ok":false,"exists":true}
	if mode=="writer_pre_unknown" and reads>=4 and reads<=6:return {"ok":false,"exists":true}
	if mode=="post_unknown" and io:return {"ok":false,"exists":true}
	if mode=="load_unknown":return {"ok":false,"exists":true}
	return row
func _write_profile_candidate(candidate:Dictionary,path:String)->bool:
	shared_calls+=1
	if not _required_fee_loader_write.is_empty():
		if loader_fault=="before":return false
		if loader_fault=="nested":nested_loader_rejected=not super._write_profile_candidate(candidate.duplicate(true),path)
	var result:bool=_parent_physical_writer(candidate,path) if parent_body else super._write_profile_candidate(candidate,path)
	if not _required_fee_loader_write.is_empty() and loader_fault=="after":return false
	return result
# Exact fixed-parent shared physical function, only name changed. Candidate
# environment comparison, not execution of an entire second parent checkout.
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
## Backend must perform owner/profile/cache/serial CAS around every invocation.
