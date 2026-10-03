extends "res://tests/brothers_golden_quests_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Policy=preload("res://server/quest_arrival_policy.gd")
func npc(b,script:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",str(n.id).split("@")[0]))==script:return n
 return {}
func answer(b,opened:Dictionary)->Dictionary:
 var state:Dictionary=b.original_quests.pending.get("service_state",{})
 return b.handle({"type":"quest_choose","token":opened.get("dialogue",{}).get("token",""),"choice":"submit" if int(state.get("answer_type",0))==4 else str(state.get("answer_choice","")),"text":str(state.get("answer_text",""))})
func run()->void:
 for row in [["genout/wpm_811_30_20",30,2755,800],["genout/wpm_831_30_20",30,2755,800],["genout/wpm_811_28_20",50,2756,820],["genout/wpm_831_28_20",50,2756,820],["genout/wpm_851_29_20",70,2757,840]]:
  var b=fresh();b.session._profile.player.level=int(row[1])
  # Reviewed preexisting entry/quiz tickets are not route evidence.
  for item in [int(row[2]),2752,2752,2752]:Equipment.add(b.session._profile,item)
  var gate:Dictionary=npc(b,row[0]);var quiz:Dictionary=npc(b,"genout/quz_%d_29_19"%int(row[3]))
  check(not gate.is_empty() and not quiz.is_empty(),"source service instances exist")
  if gate.is_empty() or quiz.is_empty():b.free();continue
  b.automation.position_changed(int(quiz.map_id),Vector2i(29,20))
  var before:Dictionary=b.session.snapshot()
  check(not Travel.commit(b,quiz) and b.session.snapshot()==before,"project quiz arrival cannot debit ticket or advance")
  b.automation.position_changed(int(gate.map_id),Vector2i(int(gate.cell[0]),int(gate.cell[1])+1))
  before=b.session.snapshot();b.save_path="user://missing-dojo-arrival/save.json"
  check(not Travel.commit(b,gate) and b.session.snapshot()==before,"original service entry save failure grants no scope")
  b.save_path=""
  check(Travel.commit(b,gate) and b.quest_arrival.has_arrival(b,int(row[3]),b.automation.position_cell),"each original level/ticket service gate establishes route")
  check(Travel.walk_near(b,quiz,[int(row[3])]),"actual original first-floor walk to quiz")
  var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":quiz.id})
  var question:Dictionary=choose(b,opened,"yes")
  check(question.get("ok",false),"original quiz ticket transaction starts")
  before=b.session.snapshot();b.save_path="user://missing-dojo-arrival/save.json"
  check(not answer(b,question).get("ok",false) and b.session.snapshot()==before,"quiz Warp save failure changes neither saved profile nor route")
  b.save_path=""
  opened=b.handle({"type":"quest_talk","npc_id":quiz.id});question=choose(b,opened,"yes")
  var token:String=str(question.get("dialogue",{}).get("token",""))
  check(answer(b,question).get("ok",false) and b.automation.position_cell==Vector2i(29,15) and b.quest_arrival.has_arrival(b,int(row[3]),Vector2i(29,15)),"real correct-answer saved Warp retains own route")
  check(not b.handle({"type":"quest_choose","token":token,"choice":"1"}).get("ok",false),"old service token cannot repeat advancement")
  if int(row[3])==840:
   var next_quiz:Dictionary=npc(b,"genout/quz_841_18_19")
   check(Travel.walk_near(b,next_quiz,[840,841]),"actual portal to second quiz floor")
   # Seed1 uses original questions73(choice) then38(text). The service
   # retains answer_choice from question1, so current answer_type must win.
   # This reproduces the former random failure without any timing/sleep.
   b.original_quests.services.rng.seed=1
   question=choose(b,b.handle({"type":"quest_talk","npc_id":next_quiz.id}),"yes")
   var first_state:Dictionary=b.original_quests.pending.get("service_state",{}).duplicate(true)
   check(question.get("ok",false) and int(first_state.get("answer_type",0))==2 and int(first_state.get("index",-1))==0,"real source sequence begins with a choice question")
   question=answer(b,question)
   var second_state:Dictionary=b.original_quests.pending.get("service_state",{}).duplicate(true)
   check(question.get("ok",false) and int(second_state.get("answer_type",0))==4 and int(second_state.get("index",-1))==1 and int(second_state.get("correct",0))==1 and second_state.get("answer_choice","")==first_state.get("answer_choice",""),"real second question is text despite retained previous choice")
   check(question.get("dialogue",{}).get("input","")=="text" and question.get("dialogue",{}).get("choices",[]).any(func(c):return str(c.id)=="submit"),"authoritative public text prompt requires submit")
   question=answer(b,question)
   check(question.get("ok",false) and question.get("closed",false) and b.automation.position_map==841 and b.automation.position_cell==Vector2i(18,15) and b.quest_arrival.has_arrival(b,841,b.automation.position_cell),"real two-answer source quiz advances: "+str(question))
   var fist:Dictionary=npc(b,"genout/jan_842_29_19")
   check(Travel.walk_near(b,fist,[841,842]),"actual source portal and walking reach janken")
   question=choose(b,b.handle({"type":"quest_talk","npc_id":fist.id}),"yes")
   check(question.get("ok",false) and 2751 not in b.session.snapshot().original_items,"approved original no-ticket janken remains playable with real route")
   b.original_quests.services.rng.seed=44
   for attempt in range(20):
    question=choose(b,question,"rock")
    if not question.get("ok",false) or question.get("closed",false):break
   check(question.get("ok",false) and question.get("closed",false) and b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"actual janken result Warp preserves independently earned route")
  b.free()
 var b=fresh();var count:int=0
 for n in b.quest_catalog.active_npcs():
  if Policy.scope(int(n.map_id))!="dojo":continue
  b.automation.position_changed(int(n.map_id),Vector2i(int(n.cell[0])+1,int(n.cell[1])))
  check(not b.quest_arrival.check_action(b,n,{},"SERVICE").is_empty(),"all actual dojo internal service/action identities reject project arrival "+str(n.id));count+=1
 check(count>0,"full active dojo source set audited")
 for public_map in [811,831,851]:check(Policy.scope(public_map).is_empty(),"public ticket shops and entrance halls keep source conditions")
 b.free();print("QUEST ARRIVAL DOJO: %d failures"%failures);quit(1 if failures else 0)
