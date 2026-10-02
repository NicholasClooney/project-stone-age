extends "res://tests/yam_axe_ui_test.gd"
const KATAN="seimu/event/event02_1@100:230:180:area:525:200"
func stage(step:String,job:int) -> bool:
 world.quest_helper_menu.open_menu()
 if not await ready(func():return visit_button(step,"near",job)!=null,"Current born source stage exists"):return false
 if not await click(visit_button(step,"near",job)):return false
 if not await ready(func():return not world.quest_helper_travel.active and not world.area_transition_busy,"Real near pointer navigation settles"):return false
 if not check(await Wait.settle(self,world),"Real random-area destination confirmed"):return false
 var sprite:Sprite2D
 for index in range(world.world_travel.entries.size()):
  if str(world.world_travel.entries[index].id)==KATAN:sprite=world.world_travel.sprites[index];break
 if not check(is_instance_valid(sprite),"Server-born NPC rendered at actual random cell"):return false
 var point:Vector2=sprite.get_global_transform_with_canvas()*sprite.get_rect().get_center()
 if not check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(point),"Actual NPC click point visible in phone"):return false
 for pressed in [true,false]:
  var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;root.push_input(move,true)
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point;root.push_input(event,true)
 if not await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Real NPC sprite click opens source dialogue"):return false
 return check(await Wait.settle(self,world),"Original conversation settles over socket")
func run() -> void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var host=Backend.new();root.add_child(host)
 host.session._profile.no_random_encounters=true;host.session._profile.default_companions_claimed=true
 host.session.gm_raise_level(-1,30)
 for key in host.session._profile.inventory:host.session._profile.inventory[key]=0
 for species in [223,224,221,222]:
  if not check(host.session.gm_grant_pet(species) and host.session.level_pet_to(str(host.session._profile.pets[-1].pet_id),25),"Original birth and exact25 growth fixture"):return
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Real phone socket uses port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://katan-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Remote portrait startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Remote UI lacks authority backend"):return
 if not await ready(func():return world.state.derived.get("quest_npcs",{}).has(KATAN),"Actual random birth reaches client"):return
 var born:Dictionary=world.state.derived.quest_npcs[KATAN].duplicate(true)
 if not await stage("katan:request",4):return
 await proof("katan-01-random-born-request")
 if not await choose("yes") or not await choose("ok"):return
 world.quest_helper_menu.open_menu()
 if not await ready(func():return visit_button("katan:first","near",4)!=null,"Helper advances to actual first pair"):return
 await proof("katan-02-first-pair-helper")
 world.quest_helper_menu.close_menu()
 if not await stage("katan:first",4):return
 await proof("katan-03-two-sharks-offer")
 if not await choose("yes") or not await choose("ok"):return
 if not check(world.session.snapshot().pets.size()==2 and world.session.snapshot().original_items==[2607],"Real clicked first pair consumes exactly two and gives source proof"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_0")):return
 await proof("katan-04-original-proof-item")
 world.close_adventure_menu()
 if not await stage("katan:second",4):return
 if not await choose("yes"):return
 await proof("katan-05-source-reward-confirmation")
 if not await choose("ok"):return
 var profile:Dictionary=world.session.snapshot()
 if not check(Rules.flag(profile,"ended",35) and profile.pets.size()==1 and int(profile.pets[0].source_enemy_id)==93 and int(profile.pets[0].level)==1 and not 2607 in profile.original_items,"Real clicked reward is source level1 Xiubao"):return
 if not check(world.state.derived.quest_npcs[KATAN]==born,"Completed chain retains server-born personal position"):return
 world.show_adventure_menu("pets")
 if not await click(world.adventure_menu.panel.find_child("PetRow0",true,false)):return
 await proof("katan-06-original-xiubao-detail")
 world.close_adventure_menu()
 world.quest_helper_menu.open_menu()
 if not await ready(func():return visit_button("katan:second","near",4)!=null,"Completed helper keeps reviewed original step"):return
 await proof("katan-07-completed-helper")
 var scroll:ScrollContainer=world.quest_helper_menu.detail_scroll
 if not await ready(func():
  if scroll.scroll_vertical>=scroll.get_v_scroll_bar().max_value-scroll.get_v_scroll_bar().page-1:return true
  var point:=scroll.get_global_rect().get_center()
  var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;root.push_input(move,true)
  for pressed in [true,false]:
   var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=pressed;event.position=point;event.global_position=point;root.push_input(event,true)
  return false,"Actual pointer wheel reveals original limits and personal-birth policy"):return
 await proof("katan-08-source-and-birth-limits")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free();await process_frame
 print("KATAN UI: %d failures"%failures);quit(1 if failures else 0)
