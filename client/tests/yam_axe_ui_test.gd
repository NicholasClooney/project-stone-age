extends "res://tests/quest_helper_ui_test.gd"
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
var proof_dir:=""
func proof(name:String) -> void:
 if proof_dir.is_empty():return
 if not check(DisplayServer.get_name()!="headless","Pixel evidence requires real rendering"):return
 await RenderingServer.frame_post_draw
 var pixels:=root.get_texture().get_image()
 if check(pixels.get_size()==Vector2i(390,844),"Exact portrait pixels 390x844"):
  check(pixels.save_png(proof_dir.path_join(name+".png"))==OK,"Portrait screenshot saved")
func scroll_details() -> bool:
 var scroll:ScrollContainer=world.adventure_menu.panel.get_node("OriginalItemDetailsScroll")
 if not check(scroll.get_global_rect().end.x<=390 and scroll.get_global_rect().end.y<=world.adventure_menu.panel.get_node("EquipOriginalItem").get_global_rect().position.y,"Details stay inside frame above equipment button"):return false
 if not await ready(func():return scroll.get_v_scroll_bar().max_value>scroll.size.y,"Original detail scroll is laid out"):return false
 return await ready(func():
  if scroll.scroll_vertical>=scroll.get_v_scroll_bar().max_value-scroll.get_v_scroll_bar().page-1:return true
  var point:=scroll.get_global_rect().get_center()
  var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;root.push_input(move,true)
  for pressed in [true,false]:
   var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=pressed;wheel.position=point;wheel.global_position=point;root.push_input(wheel,true)
  return false,"Actual pointer wheel reveals the entire original item note")
func stage(step:String,job:int) -> bool:
 world.quest_helper_menu.open_menu()
 if not await ready(func():return visit_button(step,"arrival",job)!=null,"Original stage button exists"):return false
 if not await click(visit_button(step,"arrival",job)):return false
 if not await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Actual helper click walks and opens NPC dialogue"):return false
 return check(await Wait.settle(self,world),"Stage map report settles")
func run() -> void:
 root.unfocusable=true
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var backend=Backend.new();root.add_child(backend)
 backend.session._profile.no_random_encounters=true
 backend.session.gm_raise_level(-1,25)
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Portrait test real server on port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://yam-ui.cfg"
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Remote portrait world startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"No client authority backend"):return
 if not await stage("yam3:request",12):return
 await proof("yam-01-original-request")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2416 in world.session.snapshot().original_items,"Clicked original request really grants temporary axe"):return
 if not await stage("yam3:deliver",12):return
 await proof("yam-02-deliver-axe")
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",3),"Clicked delivery writes END3"):return
 if not await stage("yam5:request",13):return
 if not await choose("yes") or not await choose("ok"):return
 if not await stage("yam5:deliver",13):return
 if not await choose("yes"):return
 await proof("yam-03-original-reward")
 if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",5) and 2448 in world.session.snapshot().original_items,"Clicked final OK writes END5 and grants reward"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_0")):return
 var description:Label=world.adventure_menu.panel.find_child("OriginalItemDescription",true,false)
 if not check(description.text.contains("尚无地面拾取"),"Actual inventory describes discard limitation"):return
 await proof("yam-04-reward-details")
 if not await scroll_details():return
 await proof("yam-04b-visible-discard-limit")
 if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
 if not check(await Wait.settle(self,world) and int(world.session.snapshot().original_equipment.arm)>0,"Actual portrait equip button changes server ARM"):return
 await proof("yam-05-equipped-reward")
 world.close_adventure_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free()
 await process_frame
 print("YAM AXE UI: %d failures"%failures)
 quit(1 if failures else 0)
