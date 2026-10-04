extends SceneTree
## UNRUN. Pure stage selection + four existing public keyword resolver contracts.
## Does not execute source services, Warp, Charm, bosses or saves.
const Rules=preload("res://server/original_quests.gd")
const Munde=preload("res://server/quest_auto_munde_plan.gd")
const Jan=preload("res://server/quest_auto_jan_plan.gd")
const Answers=preload("res://server/quest_auto_source_answers.gd")
var failures:=0
var assertions:=0
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:
  failures+=1
  push_error(label)
func fixture(items:Array=[],now:Array=[],ended:Array=[],level:int=80)->Dictionary:
 var p:Dictionary={"player":{"level":level},"original_items":items.duplicate(),
  "original_events":{"now":[0,0,0,0,0,0],"ended":[0,0,0,0,0,0]}}
 for event in now:Rules.set_flag(p,"now",event,true)
 for event in ended:Rules.set_flag(p,"ended",event,true)
 return {"session":{"_profile":p},"automation":{"position_map":100}}
func expect(plan,b:Dictionary,job:int,stage:String,key:String="",line:int=0)->Dictionary:
 var before:Dictionary=b.duplicate(true)
 var result:Dictionary=plan.select(b,job)
 check(b==before,"read-only: "+stage)
 check(result.status==("done" if stage=="done" else "manual"),"status: "+stage)
 check(not result.has("step") and not result.has("action"),"no execution capability: "+stage)
 if stage!="done":
  check(result.get("stage")==stage,"stage: "+stage)
  check(not str(result.get("reason","")).is_empty(),"manual explanation: "+stage)
  if not key.is_empty():
   check(result.required_source.key==key and result.required_source.line==line,"exact source branch hint: "+stage)
 return result
func _initialize()->void:call_deferred("run")
func run()->void:
 expect(Munde,fixture(),8,"prerequisite")
 expect(Munde,fixture([],[],[4],29),8,"prerequisite")
 expect(Munde,fixture([],[],[4],30),8,"request9","sainasu/event/event09",14)
 expect(Munde,fixture([],[9],[4]),8,"request11","sainasu/event/event11",41)
 expect(Munde,fixture([],[9,10],[4]),8,"request11","sainasu/event/event11",29)
 expect(Munde,fixture([],[9,11],[4]),8,"request10","sainasu/event/event10",28)
 expect(Munde,fixture([],[9,10,11],[4]),8,"keyword_route","genout/wpm_100_443_127",1)
 var summit=fixture([],[9,10,11],[4])
 summit.automation.position_map=11107
 expect(Munde,summit,8,"boss_and_stones","sainasu/event/event12",4)
 expect(Munde,fixture([2419,2420],[9,10,11],[4]),8,"return_stone_charm","sainasu/event/event11",16)
 expect(Munde,fixture([2420],[9,11],[4,10]),8,"return_stone_charm","sainasu/event/event11",4)
 expect(Munde,fixture([2419],[9,10],[4,11]),8,"return_stone10","sainasu/event/event10",4)
 expect(Munde,fixture([2419],[9,10,11],[4]),8,"partial_state")
 expect(Munde,fixture([],[9],[10,11,12]),8,"final_reward","sainasu/event/event09",3)
 expect(Munde,fixture([],[],[9]),8,"done")
 expect(Jan,fixture(),27,"flower","jaruga/event/event20_1",23)
 expect(Jan,fixture([2486]),27,"request20","jaruga/event/event20_2",17)
 expect(Jan,fixture([],[20]),27,"claim_token","jaruga/event/event20_3",6)
 expect(Jan,fixture([2487],[20]),27,"keyword_boss_return","jaruga/event/event20_4",5)
 expect(Jan,fixture(),28,"prerequisite")
 expect(Jan,fixture(),29,"prerequisite")
 expect(Jan,fixture([],[],[20]),28,"missing_token")
 expect(Jan,fixture([2487],[],[20]),28,"request21","jaruga/event/event20_6",26)
 var parent_hint:=expect(Jan,fixture([],[21],[20]),28,"parent_job29")
 check(parent_hint.get("required_parent_job")==29,"parent-only 28 -> 29 hint")
 expect(Jan,fixture([],[],[20]),29,"parent_request28")
 expect(Jan,fixture([],[21],[20]),29,"random_equipment","jaruga/event/event20_4",16)
 expect(Jan,fixture([],[21],[20,22]),28,"claim_letter","jaruga/event/event20_6",5)
 for held in [[2488],[2488,2489]]:
  expect(Jan,fixture(held,[21],[20,22]),28,"deliver_letter","jaruga/event/event20_2",5)
 # 2489 is the original output, not an additional required/consumed input.
 expect(Jan,fixture([2489],[21],[20,22]),28,"claim_letter","jaruga/event/event20_6",5)
 for mapping in [[27,20],[28,21],[29,22]]:
  expect(Jan,fixture([],[],[mapping[1]]),mapping[0],"done")
 for plan in [Munde,Jan]:
  for job in [2,34,35,999]:expect(plan,fixture(),job,"unsupported_job")
 # Four audited static sources, public dialogue only. No service pending/token/RNG.
 var rows:Array=[
  ["genout/wpm_100_443_127","@100:443:127","干么，有什么事吗？,喂，你看什么看。","在卡坦有梦德","ab24fd28d53a0230943ff27ed0c852b4cde5d4b2d1ad22de4fccafadba700da5"],
  ["genout/wpm_20604_11_53","@20604:11:53","想通过这里的话，先说出暗号。","红色月亮的光芒","f8b7c37293c00d1b823f7bfb5841337c307554dae82f95d841ce32905767ce36"],
  ["genout/wpm_20605_51_4","@20605:51:4","如果不说的话我就要叫人来了。","蓝色山脉即力量","1041e0f8ed17b33db3492eb4368868b9b15c7c9997c3173233dbc801dc63e355"],
  ["genout/wpm_20606_9_23","@20606:9:23","想通过这里，先说出暗号‘山’…","白色之风即速度","c9dbab118a5c7480bbe01ed5f8029e3e4120aea3ec7d2407a2017a10c156be23"]]
 var resolver=Answers.new()
 for row in rows:
  var dialogue:Dictionary={"npc_id":row[0]+row[1],"kind":"original_keyword","input":"text","text":row[2],"choices":[{"id":"submit","text":"说出口令"},{"id":"no","text":"取消"}]}
  var before:=dialogue.duplicate(true)
  var result:Dictionary=resolver.resolve_keyword(row[0],dialogue)
  check(dialogue==before,"resolver does not mutate public dialogue")
  check(result.get("status")=="answer" and result.get("choice")=="submit" and result.get("text")==row[3],"exact original keyword: "+row[0])
  check(result.get("evidence",{}).get("source_sha")==row[4],"pinned original keyword SHA")
  check(not result.has("action") and not result.has("step"),"answer is not SERVICE permission")
  dialogue.npc_id="unreviewed"
  check(resolver.resolve_keyword(row[0],dialogue).status=="manual","wrong public actor rejected")
 check(resolver.resolve_keyword("genout/unknown",{}).status=="manual","unknown source not generalized")
 print("quest_auto_regular_keyword_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
