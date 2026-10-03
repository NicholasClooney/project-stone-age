extends "res://tests/brothers_golden_ui_test.gd"
## Full original route using GameScene walking/doors and actual quest commands.
var host
var routes:Dictionary
var timing_started:int=0
var timing_setup:int=0
var timing_ui:int=0
var timing_battle:int=0
func find_npc(script:String)->Dictionary:
 for npc in host.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))==script:return npc
 return {}
func leave_occupied_landing()->bool:
 if world.is_walkable(world.cell):return true
 for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
  var target:Vector2i=world.cell+offset
  if world.can_step(world.cell,target) and not world.world_catalog.links(int(world.data.map_id)).has(target):
   if not world.request_step(target):return false
   return await Wait.until(self,func():return world.cell==target and not world.moving) and await Wait.settle(self,world)
 return false
func walk(point:Vector2i)->bool:
 if world.cell==point:return true
 var path:Array[Vector2i]=world.travel_router._path_to(point)
 if path.is_empty():return false
 path.pop_front()
 for step in path:
  world.walk_to(step)
  if not await Wait.until(self,func():return world.cell==step and not world.moving,90.0):return false
 return await Wait.settle(self,world)
func approach(npc:Dictionary)->bool:
 if int(world.data.map_id)!=int(npc.map_id):return false
 if not await leave_occupied_landing():return false
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  var point:Vector2i=target+offset
  if world.is_walkable(point) and not world.world_catalog.links(int(npc.map_id)).has(point) and not world.travel_router._path_to(point).is_empty():return await walk(point)
 return false
func use(npc:Dictionary,keyword:String="")->bool:
 print("WIND use ",npc.get("id","")," map=",world.data.map_id," cell=",world.cell)
 if not check(await approach(npc),"Natural walk reaches "+str(npc.id)):return false
 var r:Dictionary=host.handle({"type":"quest_talk","npc_id":npc.id})
 if not check(r.ok,"Actual source dialogue "+str(npc.id)):return false
 var phase:String=host.original_quests.pending.get("phase","")
 var choice:String="submit" if phase=="KEYWORD" else "yes"
 r=host.handle({"type":"quest_choose","token":r.dialogue.token,"choice":choice,"text":keyword})
 if r.has("dialogue"):r=host.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"ok"})
 if not check(r.ok,"Original command commits "+str(npc.id)):return false
 if host.battle_open:
  for turn in range(100):
   var state:Dictionary=host.battle.snapshot()
   if not state.active:break
   var target:=0
   for index in range(state.enemies.size()):
    if int(state.enemies[index].hp)>0:target=index;break
   host.handle({"type":"battle_command","action":"attack","target":target})
  if not check(host.handle({"type":"battle_close"}).ok,"Natural required battle settles"):return false
  if not await ready(func():return not world.battle_view.visible,"Battle close releases walking"):return false
 return await Wait.settle(self,world)
func follow(name:String)->bool:
 var started:int=Time.get_ticks_msec()
 for edge in routes[name]:
  print("WIND route ",name," ",edge.from_map," ",edge.cell," -> ",edge.to_map)
  if not check(int(world.data.map_id)==int(edge.from_map),"Route starts on actual prior landing"):return false
  if name=="wind-up" and int(edge.from_map)==11206 and Vector2i(int(edge.cell[0]),int(edge.cell[1]))==Vector2i(3,38) and not 2758 in host.session.snapshot().original_items:
   if not await use(find_npc("sainasu/event/genou_4")):return false
  if edge.has("npc_id"):
   if not await use(host.original_quests.npc_by_id(str(edge.npc_id))):return false
   if str(edge.npc_id).begins_with("genout/wpm_11206_5_42"):
    if not check(not 2758 in host.session.snapshot().original_items,"original return gate consumes bag bracelet"):return false
  else:
   var source:=Vector2i(int(edge.cell[0]),int(edge.cell[1]));var destination:=Vector2i(int(edge.target[0]),int(edge.target[1]))
   # On the guard floor, defeat every still-visible reachable source guard
   # that bars the route; no fake hidden flag or post-battle teleport fixture.
   if int(edge.from_map)==11208 and world.travel_router._path_to(source).is_empty():
    for guardian in host.quest_catalog.active_npcs():
     if str(guardian.get("source_script",""))=="100/sb_kbu.arg" and await approach(guardian):
      if not await use(guardian):return false
   if world.cell==source:
    var off:=Vector2i(-1,-1)
    for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
     if world.is_walkable(source+delta) and not world.world_catalog.links(int(edge.from_map)).has(source+delta):off=source+delta;break
    if off.x<0 or not await walk(off):return false
   if not check(not world.travel_router._path_to(source).is_empty(),"Production path reaches original door "+str(edge.source)):return false
   var path:Array[Vector2i]=world.travel_router._path_to(source)
   path.pop_front()
   for point in path:
    world.walk_to(point)
    if point!=source and not await Wait.until(self,func():return world.cell==point and not world.moving,90.0):return false
   if not check(await Wait.until(self,func():return int(world.data.map_id)==int(edge.to_map) and world.cell==destination and not world.moving and not world.area_transition_busy,90.0),"Original door lands exactly "+str(edge.source)):return false
   if not await Wait.settle(self,world):return false
 print("WIND LEG TIMING ",name," ms=",Time.get_ticks_msec()-started)
 return true
func after_completion()->bool:return true
func run()->void:
 timing_started=Time.get_ticks_msec()
 root.unfocusable=true;Engine.time_scale=20.0
 print("WIND startup")
 routes=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-wind-routes.json"))
 host=Backend.new();root.add_child(host)
 host.session._profile.default_companions_claimed=true;host.session._profile.no_random_encounters=true
 host.session.gm_raise_level(-1,80)
 for stat in ["vitality","strength","toughness","dexterity"]:host.session.gm_set_base_stat(-1,stat,10000)
 host.session._profile.player.hp=host.session._profile.player.max_hp
 Rules.set_flag(host.session._profile,"ended",4,true)
 # Sole starting position fixture is OUTSIDE the first original gate.
 host.automation.position_changed(100,Vector2i(279,325),true);host.session.set_location(100,279,325)
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Natural route isolated server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://wind-route.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Natural wind remote startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Natural route remote authority"):return
 timing_setup=Time.get_ticks_msec()-timing_started
 if not await use(find_npc("genout/wpm_100_278_325")):return
 if not await follow("wind-up"):return
 if not await use(find_npc("sainasu/event/genou_1")):return
 if not check(Rules.flag(host.session.snapshot(),"now",41),"Natural first climb starts41"):return
 if not await follow("wind-down"):return
 if not await use(find_npc("sainasu/event/genou_3")):return
 if not await use(find_npc("genout/wpm_100_443_127"),"在卡坦有梦德"):return
 if not await follow("munde-up"):return
 if not await use(find_npc("sainasu/event/event12")):return
 if not check(Rules.flag(host.session.snapshot(),"ended",41) and 2736 in host.session.snapshot().original_items,"Natural cave raid earns harp41"):return
 if not await follow("munde-down"):return
 if not await use(find_npc("genout/wpm_100_278_325")):return
 if not await follow("wind-up"):return
 if not await use(find_npc("sainasu/event/genou_1")):return
 if not check(Rules.flag(host.session.snapshot(),"ended",42) and 2735 in host.session.snapshot().original_items,"Full natural route completes42 with original wind lock"):return
 if not await after_completion():return
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free()
 await process_frame;Engine.time_scale=1.0
 var total:int=Time.get_ticks_msec()-timing_started
 print("WIND TIMING total_ms=",total," setup_ms=",timing_setup," route_ms=",total-timing_setup-timing_ui-timing_battle," battle_ms=",timing_battle," ui_wait_ms=",timing_ui)
 print("WIND NATURAL ROUTE: %d failures"%failures);quit(1 if failures else 0)
