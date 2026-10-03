extends "res://tests/original_fixed_guards_test.gd"
const Shop=preload("res://server/original_jug_shop_service.gd")
var npc:Dictionary={}
func setup():
 var b=fresh()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-jug-shop.json"))
 npc=fixture.npcs[0]
 b.quest_catalog.npcs=b.quest_catalog.npcs.filter(func(n):return str(n.id)!=Shop.ID)
 b.quest_catalog.npcs.append(npc)
 b.quest_catalog.items.merge(fixture.items,true)
 if not 40 in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(40)
 b.session.snapshot()
 b.session._profile.player.gold=5000
 return b
func run()->void:
 transactions()
 rejection()
 await lan()
 print("ORIGINAL JUG SHOP: %d failures"%failures)
 quit(1 if failures else 0)
func transactions()->void:
 var b=setup()
 b.quest_catalog.enabled_events.erase(40)
 check(b.original_quests.npc_by_id(Shop.ID).is_empty(),"disabled fire hides original shop")
 b.quest_catalog.enabled_events.append(40)
 check(not b.original_quests.npc_by_id(Shop.ID).is_empty(),"enabled zero-branch ItemShop visible")
 b.quest_visit_guard=func():return "team"
 b.session._profile.player.gold=1149
 var r:=source_talk(b,npc);var before:Dictionary=b.session.snapshot()
 check(r.ok and not choose(b,r,"buy_one").ok and b.session.snapshot()==before,"1149 insufficient; no invented team restriction")
 b.session._profile.player.gold=1150;r=source_talk(b,npc)
 check(choose(b,r,"buy_one").ok and b.session.snapshot().player.gold==0 and b.session.snapshot().original_items==[2708],"1150 purchases exactly one UID jug")
 check(not choose(b,r,"buy_one").ok,"successful token replay rejected")
 b.session._profile.player.gold=2300;r=source_talk(b,npc);before=b.session.snapshot()
 b.save_path="user://missing-jug-parent/fail.json"
 check(not choose(b,r,"buy_one").ok and b.session.snapshot()==before,"savefail restores full profile including UID counter and money")
 check(not choose(b,r,"buy_one").ok,"failed token single use")
 b.save_path="user://original-jug-shop.json";r=source_talk(b,npc)
 check(choose(b,r,"buy_one").ok,"new token retries failed purchase")
 var saved:Dictionary=b.session.snapshot()
 check(saved.original_instances.size()==2 and saved.original_instances[0].uid!=saved.original_instances[1].uid,"repeat purchase allocates distinct UID")
 var loaded=Backend.new();check(loaded.load_profile(b.save_path),"purchase persisted")
 check(loaded.session.snapshot().original_instances==saved.original_instances and loaded.session.snapshot().player.gold==saved.player.gold,"reload retains money and UID")
 loaded.free();b.save_path=""
 while Session.bag_slots(b.session._profile)<14:Session.OriginalEquipment.add(b.session._profile,2708)
 b.session._profile.player.gold=2300;r=source_talk(b,npc)
 check(choose(b,r,"buy_one").ok and Session.bag_slots(b.session.snapshot())==15,"14 to15 bag purchase")
 r=source_talk(b,npc);before=b.session.snapshot()
 check(not choose(b,r,"buy_one").ok and b.session.snapshot()==before,"full bag purchase atomic rejection")
 b.free()
func rejection()->void:
 var b=setup();var r:=source_talk(b,npc);var before:Dictionary=b.session.snapshot()
 check(choose(b,r,"no").ok and b.session.snapshot()==before,"cancel no mutation")
 r=source_talk(b,npc);b.automation.position_changed(30504,Vector2i(1,1))
 check(not choose(b,r,"buy_one").ok,"walk away invalidates confirmation")
 r=source_talk(b,npc);b.quest_catalog.enabled_events.erase(40)
 check(not choose(b,r,"buy_one").ok,"disable invalidates confirmation")
 b.quest_catalog.enabled_events.append(40)
 check(not Shop.reply(npc,b.session.snapshot(),{"phase":"confirm"},"buy_one","price=0").ok,"text cannot override price")
 for actions in [{"DelStone":"0","GetItem":"2708"},{"DelStone":"1150","GetItem":"2708*2"},{"DelStone":"1150","GetItem":"2708","Warp":"1000,1,1"}]:
  check(not b.original_quests.services.apply(b.original_quests,b,npc,{"ok":true,"close":true,"actions":actions}).ok,"service plan action allowlist")
 var gold_npc:={"kind":"golden_bui_quiz"}
 check(not b.original_quests.services.apply(b.original_quests,b,gold_npc,{"ok":true,"close":true,"actions":{"DelStone":"1150"}}).ok,"GoldenBui cannot charge jug actions")
 b.free()
func lan()->void:
 var b=setup();root.add_child(b);source_talk(b,npc);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"jug LAN port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two jug devices")
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":Shop.ID})
 var token:=str(r.get("dialogue",{}).get("token",""))
 var buy:={"type":"quest_choose","token":token,"choice":"buy_one","price":0,"quantity":99,"item_id":2709}
 check((await request(links[1],buy)).ok,"other device consumes shared token")
 check(not (await request(links[0],buy)).ok,"LAN replay rejected")
 check(b.session.snapshot().original_items==[2708] and b.session.snapshot().player.gold==3850,"client fake fields cannot alter fixed quantity/item/price")
 for link in links:link.close()
 links.clear();server.stop();server.queue_free();b.queue_free()
 await process_frame
