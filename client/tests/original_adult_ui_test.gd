extends "res://tests/quest_helper_ui_test.gd"
func check(value:bool,message:String) -> bool:
 print(("PASS: " if value else "FAIL: ")+message)
 return super.check(value,message)
func walk_channel(backend,id:String)->bool:
 var npc:Dictionary=backend.original_quests.npc_by_id(id)
 var target:Dictionary=backend.quest_helper.adult_walk_destination(backend,npc)
 if not check(not target.is_empty(),"Original adult geometry target exists"):return false
 var goal:=Vector2i(int(target.cell[0]),int(target.cell[1]))
 var route:Array[Vector2i]=world.travel_router._path_to(goal)
 if not check(not route.is_empty(),"Production router finds original channel path"):return false
 route.pop_front()
 for point in route:
  world.walk_to(point)
  if not await ready(func():return world.cell==point and not world.moving,"Production adjacent channel walking settles"):return false
 return check(await Wait.settle(self,world) and backend.quest_arrival.has_arrival(backend,10204,backend.automation.position_cell),"Actual continuous channel walking preserves arrival")
func run() -> void:
 var backend=preload("res://server/backend.gd").new()
 for key in backend.session._profile.inventory:backend.session._profile.inventory[key]=0
 backend.session.gm_raise_level(-1,30)
 root.add_child(backend)
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
 root.add_child(server)
 if not check(server.start()==OK,"Real ephemeral adult server starts"):return
 var script=load("res://scripts/game.gd")
 script.server_url_override="ws://127.0.0.1:%d" % server.port
 world=load("res://scenes/main.tscn").instantiate()
 script.server_url_override=""
 world.profile_persistence=false
 world.viewer_prefs_path="user://adult-ui.cfg"
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Remote startup connects"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Adult remote viewer has no backend"):return
 world.helper_menu.open_menu()
 if not await click(world.helper_menu.find_child("HelperNoRandomEncounters",true,false)):return
 if not await ready(func():return world.state.derived.get("no_random_encounters",false),"Remote general no-encounter toggle settles"):return
 world.helper_menu.close_menu()
 world.quest_helper_menu.open_menu()
 if not await click(visit_button("adult:request","near",1)):return
 if not await ready(func():return not world.quest_helper_travel.active,"Helper near teleport completes"):return
 if not check(await Wait.settle(self,world),"Adult position settles"):return
 if not check(int(world.data.map_id)==10202,"Helper stays outside original adult gate"):return
 world.walk_to(Vector2i(31,13))
 if not await ready(func():return int(world.data.map_id)==10204 and not world.area_transition_busy and not world.moving,"Production walking enters actual level30 portal"):return
 if not check(await Wait.settle(self,world),"Original gate position reaches authority"):return
 if not await walk_channel(backend,"jaruga/event/event04_1"):return
 world.world_travel.quest_dialogue.open("jaruga/event/event04_1")
 if not await choose("yes"):return
 if not await choose("ok"):return
 if not await walk_channel(backend,"jaruga/event/event04_2"):return
 world.quest_helper_menu.open_menu()
 if not await click(visit_button("adult:jade","arrival",1)):return
 if not await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Arrival route really walks channel to messenger"):return
 if not await choose("yes"):return
 if not check(world.world_travel.body.text.contains("１５个仪玉") and world.session.snapshot().original_items.is_empty(),"Original messenger text before committed reward"):return
 if not await choose("ok"):return
 if not check(world.session.snapshot().original_items.count(2417)==15,"Remote exchange grants fifteen independent jade"):return
 if not await walk_channel(backend,"jaruga/event/event04_1"):return
 world.quest_helper_menu.open_menu()
 if not await click(visit_button("adult:return","near",1)):return
 if not await ready(func():return not world.quest_helper_travel.active,"Return near visit completes"):return
 world.world_travel.quest_dialogue.open("jaruga/event/event04_1")
 if not await choose("yes"):return
 if not await choose("ok"):return
 if not check(world.session.snapshot().original_items==[2418],"Remote original reward commits once"):return
 world.quest_helper_menu.open_menu()
 if not check(world.quest_helper_menu.find_child("QuestHelper_1",true,false).text.ends_with("已完成"),"Remote helper reflects completed event4"):return
 world.quest_helper_menu.close_menu()
 # Real remote start, a genuine random battle settlement, then true stop/disconnect.
 var rules=preload("res://server/original_quests.gd")
 rules.set_flag(backend.session._profile,"ended",4,false)
 rules.set_flag(backend.session._profile,"now",4,false)
 backend.session._profile.original_items=[]
 backend.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(backend.session._profile.player)
 backend.session._profile.player.hp=backend.session._profile.player.max_hp
 backend.encounter_rng.seed=7
 backend.publish()
 if not check(await Wait.settle(self,world),"Remote fresh original task fixture settles"):return
 world.helper_menu.open_menu()
 if not await click(world.helper_menu.find_child("HelperNoRandomEncounters",true,false)):return
 if not await ready(func():return not world.state.derived.get("no_random_encounters",true),"Remote turns original walking encounters back on"):return
 world.helper_menu.close_menu()
 world.quest_helper_menu.open_menu()
 if not await click(world.quest_helper_menu.find_child("QuestHelper_1",true,false)):return
 if not await click(world.quest_helper_menu.find_child("QuestAutoStart_1",true,false)):return
 world.quest_helper_menu.hide()
 world.paused_input=false
 if not await ready(func():return not backend.session._profile.completed_battles.is_empty() and backend.quest_auto.running and backend.quest_auto.phase=="walking","Remote auto walks, settles real battle and continues task"):return
 if not check(world.backend==null,"Automatic battle still controlled by remote server"):return
 world.quest_helper_menu.open_menu()
 if not await click(world.quest_helper_menu.find_child("QuestAutoStop",true,false)):return
 if not await ready(func():return not backend.quest_auto.running and not backend.automation.running,"Remote true stop button cancels owned automation"):return
 if not check(await Wait.settle(self,world),"Remote stop snapshot round trip settles before restart click"):return
 world.quest_helper_menu.close_menu()
 world.quest_helper_menu.open_menu()
 if not await click(world.quest_helper_menu.find_child("QuestHelper_1",true,false)):return
 if not await click(world.quest_helper_menu.find_child("QuestAutoStart_1",true,false)):return
 if not await ready(func():return backend.quest_auto.running,"Remote restarts original task"):return
 world.link.close()
 if not await ready(func():return not backend.quest_auto.running and not backend.automation.running,"Real initiating WebSocket disconnect stops task"):return
 world.process_mode=Node.PROCESS_MODE_DISABLED
 world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 server.stop();server.queue_free();backend.queue_free()
 await process_frame
 print("ORIGINAL ADULT UI: %d failures" % failures)
 quit(1 if failures else 0)
