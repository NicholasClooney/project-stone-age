extends "res://tests/original_fixed_guards_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Fire=preload("res://server/transmigration_fire_helper.gd")
const Shop=preload("res://server/original_jug_shop_service.gd")
const PREFIX="giiru/event/sink/"
func setup():
 var b=fresh();b.session.snapshot()
 Rules.set_flag(b.session._profile,"ended",4,true)
 return b
func source(b,short:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",""))==PREFIX+short:return n
 return {}
func named(b,script:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",""))==script:return n
 return {}
func walk_npc(b,npc:Dictionary,maps:Array)->bool:
 if not int(b.automation.position_map) in maps:return false
 var target:=Vector2i(npc.cell[0],npc.cell[1])
 for delta in [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]:
  var cell:Vector2i=target+delta
  if b.automation.position_cell==cell and int(b.automation.position_map)==int(npc.map_id):return true
  var steps:Array=Route.path(b,int(npc.map_id),cell,maps)
  if steps.is_empty():continue
  for step in steps:
   if not b.handle({"type":"report_position","map_id":step.map_id,"cell":step.cell}).get("ok",false):return false
  return true
 return false
func root_fire(b,upper:bool=false)->bool:
 var gate:=named(b,"genout/wpm_30503_26_5" if upper else "genout/wpm_30502_45_41")
 b.automation.position_changed(int(gate.map_id),Vector2i(gate.cell[0],gate.cell[1]+1))
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":gate.id})
 return choose(b,r,"yes").get("ok",false)
func cross_guard(b,script:String)->bool:
 var guard:=named(b,script)
 if not walk_npc(b,guard,range(30001,30017)):return false
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":guard.id})
 if not choose(b,r,"yes").get("ok",false):return false
 fight(b)
 return b.handle({"type":"battle_close"}).get("ok",false)
func source_talk(b,npc:Dictionary)->Dictionary:
 var map_id:=int(npc.map_id)
 if map_id in range(20301,20310):
  if not b.quest_arrival.has_arrival(b,map_id,b.automation.position_cell) or not walk_npc(b,npc,range(20301,20310)):
   b.automation.position_changed(200,Vector2i(421,577))
   if not b.handle({"type":"report_position","map_id":20301,"cell":[18,6]}).ok:return {"ok":false}
   var gate:=named(b,"genout/wpm_20301_200_39")
   if not walk_npc(b,gate,[20301]):return {"ok":false}
   var r:Dictionary=b.handle({"type":"quest_talk","npc_id":gate.id})
   if not choose(b,r,"yes").ok or not walk_npc(b,npc,range(20301,20310)):return {"ok":false}
 elif map_id in range(30001,30017):
  var reached:=false
  if b.quest_arrival.has_arrival(b,int(b.automation.position_map),b.automation.position_cell):reached=walk_npc(b,npc,range(30001,30017))
  if not reached:
   if not root_fire(b):return {"ok":false}
   reached=walk_npc(b,npc,range(30001,30017))
  if not reached and map_id not in [30008,30016]:
   if not root_fire(b,true):return {"ok":false}
   reached=walk_npc(b,npc,range(30001,30017))
  if not reached:
   if not root_fire(b) or not cross_guard(b,"300/sb_hba7.arg"):return {"ok":false}
   reached=walk_npc(b,npc,range(30001,30017))
  if not reached and map_id==30016:
   if not cross_guard(b,"300/sb_hpa.arg"):return {"ok":false}
   reached=walk_npc(b,npc,[30016])
  if not reached:return {"ok":false,"reason":"No source route to "+str(npc.id)}
 else:b.automation.position_changed(map_id,Vector2i(npc.cell[0],npc.cell[1]))
 return b.handle({"type":"quest_talk","npc_id":npc.id})
func grant(b,items:Array)->void:
 b.session._profile.original_items=[];b.session._profile.original_instances=[]
 for id in items:Session.OriginalEquipment.add(b.session._profile,int(id))
func commit_trade(b,npc:Dictionary)->Dictionary:
 var r:=source_talk(b,npc)
 if not r.get("ok",false):return r
 r=choose(b,r,"yes")
 return choose(b,r,"ok") if r.has("dialogue") else r
func run()->void:
 var b=setup()
 check(40 in b.quest_catalog.enabled_events and not source(b,"sink07").is_empty(),"production fire module imported and active")
 check(b.quest_catalog.active_npcs().filter(func(n):return Fire.new().owns(n)).size()==19,"19 real source fire NPCs including shop")
 b.free()
 water()
 rewards()
 await lan_water()
 print("TRANSMIGRATION FIRE: %d failures"%failures)
 quit(1 if failures else 0)
func core()->void:
 var b=setup();Rules.set_flag(b.session._profile,"ended",4,true)
 var request:=source(b,"sink07");var r:=source_talk(b,request)
 r=choose(b,r,"yes");check(choose(b,r,"ok").ok and Rules.flag(b.session.snapshot(),"now",40),"original true request starts40")
 var phoenix:=source(b,"sink01");r=source_talk(b,phoenix);r=choose(b,r,"yes")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-fire-parent/fail.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"feather save failure preserves profile")
 check(b.original_quests.npc_by_id(phoenix.id).cell==phoenix.cell,"save failure does not move phoenix")
 b.save_path="";check(commit_trade(b,phoenix).ok,"receive original phoenix feather")
 check(2706 in b.session.snapshot().original_items and b.original_quests.npc_by_id(phoenix.id).cell!=phoenix.cell,"personal phoenix moves after successful save")
 var untouched=setup();check(source(untouched,"sink01").cell==phoenix.cell,"other character sees original phoenix position");untouched.free()
 var ira:=source(b,"sink02");r=source_talk(b,ira);r=choose(b,r,"yes");before=b.session.snapshot();b.save_path="user://missing-fire-parent/fail.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"core savefail retains feather UID and flags")
 b.save_path="user://fire-core.json";check(commit_trade(b,ira).ok,"original core commits")
 var after:Dictionary=b.session.snapshot()
 check(Rules.flag(after,"ended",40) and not Rules.flag(after,"now",40) and 2707 in after.original_items and not 2706 in after.original_items and after.player.charm==before.player.charm+1,"core END40+charm+fire feather precisely once")
 var loaded=Backend.new();check(loaded.load_profile(b.save_path) and loaded.session.snapshot().original_instances==after.original_instances,"core saved UID reload");loaded.free()
 r=source_talk(b,ira);check(b.original_quests.pending.get("phase","")=="end" and b.session.snapshot().player.charm==after.player.charm,"ended core never grants twice")
 b.free()
func water(which:String="")->void:
 var b=setup();var elder:=source(b,"sink03")
 if which.is_empty():
  for pair in [["很多",2709],["一半",2710],["一点点",2711]]:
   grant(b,[2708,2708]);var r:=source_talk(b,elder)
   r=b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"submit","text":pair[0]})
   r=choose(b,r,"yes");check(choose(b,r,"ok").ok and b.session.snapshot().original_items==[pair[1]],"original exact water keyword, bareDelItem consumes all empty jugs")
  grant(b,[2708,2708,2712]);var gold:int=b.session._profile.player.gold
  check(commit_trade(b,elder).ok and b.session.snapshot().original_items==[2712] and b.session.snapshot().player.gold==gold+1149,"refund all empty jugs once1149 only with existing water")
  b.free();return
 var npc:=source(b,which)
 var pairs:Array=[[2709,2716],[2712,2717],[2713,2718],[2710,2708],[2711,2708],[2714,2708],[2715,2708],[2716,2708],[2717,2708],[2718,2708]] if which.begins_with("sink044") else [[2709,2712],[2710,2715],[2711,2716],[2712,2713],[2713,2714],[2714,2715],[2715,2716],[2716,2717],[2717,2718],[2718,2708]]
 for index in range(pairs.size()):
  # Independent item-state cases reuse one genuinely earned player route.
  # Only this NPC's test fixture is restored; never touch arrival/position.
  b.original_quests.npc_state.records[npc.id]={"counter":index}
  b.original_quests.npc_state.version+=1;b.original_quests.refresh_npc_state()
  var pair:Array=pairs[index];grant(b,[pair[0],pair[0]])
  var selected:Dictionary=b.original_quests.branch_for(npc,b.session.snapshot())
  var destinations:Array=[]
  for raw in str(selected.actions.NpcWarp).split(",",false):destinations.append(Array(raw.split(".")))
  check(commit_trade(b,npc).ok and b.session.snapshot().original_items==[pair[1]],which+" conversion "+str(pair))
  var moved:Dictionary=b.original_quests.npc_by_id(npc.id)
  var expected:Array=destinations[index%destinations.size()]
  check(int(moved.map_id)==int(expected[0]) and moved.cell==[int(expected[1]),int(expected[2])],which+" actual source NpcWarp destination "+str(index))
 b.original_quests.npc_state.records.erase(npc.id)
 b.original_quests.npc_state.version+=1;b.original_quests.refresh_npc_state()
 if which=="sink044a":
  grant(b,[2712,2710]);check(commit_trade(b,npc).ok and b.session.snapshot().original_items==[2710,2717],"044a earlier conversion beats overlapping clear branch")
 if which=="sink044":
  grant(b,[2710,2711,2714,2715,2716,2717,2718]);check(commit_trade(b,npc).ok and b.session.snapshot().original_items==[2708],"clear branch consumes complete bare-ID list including trailing comma")
 b.free()
func rewards()->void:
 var b=setup();var npc:=source(b,"sink06")
 grant(b,[2718]);Rules.set_flag(b.session._profile,"now",40,true)
 check(b.original_quests.branch_for(npc,b.session.snapshot()).source_branch_index==1,"NOW40 explanation precedes reward")
 Rules.set_flag(b.session._profile,"now",40,false);grant(b,[2708,2718])
 check(b.original_quests.branch_for(npc,b.session.snapshot()).source_branch_index==2,"original empty jug explanation precedes reward")
 for id in range(2712,2719):
  grant(b,[id,id]);var r:=source_talk(b,npc)
  var pool:Array=Rules.item_list(str(b.original_quests.pending.branch.actions.GetRandItem))
  var before:Dictionary=b.session.snapshot();r=choose(b,r,"yes");b.save_path="user://missing-fire-parent/fail.json"
  check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"random reward failed save is atomic")
  b.save_path="";check(commit_trade(b,npc).ok,"random trade allowed without fabricatedEND40")
  var items:Array=b.session.snapshot().original_items
  check(items.size()==1 and items[0] in pool and not Rules.flag(b.session.snapshot(),"ended",40),"one original pool result consumes all same-ID tickets and does not complete40")
 b.free()
func guards_and_navigation()->void:
 var b=setup();var helper=Fire.new()
 for npc in b.quest_catalog.active_npcs():
  if str(npc.get("source_script","")) not in Fire.GUARDS:continue
  var r:=source_talk(b,npc);check(choose(b,r,"yes").ok,"fire actual guard starts")
  check(b.session._pending.enemies.size()==10,"fire guard all ten enemies")
  fight(b);check(b.handle({"type":"battle_close"}).ok,"fire guard settlement")
 var ira:=source(b,"sink02")
 b.automation.position_changed(30016,Vector2i(28,99))
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":ira.id,"mode":mode}).ok,"rawNPC cannot skip final guardian")
 check(source_talk(b,ira).get("ok",false),"real route returns to Ira after project invalidation")
 var steps:Dictionary=b.quest_helper.snapshot(b)
 var fire:Dictionary=steps.quests.filter(func(q):return int(q.event)==40)[0]
 var old:Dictionary=fire.steps.filter(func(s):return s.npc_id==ira.id)[0]
 check(helper.can_visit(b.quest_helper,b,old),"legitimate final mark and current near position authorize stationary step")
 for mode in ["near","arrival"]:
  var point:Dictionary=helper.destination(b.quest_helper,b,ira,mode)
  if not point.is_empty():check(helper.region_at(b.quest_helper,b,30016,Vector2i(point.cell[0],point.cell[1]))==helper.region_at(b.quest_helper,b,30016,b.automation.position_cell),"near/arrival same component")
 b.automation.position_changed(30001,Vector2i(29,14))
 check(not helper.can_visit(b.quest_helper,b,old),"stale step cannot visit future floor")
 for mode in ["near","arrival"]:check(not b.handle({"type":"quest_visit","npc_id":ira.id,"mode":mode}).ok,"rawNPC cannot visit future floor")
 b.free()

func lan_water()->void:
 var b=setup();root.add_child(b);var elder:=source(b,"sink03")
 grant(b,[2708,2708]);source_talk(b,elder);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"fire water LAN port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two fire water devices")
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":elder.id})
 r=await request(links[0],{"type":"quest_choose","token":r.dialogue.token,"choice":"submit","text":"很多"})
 r=await request(links[0],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 var confirm:={"type":"quest_choose","token":r.dialogue.token,"choice":"ok"}
 check((await request(links[1],confirm)).ok,"second fire device commits shared keyword token")
 var after:Dictionary=b.session.snapshot()
 check(after.original_items==[2709] and after.original_instances.size()==1,"LAN bare DelItem consumes both UID jugs once")
 check(not (await request(links[0],confirm)).ok and b.session.snapshot()==after,"LAN old confirmation cannot repeat conversion or allocate UID")
 for link in links:link.close()
 links.clear();server.stop();server.queue_free();b.queue_free();await process_frame
