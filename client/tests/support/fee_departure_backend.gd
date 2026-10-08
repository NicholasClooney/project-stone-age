extends "res://server/backend.gd"
## Static candidate fault seams: real writers unless a named fault is armed.
var gate:=true
var hook:Callable
var at:=""
var fired:=0
var side_fault:=""
var battle_commands:=0
func _fee_departure_enabled()->bool:return gate
func fire(point:String)->void:
	if point!=at or not hook.is_valid():return
	at="";fired+=1
	hook.call()
func publish()->void:
	super.publish()
	fire("publish")
func emit_event(message:Dictionary)->void:
	super.emit_event(message)
	fire("event")
func set_capture_assist(enabled:bool)->void:
	super.set_capture_assist(enabled)
	fire("assist")
func battle_command(command:Dictionary)->Dictionary:
	battle_commands+=1
	var result:Dictionary=super.battle_command(command)
	fire("battle_command")
	return result
func _begin_quest_auto_stop_operation(owner_auto:Variant)->Dictionary:
	var result:Dictionary=super._begin_quest_auto_stop_operation(owner_auto)
	fire("stop_claim")
	return result
func _fee_resume_io_read(path:String)->Dictionary:
	var result:Dictionary=super._fee_resume_io_read(path)
	fire("side_read")
	return {"ok":false,"exists":true} if side_fault=="unknown" else result
func _fee_resume_io_remove()->int:
	if side_fault=="remove_before":return ERR_CANT_CREATE
	var result:int=super._fee_resume_io_remove()
	fire("side_remove")
	return ERR_CANT_CREATE if side_fault=="remove_after" else result
func _fee_resume_io_write_tmp(payload:PackedByteArray)->Dictionary:
	if side_fault=="write_before":return {"ok":false,"error":ERR_CANT_CREATE}
	var result:Dictionary=super._fee_resume_io_write_tmp(payload)
	fire("side_write")
	return result

var load_observer:Callable
func load_profile(path:String)->bool:
	if load_observer.is_valid():load_observer.call()
	return super.load_profile(path)

func _observe_fee_departure(f:Dictionary)->void:
	if at=="observation":session.read_callback=func():fire("observation")
	super._observe_fee_departure(f)

func _fee_resume_io_rename()->int:
	var result:int=super._fee_resume_io_rename()
	fire("side_rename")
	return result

var start_journal_frames:=0
func _begin_fee_start_journal_frame(candidate:Variant)->Dictionary:
	start_journal_frames+=1
	return super._begin_fee_start_journal_frame(candidate)

func parent_start_3ebd(command: Dictionary) -> Dictionary:
	if _fee_start_intent_enabled() and _fee_start_intent.classified(command):return _fee_start_intent.start(self,command)
	return quest_auto.start(self,command)
