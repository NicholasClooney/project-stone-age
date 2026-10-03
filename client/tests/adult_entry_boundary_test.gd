extends "res://tests/original_adult_quest_test.gd"
func run()->void:
 var b=Backend.new();clear_bag(b)
 var before:Dictionary=b.session.snapshot()
 check(preload("res://scripts/quest_auto_policy.gd").JOB_MAPS[1]==[10202,10204],"exact adult preloads include original gate outside and channel")
 for mode in ["near","arrival"]:
  for selector in [{"npc_id":JUDGE},{"quest_id":1,"step_id":"adult:request"}]:
   var command:Dictionary=selector.duplicate();command.type="quest_visit";command.mode=mode
   check(b.handle(command).ok and b.automation.position_map==10202,"raw NPC and old step both modes stop outside at level1")
   check(not b.handle({"type":"quest_talk","npc_id":JUDGE}).ok,"outside helper destination cannot start original NPC request")
 b.automation.position_changed(10202,Vector2i(31,13))
 check(not b.handle({"type":"check_passage","from_map":10202,"to_map":10204}).ok,"real original gate refuses level1")
 check(not b.handle({"type":"report_position","map_id":10204,"cell":[2,6]}).ok,"direct low-level portal report also refused")
 var start:Dictionary=b.handle({"type":"quest_auto_start","quest_id":1,"client":"test"})
 check(not start.ok and str(start.reason).contains("等级30") and not b.quest_auto.running,"low-level automatic ritual does not start and explicitly explains gate")
 check(b.session.snapshot().original_items==before.original_items and b.session.snapshot().original_events==before.original_events,"all denied entries preserve exact items and event words")
 b.free();print("ADULT ENTRY BOUNDARY: %d failures"%failures);quit(1 if failures else 0)
