extends "res://server/backend.gd"
## Test-only real save seam. No fabricated writer success or disk repair.
const NewSession=preload("res://server/game_session.gd")
const NewIdentity=preload("res://server/quest_auto_state.gd")
var enabled:bool=true
var doctor_enabled:bool=false
func _doctor_request_enabled()->bool:return doctor_enabled
var fault:String=""
var armed:bool=false
var writes:int=0
var actual_save:Variant=null
var at_return:Dictionary={}
var successor_call:Dictionary={}
var old_session:RefCounted
var old_profile_after:Dictionary={}
func _saton_request_enabled()->bool:return enabled
func disk_rows()->Array:
	var result:Array=[]
	for suffix in ["", ".bak", ".tmp"]:
		var exists:bool=FileAccess.file_exists(save_path+suffix)
		result.append({"exists":exists,"bytes":FileAccess.get_file_as_bytes(save_path+suffix) if exists else PackedByteArray()})
	return result
func arrival_state()->Dictionary:
	var result:Dictionary={}
	# Every script variable, including authority tokens/cache values; no decoding.
	for row in quest_arrival.get_property_list():
		if (int(row.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE)!=0:
			var value:Variant=quest_arrival.get(row.name)
			result[row.name]=value.duplicate(true) if value is Dictionary or value is Array else value
	return result
func whole_state()->Dictionary:
	return {"profile":session._profile.duplicate(true),"session_pending":session._pending.duplicate(true),"arrival":arrival_state(),"pending":original_quests.pending.duplicate(true),"cache":last_saved_payload,"serial":quest_save_serial,"disks":disk_rows(),"checkpoint":quest_auto.identity.checkpoint(),"phase":quest_auto.phase,"running":quest_auto.running,"internal":quest_auto.internal,"connection":quest_auto.connection,"binding":_fee_bindings.get(61515)}
func save()->bool:
	if not armed:return super.save()
	armed=false;writes+=1
	var written:bool=false
	if fault=="success" or fault.ends_with("after"):
		written=super.save()
	actual_save=written
	old_session=session
	old_profile_after=session._profile.duplicate(true)
	if fault.begins_with("session_"):
		var next=NewSession.new()
		next._profile=session._profile.duplicate(true)
		next._profile.player.gold+=17
		next._profile.character_id="100005"
		session=next
	elif fault.begins_with("run_"):
		quest_auto.identity=NewIdentity.new()
		quest_auto.identity.begin()
		quest_auto.phase="successor"
		quest_auto.internal=false
	elif fault.begins_with("binding_"):
		_fee_bindings[61515]=RefCounted.new()
	if fault.contains("_"):
		original_quests.pending={"successor":fault,"native_key":Vector2i(3,4)}
		quest_arrival._marks["successor"]={"value":fault}
		if fault.begins_with("registration_"):
			successor_call={"successor":RefCounted.new()}
			_saton_request_call=successor_call
	at_return=whole_state()
	return written if fault=="success" or fault.ends_with("after") and fault.contains("_") else false
