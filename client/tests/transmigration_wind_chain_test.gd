extends "res://tests/original_fixed_guards_test.gd"
const Clock=preload("res://scripts/clock.gd")
const Wind=preload("res://server/transmigration_wind_helper.gd")
const Driver=preload("res://tests/support/original_route_driver.gd")
var measured_route:int=0
var measured_battle:int=0
var measured_fixture:int=0
func route_walk(b,map_id:int,cell:Vector2i,maps:Array)->Dictionary:
 var started:int=Clock.ticks_msec()
 var result:Dictionary=Driver.walk(b,map_id,cell,maps)
 measured_route+=Clock.ticks_msec()-started
 return result
func setup():
 var started:int=Clock.ticks_msec()
 var b=fresh();Rules.set_flag(b.session._profile,"ended",4,true)
 measured_fixture+=Clock.ticks_msec()-started
 return b
func near_source(b,n:Dictionary)->bool:
 if int(b.automation.position_map)!=int(n.map_id):return false
 var maps:Array=[int(n.map_id)]
 var data:Dictionary=preload("res://scripts/map_file.gd").load_map(b.quest_helper.places.file(int(n.map_id)))
 for delta in preload("res://scripts/npc_interaction.gd").offsets():
  var goal:=Vector2i(int(n.cell[0]),int(n.cell[1]))+delta
  if goal.x<0 or goal.y<0 or goal.x>=int(data.width) or goal.y>=int(data.height) or int(data.blocked[goal.y*int(data.width)+goal.x])!=0:continue
  if route_walk(b,int(n.map_id),goal,maps).ok:return true
 return false
func local_trade(b,n:Dictionary,keyword:String="")->Dictionary:
 if not near_source(b,n):return {"ok":false,"reason":"no original route to NPC"}
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":n.id})
 if not r.ok:return r
 r=b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"submit" if not keyword.is_empty() else "yes","text":keyword})
 if r.has("dialogue"):r=choose(b,r,"ok")
 if b.battle_open:
  var started:int=Clock.ticks_msec()
  fight(b);r=b.handle({"type":"battle_close"})
  measured_battle+=Clock.ticks_msec()-started
 return r
func source_leg(b,name:String,target:Dictionary={})->bool:
 var started:int=Clock.ticks_msec()
 var routes:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-wind-routes.json"))
 for edge in routes[name]:
  if not target.is_empty() and int(b.automation.position_map)==int(target.map_id) and near_source(b,target):
   print("WIND ROUTE TIMING ",name," ms=",Clock.ticks_msec()-started);return true
  print("WIND CHAIN DOOR ",name," map=",edge.from_map," elapsed_ms=",Clock.ticks_msec()-started)
  if edge.has("npc_id"):
   if not local_trade(b,b.original_quests.npc_by_id(str(edge.npc_id))).ok:return false
   continue
  var point:=Vector2i(int(edge.cell[0]),int(edge.cell[1]))
  var r:Dictionary=route_walk(b,int(edge.from_map),point,[int(edge.from_map)])
  if not r.ok and int(edge.from_map)==11208:
   for guardian in b.quest_catalog.active_npcs():
    if str(guardian.get("source_script",""))=="100/sb_kbu.arg" and near_source(b,guardian):
     if not local_trade(b,guardian).ok:return false
   r=route_walk(b,int(edge.from_map),point,[int(edge.from_map)])
  if not r.ok:return false
  if not b.handle({"type":"report_position","map_id":edge.to_map,"cell":edge.target}).ok:return false
 return true
func source_talk(b,n:Dictionary)->Dictionary:
 if int(n.map_id)==100:return super.source_talk(b,n)
 var map_id:int=b.automation.position_map
 if b.quest_arrival.has_arrival(b,map_id,b.automation.position_cell) and near_source(b,n):
  return b.handle({"type":"quest_talk","npc_id":n.id})
 var wind:bool=int(n.map_id)>=11201
 var gate:Dictionary=npc(b,"genout/wpm_100_278_325" if wind else "genout/wpm_100_443_127")
 var opened:Dictionary=super.source_talk(b,gate)
 if not opened.ok:return opened
 var r:Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes" if wind else "submit","text":"" if wind else "在卡坦有梦德"})
 if not r.ok:return r
 if not source_leg(b,"wind-up" if wind else "munde-up",n) or not near_source(b,n):return {"ok":false,"reason":"natural source leg failed"}
 return b.handle({"type":"quest_talk","npc_id":n.id})
func npc(b,script:String,index:int=0)->Dictionary:
 return b.quest_catalog.active_npcs().filter(func(n):return str(n.get("source_script",""))==script)[index]
func exchange(b,n:Dictionary)->Dictionary:
 var r:=source_talk(b,n)
 r=choose(b,r,"yes")
 return choose(b,r,"ok") if r.has("dialogue") else r
var timer_started:int=0
var timer_previous:int=0
func timed(label:String)->void:
 var now:int=Clock.ticks_msec()
 print("WIND TIMING ",label," segment_ms=",now-timer_previous," total_ms=",now-timer_started)
 timer_previous=now
func run()->void:
 timer_started=Clock.ticks_msec();timer_previous=timer_started
 var b=core()
 timed("core")
 offerings(b)
 timed("three-tiers")
 cooldowns(b)
 b.free()
 boundaries()
 timed("boundaries")
 print("WIND CHAIN COST route_ms=",measured_route," battle_ms=",measured_battle," fixture_ms=",measured_fixture," transaction_ms=",Clock.ticks_msec()-timer_started-measured_route-measured_battle-measured_fixture)
 print("WIND CHAIN: %d failures"%failures);quit(1 if failures else 0)
func core():
 var b=setup();Rules.set_flag(b.session._profile,"ended",4,true)
 var will:=npc(b,"sainasu/event/genou_1");var mu:=npc(b,"sainasu/event/genou_3");var munde:=npc(b,"sainasu/event/event12")
 check(munde.branches.map(func(x):return int(x.source_branch_index))==[0,1,2,3,4],"one merged Munde retains full original branch ordering")
 # The UI end-to-end route covers REQUEST41 and the first ascent. Seed only
 # quest progress for this independent reward matrix; arrival is never seeded.
 Rules.set_flag(b.session._profile,"now",41,true)
 check(exchange(b,mu).ok and Rules.flag(b.session.snapshot(),"now",42),"original Mu starts42")
 for e in [9,10,11]:Rules.set_flag(b.session._profile,"now",e,true)
 var before_charm:int=b.session.snapshot().player.charm
 check(exchange(b,munde).ok and 2419 in b.session.snapshot().original_items and not 2736 in b.session.snapshot().original_items,"shared Munde first grants existing original stones")
 var r:=choose(b,source_talk(b,munde),"yes");var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-wind-chain-parent/fail.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"first harp failed save preserves state and flags")
 b.save_path=""
 check(exchange(b,munde).ok and Rules.flag(b.session.snapshot(),"ended",41) and 2736 in b.session.snapshot().original_items,"Munde grants harp andEND41 after earlier source branch")
 var charm:int=b.session.snapshot().player.charm
 Session.OriginalEquipment.remove(b.session._profile,2736)
 check(exchange(b,munde).ok and int(b.session.snapshot().player.charm)==charm,"lost harp replenishment does not grant charm again")
 r=source_talk(b,will)
 check(r.ok,"actual wind ascent reaches final reward")
 r=choose(b,r,"yes");before=b.session.snapshot();b.save_path="user://missing-wind-chain-parent/fail.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"wind42 save failure preserves harp UID and completion")
 b.save_path="user://wind-core-chain.json"
 check(exchange(b,will).ok and Rules.flag(b.session.snapshot(),"ended",42) and not Rules.flag(b.session.snapshot(),"now",42) and 2735 in b.session.snapshot().original_items and not 2736 in b.session.snapshot().original_items,"core ends42 and replaces harp with wind lock")
 check(not choose(b,r,"ok").ok,"core old reward cannot replay")
 var reload_started:int=Clock.ticks_msec()
 var loaded=Backend.new();check(loaded.load_profile(b.save_path) and Rules.flag(loaded.session.snapshot(),"ended",42),"core persisted completion reloads")
 check(not loaded.quest_arrival.check_action(loaded,will,will.branches[0],"reward").is_empty(),"reload cannot restore an in-memory final arrival")
 loaded.free()
 measured_fixture+=Clock.ticks_msec()-reload_started
 for mode in ["near","arrival"]:
  var standing:Vector2i=b.automation.position_cell
  check(b.handle({"type":"quest_visit","npc_id":will.id,"mode":mode}).ok and b.automation.position_cell==standing,"legal nearby helper stays stationary "+mode)
 return b
func offerings(b)->void:
 for level in [1,43,61]:
  b.save_path=""
  for item in b.session.snapshot().original_items:Session.OriginalEquipment.remove(b.session._profile,int(item))
  b.session._profile.pets=[];b.session.gm_grant_pet(95)
  b.session._profile.pets[0].level=level
  if level==61:
   Rules.set_flag(b.session._profile,"ended",4,true);Rules.set_flag(b.session._profile,"ended",42,true)
  else:
   Session.OriginalEquipment.add(b.session._profile,2758);Session.OriginalEquipment.add(b.session._profile,2758)
  var n:=npc(b,"sainasu/event/genou_2")
  var branch:Dictionary=b.original_quests.branch_for(n,b.session.snapshot())
  var expected:int=0 if level==61 else (1 if level==43 else 2)
  check(int(branch.source_branch_index)==expected,"actual source tier priority Lv%d"%level)
  var prizes:Array=Rules.item_list(str(branch.actions.GetRandItem))
  var before:Dictionary=b.session.snapshot()
  var r:=choose(b,source_talk(b,n),"yes")
  b.save_path="user://missing-wind-prize-parent/fail.json"
  check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"tier rollback preserves every UID Lv%d"%level)
  b.save_path=""
  check(exchange(b,n).ok and b.session.snapshot().pets.is_empty(),"actual tier consumes one ordinary95 Lv%d"%level)
  var items:Array=b.session.snapshot().original_items
  check(items.size()==1 and int(items[0]) in prizes and not 2758 in items,"actual original weighted prize and all bracelets consumed Lv%d"%level)
func boundaries()->void:
 var b=setup();var h=Wind.new();var helper=b.quest_helper
 var will:=npc(b,"sainasu/event/genou_1");var munde:=npc(b,"sainasu/event/event12")
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":will.id,"mode":mode}).ok,"raw Will cannot jump to temple "+mode)
  check(not b.handle({"type":"quest_visit","npc_id":munde.id,"mode":mode}).ok,"raw shared Munde cannot cross cave guard "+mode)
 b.automation.position_changed(11215,Vector2i(9,16))
 var state:Dictionary=helper.snapshot(b)
 var quest:Dictionary=state.quests.filter(func(q):return int(q.event)==41)[0]
 var step:Dictionary=quest.steps.filter(func(s):return str(s.npc_id)==will.id)[0]
 check(not h.can_visit(helper,b,step),"project temple landing cannot authorize Will navigation")
 for mode in ["near","arrival"]:
  var result:Dictionary=h.destination(helper,b,will,mode)
  if not result.is_empty():check(h.region_at(helper,b,11215,Vector2i(int(result.cell[0]),int(result.cell[1])))==h.region_at(helper,b,11215,b.automation.position_cell),"near and arrival remain in current component")
 b.automation.position_changed(11214,Vector2i(40,35))
 check(not h.can_visit(helper,b,step),"cached old temple step cannot bypass return across map")
 for mode in ["near","arrival"]:check(not b.handle({"type":"quest_visit","quest_id":quest.id,"step_id":step.id,"mode":mode}).ok,"old quest-step denied after map movement "+mode)
 var gate:=npc(b,"genout/wpm_100_278_325")
 Rules.set_flag(b.session._profile,"ended",4,false)
 source_talk(b,gate);check(b.original_quests.pending.phase=="end","wind entrance keeps END4")
 Rules.set_flag(b.session._profile,"ended",4,true);b.session._profile.player.level=69
 source_talk(b,gate);check(b.original_quests.pending.phase=="end","wind entrance keeps level70")
 b.session._profile.player.level=70
 check(choose(b,source_talk(b,gate),"yes").ok and b.automation.position_map==11201,"legal original entrance Warp")
 b.free()
func cooldowns(b)->void:
 var state=b.original_quests.npc_state
 var old:Callable=state.clock
 for id in state.records.keys():
  if not str(id).begins_with("100/sb_kbu.arg") or not state.records[id].has("dead_until"):continue
  var deadline:int=state.records[id].dead_until
  state.clock=func():return deadline
  b.original_quests.refresh_npc_state()
  check(b.original_quests.npc_by_id(id).is_empty(),"exact180 remains hidden")
  state.clock=func():return deadline+1
  b.original_quests.refresh_npc_state()
  check(not b.original_quests.npc_by_id(id).is_empty(),"181 guardian returns")
 state.clock=old
