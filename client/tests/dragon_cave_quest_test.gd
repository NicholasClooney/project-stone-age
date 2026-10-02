extends "res://tests/original_fixed_guards_test.gd"
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
func boundary(b)->void:
 var snapshot:Dictionary=b.quest_helper.snapshot(b)
 for mode in ["near","arrival"]:
  for id in REWARDS:
   check(not b.handle({"type":"quest_visit","npc_id":id,"mode":mode}).ok,"raw reward NPC cannot bypass three-jewel gate")
  for quest in snapshot.quests:
   if int(quest.event)!=17:continue
   for step in quest.steps:
    if str(step.id).begins_with("dragon17:reward:"):
     check(not b.handle({"type":"quest_visit","step_id":step.id,"quest_id":26,"mode":mode}).ok,"reward step cannot bypass source gate")
  check(b.handle({"type":"quest_visit","npc_id":GATE,"mode":mode}).ok and not Dragon.inside(b),"both gate navigation modes remain in entrance component")
func run()->void:
 var b=fresh()
 check(17 in b.quest_catalog.enabled_events,"registered17")
 check(trade(b,FLUTE).ok and Rules.flag(b.session.snapshot(),"now",17) and 2505 in b.session.snapshot().original_items,"source guardian gives flute and NOW17")
 boundary(b)
 gems(b)
 boundary(b)
 var opened:=talk(b,GATE);var before:Dictionary=b.session.snapshot();b.save_path="user://dragon-missing-parent/save.json"
 check(not choose(b,opened,"yes").ok and b.session.snapshot()==before and not Dragon.inside(b),"failed gate save preserves entrance and all gems")
 b.save_path=""
 check(trade(b,GATE).ok and Dragon.inside(b),"original guard alone enters reward component")
 for id in [2457,2458,2459]:check(id in b.session.snapshot().original_items,"source gate keeps jade")
 for mode in ["near","arrival"]:
  for id in REWARDS:check(b.handle({"type":"quest_visit","npc_id":id,"mode":mode}).ok and Dragon.inside(b),"after source gate reward navigation stays inside component")
 var earned:Dictionary=b.session.snapshot()
 # A previously valid reward step is re-resolved after leaving the component.
 b.automation.position_changed(20807,Vector2i(11,38))
 check(not b.handle({"type":"quest_visit","quest_id":26,"step_id":"dragon17:reward:2","mode":"near"}).ok,"stale inside reward step cannot jump back through gate")
 check(trade(b,GATE).ok,"re-enter only through original gate")
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
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
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
 await request(links[0],{"type":"quest_visit","npc_id":GATE,"mode":"near"})
 var a:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":GATE})
 check((await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})).ok,"remote source gate enters")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
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
