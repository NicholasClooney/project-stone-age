extends "res://tests/original_fixed_guards_test.gd"
## Real first-stage source fixtures; production spirit chains remain disabled.
var fixture:Dictionary={}
var now:=1000
func setup():
 var b=fresh()
 b.session.snapshot() # initialize authoritative original item UID fields
 if fixture.is_empty():fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-foundation.json"))
 b.quest_catalog.npcs.append_array(fixture.module.npcs.duplicate(true))
 b.quest_catalog.items.merge(fixture.module.items)
 b.quest_catalog.enabled_events.append_array([39,40])
 b.original_quests.npc_state.clock=func():return now
 return b
func source(script:String,index:int=0)->Dictionary:
 var matches:Array=fixture.module.npcs.filter(func(n):return str(n.source_script)==script)
 return matches[index]
func grant(b,id:int)->void:b.session.OriginalEquipment.add(b.session._profile,id)
func submit(b,r:Dictionary,text:String)->Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":"submit","text":text})
func run()->void:
 var plain=Backend.new()
 check(not [39,40,41,42,46].any(func(e):return e in plain.quest_catalog.enabled_events),"foundation does not activate spirit flags")
 check(plain.quest_catalog.active_npcs().all(func(n):return not str(n.id).contains("777/ten.arg")),"32021 import does not spawn spirit king")
 check(plain.session.world_catalog.info(32021).get("dev_only",false),"32021 remains developer-only scenery")
 plain.free()
 keyword_transactions()
 gates()
 fixed_troops()
 await keyword_lan()
 print("TRANSMIGRATION FOUNDATION: %d failures"%failures)
 quit(1 if failures else 0)
func keyword_transactions()->void:
 var b=setup();var npc:=source("giiru/event/sink/sink03")
 b.session._profile.player.base_stats={"vitality":10,"strength":10,"toughness":10,"dexterity":10}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 for pair in [["很多",2709],["一半",2710],["一点点",2711]]:
  b.session._profile.original_items=[];b.session._profile.original_instances=[]
  grant(b,2708)
  var r:=source_talk(b,npc)
  check(r.get("dialogue",{}).get("kind","")=="original_keyword","original water amounts ask for exact spoken keyword")
  var before:Dictionary=b.session.snapshot()
  var wrong:=submit(b,r,"一半 ")
  check(b.session.snapshot()==before,"wrong exact keyword never consumes jug")
  if wrong.has("dialogue"):choose(b,wrong,"ok")
  r=submit(b,source_talk(b,npc),str(pair[0]))
  check(r.ok and b.original_quests.pending.phase=="ACCEPT","source keyword selects correct ACCEPT")
  r=choose(b,r,"yes")
  b.save_path="user://missing-transmigration-parent/fail.json"
  check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"keyword save failure preserves UID and empty jug")
  check(not choose(b,r,"ok").ok,"failed keyword reward token is single-use")
  b.save_path="user://transmigration-keyword.json"
  r=choose(b,submit(b,source_talk(b,npc),str(pair[0])),"yes")
  check(choose(b,r,"ok").ok,"water amount commits through existing real save")
  check(b.session.snapshot().original_items==[int(pair[1])],"exact source water variant received")
  check(not choose(b,r,"ok").ok,"saved water reward cannot replay")
  var loaded=Backend.new();check(loaded.load_profile(b.save_path),"keyword save reload succeeds")
  check(loaded.session.snapshot().original_items==[int(pair[1])],"water variant survives reload")
  loaded.free()
 b.free()
func gates()->void:
 var b=setup();var gate:=source("genout/wpm_100_278_325")
 var r:=source_talk(b,gate)
 check(b.original_quests.pending.phase=="end","level alone cannot bypass END4 entrance")
 Rules.set_flag(b.session._profile,"ended",4,true)
 r=source_talk(b,gate);check(b.original_quests.pending.phase=="FREEWARP","original adult and level gate accepted")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-transmigration-parent/fail.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"gate save failure cannot warp")
 b.save_path="";r=source_talk(b,gate)
 check(choose(b,r,"yes").ok and b.automation.position_map==11201,"source gate target commits")
 gate=source("genout/wpm_40_13_1");b.session._profile.player.gold=299
 r=source_talk(b,gate);before=b.session.snapshot()
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"paid source door refuses insufficient stones")
 b.session._profile.player.gold=300;r=source_talk(b,gate)
 check(choose(b,r,"yes").ok and b.session.snapshot().player.gold==0 and b.automation.position_map==31301,"paid source door charges exact300 once")
 check(not choose(b,r,"yes").ok,"paid door token cannot replay")
 b.free()
func fixed_troops()->void:
 var b=setup()
 for npc in fixture.module.npcs:
  var branch:Dictionary=npc.branches[0]
  if branch.type!="BATTLE":continue
  var r:=source_talk(b,npc)
  check(choose(b,r,"yes").ok and b.battle_open,"actual four-spirit fixed troop opens")
  if not b.battle_open:continue
  check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==branch.guard.enemy_ids.map(func(i):return int(i)),"all ten original enemy ids and order")
  var before:Dictionary=b.session.snapshot();b.save_path="user://missing-transmigration-parent/fail.json"
  fight(b)
  check(b.session.snapshot()==before and b.session._pending.has("quest_guard"),"fixed battle save failure rolls back and retains retry")
  check(not b.original_quests.npc_by_id(npc.id).is_empty(),"failed battle cannot hide guard")
  b.save_path=""
  check(b.handle({"type":"battle_close"}).ok,"fixed battle settlement retries")
  if int(branch.guard.dieact)==0:
   check(b.original_quests.npc_by_id(npc.id).is_empty(),"source no-item guardian gets personal cooldown")
   now+=180;b.original_quests.refresh_npc_state()
   check(b.original_quests.npc_by_id(npc.id).is_empty(),"exact180 seconds remains hidden")
   now+=1;b.original_quests.refresh_npc_state()
   check(not b.original_quests.npc_by_id(npc.id).is_empty(),"more than180 seconds restores guardian")
  else:
   var warp:PackedStringArray=str(branch.actions.Warp).split(",")
   check(b.automation.position_map==int(warp[0]) and b.automation.position_cell==Vector2i(int(warp[1]),int(warp[2])),"source fixed victory target preserved")
  check(not choose(b,r,"yes").ok,"fixed troop token cannot replay")
 b.free()
func keyword_lan()->void:
 var b=setup();root.add_child(b);var npc:=source("giiru/event/sink/sink03");grant(b,2708)
 source_talk(b,npc);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"keyword LAN server port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two keyword devices connect")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var a:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":npc.id})
 var c:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":npc.id})
 check(not (await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"submit","text":"很多"})).ok,"new device invalidates stale keyword input")
 c=await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"submit","text":"一半","GetItem":2709})
 c=await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"yes"})
 var reward_token:String=c.dialogue.token
 check((await request(links[1],{"type":"quest_choose","token":reward_token,"choice":"ok"})).ok,"keyword reward commits over real RPC")
 check(b.session.snapshot().original_items==[2710],"LAN client cannot replace keyword reward")
 check(not (await request(links[0],{"type":"quest_choose","token":reward_token,"choice":"ok"})).ok,"other device cannot replay reward")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
