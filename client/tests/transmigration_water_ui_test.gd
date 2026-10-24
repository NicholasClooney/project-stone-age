extends "res://tests/support/water_walking_ui.gd"
func run()->void:
 root.unfocusable=true;root.position=Vector2i(-10000,-10000);root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var backend=Backend.new();host=backend;root.add_child(backend)
 Engine.time_scale=30.0
 var started_at:int=Clock.ticks_msec()
 backend.session._profile.no_random_encounters=true;backend.session._profile.default_companions_claimed=true
 backend.session.gm_raise_level(-1,80)
 backend.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(backend.session._profile.player)
 backend.session._profile.player.hp=backend.session._profile.player.max_hp
 for event in [4,39]:Rules.set_flag(backend.session._profile,"ended",event,true)
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"water portrait server port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://water-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"water remote startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"water client has no authority backend"):return
 if not await stage("water46:request",46):return
 await proof("water-01-original-request")
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"now",46),"actual click accepts water46 with ONLY earth39"):return
 # Materials/combat are explicit fixtures. Actual gates/battles/walking issue
 # authority arrival; discard both materials after the door to exercise OR.
 for id in [2767,2768]:backend.session.OriginalEquipment.add(backend.session._profile,id)
 backend.automation.position_changed(200,Vector2i(74,696))
 backend._emit({"type":"position","map_id":200,"cell":[74,696],"client":"server"});backend.publish()
 if not await ready(func():return int(world.data.map_id)==200 and world.cell==Vector2i(74,696) and not world.area_transition_busy,"public adult approach fixture synchronizes"):return
 var route_start:int=Clock.ticks_msec()
 if not await to_sage():return
 print("WATER TIMING outward_route_ms=",Clock.ticks_msec()-route_start)
 for id in [2767,2768]:backend.handle({"type":"quest_discard","item_id":id})
 backend.publish()
 if not check(await Wait.settle(self,world),"post-door original material discard settles"):return
 if not await stage("water46:crystal",46):return
 await proof("water-02-original-or-synthesis")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2769 in world.session.snapshot().original_items,"real server OR synthesis without materials"):return
 route_start=Clock.ticks_msec()
 if not await return_to_goddess():return
 print("WATER TIMING return_route_ms=",Clock.ticks_msec()-route_start)
 if not await stage("water46:reward",46):return
 if not await choose("yes"):return
 await proof("water-03-water-ring-reward")
 if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",46) and 2770 in world.session.snapshot().original_items,"actual final click gives2770 and END46"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_0")):return
 var ordinary:Label=world.adventure_menu.panel.find_child("OriginalEquipmentDetails",true,false)
 if not check(is_instance_valid(ordinary) and ordinary.text.contains("魅"),"water ring fixed ordinary stats displayed"):return
 await proof("water-04-ring-effect-labels")
 if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
 if not check(await Wait.settle(self,world) and int(world.session.snapshot().original_equipment.amulet)>0,"actual ring equip click commits server UID"):return
 await proof("water-04b-ring-equipped")
 world.close_adventure_menu()
 backend.session.OriginalEquipment.add(backend.session._profile,2766);backend.session.OriginalEquipment.add(backend.session._profile,2766);backend.publish()
 if not await ready(func():return world.session.snapshot().original_items.count(2766)==2,"two shell fixture reaches remote client"):return
 if not await walk_to_npc(original("jaruga/event/hekisei05")):return
 if not await stage("water46:box:05",46):return
 await proof("water-05-original-small-box")
 if not await choose("yes") or not await choose("ok"):return
 if not check(world.session.snapshot().original_items.count(2766)==0 and world.session.snapshot().original_items.size()==2,"actual box click consumes all shells for one reward"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_1")):return
 var effects:Label=world.adventure_menu.panel.find_child("OriginalEffectsMetadata",true,false)
 if not check(is_instance_valid(effects) and effects.text.contains("未生效"),"actual box equipment magic remains explicitly inactive"):return
 await scroll_details()
 await proof("water-06-box-equipment-inactive-magic")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 Engine.time_scale=1.0
 print("WATER TIMING total_ms=",Clock.ticks_msec()-started_at," walking_ms=",walking_ms," battle_ms=",battle_ms," setup_ui_and_gate_ms=",Clock.ticks_msec()-started_at-walking_ms-battle_ms)
 print("TRANSMIGRATION WATER UI: %d failures"%failures);quit(1 if failures else 0)
