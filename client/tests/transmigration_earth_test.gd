extends "res://tests/original_fixed_guards_test.gd"
const EarthRoute=preload("res://tests/support/earth_route_driver.gd")
const Earth=preload("res://server/transmigration_earth_helper.gd")
func npc(b,script:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",""))==script:return n
 return {}
func source_talk(b,n:Dictionary)->Dictionary:
 if int(n.map_id) in range(21001,21017):
  if not EarthRoute.approach(b,n):return {"ok":false,"reason":"original path unavailable"}
 else:b.automation.position_changed(int(n.map_id),Vector2i(int(n.cell[0])+1,int(n.cell[1])))
 return b.handle({"type":"quest_talk","npc_id":n.id})
func grant(b,id:int)->void:b.session.OriginalEquipment.add(b.session._profile,id)
func exchange(b,n:Dictionary)->Dictionary:
 var r:=choose(b,source_talk(b,n),"yes")
 while r.has("dialogue") and not str(r.dialogue.get("token","")).is_empty():
  r=choose(b,r,"ok")
 return r
func run()->void:
 var b=fresh();b.session.snapshot()
 check(39 in b.quest_catalog.enabled_events,"earth39 active via trusted descriptor")
 check(JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/transmigration-earth.json")).enabled_events.map(func(e):return int(e))==[39],"earth descriptor owns exactly39 independently of other active chains")
 var father:=npc(b,"jaruga/event/ruri02");var son:=npc(b,"jaruga/event/ruri03");var goddess:=npc(b,"jaruga/event/ruri01")
 if father.is_empty() or son.is_empty() or goddess.is_empty():check(false,"actual earth NPCs imported");b.free();quit(1);return
 check(not b.original_quests.branch_for(father,b.session.snapshot()).get("type","")=="REQUEST","adult prerequisite remains authoritative")
 Rules.set_flag(b.session._profile,"ended",4,true)
 check(exchange(b,father).ok and Rules.flag(b.session.snapshot(),"now",39),"real request39")
 check(Rules.item_count(b.session.snapshot(),2699)==1,"request gives necklace")
 var before:Dictionary=b.session.snapshot();var original_cell:Array=son.cell.duplicate()
 var r:=choose(b,source_talk(b,son),"yes");b.save_path="user://missing-earth-parent/fail.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"diary save failure keeps profile and UID")
 check(npc(b,"jaruga/event/ruri03").cell==original_cell,"failed diary does not move personal NPC")
 b.save_path="";check(exchange(b,son).ok and Rules.item_count(b.session.snapshot(),2698)==1,"actual ruri03 gives diary")
 var diary_uid:int=0
 for item in b.session.snapshot().original_instances:
  if int(item.item_id)==2698:diary_uid=int(item.uid)
 check(diary_uid>0,"diary uses authoritative UID")
 var necklace_uid:int=0
 for item in b.session.snapshot().original_instances:
  if int(item.item_id)==2699:necklace_uid=int(item.uid)
 check(b.handle({"type":"equip_item","item":"original:%d"%necklace_uid}).ok,"original necklace actually equips")
 check(b.original_quests.branch_for(goddess,b.session.snapshot()).get("type","")!="ACCEPT","worn necklace cannot satisfy core bareITEM gate")
 check(b.handle({"type":"equip_item","item":"original:%d"%necklace_uid}).ok,"unequip restores core material eligibility")
 check(EarthRoute.reach_goddess(b,self),"real entrance, judgement and both battles grant final arrival")
 before=b.session.snapshot();r=choose(b,source_talk(b,goddess),"yes")
 b.save_path="user://missing-earth-parent/fail.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"core save failure consumes neither material nor UID")
 b.save_path="user://earth-chain.json"
 check(exchange(b,goddess).ok,"core retry succeeds")
 var done:Dictionary=b.session.snapshot()
 check(Rules.flag(done,"ended",39) and Rules.item_count(done,2701)==1 and Rules.item_count(done,2698)==0 and Rules.item_count(done,2699)==0,"END39 only after both materials become bond")
 check(int(done.player.charm)==int(before.player.charm)+1,"core charm exactly once")
 exchange(b,goddess);check(b.session.snapshot()==done,"completed core cannot repeat")
 var loaded=Backend.new();check(loaded.load_profile(b.save_path) and loaded.session.snapshot().original_instances==done.original_instances,"saved reward UIDs reload unchanged");loaded.free()
 b.save_path=""
 bags(b)
 await lan_bag(b)
 navigation(b)
 b.free()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://earth-chain.json"+suffix))
 print("TRANSMIGRATION EARTH: %d failures"%failures)
 quit(1 if failures else 0)
func bags(b)->void:
 for script in ["jaruga/event/ruri05","jaruga/event/ruri06"]:
  var bag:=npc(b,script)
  check(str(bag.branches[0].actions.GetRandItem).split(",").size()==85,"complete85 weighted source slots")
  grant(b,2700)
  var feather_uid:int=int(b.session.snapshot().original_instances[-1].uid)
  check(b.handle({"type":"equip_item","item":"original:%d"%feather_uid}).ok,"source feather actually equips")
  check(b.original_quests.branch_for(bag,b.session.snapshot()).get("type","")!="ACCEPT","worn feather cannot open bag exchange")
  check(b.handle({"type":"equip_item","item":"original:%d"%feather_uid}).ok,"unequip restores bag ticket")
  grant(b,2700)
  var before:Dictionary=b.session.snapshot()
  var r:=choose(b,source_talk(b,bag),"yes");b.save_path="user://missing-earth-parent/fail.json"
  check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"bag save failure keeps both feather UIDs")
  check(not choose(b,r,"ok").ok,"failed bag token is single use")
  b.save_path=""
  r=choose(b,source_talk(b,bag),"yes")
  check(choose(b,r,"ok").ok,"bag retry real save transaction")
  var after:Dictionary=b.session.snapshot()
  check(Rules.item_count(after,2700)==0 and after.original_items.size()==before.original_items.size()-1,"all feathers consumed for exactly one reward")
  check(not choose(b,r,"ok").ok,"bag reward token cannot replay")
  var ids:Array=str(bag.branches[0].actions.GetRandItem).split(",")
  check(str(after.original_items[-1]) in ids,"reward belongs to source85 pool")
  grant(b,2700);check(exchange(b,bag).ok and Rules.item_count(b.session.snapshot(),2700)==0,"new feather permits source repeat without added flag")
func navigation(b)->void:
 var goddess:=npc(b,"jaruga/event/ruri01")
 for mode in ["near","arrival"]:
  b.automation.position_changed(21014,Vector2i(22,23))
  check(not b.handle({"type":"quest_visit","npc_id":goddess.id,"mode":mode}).ok,"raw goddess cannot bypass final guard "+mode)
  b.automation.position_changed(21015,Vector2i(9,17))
  var step:Dictionary={}
  for q in b.quest_helper.snapshot(b).quests:
   if int(q.event)==39:
    for candidate in q.steps:
     if str(candidate.id)=="earth39:deliver":step=candidate
  check(not step.is_empty(),"authoritative earth helper step exists")
  var dest:Dictionary=Earth.destination(b.quest_helper,b,goddess,mode)
  check(dest.is_empty(),"project arrival in same component grants no navigation "+mode)
  if not dest.is_empty():check(Earth.region_at(b.quest_helper,b,21015,Vector2i(int(dest.cell[0]),int(dest.cell[1])))==Earth.region_at(b.quest_helper,b,21015,b.automation.position_cell),"final destination remains same component")
  b.automation.position_changed(21014,Vector2i(22,23))
  check(not Earth.can_visit(b.quest_helper,b,step),"old eligible step rechecks actual floor")
  check(not b.handle({"type":"quest_visit","quest_id":36,"step_id":"earth39:deliver","mode":mode}).ok,"old step request denied after leaving")
 var gate:=npc(b,"genout/wpm_21003_34_10")
 b.automation.position_changed(21003,Vector2i(34,28))
 for mode in ["near","arrival"]:
  var target:Dictionary=Earth.destination(b.quest_helper,b,gate,mode)
  check(target.is_empty(),"project arrival cannot approach judgement "+mode)
  if not target.is_empty():check(Earth.region_at(b.quest_helper,b,21003,Vector2i(int(target.cell[0]),int(target.cell[1])))==Earth.region_at(b.quest_helper,b,21003,Vector2i(34,28)),"gate navigation cannot cross wall")
func earth_guard(b,guard:Dictionary)->void:
 check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==guard.branches[0].guard.enemy_ids.map(func(e):return int(e)),"complete original ten enemy order")
 check(preload("res://server/troop_art.gd").can_render(b.session._pending.enemies),"ten original enemy art available")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-earth-parent/fail.json"
 fight(b);check(b.session.snapshot()==before,"guard failed save cannot warp")
 b.save_path="";check(b.handle({"type":"battle_close"}).ok,"guard victory same-roll retry")
 var warp:PackedStringArray=str(guard.branches[0].actions.Warp).split(",")
 check(b.automation.position_map==int(warp[0]) and b.automation.position_cell==Vector2i(int(warp[1]),int(warp[2])),"exact source victory warp")
func lan_bag(b)->void:
 root.add_child(b);var bag:=npc(b,"jaruga/event/ruri05");grant(b,2700)
 source_talk(b,bag);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"earth LAN ephemeral server")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two real devices connect")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var a:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":bag.id})
 var c:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":bag.id})
 check(not (await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})).ok,"second device invalidates stale bag token")
 c=await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"yes","GetItem":95})
 var token:String=c.dialogue.token
 check((await request(links[1],{"type":"quest_choose","token":token,"choice":"ok"})).ok,"real RPC bag commit")
 check(not 95 in b.session.snapshot().original_items and Rules.item_count(b.session.snapshot(),2700)==0,"client cannot override full source pool")
 check(not (await request(links[0],{"type":"quest_choose","token":token,"choice":"ok"})).ok,"cross-device reward replay denied")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();root.remove_child(b)
