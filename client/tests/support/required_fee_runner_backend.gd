extends "res://server/backend.gd"
## Test-only private issuer/dispatch fixture. NOT real Start, route, WS or auth.
var enabled:bool=true
var mode:String=""
var physical_calls:int=0
var actual_return:bool=false
var writer_observation:Dictionary={}
var facts:Array=[]
var nested_rejected:bool=false
var after:Callable
func _required_fee_runner_enabled()->bool:return enabled
func _emit(message:Dictionary)->void:
 if message.get("type")=="quest_result" and message.has("fee_fact"):facts.append(message.duplicate(true))
 super._emit(message)
func _write_required_fee_runner(call:RefCounted,candidate:Dictionary)->bool:
 physical_calls+=1
 if mode=="false_before":return false
 if mode=="forged_true":return true
 if mode=="tamper":candidate.player.hp-=1
 if mode=="nested":nested_rejected=not super._persist_required_fee_runner(call,candidate) and not _execute_required_fee_runner(RefCounted.new()).get("ok",false)
 actual_return=super._write_required_fee_runner(call,candidate)
 if after.is_valid():after.call(self)
 if mode=="false_after":return false
 return actual_return
func _persist_required_fee_runner(call:RefCounted,candidate:Dictionary)->bool:
 var result:bool=super._persist_required_fee_runner(call,candidate)
 var op:Dictionary=_required_fee_runner._op
 writer_observation={"marked":op.get("marked",false),"io_entered":op.get("io_entered",false),"physical_ran":op.get("physical_ran",false),"transaction_id":op.get("transaction_id",""),"result":result}
 if mode=="wrapper_successor":save_path+=".successor"
 return false if mode=="wrapper_false" else result
func turn(call:RefCounted)->Dictionary:
 _depth+=1;_dispatch_boundary_depth+=1
 var result:Dictionary=_execute_required_fee_runner(call)
 _depth-=1;_flush();_dispatch_boundary_depth-=1
 return result
func issue(kind:String,source:String)->RefCounted:
 # This future producer is deliberately NOT installed in production D0.
 _required_fee_runner_authority=RefCounted.new()
 _depth+=1
 var call:RefCounted=_prepare_required_fee_runner(_required_fee_runner_authority,kind,source)
 _depth-=1
 return call

var actual_loads:int=0
var load_counter:Dictionary={"count":0}
func load_profile(path:String)->bool:
 actual_loads+=1;load_counter.count+=1
 return super.load_profile(path)
