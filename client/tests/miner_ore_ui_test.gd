extends "res://tests/yam_axe_ui_test.gd"
const Session=preload("res://server/game_session.gd")
var route_backend
func stage(step:String,job:int) -> bool:
 if not check(await Wait.settle(self,world),"Prior mining client activity settles before route setup"):return false
 var entry:Dictionary=route_backend.quest_helper.resolve_step(route_backend,job,step)
 var npc:Dictionary=route_backend.original_quests.npc_by_id(str(entry.get("npc_id","")))
 if int(npc.get("map_id",0)) in range(31801,31807):
  if not check(preload("res://tests/support/legacy_cave_route.gd").approach(route_backend,npc).ok,"mining fixture follows original portals and collision path"):return false
  var cell:Vector2i=route_backend.automation.position_cell
  route_backend._emit({"type":"position","map_id":int(npc.map_id),"cell":[cell.x,cell.y],"client":"route_fixture"})
  if not await ready(func():return int(world.data.map_id)==int(npc.map_id) and world.cell==cell and not world.area_transition_busy,"Remote renders actual mining route endpoint"):return false
  if not check(await Wait.settle(self,world),"Legitimate route report settles before helper click"):return false
 return await super.stage(step,job)
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var backend=Backend.new();root.add_child(backend);route_backend=backend
 backend.quest_catalog.enabled_events=[27]
 backend.session._profile.default_companions_claimed=true
 backend.session._profile.no_random_encounters=true
 backend.session.gm_raise_level(-1,80)
 backend.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(backend.session._profile.player)
 backend.session._profile.player.hp=backend.session._profile.player.max_hp
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"miner portrait server port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://miner-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"miner remote world connects"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"portrait client has no backend"):return
 if not await stage("miner27:request",14):return
 if not await choose("yes") or not await choose("ok"):return
 if not await stage("miner27:permit",14):return
 if not await choose("yes") or not await choose("ok"):return
 if not check(2536 in world.session.snapshot().original_items,"actual clicks earn mining permit"):return
 if not check(await Wait.settle(self,world),"Permit click settles before actual walk to mining point"):return
 if not check(preload("res://tests/support/original_route_driver.gd").walk(backend,31801,Vector2i(37,48),range(31801,31806)).ok,"Actual original route back to first-floor mining cell"):return
 backend._emit({"type":"position","map_id":31801,"cell":[37,48],"client":"route_fixture"})
 if not await ready(func():return int(world.data.map_id)==31801 and world.cell==Vector2i(37,48) and not world.area_transition_busy,"Client renders actual mining position"):return
 if not check(await Wait.settle(self,world),"Mining position report settles before encounter"):return
 backend.encounter_rng.seed=27
 var opened:Dictionary=backend.wild_encounter(31801,Vector2i(37,48))
 if not check(opened.ok,"seed27 production wild encounter passes art gate"):return
 var ore_index:=-1
 for index in range(opened.troop.enemies.size()):
  if int(opened.troop.enemies[index].source_enemy_id)==1043:ore_index=index
 if not check(ore_index>=0 and int(opened.troop.enemies[ore_index].sprite)==100469,"seed27 natural troop contains original ore art100469"):return
 if not await ready(func():return world.battle_view.visible and not world.world_travel.quest_dialogue.active and not world.battle_view.is_animating() and world.battle_view.state.get("active",false),"natural mining battle presented"):return
 if not await click(world.battle_view.find_child("Attack",true,false)):return
 var target_name:="EnemyTarget" if ore_index==0 else "EnemyTarget%d"%(ore_index+1)
 var target=world.battle_view.find_child(target_name,true,false)
 if not check(target!=null and target.is_visible_in_tree(),"original ore has visible clickable target"):return
 await proof("miner-10-natural-ore-selected")
 if not await click(target):return
 if not check(await Wait.settle(self,world),"real ore target click reaches server"):return
 if not await ready(func():return not world.battle_view.is_animating(),"clicked ore attack animation settles"):return
 check(int(backend.battle.snapshot().enemies[ore_index].hp)==0,"real target click defeats original ore")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 print("MINER ORE UI: %d failures"%failures);quit(1 if failures else 0)
