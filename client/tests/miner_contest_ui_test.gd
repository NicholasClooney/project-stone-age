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
 await proof("miner-01-request")
 if not await choose("yes") or not await choose("ok"):return
 if not await stage("miner27:permit",14):return
 await proof("miner-02-mining-permit")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2536 in world.session.snapshot().original_items,"actual clicks earn mining permit"):return
 # Isolated ore-return fixture for rendered controls; the backend suite wins
 # the real conditional group508 battle, including failed-save retry.
 Session.OriginalEquipment.add(backend.session._profile,2534);backend.publish();await Wait.settle(self,world)
 if not await stage("miner27:qualify",14):return
 await proof("miner-03-qualification")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2535 in world.session.snapshot().original_items and not 2536 in world.session.snapshot().original_items,"clicked exchange consumes ore and mining permit"):return
 if not await stage("miner27:battle",14):return
 await proof("miner-04-contest-original-rule")
 if not await choose("yes"):return
 if not await ready(func():return world.battle_view.visible,"clicked guard opens battle"):return
 if not await ready(func():return not world.world_travel.quest_dialogue.active and not world.battle_view.is_animating() and world.battle_view.state.get("active",false),"battle fully presented before proof"):return
 await proof("miner-05-real-contest")
 for turn in range(60):
  if not world.battle_session.snapshot().active:break
  if not await ready(func():return not world.battle_view.is_animating(),"battle animation settles"):return
  var attack=world.battle_view.find_child("Attack",true,false)
  if not await click(attack):return
  var target=world.battle_view.find_child("EnemyTarget",true,false)
  if not await click(target):return
  if not check(await Wait.settle(self,world),"clicked attack roundtrip"):return
 if not await ready(func():return not world.battle_view.is_animating() and not world.battle_session.snapshot().active,"contest terminal animation"):return
 if not await ready(func():return world.battle_view.return_button.is_visible_in_tree(),"result return control presented"):return
 await proof("miner-06-won-rights")
 if not await click(world.battle_view.return_button):return
 if not await ready(func():return not world.battle_view.visible,"clicked result returns to mine"):return
 if not check(await Wait.settle(self,world) and 2533 in world.session.snapshot().original_items,"real clicked victory grants rights"):return
 if not await stage("miner27:reward",14):return
 if not await choose("yes"):return
 await proof("miner-07-final-reward")
 if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",27) and 2527 in world.session.snapshot().original_items,"clicked final reward writes END27"):return
 if not await stage("miner27:enter",14):return
 await proof("miner-08-ticket-gate")
 if not await choose("yes"):return
 if not await ready(func():return int(world.data.map_id)==31806,"saved ticket gate loads floor6"):return
 if not check(await Wait.settle(self,world) and not 2527 in world.session.snapshot().original_items,"clicked original gate consumes ticket"):return
 await proof("miner-09-sixth-floor")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 print("MINER CONTEST UI: %d failures"%failures);quit(1 if failures else 0)
