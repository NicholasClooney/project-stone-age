extends SceneTree
## UNRUN pure stages; no paper transaction, trap, gate, loot or Boss execution.
const Rules=preload("res://server/original_quests.gd")
const Brothers=preload("res://server/quest_auto_brothers_plan.gd")
const Dragon=preload("res://server/quest_auto_dragon_plan.gd")
const Miner=preload("res://server/quest_auto_miner_plan.gd")
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
 return {"session":{"_profile":p}}
func expect(plan,b:Dictionary,job:int,stage:String,key:String="",line:int=0)->Dictionary:
 var before:Dictionary=b.duplicate(true)
 var result:Dictionary=plan.select(b,job)
 check(b==before,"read-only: "+stage)
 check(result.status==("done" if stage=="done" else "manual"),"status: "+stage)
 for forbidden in ["step","action","source","signature","choice","token","receipt","battle_id","ledger"]:
  check(not result.has(forbidden),"no executable authority %s: %s"%[forbidden,stage])
 if stage!="done":
  check(result.get("stage")==stage,"stage: "+stage)
  check(not str(result.get("reason","")).is_empty(),"explicit manual reason: "+stage)
  if not key.is_empty():check(result.required_source.key==key and result.required_source.line==line,"exact review source: "+stage)
 return result
func _initialize()->void:call_deferred("run")
func run()->void:
 expect(Brothers,fixture([],[],[],30),18,"level")
 expect(Brothers,fixture([],[],[],31),18,"request28","giiru/event/ev28_0",11)
 var correct:Array=[2507,2509,2511,2513,2515]
 var statues:Array=[5,8,12,15,19]
 for index in range(5):
  var held:=correct.duplicate()
  held.erase(correct[index])
  for wrong_present in [false,true]:
   var variant:=held.duplicate()
   if wrong_present:variant.append(correct[index]+1)
   var result:=expect(Brothers,fixture(variant,[28]),18,"statue_contract_missing","giiru/event/ev28_%d"%statues[index])
   check(result.reason.contains("yes→ok") and result.reason.contains("MESSAGE"),"exact two-page contract pending; no cleanup probe")
 # ev28_23 typo can leave correct+wrong paper: never normalize/delete either.
 var both:=correct.duplicate()
 both.append(2516)
 expect(Brothers,fixture(both,[28]),18,"claim_crystal","giiru/event/ev28_end",11)
 # ev28_21 malformed no-paper branch grants nothing; selector still needs correct5.
 expect(Brothers,fixture([2507,2509,2511,2513],[28]),18,"statue_contract_missing","giiru/event/ev28_19")
 expect(Brothers,fixture([],[],[28]),18,"done")
 expect(Brothers,fixture(),19,"prerequisite")
 for held in [[],[2517]]:expect(Brothers,fixture(held,[],[28]),19,"request31","giiru/event/ev28_end",22)
 expect(Brothers,fixture([],[31],[28]),19,"missing_crystal","giiru/event/ev28_end",22)
 var reward:=expect(Brothers,fixture([2517],[31],[28]),19,"trap_boss_manual_reward","genout/wpm_31705_25_8",1)
 check(reward.reason.contains("不自动选"),"five bosses/reward NPCs stay player choices")
 expect(Brothers,fixture([],[],[31]),19,"done")
 expect(Dragon,fixture(),26,"request","jaruga/event/event17_4",13)
 expect(Dragon,fixture([2505]),26,"inconsistent_token")
 expect(Dragon,fixture([],[17]),26,"replace_token","jaruga/event/event17_4",3)
 var gems:Array=[2457,2458,2459]
 for index in range(3):
  var held:=gems.duplicate()
  held.erase(gems[index])
  held.append(2505)
  var result:=expect(Dragon,fixture(held,[17]),26,"loot_contract_missing")
  check(result.review_needed=={"item_id":gems[index],"count":1,"map_id":20804+index,"group_id":404+index,"enemy_id":[562,560,559][index]},"exact dragon source review requirement")
  check(result.reason.contains("2760合同不可复用"),"jewel signature never reused")
 var gate:=expect(Dragon,fixture([2505,2457,2458,2459],[17]),26,"gate_and_manual_reward","genout/wpm_20807_11_37",1)
 check(gate.reason.contains("三NPC") and gate.reason.contains("独立hook"),"all gems still no Warp/reward permission")
 expect(Dragon,fixture([],[],[17]),26,"done")
 expect(Miner,fixture([],[],[],29),14,"level")
 expect(Miner,fixture([],[],[],30),14,"request","giiru/event/giruev2_1",41)
 expect(Miner,fixture([],[27]),14,"claim_lunch","giiru/event/giruev2_2",43)
 var ore:=expect(Miner,fixture([2536],[27]),14,"loot_contract_missing")
 check(ore.review_needed=={"item_id":2534,"count":1,"group_id":508,"enemy_id":1043,"map_ids":[31801,31802,31803]},"exact unbound ore source review requirement")
 # Source condition is NOW27 & 2534, not NOW27 & 2534 & 2536.
 for held in [[2534],[2534,2536]]:
  expect(Miner,fixture(held,[27]),14,"exchange_ore","giiru/event/giruev2_2",27)
 expect(Miner,fixture([2534]),14,"request","giiru/event/giruev2_1",41)
 expect(Miner,fixture([2535],[27]),14,"wait_boss","300/sb_bac.arg",5)
 expect(Miner,fixture([2534,2535],[27]),14,"wait_boss","300/sb_bac.arg",5)
 expect(Miner,fixture([2533]),14,"claim_ticket","giiru/event/giruev2_1",23)
 expect(Miner,fixture([2533,2535],[27]),14,"claim_ticket","giiru/event/giruev2_1",23)
 # Completed miner never chooses original paid replacement or consumes ticket.
 for held in [[],[2527],[2533]]:expect(Miner,fixture(held,[],[27]),14,"done")
 for plan in [Brothers,Dragon,Miner]:
  for job in [2,34,35,999]:expect(plan,fixture(),job,"unsupported_job")
 print("quest_auto_regular_guarded_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
