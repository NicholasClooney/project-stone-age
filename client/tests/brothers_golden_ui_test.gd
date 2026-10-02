extends "res://tests/quest_helper_ui_test.gd"
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
var proof_dir:=""
func proof(name:String) -> void:
 if proof_dir.is_empty():return
 if not check(DisplayServer.get_name()!="headless","Pixel proofs require a real renderer"):return
 await RenderingServer.frame_post_draw
 var pixels:=root.get_texture().get_image()
 if check(not pixels.is_empty(),"Rendered viewport pixels exist"):
  check(pixels.save_png(proof_dir.path_join(name+".png"))==OK,"Saved actual rendered proof "+name)
func visit(id:String) -> bool:
 var answer:=[{}]
 world.link.request({"type":"quest_visit","npc_id":id,"mode":"near"},func(r):answer[0]=r)
 if not await ready(func():return not answer[0].is_empty(),"Remote helper visit reply"):return false
 if not check(answer[0].ok,"Safe source NPC visit"):return false
 if not await ready(func():return int(world.data.map_id)==int(answer[0].target.map_id) and not world.moving,"Real map loaded"):return false
 if not check(await Wait.settle(self,world),"Position and map report settled"):return false
 var index:int=world.world_travel.entries.find(world.world_travel.entries.filter(func(n):return str(n.id)==id)[0])
 var sprite=world.world_travel.sprites[index]
 if not check(sprite.texture!=null,"Original NPC pixels loaded"):return false
 world.world_travel.handle_click(sprite.to_global(sprite.get_rect().get_center()))
 return await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Clicked NPC opens remote original text")
func run() -> void:
 root.unfocusable=true
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var backend=Backend.new();root.add_child(backend)
 backend.session._profile.default_companions_claimed=true
 backend.session.gm_raise_level(-1,80)
 backend.session._profile.no_random_encounters=true
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Ephemeral remote quest server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://brothers-ui.cfg"
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Remote world startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"UI runs with no backend"):return
 if not await visit("giiru/event/ev28_0"):return
 if not check(world.world_travel.body.text.contains("谜底"),"Original request text visible"):return
 await proof("brothers-original-request")
 if not await choose("yes"):return
 if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"now",28),"Real clicked request changed server NOW28"):return
 # Isolated source-complete return fixture. All reward operations below are
 # real server dialogue transactions; the full chain is in the backend suite.
 for e in [4,29,30]:Rules.set_flag(backend.session._profile,"ended",e,true)
 Rules.set_flag(backend.session._profile,"now",54,true)
 Session.OriginalEquipment.add(backend.session._profile,2547)
 Session.OriginalEquipment.add(backend.session._profile,2551)
 backend.publish();await Wait.settle(self,world)
 if not await visit("king/event69_1"):return
 await proof("golden-first-mirror-return")
 if not await choose("yes"):return
 if not check(world.world_travel.body.text.contains("精灵的使者"),"Original reward thanks visible"):return
 await proof("golden-original-reward-dialogue")
 if not await choose("ok"):return
 if not check(world.session.snapshot().pets.size()==1 and world.session.snapshot().pets[0].source_enemy_id==355,"Clicked original final OK grants exact antelope"):return
 world.show_adventure_menu("pets")
 if not await click(world.adventure_menu.panel.get_node("PetRow0")):return
 if not check(world.adventure_menu.pet_view=="detail","Actual click opens reward pet portrait"):return
 await proof("golden-reward-pet")
 world.close_adventure_menu()
 world.show_adventure_menu("inventory")
 var slot=world.adventure_menu.panel.get_node("OriginalItemSlot_0")
 if not await click(slot):return
 if not check(world.adventure_menu.panel.get_node("OriginalItemDescription").text.contains("尚未实现"),"Unavailable equipment effects explicitly visible"):return
 await proof("golden-reward-equipment-limit")
 world.close_adventure_menu()
 # Phone landscape: the actual viewport size changes, then clicks travel and
 # server-owned choices. Screenshots come from this resized rendered viewport.
 root.size=Vector2i(960,540)
 world.quest_helper_menu.open_menu()
 if not await ready(func():return world.quest_helper_menu.size.x>0,"Phone helper layout ready"):return
 var source_row=world.quest_helper_menu.find_child("QuestHelper_17",true,false)
 if source_row==null:
  for row in world.state.derived.quest_helper.quests:
   if int(row.event)==28:source_row=world.quest_helper_menu.find_child("QuestHelper_%d"%int(row.id),true,false)
 if source_row!=null:
  var parent=source_row.get_parent()
  if parent.get_parent() is ScrollContainer:
   var scroll:ScrollContainer=parent.get_parent()
   if not await ready(func():return scroll.get_v_scroll_bar().max_value>scroll.size.y,"Phone helper content laid out"):return
   scroll.ensure_control_visible(source_row)
   if not await ready(func():return scroll.scroll_vertical>0,"Phone original quest scrolled into view"):return
 await proof("phone-quest-helper")
 world.quest_helper_menu.close_menu()
 if not await visit("giiru/event/ev28_5"):return
 await proof("phone-original-answer")
 if not await choose("yes"):return
 if not await choose("ok"):return
 if not check(2507 in world.session.snapshot().original_items,"Phone viewport click exchanges actual correct paper"):return
 # A real 390x844 portrait canvas, not a letterboxed landscape viewport.
 root.content_scale_size=Vector2i.ZERO
 root.size=Vector2i(390,844)
 if not await ready(func():return world.get_viewport_rect().size==Vector2(390,844),"Actual 390x844 portrait viewport"):return
 if not await visit("giiru/event/ev28_6"):return
 var dialogue_panel:Control=world.world_travel.quest_dialogue.panel
 if not check(Rect2(Vector2.ZERO,Vector2(390,844)).encloses(dialogue_panel.get_global_rect()),"Portrait original dialogue fits viewport"):return
 await proof("portrait-390x844-original-options")
 if not await choose("yes"):return
 await proof("portrait-390x844-original-reply")
 if not await choose("ok"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_0")):return
 var description:Label=world.adventure_menu.panel.get_node("OriginalItemDescription")
 if not check(description.text.contains("尚未实现") and Rect2(Vector2.ZERO,Vector2(390,844)).encloses(description.get_global_rect()),"Portrait reward limitation visibly bounded"):return
 await proof("portrait-390x844-reward-limit")
 world.close_adventure_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free()
 await process_frame
 print("BROTHERS GOLDEN UI: %d failures"%failures)
 quit(1 if failures else 0)
