extends "res://tests/golden_bui_ui_test.gd"
const Jug=preload("res://server/original_jug_shop_service.gd")
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 host=Backend.new();root.add_child(host)
 host.session._profile.default_companions_claimed=true;host.session._profile.no_random_encounters=true
 host.session._profile.player.gold=2300
 for key in host.session._profile.inventory:host.session._profile.inventory[key]=0
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-jug-shop.json"))
 var shop:Dictionary=fixture.npcs[0]
 # The source picture comes from the actual art importer; no drawn substitute.
 shop.path="quests/npcs/n-"+str(shop.id).to_utf8_buffer().hex_encode()+".png"
 shop.offset=[-15,-75]
 host.quest_catalog.npcs=host.quest_catalog.npcs.filter(func(n):return str(n.id)!=Jug.ID)
 host.quest_catalog.npcs.append(shop);host.quest_catalog.enabled_events.append(40)
 host.automation.position_changed(30504,Vector2i(10,12));host.session.set_location(30504,10,12)
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"jug phone real port0 server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://jug-shop-ui.cfg"
 var catalog=preload("res://scripts/quest_catalog.gd").new()
 catalog.npcs=catalog.npcs.filter(func(n):return str(n.id)!=Jug.ID);catalog.npcs.append(shop);catalog.enabled_events.append(40)
 world.world_catalog.set_quest_catalog(catalog);root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"jug phone remote world"):return
 if not check(world.backend==null and await Wait.settle(self,world),"jug UI remote authority only"):return
 # This public shop fixture already stands adjacent to the original NPC.
 # The inherited DojoRoute.near uses y22 for dojo lobbies, which moved this
 # unrelated shop fixture eleven cells away from its y11 merchant.
 if not check(host.automation.position_cell==Vector2i(10,12) and world.cell==Vector2i(10,12),"Public shop adjacent source position settled"):return
 if not await click_source(Jug.ID):return
 if not bounded():return
 var controls=world.world_travel.quest_dialogue.service_controls
 if not check(controls.buttons[0].text.contains("1150") and controls.buttons[0].size.x<=348,"purchase full price fits service controls"):return
 await proof("jug-01-390-purchase-confirm")
 world.world_travel.quest_dialogue.service_scroll.ensure_control_visible(controls.buttons[0])
 if not await ready(func():
  var scroll:ScrollContainer=world.world_travel.quest_dialogue.service_scroll
  scroll.ensure_control_visible(controls.buttons[0])
  return scroll.get_global_rect().encloses(controls.buttons[0].get_global_rect()),"Purchase button scroll layout settled"):return
 await proof("jug-01b-390-price-button")
 if not await choose("buy_one"):return
 if not check(host.session.snapshot().player.gold==1150 and host.session.snapshot().original_items==[2708],"phone actual click buys one UID jug for1150"):return
 await proof("jug-02-390-purchased")
 if not await click_source(Jug.ID) or not await choose("no"):return
 if not check(host.session.snapshot().player.gold==1150 and host.session.snapshot().original_items==[2708],"phone cancel preserves purchase"):return
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free();await process_frame
 print("ORIGINAL JUG SHOP UI: %d failures"%failures);quit(1 if failures else 0)
