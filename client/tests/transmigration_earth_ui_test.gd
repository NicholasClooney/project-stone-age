extends "res://tests/brothers_golden_ui_test.gd"
## Remote390px real clicks after the original route grants arrival authority.
const EarthRoute=preload("res://tests/support/earth_route_driver.gd")
func stage(step:String)->bool:
 world.quest_helper_menu.open_menu()
 if not await click(visit_button(step,"near",36)):return false
 if not await ready(func():return not world.quest_helper_travel.active,"Earth near helper transaction finished"):return false
 if not check(await Wait.settle(self,world),"Near visit position settled"):return false
 var projection:Dictionary={}
 for q in world.state.derived.quest_helper.quests:
  if int(q.event)==39:
   for entry in q.steps:
    if str(entry.id)==step:projection=entry
 if not check(not projection.is_empty(),"Remote stage exposes original NPC identity"):return false
 world.world_travel.quest_dialogue.open(str(projection.npc_id))
 if not check(await Wait.until(self,func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,300.0),"Earth helper click approaches original NPC"):return false
 return check(await Wait.settle(self,world),"Original approach settles")
func run()->void:
 root.unfocusable=true;root.gui_embed_subwindows=true
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var host=Backend.new();root.add_child(host)
 host.save_path="user://earth-ui.json"
 host.session.gm_raise_level(-1,80)
 host.session._profile.no_random_encounters=true
 host.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(host.session._profile.player)
 host.session._profile.player.hp=host.session._profile.player.max_hp
 Rules.set_flag(host.session._profile,"ended",4,true)
 for key in host.session._profile.inventory:host.session._profile.inventory[key]=0
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Earth UI isolated websocket server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://earth-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Earth remote scene ready"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Earth client reads remote authority only"):return
 world.quest_helper_menu.open_menu()
 if not await click(world.quest_helper_menu.find_child("QuestHelper_36",true,false)):return
 await proof("earth-01-helper-stages")
 if not await scroll_end(world.quest_helper_menu.detail_scroll):return
 await proof("earth-01b-helper-project-fix")
 if not await stage("earth39:request"):return
 await proof("earth-02-original-request")
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"now",39) and 2699 in world.session.snapshot().original_items,"Real click accepts39 and necklace"):return
 if not await stage("earth39:diary"):return
 await proof("earth-03-original-diary")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2698 in world.session.snapshot().original_items,"Real click acquires diary"):return
 # Enter at the public gate using the helper's permitted surface approach.
 if not await stage("earth39:entrance:genout/wpm_200_359_671"):return
 if not await choose("yes"):return
 if not await ready(func():return int(world.data.map_id)==21001,"Original gate warp renders"):return
 var gate:Dictionary=EarthRoute.npc(host,"genout/wpm_21003_34_10")
 if not await route_near(host,gate):return
 if not await stage("earth39:judgement"):return
 await proof("earth-route-judgement")
 if not await choose("yes"):return
 for script_name in ["200/sb_dtp.arg","200/sb_dbt.arg"]:
  var guard:Dictionary=EarthRoute.npc(host,script_name)
  if not await route_near(host,guard):return
  if not await stage("earth39:guard9" if script_name.ends_with("dtp.arg") else "earth39:guard14"):return
  await proof("earth-route-"+("guard9" if script_name.ends_with("dtp.arg") else "guard14"))
  if not await choose("yes"):return
  if not await route_battle(host):return
 if not check(host.quest_arrival.has_arrival(host,21015,host.automation.position_cell),"Real dbt victory grants final route"):return
 if not await route_near(host,EarthRoute.npc(host,"jaruga/event/ruri01")):return
 if not await stage("earth39:deliver"):return
 await proof("earth-04-goddess-core")
 if not await choose("yes"):return
 await proof("earth-05-original-core-reply")
 if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",39) and 2701 in world.session.snapshot().original_items,"Remote real clicks complete39"):return
 for bag in [5,6]:
  Session.OriginalEquipment.add(host.session._profile,2700);host.publish()
  if not check(await Wait.settle(self,world),"Feather fixture settles"):return
  if not await route_near(host,EarthRoute.npc(host,"jaruga/event/ruri%02d"%bag)):return
  if bag==5:
   world.quest_helper_menu.open_menu()
   var action:Button=visit_button("earth39:bag5","near",36)
   if not await ready(func():return is_instance_valid(action) and root.get_visible_rect().encloses(action.get_global_rect()),"85-slot summary leaves action visible at390"):return
   await proof("earth-summary-390-bag-actions")
   if not await scroll_end(world.quest_helper_menu.detail_scroll):return
   await proof("earth-summary-390-full-explanation")
  if not await stage("earth39:bag%d"%bag):return
  await proof("earth-06-bag%d-original-choice"%bag)
  if not await choose("yes") or not await choose("ok"):return
  if not check(not 2700 in world.session.snapshot().original_items,"Real bag click consumes feather"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_0")):return
 await proof("earth-07-bond-stats")
 if not await scroll_end(world.adventure_menu.panel.get_node("OriginalItemDetailsScroll")):return
 await proof("earth-07a-bond-effect-labels")
 if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
 if not check(await Wait.settle(self,world) and int(world.session.snapshot().original_equipment.amulet)>0,"Actual click equips original earth bond with fixed ordinary stats"):return
 await proof("earth-07b-bond-equipped")
 if not check(root.get_visible_rect().encloses(world.adventure_menu.panel.get_global_rect()),"390 inventory remains within viewport"):return
 world.close_adventure_menu();world.quest_helper_menu.open_menu()
 if world.quest_helper_menu.detail_open:
  if not await click(world.quest_helper_menu.find_child("QuestHelperBack",true,false)):return
 if not await click(world.quest_helper_menu.find_child("QuestHelper_36",true,false)):return
 await proof("earth-08-completed-helper")
 world.quest_helper_menu.close_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free()
 await process_frame
 for name in ["earth-ui.json","earth-ui.cfg"]:
  for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://"+name+suffix))
 print("TRANSMIGRATION EARTH UI: %d failures"%failures)
 quit(1 if failures else 0)

func scroll_end(scroll:ScrollContainer)->bool:
 await process_frame
 return await ready(func():
  if scroll.scroll_vertical>=scroll.get_v_scroll_bar().max_value-scroll.get_v_scroll_bar().page-1:return true
  var point:=scroll.get_global_rect().get_center()
  var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
  for pressed in [true,false]:
   var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=pressed;wheel.position=point;wheel.global_position=point;root.push_input(wheel,true)
  return false,"Actual pointer wheel reveals complete source note")

func route_near(host,n:Dictionary)->bool:
 world.quest_helper_menu.close_menu()
 var route:Array=EarthRoute.path_to(host,n)
 if not check(not route.is_empty(),"Natural collision path to "+str(n.id)):return false
 var index:=0
 for step in route:
  if not check(host.handle({"type":"report_position","map_id":step.map_id,"cell":step.cell,"client":"earth-ui-route"}).get("ok",false),"Original walk/portal command"):return false
  index+=1
  if index%16==0:await process_frame
 if not await ready(func():return int(world.data.map_id)==int(n.map_id) and not world.moving,"Original route rendered at NPC map"):return false
 return check(await Wait.settle(self,world),"Original route settles before real click")
func route_battle(host)->bool:
 if not await ready(func():return host.battle_open,"Original source battle begins"):return false
 for i in range(100):
  var state:Dictionary=host.battle.snapshot()
  if not state.active:break
  var target:=0
  for index in range(state.enemies.size()):
   if int(state.enemies[index].hp)>0:target=index;break
  if not check(host.handle({"type":"battle_command","action":"attack","target":target}).get("ok",false),"Actual original ten-enemy combat command"):return false
  await process_frame
 if not check(not host.battle.snapshot().active,"Original guard battle finishes"):return false
 if not check(host.handle({"type":"battle_close"}).get("ok",false),"Saved guard victory publishes original Warp"):return false
 return check(await Wait.settle(self,world),"Battle and original Warp settle")
