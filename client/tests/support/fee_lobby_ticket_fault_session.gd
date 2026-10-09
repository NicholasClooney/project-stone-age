extends "res://server/game_session.gd"
var host:WeakRef
var mode:=""
var save_mode:=""
func save_game(path:String)->bool:
	if save_mode=="false_before":return false
	return super.save_game(path)
var at:int=0
var writes:int=0
var reads:int=0
var snapshot_calls:int=0
var calls:Array=[]
func snapshot()->Dictionary:
	snapshot_calls+=1
	return super.snapshot()
func lobby_write(b,call:RefCounted,candidate:Dictionary)->bool:
	writes+=1;calls.append(candidate.duplicate(true))
	if writes==at and mode=="false_before":return false
	if writes==at and mode=="raw_forged":return true
	if writes==at and mode=="candidate_unrelated":candidate.player.hp-=1
	var actual:bool=b._fee_lobby_ticket.write_physical(b,call,candidate)
	if writes==at:
		match mode:
			"false_after":return false
			"binding":b.fee_attach(71)
			"serial":b.quest_save_serial+=9
			"path":b.save_path+=".successor"
			"owner":_profile=_profile.duplicate(true);_profile.character_id="100005"
			"profile_ref":_profile=_profile.duplicate(true)
			"session":
				var successor=preload("res://server/game_session.gd").new(func():return 1791504000)
				successor._profile=_profile.duplicate(true);b.session=successor
				successor.battle_pets_hook=b._live_battle_pets;successor.capture_entry_hook=b._capture_entry
			"run":b.quest_auto.identity.begin()
			"nested":b._fee_lobby_ticket.persist(b,b._fee_lobby_ticket._op.call)
	return actual
func _read_fee_attempt_file(path:String,bytes:PackedByteArray)->Dictionary:
	reads+=1
	var row:Dictionary=super._read_fee_attempt_file(path,bytes)
	if writes==at and mode=="unknown":return {"ok":false,"exists":true}
	return row

var shared_calls:int=0
var loader_fault:String=""
var loader_nested_rejected:bool=false
var use_parent_writer:bool=false
func _write_profile_candidate(candidate:Dictionary,path:String)->bool:
	shared_calls+=1
	if not _fee_purchase_loader_write.is_empty():
		if loader_fault=="before":return false
		if loader_fault=="nested":
			loader_nested_rejected=not super._write_profile_candidate(candidate.duplicate(true),path)
	if use_parent_writer:return _parent_physical_writer(candidate,path)
	var result:bool=super._write_profile_candidate(candidate,path)
	if not _fee_purchase_loader_write.is_empty() and loader_fault=="after":return false
	return result

# Exact 7b48e391 original physical body, static blob/SHA-locked. Test only.
func _parent_physical_writer(candidate:Dictionary,path:String)->bool:
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
