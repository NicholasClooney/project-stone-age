extends "res://tests/original_fixed_guards_test.gd"
const Travel=preload("res://tests/support/water_route_driver.gd")
const Dragon=preload("res://server/dragon_cave_helper.gd")
const FLUTE="jaruga/event/event17_4@20801:13:63"
const GATE="genout/wpm_20807_11_37@20807:11:37"
const REWARDS=["jaruga/event/event17_1@20807:7:8","jaruga/event/event17_2@20807:23:6","jaruga/event/event17_3@20807:41:14"]
func gems(b)->void:
 var rng:=RandomNumberGenerator.new();rng.seed=17
 for spec in [[20804,404,2457],[20805,405,2458],[20806,406,2459]]:
  var info:Dictionary=b.quest_helper.places.info(int(spec[0]));var pos:Array=info.spawn
  var area:Dictionary=b.encounter_catalog.area_at(int(spec[0]),Vector2i(int(pos[0]),int(pos[1])))
  check(not area.is_empty(),"original dragon floor has encounter region")
  check(b.encounter_catalog.roll_group(area,int(spec[1]),rng,[]).is_empty(),"without flute source dragon group unavailable")
  for attempt in range(40):
   var troop:Dictionary=b.encounter_catalog.roll_group(area,int(spec[1]),rng,b.session.snapshot().original_items)
   check(not troop.is_empty() and preload("res://server/troop_art.gd").can_render(troop.enemies),"source conditional dragon troop has original art")
   var config:Dictionary=b.session.start_wild_battle_config(troop)
   check(not config.is_empty(),"real Session validates full original dragon troop")
   if config.is_empty():return
   b.open_battle(config);fight(b);b.handle({"type":"battle_close"})
   if int(spec[2]) in b.session.snapshot().original_items:break
  check(int(spec[2]) in b.session.snapshot().original_items,"real dragon victory earns source80percent jade")
func enter(b)->bool:
 b.original_quests.pending={}
 for portal in b.quest_helper.places.links(200).values():
  if int(portal.to_map)==20801 and not portal.get("disabled",false):
   b.automation.position_changed(200,Vector2i(int(portal.cell[0]),int(portal.cell[1])))
   return b.handle({"type":"report_position","map_id":20801,"cell":portal.target}).get("ok",false)
 return false
func talk(b,id:String)->Dictionary:
 b.original_quests.pending={}
 check(Travel.walk_near(b,b.original_quests.npc_by_id(id),range(20801,20808)),"real route to "+id)
 return b.handle({"type":"quest_talk","npc_id":id})
func boundary(b)->void:
 var before:Dictionary=b.session.snapshot()
 var pos:Vector2i=b.automation.position_cell
 for mode in ["near","arrival"]:
  for id in REWARDS:
   check(not b.handle({"type":"quest_visit","npc_id":id,"mode":mode}).ok,"raw reward NPC cannot bypass three-jewel gate")
  for step in ["dragon17:reward:1","dragon17:reward:2","dragon17:reward:3","dragon17:jade:2457"]:
   check(not b.handle({"type":"quest_visit","step_id":step,"quest_id":26,"mode":mode}).ok,"old reward/jade step cannot bypass original route")
 check(b.session.snapshot()==before and b.automation.position_cell==pos,"refused helper requests leave profile and position unchanged")
func nearby(b,id:String)->void:
 check(Travel.walk_near(b,b.original_quests.npc_by_id(id),range(20801,20808)),"real walk to near interaction")
 var point:Vector2i=b.automation.position_cell
 for mode in ["near","arrival"]:
  check(b.handle({"type":"quest_visit","npc_id":id,"mode":mode}).ok and b.automation.position_cell==point,"both modes preserve legitimate near position")
func run()->void:
 var b=fresh()
 check(17 in b.quest_catalog.enabled_events,"registered17")
 var original_events:Array=b.quest_catalog.enabled_events.duplicate()
 var key_with_dragon:Array=b.quest_helper.navigation_key(b)
 b.quest_catalog.enabled_events=original_events.filter(func(event):return int(event)!=17)
 check(Dragon.stage_key(b).is_empty() and b.quest_helper.navigation_key(b)==key_with_dragon,"outside dragon contributes nothing while every other module key remains intact")
 b.quest_catalog.enabled_events=original_events
 b.automation.position_changed(-999,Vector2i.ZERO)
 check(Dragon.stage_key(b).is_empty() and not Dragon.inside(b),"unknown map fails closed without global stage key")
 b.quest_catalog.enabled_events=original_events
 b.automation.position_changed(20801,Vector2i(12,63))
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":FLUTE,"mode":mode}).ok,"project first-floor placement cannot claim flute via raw helper")
  check(not b.handle({"type":"quest_visit","quest_id":26,"step_id":"dragon17:flute","mode":mode}).ok,"old flute step cannot bless project placement")
 check(enter(b),"actual public portal starts seven-floor route")
 check(Travel.walk_near(b,b.original_quests.npc_by_id(FLUTE),[20801]),"walk near original flute NPC")
 for mode in ["near","arrival"]:
  check(b.handle({"type":"quest_visit","quest_id":26,"step_id":"dragon17:flute","mode":mode}).ok,"arriving near refreshes previously hidden flute step")
 check(trade(b,FLUTE).ok and Rules.flag(b.session.snapshot(),"now",17) and 2505 in b.session.snapshot().original_items,"source guardian gives flute and NOW17")
 boundary(b)
 check(Dragon.stage_key(b)[0]=="dragon17" and not Dragon.inside(b),"route stage includes near and arrival state")
 gems(b)
 boundary(b)
 var opened:=talk(b,GATE);var before:Dictionary=b.session.snapshot();b.save_path="user://dragon-missing-parent/save.json"
 check(not choose(b,opened,"yes").ok and b.session.snapshot()==before and not Dragon.inside(b),"failed gate save preserves entrance and all gems")
 b.save_path=""
 check(trade(b,GATE).ok and Dragon.inside(b),"original guard alone enters reward component")
 check(Dragon.stage_key(b)[0]=="dragon17" and Dragon.inside(b),"gate grants original inside component")
 for id in [2457,2458,2459]:check(id in b.session.snapshot().original_items,"source gate keeps jade")
 for id in REWARDS:nearby(b,id)
 var earned:Dictionary=b.session.snapshot()
 # A previously valid reward step is re-resolved after leaving the component.
 b.automation.position_changed(20807,Vector2i(11,38))
 check(not b.handle({"type":"quest_visit","quest_id":26,"step_id":"dragon17:reward:2","mode":"near"}).ok,"stale inside reward step cannot jump back through gate")
 check(not Travel.commit(b,b.original_quests.npc_by_id(GATE)),"project placement at gate cannot launder arrival")
 check(enter(b) and Travel.walk_near(b,b.original_quests.npc_by_id(GATE),range(20801,20808)) and Travel.commit(b,b.original_quests.npc_by_id(GATE)),"re-enter through actual public root, seven floors and source gate")
 for index in range(REWARDS.size()):
  b.session._profile=earned.duplicate(true)
  var r:=choose(b,talk(b,REWARDS[index]),"yes");before=b.session.snapshot();b.save_path="user://dragon-missing-parent/save.json"
  check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"reward save failure leaves gems/flute and END17 atomic")
  b.save_path=""
  check(trade(b,REWARDS[index]).ok and Rules.flag(b.session.snapshot(),"ended",17),"source selected reward completes17")
  check([2462,2460,2461][index] in b.session.snapshot().original_items,"correct one-of-three source reward")
  for id in [2457,2458,2459,2505]:check(not id in b.session.snapshot().original_items,"reward consumes source jade/flute")
  before=b.session.snapshot();trade(b,REWARDS[(index+1)%3])
  check(b.session.snapshot().original_items==before.original_items,"completed17 cannot claim another dragon reward")
 var path:="user://dragon-earned.json";check(b.session.save_game(path),"earned dragon save")
 var restored=Session.new();check(restored.load_game(path) and Rules.flag(restored.snapshot(),"ended",17),"END17 survives reload")
 var reboot=fresh()
 check(reboot.session.load_game(path),"new authority loads earned save")
 reboot.automation.position_changed(20807,b.automation.position_cell)
 check(not reboot.quest_arrival.has_arrival(reboot,20807,reboot.automation.position_cell) and not reboot.handle({"type":"quest_visit","npc_id":REWARDS[2],"mode":"arrival"}).ok,"fresh authority never restores route from saved inventory or END17")
 reboot.free()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 b.quest_arrival.reset()
 check(not b.handle({"type":"quest_visit","npc_id":REWARDS[2],"mode":"near"}).ok,"restart loses route despite retained END17 and room")
 b.free()
 await dragon_lan(earned)
 print("DRAGON CAVE: %d failures"%failures);quit(1 if failures else 0)

func dragon_lan(earned:Dictionary)->void:
 var b=fresh();b.session._profile=earned.duplicate(true);root.add_child(b)
 b.automation.position_changed(20807,Vector2i(11,38))
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"dragon LAN port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"dragon two real sockets")
 check(not (await request(links[0],{"type":"quest_visit","npc_id":REWARDS[1],"mode":"arrival"})).ok,"remote client cannot navigate across wall")
 check(not (await request(links[0],{"type":"quest_talk","npc_id":GATE})).ok,"LAN project gate cannot launder route")
 check(enter(b) and Travel.walk_near(b,b.original_quests.npc_by_id(GATE),range(20801,20808)),"LAN authority traverses actual seven floors")
 await request(links[0],{"type":"quest_visit","npc_id":GATE,"mode":"near"})
 var a:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":GATE})
 check((await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})).ok,"remote source gate enters")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check(Travel.walk_near(b,b.original_quests.npc_by_id(REWARDS[1]),[20807]),"LAN authority walks from committed gate to reward")
 await request(links[0],{"type":"quest_visit","npc_id":REWARDS[1],"mode":"near"})
 a=await request(links[0],{"type":"quest_talk","npc_id":REWARDS[1]})
 a=await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})
 await request(links[0],{"type":"ping"})
 var c:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":REWARDS[1]})
 check(not (await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"ok"})).ok,"second socket invalidates old reward token")
 c=await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"yes"})
 check((await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"ok"})).ok,"second socket commits source spear")
 check(not (await request(links[0],{"type":"quest_choose","token":c.dialogue.token,"choice":"ok"})).ok and b.session.snapshot().original_items.count(2460)==1,"LAN retry cannot duplicate chosen reward")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free();await process_frame
