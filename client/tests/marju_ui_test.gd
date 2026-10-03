extends "res://tests/yam_axe_ui_test.gd"
## Real socket, real portrait renderer, real pointer/scroll events throughout.
const Route=preload("res://tests/support/original_route_driver.gd")
func walk_route(host,map_id:int,cell:Vector2i,maps:Array)->bool:
 world.quest_helper_menu.close_menu()
 var route:Array=Route.path(host,map_id,cell,maps)
 if not check(not route.is_empty(),"Original Marju collision route"):return false
 var index:=0
 for point in route:
  if not check(host.handle({"type":"report_position","map_id":point.map_id,"cell":point.cell}).get("ok",false),"Real maze step or original portal"):return false
  index+=1
  if index%16==0:await process_frame
 host.publish()
 if not await ready(func():return int(world.data.map_id)==map_id and not world.moving,"Original route rendered"):return false
 return check(await Wait.settle(self,world),"Maze route settles")
func stage(step:String,job:int)->bool:
 world.quest_helper_menu.open_menu()
 if not await click(visit_button(step,"near",job)):return false
 if not await ready(func():return not world.quest_helper_travel.active,"Original helper finishes"):return false
 if not check(await Wait.settle(self,world),"Helper position settles"):return false
 var target:Dictionary={}
 for quest in world.state.derived.quest_helper.quests:
  if int(quest.id)==job:
   for entry in quest.steps:
    if str(entry.id)==step:target=entry
 if not check(not target.is_empty(),"Original stage retains source NPC identity"):return false
 world.world_travel.quest_dialogue.open(str(target.npc_id))
 if not await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Actual original dialogue opens"):return false
 return check(await Wait.settle(self,world),"Original dialogue settles")
func run() -> void:
 root.unfocusable=true
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var backend=Backend.new();root.add_child(backend)
 backend.session._profile.no_random_encounters=true
 backend.session.gm_raise_level(-1,50)
 for key in backend.session._profile.inventory:backend.session._profile.inventory[key]=0
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Portrait real server on port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://marju-ui.cfg"
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Remote portrait startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Remote UI has no backend"):return
 if not await stage("marju:request",5):return
 await proof("marju-01-original-mail-request")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2687 in world.session.snapshot().original_items,"Clicked request grants actual letter"):return
 if not await stage("marju:gate",5):return
 await proof("marju-02-original-level-gate")
 if not await choose("yes"):return
 if world.world_travel.quest_dialogue.active:
  if not await choose("ok"):return
 if not await ready(func():return backend.automation.position_map==122,"Clicked original gate enters maze122"):return
 if not await walk_route(backend,119,Vector2i(97,89),[122,118,119]):return
 if not await stage("marju:deliver",5):return
 await proof("marju-03-original-recipient")
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",37) and not Rules.flag(world.session.snapshot(),"ended",38),"Clicked delivery only writes37"):return
 if not await walk_route(backend,119,Vector2i(103,93),[119]):return
 if not check(backend.handle({"type":"report_position","map_id":121,"cell":[17,15]}).get("ok",false),"Real original one-way exit before return"):return
 if not check(await Wait.settle(self,world),"Exit settles"):return
 if not await stage("marju:return",9):return
 if not await choose("yes"):return
 await proof("marju-04-original-return-reward")
 if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",38),"Clicked final return writes38"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_1")):return
 var description:Label=world.adventure_menu.panel.find_child("OriginalEffectsMetadata",true,false)
 if not check(is_instance_valid(description) and description.text.contains("未生效"),"Actual reward detail exposes magic limitation"):return
 await proof("marju-05-reward-details")
 if not await scroll_details():return
 await proof("marju-06-visible-magic-tag")
 if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
 if not check(await Wait.settle(self,world) and int(world.session.snapshot().original_equipment.arm)>0,"Actual equip click equips source weapon"):return
 await proof("marju-07-equipped-source-weapon")
 world.close_adventure_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free()
 await process_frame
 print("MARJU UI: %d failures"%failures)
 quit(1 if failures else 0)
