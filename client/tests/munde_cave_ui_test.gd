extends "res://tests/yam_axe_ui_test.gd"
func stage(step:String,job:int)->bool:
 print("UI STAGE: "+step)
 world.quest_helper_menu.open_menu()
 if not await ready(func():return visit_button(step,"arrival",job)!=null,"Original stage button exists"):return false
 if not await click(visit_button(step,"arrival",job)):return false
 var arrived:bool=await Wait.until(self,func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,180.0 if step=="munde9:gate" else Wait.DEADLINE)
 if not arrived:
  print("NAV FAILURE: ",world.last_adventure_message," ",world.quest_helper_travel.phase," ",world.travel_router.last_error," map=",world.data.map_id," cell=",world.cell)
  await proof("munde-debug-stage")
 if not check(arrived,"Actual helper click opens "+step):return false
 return check(await Wait.settle(self,world),"Stage map settles")
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var host=Backend.new();root.add_child(host)
 host.session._profile.no_random_encounters=true
 host.session.gm_raise_level(-1,80)
 for stat in ["vitality","strength","toughness","dexterity"]:host.session.gm_set_base_stat(-1,stat,10000)
 host.session._profile.player.hp=host.session._profile.player.max_hp
 Rules.set_flag(host.session._profile,"ended",4,true)
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Munde remote portrait server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://munde-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Munde remote startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Remote client has no backend"):return
 for step in ["munde9:request","munde11:request","munde10:request"]:
  if not await stage(step,8):return
  if step=="munde9:request":await proof("munde-01-request")
  if not await choose("yes") or not await choose("ok"):return
 if not await stage("munde9:gate",8):return
 var input:LineEdit=world.world_travel.overlay.find_child("GoldenBuiAnswer",true,false)
 if not await click(input):return
 for character in "在卡坦有梦德":
  var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0);root.push_input(key,true)
 await proof("munde-02-original-keyword")
 if not await choose("submit"):return
 if not await ready(func():return int(world.data.map_id)==11101 and not world.area_transition_busy,"Original keyword enters first floor"):return
 # Each ordinary staircase uses production portal collision and transition.
 for level in range(11101,11107):
  var door:Dictionary={}
  for p in world.world_catalog.links(level).values():
   if int(p.to_map)==level+1:door=p;break
  if not check(not door.is_empty(),"Original next-floor portal exists"):return
  if not check(world.load_area_id(level,Vector2i(int(door.cell[0]),int(door.cell[1]))),"Load original stair cell fixture"):return
  world.arrival_lock=Vector2i(-1,-1)
  if not check(world.handle_arrival(),"Actual original staircase trigger"):return
  if not await ready(func():return not world.area_transition_busy and int(world.data.map_id)==level+1,"Source staircase destination loaded"):return
  if not check(await Wait.settle(self,world),"Staircase position settles"):return
 if not check(not world.world_catalog.links(11107).has(Vector2i(22,41)) and not world.world_catalog.links(11107).has(Vector2i(23,41)),"Both scenic guard bypasses removed"):return
 if not await stage("munde9:battle",8):return
 if not await choose("yes"):return
 if not await ready(func():return world.battle_view.visible and world.battle_view.transition_tiles.is_empty() and not world.battle_view.is_animating(),"Original four-enemy battle rendered"):return
 if not check(world.battle_view.actors.size()==6,"Four original enemies plus player and stable pet slot all have art"):return
 if not check(world.battle_view.actors.map(func(a):return str(a.character_id)).slice(3)==["100439","100279","100282"],"Exact remaining original enemy sprites render without slot collapse"):return
 await proof("munde-03-four-original-enemies")
 for turn in range(100):
  var state:Dictionary=host.battle.snapshot()
  if not state.active:break
  var target:=0
  for index in range(state.enemies.size()):
   if int(state.enemies[index].hp)>0:target=index;break
  world.link.request({"type":"battle_command","action":"attack","target":target})
  if not check(await Wait.settle(self,world),"Remote actual attack settles"):return
 world.link.request({"type":"battle_close"})
 if not await ready(func():return not world.battle_view.visible,"Battle closes after source victory"):return
 if not check(await Wait.settle(self,world) and host.automation.position_cell==Vector2i(23,35),"Server victory Warp beyond guards"):return
 for step in ["munde12:stones","munde11:deliver","munde10:deliver","munde9:deliver"]:
  if not await stage(step,8):return
  if not await choose("yes"):return
  await proof("munde-04-"+step.replace(":","-"))
  if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",9) and 1357 in world.session.snapshot().original_items,"All clicked deliveries complete9 and grant1357"):return
 world.quest_helper_menu.open_menu();world.quest_helper_menu.select_quest(8)
 await proof("munde-05-completed-helper")
 world.quest_helper_menu.close_menu()
 for item_id in [1052,1357]:
  world.show_adventure_menu("inventory")
  var index:int=world.session.snapshot().original_items.find(item_id)
  if not check(index>=0,"Reward inventory contains source item"):return
  if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_%d"%index)):return
  var details:Label=world.adventure_menu.panel.find_child("OriginalEffectsMetadata",true,false)
  if not check(details.text.contains("未生效"),"Unsupported source effects are explicitly labelled"):return
  await proof("munde-06-reward-%d"%item_id)
  if item_id==1357:
   var ordinary:Label=world.adventure_menu.panel.find_child("OriginalEquipmentDetails",true,false)
   if not check(ordinary.text.contains("魅 +5") and not details.text.contains("魅力"),"Existing amulet charm is separate from inactive metadata"):return
   if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
   if not check(await Wait.settle(self,world) and int(world.session.snapshot().original_equipment.amulet)>0,"Actual equip click commits amulet to remote server"):return
   await proof("munde-07-equipped-1357")
  world.close_adventure_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free()
 await process_frame
 print("MUNDE CAVE UI: %d failures"%failures)
 quit(1 if failures else 0)
