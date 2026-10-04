extends SceneTree
class Backend extends "res://server/backend.gd":
 var field_calls:=0
 func _cmd_field_step(command:Dictionary)->Dictionary:
  field_calls+=1
  return super._cmd_field_step(command)
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func command(b,full:bool=true)->Dictionary:
 var receipt:Dictionary=b.quest_auto.issued[-1]
 var result:Dictionary={"type":"report_position","map_id":receipt.map_id,"cell":receipt.cell.duplicate(),"quest_position_seq":receipt.seq,"client":"first","_quest_connection":17}
 if full:
  for field in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id"]:result[field]=receipt[field]
 return result
func issue(b)->Dictionary:
 b.quest_auto.phase="landing"
 b.quest_auto.emit_position(b,{"map_id":1000,"cell":[56,58]},{"map_id":1000,"cell":[55,58]},true)
 return command(b)
func run()->void:
 var b=Backend.new()
 b.session._profile.no_random_encounters=true
 b.automation.position_changed(1000,Vector2i(56,58))
 check(b.handle({"type":"quest_auto_start","quest_id":11,"client":"first","_quest_connection":17}).ok,"Real runner starts")
 b.quest_auto.identity.select_step("shell:request")
 var ack:Dictionary=issue(b)
 var packet:Dictionary=b.quest_auto.issued[-1]
 check(packet.quest_segment.from_cell==[55,58] and packet.quest_segment.cells==[{"map_id":1000,"cell":[56,58]}] and packet.quest_ack_required,"Position publishes only committed prefix and actual origin")
 for field in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq","map_id","cell","client","_quest_connection"]:
  var forged:Dictionary=ack.duplicate(true)
  forged[field]=[60,60] if field=="cell" else -99 if field in ["quest_revision","quest_position_seq","map_id","_quest_connection"] else "wrong"
  b.handle(forged)
  check(b.quest_auto.running and b.quest_auto.phase=="landing" and b.automation.position_map==1000 and b.automation.position_cell==Vector2i(56,58),"Wrong "+field+" cannot move or cancel current run")
 var partial:Dictionary=ack.duplicate(true);partial.erase("quest_step_id")
 b.handle(partial)
 check(b.quest_auto.phase=="landing","Partial new identity is not legacy protocol")
 check(b.handle(ack).ok and b.quest_auto.phase=="travel" and not b.quest_auto.motion.awaiting_ack,"Exact complete ack releases current landing")
 b.handle(ack)
 check(b.quest_auto.phase=="travel","Duplicate ack has no extra effect")
 var old:Dictionary=ack.duplicate(true)
 ack=issue(b)
 b.handle(old)
 check(b.quest_auto.phase=="landing","Previous segment cannot release new landing")
 check(b.handle(command(b,false)).ok and b.quest_auto.phase=="travel","Current legacy A seq-only ack still works")
 ack=issue(b)
 b.quest_auto.detach(b,17)
 b.handle(ack)
 check(b.quest_auto.detached and b.quest_auto.issued.is_empty(),"Disconnect invalidates receipts and old ack cannot rebind")
 check(b.handle({"type":"report_position","map_id":1000,"cell":[56,58],"client":"returning","_quest_connection":22}).ok and not b.quest_auto.detached and b.quest_auto.connection==22 and b.quest_auto.phase=="travel","Untagged authority-cell handshake rebinds")
 check(b.quest_auto.position_serial>int(ack.quest_position_seq) and not b.quest_auto.motion.is_empty(),"Reconnect emits fresh receipt instead of tail replay")
 b.handle(ack)
 check(b.quest_auto.client=="returning" and b.quest_auto.running,"Former connection cannot reclaim control")
 b.handle({"type":"quest_auto_stop"})
 var stopped:Dictionary=b.session.snapshot()
 ack.cell=[10,10];ack.map_id=20101
 b.handle(ack)
 check(b.session.snapshot()==stopped and b.automation.position_map==1000 and not b.quest_auto.running,"Cancelled late receipt cannot move or revive")
 check(b.handle({"type":"quest_auto_start","quest_id":11,"client":"first","_quest_connection":17}).ok,"New run starts")
 b.handle(ack)
 check(b.quest_auto.running and b.automation.position_map==1000,"Old-run report cannot cancel or move new run")
 b.handle({"type":"report_position","map_id":1000,"cell":[57,58],"client":"manual","_quest_connection":22})
 check(not b.quest_auto.running and b.automation.position_cell==Vector2i(57,58),"Untagged actual manual displacement still stops the runner")
 b.automation.position_changed(1000,Vector2i(80,90))
 check(b.handle({"type":"quest_auto_start","quest_id":11,"client":"first","_quest_connection":17}).ok,"Cancellation-on-position fixture starts")
 var before_calls:int=b.field_calls
 var cancelled:=[false]
 b.event.connect(func(event):
  if event.get("type")=="position" and event.has("quest_position_seq") and not cancelled[0]:
   cancelled[0]=true
   b.quest_auto.stop(b,"cancel while showing committed cell")
 )
 b.quest_auto.tick(b,0.21)
 check(cancelled[0] and not b.quest_auto.running and b.field_calls==before_calls,"Cancel during position publication blocks the subsequent encounter action")
 b.free()
 print("QUEST AUTO MOTION: %d failures"%failures)
 quit(1 if failures else 0)
