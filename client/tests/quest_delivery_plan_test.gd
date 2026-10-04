extends "res://tests/yam_axe_quest_test.gd"
const Plan=preload("res://server/quest_delivery_plan.gd")
const Policy=preload("res://scripts/quest_auto_policy.gd")
func expect_step(b,job:int,key:String)->void:
 var before:Dictionary=b.session.snapshot()
 var selected:Dictionary=Plan.select(b,job)
 check(str(selected.get("status",""))=="step" and str(selected.get("step",{}).get("id",""))=="delivery:"+key,"plan selects "+key+" "+str(selected.get("reason","")))
 check(b.session.snapshot()==before,"selection is read only "+key)
 if selected.get("status","")!="step":return
 var s:Dictionary=selected.step
 var npc:Dictionary=b.original_quests.npc_by_id(s.npc_id)
 check(s.source.branch_data==b.original_quests.branch_for(npc,before),"source branch stays exact "+key)
 check(s.auto_choices==(["yes"] if key=="marju_gate" else ["yes","ok"]),"explicit ordered choice permit "+key)
func fixture(now:Array=[],ended:Array=[],items:Array=[]):
 # State matrix fixtures ONLY: these assertions are not route/E2E evidence.
 var b=Backend.new()
 b.session._profile.player.level=50
 for event in now:Rules.set_flag(b.session._profile,"now",event,true)
 for event in ended:Rules.set_flag(b.session._profile,"ended",event,true)
 for item in items:Session.OriginalEquipment.add(b.session._profile,item)
 return b
func run()->void:
 for job in Plan.JOB_EVENTS:check(Policy.supports(job,Plan.JOB_EVENTS[job]),"policy exact job/event pair")
 for job in [1,11,30,23,6,37,38,999]:check(not Plan.supports(job),"no accidental event-as-job or pet support %d"%job)
 var cases:Array=[
  [12,[],[],[],"yam_request"],[12,[3],[],[2416],"yam_deliver"],
  [13,[],[3],[],"yam_reply"],[13,[5],[3],[2423],"yam_return"],
  [24,[],[],[2414],"goya_request"],[24,[7],[],[2414,2425],"goya_flower"],
  [24,[7],[],[2414,2425,2424],"goya_deliver"],
  [25,[],[7],[2414],"goya_reply"],[25,[8],[7],[2414,2426],"goya_return"],
  [5,[],[],[],"marju_request"],[5,[37],[],[2687],"marju_gate"],
  [9,[38],[37],[2697],"marju_return"]]
 for c in cases:
  var b=fixture(c[1],c[2],c[3]);expect_step(b,c[0],c[4]);b.free()
 for c in [[13,[],[],[]],[25,[],[],[2414]],[24,[],[],[]],[12,[3],[],[]],[25,[8],[7],[2414]],[5,[37],[],[]],[5,[37],[],[2687,2697]],[9,[],[],[]]]:
  var b=fixture(c[1],c[2],c[3]);check(Plan.select(b,c[0]).status=="manual","missing prerequisite never done "+str(c));b.free()
 for job in Plan.JOB_EVENTS:
  var b=fixture([], [Plan.JOB_EVENTS[job]])
  check(Plan.select(b,job).status=="done","only own END completes job %d"%job);b.free()
 var b=fixture([37],[],[2687])
 b.automation.position_changed(119,Vector2i(97,89))
 check(Plan.select(b,5).status=="manual","hidden maze helper/teleported recipient never completes or authorizes")
 b.free()
 b=fixture([7],[],[2414,2425])
 b.automation.position_changed(20404,Vector2i(44,14))
 check(Plan.select(b,24).status=="manual","Goya missing arrival hands back to player")
 b.free()
 b=fixture()
 b.session._profile.player.level=49
 check(Plan.select(b,5).status=="manual","level below50 requires manual")
 b.free()
 b=fixture()
 for i in range(15):Session.OriginalEquipment.add(b.session._profile,2424)
 check(Plan.select(b,12).status=="manual","full bag stops before request")
 b.free()
 # Unknown actions, paid branches, pet/keyword choices never gain authorization.
 for mutation in ["DelStone","DelPet","GetPet","Battle","Warp","unknown"]:
  b=fixture()
  for npc in b.quest_catalog.npcs:
   if str(npc.id)==YAM:npc.branches[1].actions[mutation]="1"
  check(Plan.select(b,12).status=="manual","unreviewed action stops "+mutation)
  b.free()
 b=fixture()
 for npc in b.quest_catalog.npcs:
  if str(npc.id)==YAM:npc.branches[1].spoken_keyword="secret"
 check(Plan.select(b,12).status=="manual","keyword remains manual")
 b.free()
 # Existing authority transactions are independently exercised, no runner simulated.
 b=fixture()
 expect_step(b,12,"yam_request")
 check(trade(b,YAM).ok,"original request transaction")
 expect_step(b,12,"yam_deliver")
 var opened:Dictionary=choose(b,talk(b,MATI),"yes")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-plan-save-dir/save.json"
 check(not choose(b,opened,"ok").ok and b.session.snapshot()==before,"source savefail retains plan prerequisites")
 b.save_path="";expect_step(b,12,"yam_deliver")
 check(trade(b,MATI).ok and Plan.select(b,12).status=="done","END3 completes only its job")
 expect_step(b,13,"yam_reply")
 check(trade(b,MATI).ok,"source gives return letter")
 expect_step(b,13,"yam_return")
 check(trade(b,YAM).ok and Plan.select(b,13).status=="done","END5 completes return job")
 b.free()
 print("QUEST DELIVERY PLAN: %d failures"%failures)
 quit(1 if failures else 0)
