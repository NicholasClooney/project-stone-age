extends RefCounted
## Capability identity only. No arrival proof or dialogue token is persisted.
var run_id:=""
var step_id:=""
var revision:=0
var waiting:Dictionary={}
func begin()->void:
 run_id=Crypto.new().generate_random_bytes(16).hex_encode()
 step_id=""
 invalidate()
func invalidate()->void:
 revision+=1
 waiting.clear()
func select_step(id:String)->void:
 if step_id==id:return
 step_id=id
 invalidate()
func wait_for(kind:String,token:String,npc_id:String,character_id:String)->void:
 invalidate()
 waiting={"kind":kind,"token":token,"npc_id":npc_id,"character_id":character_id}
func matches(command:Dictionary,character_id:String)->bool:
 return not run_id.is_empty() and not waiting.is_empty() and str(command.get("quest_run_id",""))==run_id and str(command.get("quest_step_id",""))==step_id and command.get("quest_revision",-1)==revision and str(command.get("token",""))==str(waiting.get("token","")) and character_id==str(waiting.get("character_id",""))
func snapshot()->Dictionary:
 var public_wait:Dictionary=waiting.duplicate(true)
 public_wait.erase("character_id")
 return {"run_id":run_id,"step_id":step_id,"revision":revision,"waiting":public_wait}
func checkpoint()->Dictionary:
 return {"run_id":run_id,"step_id":step_id,"revision":revision}
func restore(value:Dictionary)->bool:
 var old_run=value.get("run_id","")
 var old_step=value.get("step_id","")
 var old_revision=value.get("revision",-1)
 if not old_run is String or old_run.length()!=32 or not old_run.is_valid_hex_number():return false
 if not old_step is String or old_step.length()>256:return false
 if not (old_revision is int or old_revision is float) or not is_finite(float(old_revision)) or old_revision<0 or old_revision>2147483646 or float(old_revision)!=floor(float(old_revision)):return false
 run_id=old_run
 step_id=old_step
 revision=int(old_revision)
 invalidate()
 return true
