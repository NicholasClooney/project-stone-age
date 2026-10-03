extends "res://tests/golden_bui_ui_test.gd"
const Fire=preload("res://server/transmigration_fire_helper.gd")
const Jug=preload("res://server/original_jug_shop_service.gd")
var route:Dictionary={}
func source(script:String)->Dictionary:
 for npc in host.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))==script:return npc
 return {}
func outside(map_id:int,cell:Vector2i)->bool:
 # Fixture transport is only to publicly accessible exterior/entrance areas.
 # Every protected gate, original stair and mandatory battle below is traversed.
 if not check(map_id in [200,300,5100],"route fixture restricted to open exterior"):return false
 host.automation.position_changed(map_id,cell,true);host.session.set_location(map_id,cell.x,cell.y)
 host.publish();host._emit({"type":"position","map_id":map_id,"cell":[cell.x,cell.y],"client":"fire-route-exterior-fixture"})
 return await ready(func():return int(world.data.get("map_id",-1))==map_id and world.cell==cell and not world.area_transition_busy,"open exterior arrival") and await Wait.settle(self,world)
func walk(target:Vector2i,portal:Dictionary={})->bool:
 var started:int=Time.get_ticks_msec()
 var map_id:=int(world.data.map_id)
 if world.cell==target and not portal.is_empty():
  for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   if world.is_walkable(target+delta) and not world.world_catalog.links(map_id).has(target+delta):
    if not await walk(target+delta):return false
    break
 var path:Array[Vector2i]=world.travel_router._path_to(target)
 if not check(not path.is_empty(),"natural collision path %d %s -> %s"%[map_id,world.cell,target]):return false
 print("NATURAL WALK ",map_id," ",world.cell," -> ",target," cells=",path.size())
 path.pop_front();Engine.time_scale=8.0
 for point in path:
  world.walk_to(point)
  if point==target and not portal.is_empty():break
  if not await ready(func():return world.cell==point and not world.moving and world.path.is_empty(),"production adjacent walking step"):Engine.time_scale=1.0;return false
 Engine.time_scale=1.0
 if not portal.is_empty():
  if not await ready(func():return int(world.data.map_id)==int(portal.to_map) and world.cell==Vector2i(portal.target[0],portal.target[1]) and not world.moving and not world.area_transition_busy,"actual original portal destination"):return false
  print("NATURAL PORTAL ",map_id," ",target," -> ",portal.to_map," ",portal.target)
 var settled:bool=check(await Wait.settle(self,world),"natural walk report settles")
 print("TIMING fire walk ",map_id," -> ",target,": ",(Time.get_ticks_msec()-started)/1000.0," seconds")
 return settled
func click_source(script:String)->bool:
 var npc:=source(script)
 if not check(not npc.is_empty() and int(world.data.map_id)==int(npc.map_id),"natural route reached NPC floor "+script):return false
 var best:Array[Vector2i]=[]
 for delta in preload("res://scripts/npc_interaction.gd").offsets():
  var point:=Vector2i(npc.cell[0],npc.cell[1])+delta
  var candidate:Array[Vector2i]=world.travel_router._path_to(point)
  if not candidate.is_empty() and (best.is_empty() or candidate.size()<best.size()):best=candidate
 if not check(not best.is_empty(),"source NPC reachable without teleport "+script) or not await walk(best[-1]):return false
 var matches:Array=world.world_travel.entries.filter(func(n):return str(n.get("id",""))==str(npc.id))
 if not check(matches.size()==1,"one original rendered NPC"):return false
 var sprite=world.world_travel.sprites[world.world_travel.entries.find(matches[0])]
 if not check(sprite.texture!=null,"source sprite texture"):return false
 var point:Vector2=sprite.get_global_transform_with_canvas()*sprite.get_rect().get_center()
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point;root.push_input(event,true)
 return await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"real NPC click "+script)
## Ten original enemies can overlap: a rear actor's center may belong to
## another target for every idle animation frame. Click an exposed point on
## the intended real button, without changing actors, z order or hit testing.
func click_enemy(button: Button) -> bool:
 if not check(is_instance_valid(button),"Original enemy target exists"):return false
 var point:=[Vector2.ZERO]
 if not await ready(func():
  if not button.is_visible_in_tree() or button.disabled or button.size.x<=0 or button.size.y<=0:return false
  for y in [0.5,0.05,0.25,0.75,0.95]:
   for x in [0.5,0.05,0.25,0.75,0.95]:
    point[0]=button.get_global_transform_with_canvas()*(button.size*Vector2(x,y))
    var motion:=InputEventMouseMotion.new()
    motion.position=point[0];motion.global_position=point[0]
    root.push_input(motion,true)
    if root.gui_get_hovered_control()==button:return true
  return false,"Mouse hover reaches exposed point of "+str(button.name)):return false
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new()
  event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
  event.position=point[0];event.global_position=point[0]
  root.push_input(event,true)
 return true
func battle(script:String)->bool:
 var started:int=Time.get_ticks_msec()
 if not await click_source(script) or not await choose("yes"):return false
 world.set_battle_speed(8.0)
 if not await ready(func():return world.battle_view.visible and world.battle_view.transition_tiles.is_empty() and not world.battle_view.is_animating(),"original ten-enemy encounter rendered"):return false
 await proof("fire-battle-"+script.get_file().replace(".arg",""))
 for turn in range(100):
  var state:Dictionary=host.battle.snapshot()
  if not state.active:break
  if not await ready(func():return not world.battle_view.is_animating(),"battle ready for click"):return false
  var target:=0
  for i in range(state.enemies.size()):
   if int(state.enemies[i].hp)>0:target=i;break
  if not await click(world.battle_view.commands[0]):return false
  if not await click_enemy(world.battle_view.target_buttons[world.battle_view.enemy_actor(target)]):return false
  if not check(await Wait.settle(self,world),"actual battle mouse attack settles"):return false
  if not await ready(func():return not world.battle_view.is_animating(),"battle animation complete"):return false
 if not check(host.battle.snapshot().get("outcome")=="win","real clicked battle victory"):return false
 if not await ready(func():return world.battle_view.return_button.visible,"victory return button"):return false
 if not await click(world.battle_view.return_button):return false
 var settled:bool=await ready(func():return not world.battle_view.visible and not world.area_transition_busy,"real battle victory warp") and await Wait.settle(self,world)
 print("TIMING fire battle ",script,": ",(Time.get_ticks_msec()-started)/1000.0," seconds")
 return settled
func follow(edges:Array)->bool:
 for edge in edges:
  if not check(int(world.data.map_id)==int(edge.from_map),"route edge current floor"):return false
  if edge.get("gate",false):
   if not str(edge.get("battle","")).is_empty():
    if not await battle(str(edge.source)):return false
   else:
    if not await click_source(str(edge.source)) or not await choose("yes"):return false
    if not await ready(func():return int(world.data.map_id)==int(edge.to_map) and world.cell==Vector2i(edge.target[0],edge.target[1]) and not world.area_transition_busy,"real original gate warp"):return false
  elif not await walk(Vector2i(edge.cell[0],edge.cell[1]),edge):return false
 return true
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR");if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 route=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-fire-route.json"))
 host=Backend.new();root.add_child(host)
 host.session._profile.default_companions_claimed=true;host.session._profile.no_random_encounters=true
 host.session.gm_raise_level(-1,80)
 for stat in ["vitality","strength","toughness","dexterity"]:host.session.gm_set_base_stat(-1,stat,10000)
 host.session._profile.player.hp=host.session._profile.player.max_hp;host.session._profile.player.gold=2300
 for key in host.session._profile.inventory:host.session._profile.inventory[key]=0
 Rules.set_flag(host.session._profile,"ended",4,true)
 host.automation.position_changed(5100,Vector2i(23,31));host.session.set_location(5100,23,31)
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"fire full route port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override="";world.profile_persistence=false;world.viewer_prefs_path="user://fire-route-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"fire remote scene"):return
 if not check(world.backend==null and await Wait.settle(self,world),"fire remote has no backend"):return
 if not await walk(Vector2i(22,31),{"to_map":5106,"target":[16,49]}):return
 if not await click_source(Fire.PREFIX+"sink07"):return
 await proof("fire-01-request")
 if not await choose("yes") or not await choose("ok"):return
 if not await outside(200,Vector2i(420,577)):return
 if not await walk(Vector2i(route.phoenix_entry.cell[0],route.phoenix_entry.cell[1]),route.phoenix_entry):return
 if not await follow(route.phoenix_route):return
 if not await click_source(Fire.PREFIX+"sink01"):return
 await proof("fire-02-phoenix-natural-arrival")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2706 in host.session.snapshot().original_items,"natural feather acquired"):return
 if not await outside(300,Vector2i(388,338)):return
 if not await walk(Vector2i(388,337),{"to_map":30504,"target":[22,19]}):return
 if not await click_source("genout/ss_30504_10_11") or not await choose("buy_one"):return
 if not check(host.session.snapshot().player.gold==1150 and 2708 in host.session.snapshot().original_items,"natural shop entry and real purchase"):return
 # The shop surface exit and elder shore are disconnected public areas.
 # Public shore transport is a fixture; no protected cave arrival is granted.
 if not await walk(Vector2i(22,19),{"to_map":300,"target":[388,337]}):return
 if not await outside(300,Vector2i(407,299)):return
 if not await click_source(Fire.PREFIX+"sink03"):return
 var input:LineEdit=world.world_travel.quest_dialogue.service_controls.answer
 if not await click(input):return
 for character in "很多":
  var event:=InputEventKey.new();event.pressed=true;event.unicode=character.unicode_at(0);root.push_input(event,true)
 await proof("fire-03-water-keyword")
 if not await choose("submit") or not await choose("yes") or not await choose("ok"):return
 # Original surface entrance to30501, then source portals to30502.
 if not await outside(300,Vector2i(383,300)):return
 var entrance:Dictionary={}
 for p in world.world_catalog.links(300).values():
  if int(p.to_map)==30501:entrance=p;break
 if not check(not entrance.is_empty(),"original Banam cave entrance") or not await walk(Vector2i(entrance.cell[0],entrance.cell[1]),entrance):return
 var door:Dictionary={}
 for p in world.world_catalog.links(30501).values():
  if int(p.to_map)==30502:door=p;break
 if not check(not door.is_empty(),"original Banam lower stair") or not await walk(Vector2i(door.cell[0],door.cell[1]),door):return
 if not await click_source("genout/wpm_30502_45_41") or not await choose("yes"):return
 if not await ready(func():return int(world.data.map_id)==30001 and not world.area_transition_busy,"real65+adult gate enters deep red"):return
 if not await click_source(Fire.PREFIX+"sink055a"):return
 await proof("fire-04-original-water-conversion")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2712 in host.session.snapshot().original_items,"full jug changes to exact2712 before dungeon route"):return
 if not await follow(route.fire_route):return
 if not await click_source(Fire.PREFIX+"sink02"):return
 await proof("fire-05-ira-natural-arrival")
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(host.session.snapshot(),"ended",40) and 2707 in host.session.snapshot().original_items,"natural route completes40"):return
 if not await click_source(Fire.PREFIX+"sink06") or not await choose("yes"):return
 await proof("fire-06-water-prize")
 if not await choose("ok"):return
 if not check(not 2712 in host.session.snapshot().original_items and host.session.snapshot().original_items.size()==2,"one pool prize consumes jug after core"):return
 world.show_adventure_menu("inventory")
 var reward_index:int=world.session.snapshot().original_items.find(2707)
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_%d"%reward_index)):return
 await proof("fire-07a-original-fire-feather-stats")
 if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
 if not check(await Wait.settle(self,world) and int(host.session.snapshot().original_equipment.amulet)>0,"real phone equips source fire feather into amulet UID slot"):return
 await proof("fire-07b-equipped-fire-feather");world.close_adventure_menu()
 world.quest_helper_menu.open_menu();world.quest_helper_menu.select_quest(37)
 await proof("fire-07-completed-helper");world.quest_helper_menu.close_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free();await process_frame
 print("TRANSMIGRATION FIRE NATURAL UI: %d failures"%failures);quit(1 if failures else 0)
