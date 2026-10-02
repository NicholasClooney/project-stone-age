extends "res://tests/brothers_golden_ui_test.gd"
## Remote projection test on an already imported original NPC. Source dieact0
## and NpcWarp transactions are exercised independently in personal_quest_npcs_test.
func has_resident(id:String)->bool:
 return world.world_travel.entries.any(func(entry):return str(entry.get("id",""))==id)
func run()->void:
 root.unfocusable=true
 var backend=Backend.new();root.add_child(backend)
 backend.session._profile.default_companions_claimed=true
 backend.session._profile.no_random_encounters=true
 backend.session.gm_raise_level(-1,80)
 var now:=[1000];backend.original_quests.npc_state.clock=func():return now[0]
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"remote NPC state server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://personal-npc-ui.cfg";root.add_child(world)
 if not await ready(func():return world.link.online and not world.data.is_empty(),"remote NPC world loaded"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"remote projection has no backend"):return
 var id:="giiru/event/ev28_0"
 if not await visit(id):return
 world.world_travel.quest_dialogue.close()
 await Wait.settle(self,world)
 var original:Dictionary=backend.original_quests.npc_by_id(id)
 var cell:=Vector2i(int(original.cell[0]),int(original.cell[1]))
 var original_count:int=world.world_travel.entries.size()
 if not check(world.navigation.is_point_solid(cell),"visible NPC blocks navigation"):return
 backend.original_quests.npc_state.defeated(id,300);backend.original_quests.refresh_npc_state();backend.publish()
 if not await ready(func():return not has_resident(id),"remote hidden state removes original actor"):return
 if not check(world.world_travel.resident_nodes.size()==original_count-1 and not world.world_travel.blocks(cell),"hidden actor and click target both removed"):return
 var terrain_blocked:bool=int(world.data.blocked[cell.y*int(world.data.width)+cell.x])!=0
 if not check(world.navigation.is_point_solid(cell)==terrain_blocked,"hidden NPC restores original terrain collision"):return
 now[0]=1300;backend._process(0.0);await Wait.settle(self,world)
 if not check(not has_resident(id),"remote remains hidden at strict boundary"):return
 now[0]=1301;backend._process(0.0)
 if not await ready(func():return has_resident(id),"remote expiry recreates original actor"):return
 if not check(world.world_travel.resident_nodes.size()==original_count and world.navigation.is_point_solid(cell),"restoration does not duplicate residents and restores collision"):return
 var target:Vector2i=cell
 for offset in [Vector2i(3,0),Vector2i(-3,0),Vector2i(0,3),Vector2i(0,-3)]:
  if world.is_walkable(cell+offset):target=cell+offset;break
 if not check(target!=cell,"source map has valid relocation test cell"):return
 backend.original_quests.npc_state.moved(id,[[int(original.map_id),target.x,target.y]])
 backend.original_quests.refresh_npc_state();backend.publish()
 if not await ready(func():return world.world_travel.blocks(target),"remote relocation moves authoritative click target"):return
 if not check(not world.world_travel.blocks(cell) and world.world_travel.entries.size()==original_count,"move replaces original resident exactly once"):return
 var index:int=world.world_travel.entries.find(world.world_travel.entries.filter(func(entry):return str(entry.get("id",""))==id)[0])
 if not check(world.world_travel.resident_nodes[index].position==world.project(Vector2(target)),"real actor follows server map cell"):return
 backend.original_quests.npc_state.moved(id,[[4000,53,101]]);backend.original_quests.refresh_npc_state();backend.publish()
 if not await ready(func():return not has_resident(id),"cross-map move removes old-map actor"):return
 if not check(world.world_catalog.residents.filter(func(entry):return str(entry.get("id",""))==id).size()==1,"world catalog holds exactly one moved instance"):return
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 print("PERSONAL QUEST NPCS UI: %d failures"%failures)
 quit(1 if failures else 0)
