extends "res://tests/support/fee_lobby_ticket_backend.gd"
var start_enabled:bool=true
func _fee_start_intent_enabled()->bool:return start_enabled
var entry_mode:String=""
var entry_writes:int=0
var entry_candidates:Array=[]
var entry_results:Array=[]
var events:Array=[]
var successor:Dictionary={}
func _persist_lobby_ticket_entry(call:RefCounted,candidate:Dictionary)->Dictionary:
 if entry_mode=="forged_ok":return {"ok":true}
 var result:Dictionary=super._persist_lobby_ticket_entry(call,candidate)
 entry_results.append(result.duplicate(true))
 if entry_mode=="outer_false":return {"ok":false}
 if entry_mode=="owner_after_mark":replace_owner()
 if entry_mode=="source_after_mark":
  _quest_source_call={"successor":true};original_quests.pending={"token":"successor-page"}
 return result
func replace_owner()->void:
 session._profile=session._profile.duplicate(true);session._profile.character_id="100005"
 successor={"profile":session._profile.duplicate(true),"cache":last_saved_payload,"serial":quest_save_serial,"path":save_path,"map":automation.position_map,"cell":automation.position_cell,"binding":_fee_bindings.get(71)}
func _write_lobby_ticket_entry_candidate(call:RefCounted,candidate:Dictionary)->bool:
 entry_writes+=1;entry_candidates.append(candidate.duplicate(true))
 if entry_mode=="false_before":return false
 if entry_mode=="forged_raw":return true
 if entry_mode=="unrelated":candidate.player.hp-=1
 if entry_mode=="nested":_fee_lobby_ticket_entry.persist(self,call,candidate)
 if entry_mode=="wrong_handle":
  var wrong:Dictionary=_fee_lobby_ticket_entry.persist(self,RefCounted.new(),candidate)
  assert(wrong=={"ok":false})
 var result:bool=super._write_lobby_ticket_entry_candidate(call,candidate)
 match entry_mode:
  "false_after":return false
  "owner":replace_owner()
  "serial":quest_save_serial+=7
  "path":save_path+=".next"
  "binding":fee_attach(71)
  "run":quest_auto.identity.begin()
  "ref":session._profile=session._profile.duplicate(true)
  "pending":original_quests.pending={"token":"successor-page"}
  "router":
   original_quests=preload("res://server/original_quests.gd").new();original_quests.catalog=quest_catalog
 return result
func _emit(value:Dictionary)->void:
 events.append(value.duplicate(true))
 if entry_mode=="position_successor" and value.get("type")=="position":replace_owner()
 super._emit(value)
func source_turn()->void:
 _depth+=1;_dispatch_boundary_depth+=1;quest_auto.internal=true
 quest_auto.advance_source(self)
 quest_auto.internal=false;_depth-=1;_dispatch_boundary_depth-=1
func source_repeat(choice:Dictionary)->Dictionary:
 _depth+=1;_dispatch_boundary_depth+=1;quest_auto.internal=true
 var result:Dictionary=call_quest_source(quest_auto.source_frame,quest_auto.step,choice)
 quest_auto.internal=false;_depth-=1;_dispatch_boundary_depth-=1
 return result
