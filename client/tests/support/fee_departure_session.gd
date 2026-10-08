extends "res://server/game_session.gd"
var fail_write:=0
var after_false:=false
var writes:=0
var unknown:=false
var callback_write:=1
var callback:Callable
var read_callback:Callable
func _write_profile_candidate(candidate:Dictionary,path:String)->bool:
	writes+=1
	if writes==fail_write and not after_false:return false
	var result:bool=super._write_profile_candidate(candidate,path)
	if callback.is_valid() and writes==callback_write:
		var call:Callable=callback;callback=Callable();call.call()
	return false if writes==fail_write and after_false else result
func _read_fee_attempt_file(path:String,expected:PackedByteArray)->Dictionary:
	var result:Dictionary=super._read_fee_attempt_file(path,expected)
	if read_callback.is_valid():
		var call:Callable=read_callback;read_callback=Callable();call.call()
	return {"ok":false,"exists":true} if unknown else result
