extends "res://tests/yam_axe_ui_test.gd"
var route_backend
func stage(step:String,job:int)->bool:
 if step.begins_with("saton13:battle"):
  if not check(await Wait.settle(self,world),"Prior Saton activity settles before route fixture"):return false
  var number:=int(step.trim_prefix("saton13:battle"))
  var npc:Dictionary={}
  for actor in route_backend.quest_catalog.active_npcs():
   if str(actor.get("source_script",""))=="100/sb_nusu%d.arg"%number:npc=actor;break
  if not check(not npc.is_empty() and preload("res://tests/support/legacy_cave_route.gd").approach(route_backend,npc).ok,"Actual original route reaches Saton guard"):return false
  var cell:Vector2i=route_backend.automation.position_cell
  route_backend._emit({"type":"position","map_id":int(npc.map_id),"cell":[cell.x,cell.y],"client":"route_fixture"})
  if not await ready(func():return int(world.data.map_id)==int(npc.map_id) and world.cell==cell and not world.area_transition_busy,"Remote renders legitimate Saton endpoint"):return false
  if not check(await Wait.settle(self,world),"Saton route endpoint settles"):return false
 print("UI STAGE: "+step)
 world.quest_helper_menu.open_menu()
 if not await ready(func():return visit_button(step,"arrival",job)!=null,"Original stage button exists"):return false
 if not await click(visit_button(step,"arrival",job)):return false
 var arrived:bool=await Wait.until(self,func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,180.0)
 if not arrived:
  print("NAV FAILURE: ",world.last_adventure_message," ",world.quest_helper_travel.phase," ",world.travel_router.last_error," map=",world.data.map_id," cell=",world.cell)
  await proof("saton-debug-stage")
 if not check(arrived,"Actual helper click opens "+step):return false
 return check(await Wait.settle(self,world),"Stage map settles")
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var host=Backend.new();root.add_child(host);route_backend=host
 host.quest_catalog.enabled_events=[13,14]
 host.session._profile.no_random_encounters=true
 host.session.gm_raise_level(-1,80)
 for stat in ["vitality","strength","toughness","dexterity"]:host.session.gm_set_base_stat(-1,stat,10000)
 host.session._profile.player.hp=host.session._profile.player.max_hp
 var time:=[1000]
 host.original_quests.npc_state.clock=func():return time[0]
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Saton remote portrait server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://saton-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Saton remote startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Remote client has no backend"):return
 if not await stage("saton13:request",10):return
 await proof("saton-01-original-request")
 if not await choose("yes") or not await choose("ok"):return
 for round_index in range(2):
  if not await portal(100,Vector2i(132,421),10701):return
  for i in range(3):
   var guard_id:String="100/sb_nusu%d.arg@%d:%d:%d"%[i+1,[10701,10703,10705][i],[23,6,44][i],[51,63,41][i]]
   if not await stage("saton13:battle%d"%(i+1),10):return
   if not await choose("yes"):return
   if not await ready(func():return world.battle_view.visible and world.battle_view.transition_tiles.is_empty() and not world.battle_view.is_animating(),"Original Saton two-enemy battle rendered"):return
   if not check(world.battle_view.actors.size()==4,"Original guard and pet plus player/stable pet slot"):return
   var expected:Array=[["100405","100327"],["100436","100340"],["100230","100274"]][i]
   if not check([str(world.battle_view.actors[1].character_id),str(world.battle_view.actors[3].character_id)]==expected,"Exact original Saton actor images"):return
   if round_index==0:await proof("saton-02-original-pair%d"%(i+1))
   for turn in range(100):
    var state:Dictionary=host.battle.snapshot()
    if not state.active:break
    var target:=0
    for index in range(state.enemies.size()):
     if int(state.enemies[index].hp)>0:target=index;break
    world.link.request({"type":"battle_command","action":"attack","target":target})
    if not check(await Wait.settle(self,world),"Actual remote battle attack settles"):return
   world.link.request({"type":"battle_close"})
   if not await ready(func():return not world.battle_view.visible and not has_guard(guard_id),"Saved win hides actual remote actor"):return
   if not check(await Wait.settle(self,world) and 2428+i in world.session.snapshot().original_items,"Actual original guaranteed treasure received"):return
   if round_index==0 and i==0:
    await proof("saton-03-guard-hidden")
    time[0]+=300;host.original_quests.refresh_npc_state();host.publish()
    if not check(await Wait.settle(self,world) and not has_guard(guard_id),"Original strict300 remains invisible in GameScene"):return
    time[0]+=1;host.original_quests.refresh_npc_state();host.publish()
    if not await ready(func():return has_guard(guard_id),"301 seconds restores real GameScene actor"):return
    await proof("saton-04-guard-restored")
   if i<2:
    for floor_id in range([10701,10703][i],[10703,10705][i]):
     var door:Dictionary={}
     for p in world.world_catalog.links(floor_id).values():
      if int(p.to_map)==floor_id+1:door=p;break
     if not check(not door.is_empty(),"Original Saton forward staircase exists"):return
     if not await portal(floor_id,Vector2i(int(door.cell[0]),int(door.cell[1])),floor_id+1):return
  if not await stage("saton13:deliver",10):return
  if not await choose("yes") or not await choose("ok"):return
  if not check(Rules.flag(world.session.snapshot(),"ended",13) and Rules.flag(world.session.snapshot(),"ended",14) and world.session.snapshot().original_items.count(2450)==round_index+1,"Actual reward13 and supplemental14, one medicine per full chain"):return
  if round_index==0:
   world.show_adventure_menu("inventory")
   var index:int=world.session.snapshot().original_items.find(2450)
   if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_%d"%index)):return
   var panel=world.adventure_menu.panel
   var description:Label=panel.find_child("OriginalItemDescription",true,false)
   if not check(is_instance_valid(description),"Medicine description exists in inventory scroll content"):return
   if not check(description.text.contains("仅战斗复活道具（战斗→道具）") and not panel.has_node("OriginalItemUse"),"Earned medicine explains battle-only use without a field action"):return
   if not check(description.text.contains("原标示500，实际450～550，封顶最大HP"),"Medicine description states original power, random healing and HP cap"):return
   if not check(description.text.contains("原版行为：活目标或出手前已复活仍消耗"),"Medicine description preserves original ineffective-target consumption"):return
   var metadata:Label=panel.find_child("OriginalEffectsMetadata",true,false)
   if not check(metadata==null or not metadata.text.contains("复活"),"Implemented medicine is not labelled as inactive resurrection"):return
   await proof("saton-05-medicine-battle-use")
   world.close_adventure_menu()
   var restart:="restart:sainasu/event/event13_2@1100:86:99"
   if not await stage(restart,10):return
   await proof("saton-06-clean-confirmation")
   var before:Dictionary=world.session.snapshot()
   if not await choose("no"):return
   if not check(world.session.snapshot()==before,"Actual cancel preserves complete profile"):return
   if not await stage(restart,10):return
   if not await choose("yes") or not await choose("ok"):return
   if not check(not Rules.flag(world.session.snapshot(),"ended",13) and Rules.flag(world.session.snapshot(),"ended",14),"Actual confirmation clears13 and retains14"):return
   if not await stage("saton13:request",10):return
   if not await choose("yes") or not await choose("ok"):return
   time[0]+=301;host.original_quests.refresh_npc_state();host.publish()
   if not check(await Wait.settle(self,world),"Original individual guards recover for authorized repeat"):return
 world.quest_helper_menu.open_menu();world.quest_helper_menu.select_quest(10)
 await proof("saton-07-repeat-completed")
 world.quest_helper_menu.close_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free();await process_frame
 print("SATON CAVE UI: %d failures"%failures);quit(1 if failures else 0)
func has_guard(id:String)->bool:
 return world.world_travel.entries.any(func(entry):return str(entry.get("id",""))==id)
func portal(map_id:int,cell:Vector2i,to_map:int)->bool:
 if not check(await Wait.settle(self,world),"Prior scene activity settles before portal fixture"):return false
 if map_id==100:
  var guard:Dictionary={}
  for npc in route_backend.quest_catalog.active_npcs():
   if str(npc.get("source_script",""))=="100/sb_nusu1.arg":guard=npc;break
  if not check(route_backend.handle({"type":"quest_visit","npc_id":str(guard.id),"mode":"near"}).ok,"Helper reaches public south-island entrance only"):return false
 if not check(preload("res://tests/support/original_route_driver.gd").walk(route_backend,map_id,cell,[100]+range(10701,10706)).ok,"Fixture actually walks to original portal cell"):return false
 route_backend._emit({"type":"position","map_id":map_id,"cell":[cell.x,cell.y],"client":"route_fixture"})
 if not await ready(func():return int(world.data.map_id)==map_id and world.cell==cell and not world.area_transition_busy,"Remote renders reached original portal"):return false
 if not check(await Wait.settle(self,world),"Source portal position settles"):return false
 world.arrival_lock=Vector2i(-1,-1)
 if not check(world.handle_arrival(),"Production original portal trigger"):return false
 if not await ready(func():return not world.area_transition_busy and int(world.data.map_id)==to_map,"Original portal destination loads"):return false
 return check(await Wait.settle(self,world),"Original portal server position settles")
