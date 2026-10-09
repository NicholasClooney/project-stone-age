extends "res://server/backend.gd"
## Explicit fixture privilege: synthetic real fee_attach binding, direct runner
## turn with dispatch counters, no Accounts/PIN/WS authentication claim.
var purchase_enabled:=true
var wrapper:=""
var facts:Array=[]
var public_result:Dictionary={}
var actual_loads:int=0
var load_counter:Dictionary={}
func load_profile(path:String)->bool:
 actual_loads+=1
 if not load_counter.is_empty():load_counter.count+=1
 return super.load_profile(path)
func _fee_departure_enabled()->bool:return true
func _fee_start_intent_enabled()->bool:return true
func _fee_lobby_ticket_enabled()->bool:return purchase_enabled
func _persist_lobby_ticket_purchase(call:RefCounted)->Dictionary:
 if wrapper=="forged_ok":return {"ok":true,"stage":"purchase_committed"}
 public_result=super._persist_lobby_ticket_purchase(call)
 if wrapper=="stop_after_mark":quest_auto.stop(self,"fixture after actual mark",false)
 if wrapper=="owner_after_mark":
  session._profile=session._profile.duplicate(true);session._profile.character_id="100005"
 if wrapper=="false_after_mark":return {"ok":false}
 return public_result
func _emit(value:Dictionary)->void:
 if value.get("type")=="quest_result" and value.has("fee_fact"):facts.append(value.fee_fact.duplicate(true))
 super._emit(value)
func purchase_turn()->void:
 _depth+=1;_dispatch_boundary_depth+=1
 quest_auto.internal=true
 quest_auto.advance_source(self)
 quest_auto.internal=false
 _depth-=1;_dispatch_boundary_depth-=1

func _write_lobby_ticket_candidate(call:RefCounted,candidate:Dictionary)->bool:
 return session.lobby_write(self,call,candidate)
