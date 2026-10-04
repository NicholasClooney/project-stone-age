extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func fixture():
 var b=Backend.new()
 b.session._profile.original_savepoint_bits=1
 b.session._profile.no_random_encounters=true
 b.quest_auto.quest_id=11
 var selection:Dictionary=b.quest_auto.strict_select(b)
 var step:Dictionary=selection.step
 var npc:Dictionary=b.original_quests.npc_by_id(step.npc_id)
 var point:Dictionary=b.quest_helper.geometric_destination(b,npc,"near")
 b.automation.position_changed(point.map_id,Vector2i(point.cell[0],point.cell[1]))
 check(b.handle({"type":"quest_auto_start","quest_id":11,"client":"first"}).ok,"Start actual shell plan")
 b.quest_auto.identity.select_step(str(step.id))
 b.quest_auto.internal=true
 var reply:Dictionary=b.original_quests.talk(b,str(npc.id))
 b.quest_auto.internal=false
 b.quest_auto.wait_reward(b,reply)
 return b
func command(b,choice:String)->Dictionary:
 var state:Dictionary=b.quest_auto.snapshot(b)
 return {"type":"quest_choose","quest_run_id":state.run_id,"quest_step_id":state.step_id,"quest_revision":state.revision,"token":state.waiting.token,"choice":choice,"client":"second","_quest_connection":22}
func run()->void:
 var b=fixture()
 check(b.quest_auto.phase=="waiting_reward" and b.quest_auto.snapshot(b).waiting.dialogue.has("choices"),"Snapshot supplies actual public choices to another device")
 var first:Dictionary=command(b,"yes")
 var invalid:Dictionary=first.duplicate();invalid.quest_run_id="old"
 check(not b.handle(invalid).ok and b.quest_auto.running,"Wrong run rejected without killing current waiting")
 check(not b.handle({"type":"quest_talk","npc_id":b.quest_auto.identity.waiting.npc_id}).ok,"Unrelated talk stays locked")
 check(not b.handle({"type":"quest_choose","token":first.token,"choice":"yes"}).ok,"Bare token does not unlock runner")
 var reply:Dictionary=b.handle(first)
 check(reply.ok and b.quest_auto.phase=="travel","Saved transaction closes plain end acknowledgement without an extra click")
 check(not b.handle(first).ok,"Old stage cannot use its old revision/token")
 check(reply.ok and b.quest_auto.running and b.quest_auto.phase=="travel" and Rules.flag(b.session._profile,"now",2),"Saved real transaction automatically continues to next step")
 var next_step:Dictionary=b.quest_auto.strict_select(b).step
 var npc:Dictionary=b.original_quests.npc_by_id(next_step.npc_id)
 var point:Dictionary=b.quest_helper.geometric_destination(b,npc,"near")
 b.automation.position_changed(point.map_id,Vector2i(point.cell[0],point.cell[1]))
 b.quest_auto.identity.select_step(str(next_step.id))
 b.quest_auto.internal=true
 reply=b.original_quests.talk(b,str(npc.id))
 b.quest_auto.internal=false
 b.quest_auto.wait_reward(b,reply)
 var accept_choice:Dictionary=command(b,"yes")
 check(b.handle(accept_choice).ok and not b.quest_auto.waiting_saved and b.quest_auto.phase=="waiting_reward","Opening final reward confirmation alone cannot count as saved")
 check(not b.handle(accept_choice).ok,"Old unsaved stage token and revision cannot replay")
 var final_choice:Dictionary=command(b,"ok")
 check(b.handle(final_choice).ok and not b.quest_auto.running and Rules.flag(b.session._profile,"ended",2),"Final authentic reward saves then stops without another continue")
 check(not b.handle(final_choice).ok,"Final reward cannot replay")
 b.free()
 for mode in ["stop","close","no","savefail","restart"]:
  b=fixture()
  first=command(b,"yes")
  if mode=="stop":b.handle({"type":"quest_auto_stop","client":"second"})
  elif mode=="close":
   var close:Dictionary=first.duplicate();close.type="quest_close"
   check(b.handle(close).ok,"Matching close cancels")
  elif mode=="no":b.handle(command(b,"no"))
  elif mode=="savefail":
   b.save_path="user://quest-handoff-missing-dir/save.json"
   var before:Dictionary=b.session.snapshot()
   check(not b.handle(first).ok and b.session.snapshot()==before,"Real transaction save failure rolls reward back")
  else:
   var checkpoint:Dictionary=b.quest_auto.resume_state()
   b.quest_auto.stop(b)
   b.quest_auto.load_resume(b,checkpoint)
  check(not b.quest_auto.running and b.original_quests.pending.is_empty(),"No continuation after "+mode)
  check(not b.handle(first).ok and not b.quest_auto.running,"Late token cannot revive after "+mode)
  b.free()
 test_cancel_during_save()
 test_boss()
 print("QUEST AUTO HANDOFF: %d failures"%failures)
 quit(1 if failures else 0)
func test_boss()->void:
 var b=Backend.new()
 b.quest_auto.running=true;b.quest_auto.quest_id=11;b.quest_auto.strict_walk=true
 b.quest_auto.identity.begin();b.quest_auto.identity.select_step("guard:first")
 b.session._pending={"battle_id":"guard-1","quest_guard":{}}
 b.quest_auto.wait_boss(b)
 check(b.quest_auto.running and not b.quest_auto.owns_battle and not b.automation.running,"Guard handoff never starts automation")
 var cmd={"type":"quest_auto_continue","quest_run_id":b.quest_auto.identity.run_id,"quest_step_id":b.quest_auto.identity.step_id,"quest_revision":b.quest_auto.identity.revision,"client":"second"}
 check(not b.handle(cmd).ok,"Boss cannot continue before victory")
 b.session._pending={}
 b.battle_state={"battle_id":"guard-1","outcome":"win","settled":true}
 b.session._profile.completed_battles.append("guard-1")
 b.quest_auto.tick(b,1.0)
 check(b.quest_auto.snapshot(b).can_continue and b.quest_auto.phase=="waiting_boss","Saved victory still waits for player")
 check(not b.handle(cmd).ok,"Pre-victory continue revision expires")
 cmd.quest_revision=b.quest_auto.identity.revision
 check(b.handle(cmd).ok and b.quest_auto.phase=="travel","Explicit current continue resumes")
 check(not b.handle(cmd).ok,"Duplicate continue cannot replay")
 b.free()

func test_cancel_during_save()->void:
 var b=fixture()
 var first:Dictionary=command(b,"yes")
 var cancelled:=[false]
 b.event.connect(func(event):
  if str(event.get("type",""))=="profile" and not cancelled[0]:
   cancelled[0]=true
   b.quest_auto.stop(b,"other device cancelled")
 )
 b.handle(first)
 check(cancelled[0] and not b.quest_auto.running and b.quest_auto.identity.waiting.is_empty() and b.original_quests.pending.is_empty(),"Cancellation during successful transaction publish never resurrects waiting")
 b.free()
