extends "res://tests/yam_axe_ui_test.gd"
var authority

func stage(step:String,job:int)->bool:
 print("UI STAGE: "+step)
 var source_step:Dictionary={}
 for quest in world.state.derived.get("quest_helper",{}).get("quests",[]):
  if int(quest.id)==job:
   for candidate in quest.steps:
    if str(candidate.id)==step:source_step=candidate
 var npc:Dictionary=authority.original_quests.npc_by_id(str(source_step.get("npc_id","")))
 if not npc.is_empty() and int(npc.map_id) in range(20601,20609):
  if not await walk_near(npc):return false
 world.quest_helper_menu.open_menu()
 if not await ready(func():return visit_button(step,"arrival",job)!=null,"Original stage button exists"):return false
 if not await click(visit_button(step,"arrival",job)):return false
 var arrived:bool=await Wait.until(self,func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,180.0)
 if not arrived:
  print("NAV FAILURE: ",world.last_adventure_message," ",world.quest_helper_travel.phase," ",world.travel_router.last_error," map=",world.data.map_id," cell=",world.cell)
  await proof("jan-debug-stage")
 if not check(arrived,"Actual helper click opens "+step):return false
 return check(await Wait.settle(self,world),"Stage map settles")
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var host=Backend.new();authority=host;root.add_child(host)
 host.session._profile.no_random_encounters=true
 host.session.gm_raise_level(-1,80)
 for stat in ["vitality","strength","toughness","dexterity"]:host.session.gm_set_base_stat(-1,stat,10000)
 host.session._profile.player.hp=host.session._profile.player.max_hp
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Jan remote portrait server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://jan-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Jan remote startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Remote client has no backend"):return
 for step in ["jan20:flower","jan20:request","jan20:ornament"]:
  if not await stage(step,27):return
  if not await choose("yes") or not await choose("ok"):return
 world.quest_helper_menu.open_menu()
 world.quest_helper_menu.selected_steps[27]="jan20:meet";world.quest_helper_menu.select_quest(27)
 if not check(world.quest_helper_menu.find_child("QuestVisit_27_jan20_meet_near",true,false)==null,"Jan remains locked before original route"):return
 await proof("jan-01-locked-before-entry")
 world.quest_helper_menu.close_menu()
 world.quest_helper_menu.open_menu()
 if not await click(visit_button("jan20:entrance","arrival",27)):return
 if not await ready(func():return int(world.data.map_id)==200 and not world.quest_helper_travel.active and not world.area_transition_busy,"Real helper click stops at public entrance"):return
 if not check(str(world.quest_helper_travel.target.get("npc_id",""))=="","Public entry never carries an interior NPC target"):return
 await proof("jan-01b-public-entrance")
 if not await portal(200,Vector2i(285,926),20601):return
 for floor_id in range(20601,20604):
  var door:Dictionary={}
  for p in world.world_catalog.links(floor_id).values():
   if int(p.to_map)==floor_id+1:door=p;break
  if not check(not door.is_empty(),"Source next staircase exists"):return
  if not await portal(floor_id,Vector2i(int(door.cell[0]),int(door.cell[1])),floor_id+1):return
 var phrases:=["红色月亮的光芒","蓝色山脉即力量","白色之风即速度"]
 for i in range(3):
  if not await stage("jan20:gate%d"%(i+1),27):return
  var input:LineEdit=world.world_travel.overlay.find_child("GoldenBuiAnswer",true,false)
  if not await click(input):return
  for character in phrases[i]:
   var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0);root.push_input(key,true)
  await proof("jan-02-keyword%d"%(i+1))
  if not await choose("submit"):return
  if not await ready(func():return int(world.data.map_id)==20605+i and not world.area_transition_busy,"Original keyword floor destination"):return
 if not await stage("jan20:battle",27):return
 if not await choose("yes"):return
 if not await ready(func():return world.battle_view.visible and world.battle_view.transition_tiles.is_empty() and not world.battle_view.is_animating(),"Original bandit battle rendered"):return
 if not check(world.battle_view.actors.size()==5,"Three source enemies plus player and pet slot render"):return
 print("JAN ACTOR IDS: ",world.battle_view.actors.map(func(a):return str(a.character_id)))
 if not check([str(world.battle_view.actors[1].character_id),str(world.battle_view.actors[3].character_id),str(world.battle_view.actors[4].character_id)]==["100230","100065","100436"],"All three exact original enemy sprites"):return
 await proof("jan-03-three-original-enemies")
 for turn in range(100):
  var state:Dictionary=host.battle.snapshot()
  if not state.active:break
  var target:=0
  for index in range(state.enemies.size()):
   if int(state.enemies[index].hp)>0:target=index;break
  world.link.request({"type":"battle_command","action":"attack","target":target})
  if not check(await Wait.settle(self,world),"Remote actual attack settles"):return
 world.link.request({"type":"battle_close"})
 if not await ready(func():return not world.battle_view.visible,"Original battle closes"):return
 if not check(await Wait.settle(self,world) and host.automation.position_cell==Vector2i(36,31),"Source victory Warp opens Jan region"):return
 if not await stage("jan20:meet",27):return
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",20),"Actual Jan visit completes20"):return
 if not await stage("jan21:mother",28):return
 await proof("jan-04-original-mother-story")
 if not await choose("yes") or not await choose("ok"):return
 if not await portal(20607,Vector2i(75,13),20608):return
 if not check(world.cell==Vector2i(0,7),"Reviewed active source chooses0,7"):return
 if not await stage("jan21:request",28):return
 if not await choose("yes") or not await choose("ok"):return
 if not await portal(20608,Vector2i(0,7),20607):return
 if not await stage("jan22:reward",29):return
 if not await choose("yes"):return
 await proof("jan-05-original-random-reward")
 if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",22) and not Rules.flag(world.session.snapshot(),"ended",21),"Reward22 precedes delivery21"):return
 if not await portal(20607,Vector2i(75,13),20608):return
 if not await stage("jan21:letter",28):return
 if not await choose("yes") or not await choose("ok"):return
 if not await stage("jan21:deliver",28):return
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",21) and 2489 in world.session.snapshot().original_items,"Clicked final delivery grants flute and END21"):return
 world.quest_helper_menu.open_menu();world.quest_helper_menu.select_quest(29)
 if not check(world.quest_helper_menu.find_child("QuestVisit_29_jan22_reward_near",true,false)==null,"Completed reward cannot shortcut back into cave from village"):return
 await proof("jan-06-completed-helper")
 world.quest_helper_menu.close_menu()
 var rewards:Array=[2489]
 for item_id in world.session.snapshot().original_items:
  if int(item_id) in range(2490,2495):rewards.append(int(item_id))
 for item_id in rewards:
  world.show_adventure_menu("inventory")
  var index:int=world.session.snapshot().original_items.find(item_id)
  if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_%d"%index)):return
  var details:Label=world.adventure_menu.panel.find_child("OriginalEffectsMetadata",true,false)
  if not check(details.text.contains("未生效"),"Unsupported magic/resistance/special effect explicitly labelled"):return
  await proof("jan-07-reward-%d"%item_id)
  if item_id==2489:
   var ordinary:Label=world.adventure_menu.panel.find_child("OriginalEquipmentDetails",true,false)
   if not check(ordinary.text.contains("魅 +2") and not details.text.contains("魅力"),"Flute ordinary charm stays active apart from magic"):return
   if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
   if not check(await Wait.settle(self,world) and int(world.session.snapshot().original_equipment.amulet)>0 and int(host.session.equipment_mods().charm)==2,"Actual remote flute equip applies original charm2"):return
   await proof("jan-08-equipped-flute")
  world.close_adventure_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free()
 await process_frame
 print("JAN CAVE UI: %d failures"%failures)
 quit(1 if failures else 0)
func walk_near(npc:Dictionary)->bool:
 world.quest_helper_menu.close_menu()
 if not check(int(world.data.map_id)==int(npc.map_id),"NPC approach starts on naturally reached floor"):return false
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  var point:Vector2i=target+offset
  if world.cell!=point and world.navigation.get_id_path(world.cell,point).is_empty():continue
  world.walk_to(point)
  if not check(await Wait.until(self,func():return world.cell==point and world.path.is_empty() and not world.moving,180.0),"Actual client walks to original NPC "+str(npc.id)):return false
  return check(await Wait.settle(self,world),"Actual walking position settles before helper action")
 return check(false,"Original geometry contains a reachable talk neighbour")
func portal(map_id:int,cell:Vector2i,to_map:int)->bool:
 if not check(int(world.data.map_id)==map_id,"Portal begins at naturally reached current floor"):return false
 world.walk_to(cell)
 if not check(await Wait.until(self,func():return not world.area_transition_busy and int(world.data.map_id)==to_map,180.0),"Actual walking triggers original portal"):return false
 return check(await Wait.settle(self,world),"Original portal server position settles")
