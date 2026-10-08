extends "res://tests/support/fee_start_journal_fault_session.gd"
var start_mode := ""
var save_mode := ""
func _write_profile_candidate(candidate:Dictionary,path:String)->bool:
 var actual:bool=super._write_profile_candidate(candidate,path)
 if writer_calls==1:
  var b=host.get_ref()
  match start_mode:
   "binding_after":b.fee_attach(71)
   "timer_after":b.quest_loot=preload("res://server/quest_auto_loot.gd").new()
   "position_after":b.automation.position_cell+=Vector2i(1,0)
   "catalog_after":b.quest_catalog.enabled_events=b.quest_catalog.enabled_events.duplicate();b.quest_catalog.enabled_events.erase(44)
 return actual
func save_game(path:String)->bool:
 if save_mode=="fail":return false
 var saved:bool=super.save_game(path)
 return false if save_mode=="false_after" else saved
