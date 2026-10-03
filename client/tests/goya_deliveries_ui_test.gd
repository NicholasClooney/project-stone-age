extends "res://tests/yam_axe_ui_test.gd"
var route_backend
func stage(step:String,job:int) -> bool:
 if not check(await Wait.settle(self,world),"Prior Goya client activity settles before route setup"):return false
 var entry:Dictionary=route_backend.quest_helper.resolve_step(route_backend,job,step)
 var npc:Dictionary=route_backend.original_quests.npc_by_id(str(entry.get("npc_id","")))
 if int(npc.get("map_id",0)) in range(20401,20407):
  if not check(preload("res://tests/support/legacy_cave_route.gd").approach(route_backend,npc).ok,"Goya fixture follows original portals and collision path"):return false
  var cell:Vector2i=route_backend.automation.position_cell
  route_backend._emit({"type":"position","map_id":int(npc.map_id),"cell":[cell.x,cell.y],"client":"route_fixture"})
  if not await ready(func():return int(world.data.map_id)==int(npc.map_id) and world.cell==cell and not world.area_transition_busy,"Remote renders actual Goya route endpoint"):return false
  if not check(await Wait.settle(self,world),"Legitimate route report settles before helper click"):return false
 return await super.stage(step,job)
func run() -> void:
 root.unfocusable=true
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var backend=Backend.new();root.add_child(backend);route_backend=backend
 backend.quest_catalog.enabled_events=[6,7,8]
 backend.session._profile.default_companions_claimed=true
 backend.session._profile.no_random_encounters=true
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Goya portrait server port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://goya-ui.cfg"
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Goya portrait world connects"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Real remote-only UI"):return
 if not await stage("goya6:request",23):return
 await proof("goya-01-shell-request")
 if not await choose("yes") or not await choose("ok"):return
 if not await stage("goya6:shells",23):return
 if not await choose("yes"):return
 await proof("goya-02-free-shells")
 if not await choose("ok"):return
 if not check(world.session.snapshot().original_items.count(2414)==2,"Actual clicks earned both shells"):return
 if not await stage("goya6:deliver",23):return
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",6) and int(world.session.snapshot().pets[-1].source_enemy_id)==44,"Actual pet reward from two-shell route"):return
 var earned_pet_id:String=str(world.session.snapshot().pets[-1].pet_id)
 world.show_adventure_menu("pets")
 var pets:Array=world.session.snapshot().pets
 var earned_index:int=-1
 for i in range(pets.size()):
  if str(pets[i].pet_id)==earned_pet_id:earned_index=i
 if not check(not earned_pet_id.is_empty() and earned_index>=0,"Reward has a stable carried pet UID"):return
 # Mobile collection reparents native rows into its ScrollContainer. The shared
 # click helper scrolls, waits for actual hover, and sends real mouse events.
 var reward_row:Control=world.adventure_menu.panel.find_child("PetRow%d"%earned_index,true,false)
 if not await click(reward_row):return
 if not check(world.adventure_menu.pet_view=="detail" and str(world.session.snapshot().pets[world.adventure_menu.selected_pet].pet_id)==earned_pet_id,"Clicked portrait belongs to the earned quest pet UID"):return
 await proof("goya-03-original-pet-reward")
 world.close_adventure_menu()
 if not await stage("goya7:request",24):return
 await proof("goya-04-pig-request")
 if not await choose("yes") or not await choose("ok"):return
 if not await stage("goya7:flower",24):return
 if not await choose("yes") or not await choose("ok"):return
 if not await stage("goya7:deliver",24):return
 await proof("goya-05-summit-flower-letter")
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",7),"Clicked flower-letter handoff writes END7"):return
 if not await stage("goya8:request",25):return
 if not await choose("yes") or not await choose("ok"):return
 if not await stage("goya8:deliver",25):return
 if not await choose("yes"):return
 await proof("goya-06-return-reward")
 if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",8) and world.session.snapshot().original_items.count(1206)==1 and world.session.snapshot().original_items.count(2414)==1,"Actual final clicks preserve shell and grant bracelet"):return
 world.show_adventure_menu("inventory")
 var index:int=world.session.snapshot().original_items.find(1206)
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_%d"%index)):return
 var description:Label=world.adventure_menu.panel.find_child("OriginalItemDescription",true,false)
 if not check(description.text.contains("原字段不一致"),"Actual item panel exposes stale original prose"):return
 await proof("goya-07-red-bracelet")
 if not await scroll_details():return
 await proof("goya-07b-visible-original-stat-note")
 if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
 if not check(await Wait.settle(self,world) and int(world.session.snapshot().original_equipment.bracelet)>0,"Actual portrait equip reaches server bracelet slot"):return
 await proof("goya-08-equipped-bracelet")
 world.close_adventure_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free()
 await process_frame
 print("GOYA DELIVERIES UI: %d failures"%failures)
 quit(1 if failures else 0)
