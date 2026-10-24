extends "res://tests/original_fixed_guards_test.gd"
const Clock=preload("res://scripts/clock.gd")
const WaterRoute=preload("res://tests/support/water_route_driver.gd")
var unit_battle_ms:int=0
const Water=preload("res://server/transmigration_water_helper.gd")
func setup():
 var b=fresh();b.session.snapshot();return b
func source(b,script:String)->Dictionary:
 for npc in b.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))==script:return npc
 check(false,"source NPC exists "+script);return {}
func source_talk(b,npc:Dictionary)->Dictionary:
 var script:=str(npc.get("source_script",""))
 if int(npc.map_id) in range(21201,21316):
  # Acquisition fixture only: pass the real material door with both items,
  # then discard added copies to exercise the already-approved missing OR.
  var seeded:Array=[]
  if script=="jaruga/event/hekisei03":
   for id in [2767,2768]:
    if Rules.item_count(b.session.snapshot(),id)==0:
     grant(b,id);seeded.append(id)
  if not check_route(WaterRoute.cave(b,script),script):return {"ok":false}
  for id in seeded:b.handle({"type":"quest_discard","item_id":id})
 elif int(npc.map_id) in [31301,31302]:
  if not check_route(WaterRoute.lake(b,true),script):return {"ok":false}
 else:
  b.original_quests.pending={}
  b.automation.position_changed(int(npc.map_id),Vector2i(int(npc.cell[0])+1,int(npc.cell[1])))
 return b.handle({"type":"quest_talk","npc_id":npc.id})
func check_route(ok:bool,script:String)->bool:
 check(ok,"production original route to "+script);return ok
func grant(b,id:int)->void:b.session.OriginalEquipment.add(b.session._profile,id)
func execute(b,npc:Dictionary)->Dictionary:
 var r:=source_talk(b,npc)
 r=choose(b,r,"yes")
 if r.has("dialogue"):r=choose(b,r,"ok")
 return r
func run()->void:
 activation()
 prerequisites()
 var started:int=Clock.ticks_msec()
 var b=guards_and_gates()
 print("WATER TIMING unit_route_and_guard_ms=",Clock.ticks_msec()-started)
 exchanges(b)
 await water_lan(b)
 navigation(b)
 b.free()
 print("WATER TIMING unit_total_ms=",Clock.ticks_msec()-started," real_guard_battle_ms=",unit_battle_ms)
 print("TRANSMIGRATION WATER: %d failures"%failures);quit(1 if failures else 0)
func activation()->void:
 var b=setup()
 var frozen:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-water.json"))
 var expected:Array=frozen.npcs.map(func(n):return str(n.id));expected.sort()
 var active:Array=b.quest_catalog.active_npcs().filter(func(n):return n.get("events",[]).any(func(event):return int(event)==46)).map(func(n):return str(n.id));active.sort()
 check(expected.size()==15 and active==expected,"enabled water has exactly the fifteen frozen source NPCs")
 var quest:Dictionary={}
 for candidate in b.quest_helper.snapshot(b).quests:
  if int(candidate.event)==46:quest=candidate;break
 for row in [["water46:stone",30305,570,718,1324],["water46:shell",21209,581,723,1335]]:
  var matches:Array=quest.steps.filter(func(step):return str(step.id)==str(row[0]))
  check(matches.size()==1,"one exact original encounter helper step "+str(row[0]))
  if matches.size()==1:
   var step:Dictionary=matches[0]
   check([int(step.map_id),int(step.source.area_id),int(step.source.group_id),int(step.source.enemy_id)]==row.slice(1),"helper uses actual source area/group/enemy edge")

 var before:Array=b.quest_catalog.active_npcs().filter(func(n):return not n.get("events",[]).any(func(event):return int(event)==46)).map(func(n):return str(n.id));before.sort()
 before.append_array(frozen.always_active_npc_ids);before.sort()
 b.quest_catalog.enabled_events.erase(46)
 var disabled:Array=b.quest_catalog.active_npcs().map(func(n):return str(n.id));disabled.sort()
 check(disabled==before,"disabled water removes exactly its own NPCs and preserves all other active NPCs")
 b.free()
func prerequisites()->void:
 for event in [39,40,42]:
  var b=setup();Rules.set_flag(b.session._profile,"ended",4,true);Rules.set_flag(b.session._profile,"ended",event,true)
  check(execute(b,source(b,"jaruga/event/hekisei")).ok and Rules.flag(b.session.snapshot(),"now",46),"END4 plus ONLY %d accepts46"%event)
  check(not Rules.flag(b.session.snapshot(),"ended",46),"request cannot complete46")
  b.free()
 for flags in [[],[4],[39],[40],[42]]:
  var b=setup()
  for event in flags:Rules.set_flag(b.session._profile,"ended",event,true)
  source_talk(b,source(b,"jaruga/event/hekisei"))
  check(b.original_quests.pending.get("phase","")=="end" and not Rules.flag(b.session.snapshot(),"now",46),"missing prerequisite refuses "+str(flags))
  b.free()
func exchanges(b)->void:
 for id in [2767,2768]:b.handle({"type":"quest_discard","item_id":id})
 var sage:=source(b,"jaruga/event/hekisei03")
 # Reuse the actual guard/door arrival, then discard source materials: OR.
 check(WaterRoute.cave(b,"jaruga/event/hekisei03"),"original door arrival reaches sage")
 var at:Vector2i=b.automation.position_cell
 for mode in ["near","arrival"]:
  check(b.handle({"type":"quest_visit","npc_id":sage.id,"mode":mode}).ok and b.automation.position_cell==at,"legal sage helper is stationary "+mode)
  check(b.handle({"type":"quest_visit","quest_id":46,"step_id":"water46:crystal","mode":mode}).ok and b.automation.position_cell==at,"exact current sage branch helper is stationary "+mode)
 check(execute(b,sage).ok and Rules.item_count(b.session.snapshot(),2769)==1,"approved original OR grants crystal without materials")
 b.handle({"type":"quest_discard","item_id":2769})
 for id in [2767,2767,2768,2768]:grant(b,id)
 check(execute(b,sage).ok,"same legitimately reached sage commits material synthesis")
 check(Rules.item_count(b.session.snapshot(),2767)==0 and Rules.item_count(b.session.snapshot(),2768)==0 and Rules.item_count(b.session.snapshot(),2769)==1,"bare DelItem removes ALL both material IDs")
 var goddess:=source(b,"jaruga/event/hekisei01")
 var reward:=choose(b,source_talk(b,goddess),"yes")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-water-parent/fail.json"
 check(not choose(b,reward,"ok").ok and b.session.snapshot()==before,"core save failure preserves crystal UID and flags")
 check(not choose(b,reward,"ok").ok,"failed core token cannot replay")
 b.save_path="user://transmigration-water.json"
 check(execute(b,goddess).ok and Rules.flag(b.session.snapshot(),"ended",46),"source final core sets END46")
 check(Rules.item_count(b.session.snapshot(),2769)==0 and Rules.item_count(b.session.snapshot(),2770)==1,"core consumes crystal and grants2770")
 var saved:Dictionary=b.session.snapshot();execute(b,goddess)
 check(b.session.snapshot()==saved,"completed core cannot reward twice")
 var loaded=Backend.new();check(loaded.load_profile(b.save_path) and loaded.session.snapshot().original_instances==saved.original_instances,"reload preserves original reward UIDs");loaded.free()
 b.save_path=""
 for box in ["05","06"]:
  for id in b.session.snapshot().original_items.duplicate():b.handle({"type":"quest_discard","item_id":id})
  Rules.set_flag(b.session._profile,"now",46,false);Rules.set_flag(b.session._profile,"ended",46,false)
  for i in range(3):grant(b,2766)
  var shell_uid:int=b.session.snapshot().original_instances[0].uid
  check(b.session.equip_item("original:%d"%shell_uid),"shell can be worn in existing amulet slot")
  var npc:=source(b,"jaruga/event/hekisei"+box)
  var pool:PackedStringArray=str(npc.branches[0].actions.GetRandItem).split(",")
  check(pool.size()==36,"water box full36 weighted slots "+box)
  var r:=choose(b,source_talk(b,npc),"yes");before=b.session.snapshot();b.save_path="user://missing-water-parent/fail.json"
  check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"box save failure preserves all shell UIDs")
  b.save_path="";check(execute(b,npc).ok,"box trade without NOW/END46")
  check(b.session.snapshot().original_items.count(2766)==0 and b.session.snapshot().original_items.size()==1 and int(b.session.snapshot().original_equipment.amulet)==0,"bare DelItem consumes all3 shells INCLUDING worn copy and clears UID slot")
  check(str(b.session.snapshot().original_items[0]) in pool,"reward belongs to exact original pool")
  grant(b,2766);check(execute(b,npc).ok and b.session.snapshot().original_items.size()==2,"new shell may trade again, no invented once-only flag")
  while Session.bag_slots(b.session._profile)<15:grant(b,2766)
  before=b.session.snapshot()
  check(execute(b,npc).ok,"full15 bag uses original net-capacity after consuming shells")
  check(b.session.snapshot().original_items.count(2766)==0 and b.session.snapshot().original_items.size()==before.original_items.size()-before.original_items.count(2766)+1,"full15 bag still grants only one box reward and consumes all shell UIDs")

func guards_and_gates():
 var b=setup()
 var gate:=source(b,"genout/wpm_200_73_696")
 source_talk(b,gate);check(b.original_quests.pending.phase=="end","adult source gate cannot be bypassed by level")
 Rules.set_flag(b.session._profile,"ended",4,true)
 check(choose(b,source_talk(b,gate),"yes").ok and b.automation.position_map==21201,"adult source gate enters21201")
 gate=source(b,"genout/wpm_40_13_1");b.session._profile.player.gold=299
 check(not choose(b,source_talk(b,gate),"yes").ok,"lake door refuses299")
 b.session._profile.player.gold=300;var r:=source_talk(b,gate)
 check(choose(b,r,"yes").ok and b.session.snapshot().player.gold==0 and b.automation.position_map==31301,"lake door costs300 and reaches original landing")
 check(not choose(b,r,"yes").ok,"lake door replay refused")
 for suffix in ["mzl","mzn"]:
  var npc:=source(b,"200/sb_"+suffix+".arg");r=source_talk(b,npc)
  check(choose(b,r,"yes").ok and b.battle_open,"water original guard starts")
  check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==npc.branches[0].guard.enemy_ids.map(func(e):return int(e)),"all10 original enemies in order")
  var before:Dictionary=b.session.snapshot();b.save_path="user://missing-water-parent/fail.json"
  var battle_started:int=Clock.ticks_msec();fight(b)
  unit_battle_ms+=Clock.ticks_msec()-battle_started
  check(b.session.snapshot()==before,"guard failed save rolls back")
  b.save_path="";check(b.handle({"type":"battle_close"}).ok,"same guard victory retries")
  var warp:PackedStringArray=str(npc.branches[0].actions.Warp).split(",")
  check(b.automation.position_map==int(warp[0]) and b.automation.position_cell==Vector2i(int(warp[1]),int(warp[2])),"guard source victory target")
 Rules.set_flag(b.session._profile,"now",46,true)
 gate=source(b,"genout/wpm_21308_20_10")
 source_talk(b,gate);check(b.original_quests.pending.phase=="end","sage material door still requires BOTH materials despite synthesis OR")
 for id in [2767,2768]:grant(b,id)
 check(choose(b,source_talk(b,gate),"yes").ok and b.automation.position_cell==Vector2i(20,7),"original material door warp")
 return b
func navigation(b)->void:
 grant(b,2766)
 var box:=source(b,"jaruga/event/hekisei05")
 check(WaterRoute.cave(b,"jaruga/event/hekisei05"),"reuse legitimate final room for stale helper checks")
 var at:Vector2i=b.automation.position_cell
 var old:Dictionary=b.quest_helper.resolve_step(b,46,"water46:box:05")
 check(not old.is_empty(),"current original box branch resolves at legitimate talk range")
 var stale:Dictionary=b.handle({"type":"quest_talk","npc_id":box.id});stale=choose(b,stale,"yes")
 var before:Dictionary=b.session.snapshot()
 b.automation.position_changed(21215,at+Vector2i.DOWN);b.automation.position_changed(21215,at)
 check(not choose(b,stale,"ok").ok and b.session.snapshot()==before,"pending box token rejects same-room project out-and-back")
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","quest_id":46,"step_id":"water46:box:05","mode":mode}).ok,"old cached step rejects lost legitimate arrival "+mode)
  check(not b.handle({"type":"quest_visit","npc_id":box.id,"mode":mode}).ok,"raw NPC rejects same-component project arrival "+mode)
 check(not b.handle({"type":"quest_talk","npc_id":box.id}).ok,"raw NPC transaction rejects project arrival")
 var sage:=source(b,"jaruga/event/hekisei03")
 b.automation.position_changed(21308,Vector2i(20,11))
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":sage.id,"mode":mode}).ok,"raw sage cannot cross original material door "+mode)
func water_lan(b)->void:
 root.add_child(b)
 for id in b.session.snapshot().original_items.duplicate():b.handle({"type":"quest_discard","item_id":id})
 Rules.set_flag(b.session._profile,"ended",46,false);Rules.set_flag(b.session._profile,"now",46,true);grant(b,2769)
 var npc:=source(b,"jaruga/event/hekisei01");source_talk(b,npc);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"water LAN port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two water devices connect")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var a:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":npc.id})
 var c:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":npc.id})
 check(not (await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})).ok,"second water device invalidates old token")
 c=await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"yes"})
 var token:String=c.dialogue.token
 check((await request(links[1],{"type":"quest_choose","token":token,"choice":"ok","GetItem":1})).ok,"water final LAN commit")
 check(Rules.flag(b.session.snapshot(),"ended",46) and b.session.snapshot().original_items==[2770],"forged LAN reward ignored")
 check(not (await request(links[0],{"type":"quest_choose","token":token,"choice":"ok"})).ok,"cross-device final replay rejected")
 for link in links:link.close()
 links=[];server.stop();server.queue_free()
