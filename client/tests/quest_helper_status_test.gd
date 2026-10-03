extends "res://tests/original_wood_quest_test.gd"
## Source transactions for the regression; explicit reachable flag stages for
## neighbouring chains. No row-completion heuristic is used by the projection.
func row(b,event:int)->Dictionary:
 for q in b.quest_helper.snapshot(b).quests:
  if int(q.event)==event:return q
 return {}
func state(b,event:int,want:String,note:String)->void:
 check(str(row(b,event).get("status",""))==want,note)
func run()->void:
 var b=fresh()
 state(b,18,"未开始","wood has an available request but is not active")
 check(request(b,BARL).ok and request(b,HAHN).ok,"source wood requests")
 state(b,18,"进行中","NOW18/NOW19 preparation")
 check(accept(b,WATER).ok and accept(b,HAHN).ok,"source water and axe exchange")
 check(Quests.flag(b.session._profile,"ended",19),"END19 closes axe production only")
 state(b,18,"进行中","END19 does not complete wood chain")
 check(accept(b,BARL).ok,"source axe delivery sets END18")
 state(b,18,"进行中","END18 with recommendation still active")
 check(request(b,MERCHANT).ok,"source permit exchange")
 state(b,18,"进行中","reported zero-wood permit state stays active")
 check(row(b,18).steps.any(func(s):return s.id=="wood:harvest" and s.current),"harvest is the actual mandatory current stage")
 check(accept(b,MERCHANT).ok,"source zero-wood settlement consumes permit")
 state(b,18,"已完成","settled wood ends despite optional broken axe repair")
 check(row(b,18).steps.any(func(s):return s.get("optional",false) and not s.done),"unstarted optional repair remains present")
 check(request(b,GOSSIP).ok,"source CLEAN18")
 state(b,18,"未开始","CLEAN allows restart without automatically starting")
 b.free()
 for event in [4,9,20,21,32,33,34]:
  b=Backend.new();b.quest_catalog.enabled_events=[4,9,20,21,22,32,33,34]
  if event in [32,33,34]:
   Quests.set_flag(b.session._profile,"ended",4,true)
   for prior in range(32,event):Quests.set_flag(b.session._profile,"ended",prior,true)
  state(b,event,"未开始","eligible event%d remains unstarted"%event)
  Quests.set_flag(b.session._profile,"now",event,true)
  if event in [32,33,34]:b.session._profile.original_items=[2603]
  state(b,event,"进行中","source NOW%d tracks active stage even without navigation"%event)
  Quests.set_flag(b.session._profile,"ended",event,true)
  Quests.set_flag(b.session._profile,"now",event,false)
  b.session._profile.original_items=[]
  state(b,event,"已完成","source END%d completes only this journal chain"%event)
  b.free()
 b=Backend.new();b.quest_catalog.enabled_events=[20,21,22]
 Quests.set_flag(b.session._profile,"ended",20,true)
 state(b,22,"未开始","Jan meeting does not start optional next request")
 Quests.set_flag(b.session._profile,"now",21,true)
 state(b,22,"进行中","Sala request activates mandatory Jan reward without NOW22")
 Quests.set_flag(b.session._profile,"ended",22,true)
 state(b,22,"已完成","Jan reward complete while letter remains active")
 state(b,21,"进行中","letter remains active after END22")
 b.free()
 b=Backend.new();b.quest_catalog.enabled_events=[44];b.session._profile.player.level=30
 state(b,44,"未开始","dojo purchase available but not started")
 b.session._profile.original_items=[2750]
 # Golden helper already owns ticket/position-derived status; use its actual band.
 var band:Dictionary=preload("res://server/golden_bui_helper.gd").band(30)
 b.session._profile.original_items=[int(band.ticket)]
 state(b,44,"进行中","dojo held ticket already projects active without NOW44")
 Quests.set_flag(b.session._profile,"ended",44,true)
 state(b,44,"已完成","dojo END44 is actual pet redemption")
 b.free()
 print("QUEST HELPER STATUS: %d failures"%failures)
 quit(1 if failures else 0)
