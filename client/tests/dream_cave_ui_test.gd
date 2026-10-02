extends "res://tests/yam_axe_ui_test.gd"
const Session=preload("res://server/game_session.gd")
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var backend=Backend.new();root.add_child(backend)
 backend.session._profile.default_companions_claimed=true
 backend.session._profile.no_random_encounters=true
 backend.session.gm_raise_level(-1,80)
 backend.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(backend.session._profile.player)
 backend.session._profile.player.hp=backend.session._profile.player.max_hp
 # Isolated third-round prerequisite fixture; backend suite earns all three rounds.
 for event in [4,32,33]:Rules.set_flag(backend.session._profile,"ended",event,true)
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"dream portrait server port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://dream-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"dream remote world connects"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"portrait client has no backend"):return
 if not await stage("dream34:request",34):return
 await proof("dream-quest-01-third-request")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2603 in world.session.snapshot().original_items and not Rules.flag(world.session.snapshot(),"ended",34),"third request gives light but does not complete34"):return
 # Isolated maze-arrival fixture. Natural timed walking and full original
 # maze traversal are independently verified; no helper bypass is used.
 backend.automation.position_changed(41,Vector2i(34,42))
 backend._emit({"type":"position","map_id":41,"cell":[34,42],"client":"server"});backend.publish()
 if not await ready(func():return int(world.data.map_id)==41 and world.cell==Vector2i(34,42),"remote presents source final-room arrival fixture"):return
 if not await stage("dream34:battle:1",34):return
 if not await choose("yes"):return
 if not await ready(func():return world.battle_view.visible and not world.world_travel.quest_dialogue.active and not world.battle_view.is_animating() and world.battle_view.state.get("active",false),"original ten-enemy battle presented"):return
 if not check(world.battle_session.snapshot().enemies.size()==10,"actual source ten enemies shown"):return
 await proof("dream-quest-02-ten-original-enemies")
 for turn in range(100):
  if not world.battle_session.snapshot().active:break
  if not await ready(func():return not world.battle_view.is_animating(),"dream battle animations settle"):return
  var index:=0
  var enemies:Array=world.battle_session.snapshot().enemies
  for i in range(enemies.size()):
   if int(enemies[i].hp)>0:index=i;break
  if not await click(world.battle_view.find_child("Attack",true,false)):return
  if not await click(world.battle_view.find_child("EnemyTarget" if index==0 else "EnemyTarget%d"%(index+1),true,false)):return
  if not check(await Wait.settle(self,world),"actual target command reaches server"):return
 if not await ready(func():return not world.battle_view.is_animating() and world.battle_view.return_button.is_visible_in_tree(),"dream battle result ready"):return
 if not await click(world.battle_view.return_button):return
 if not await ready(func():return not world.battle_view.visible and int(world.data.map_id)==41,"saved victory enters original reward side"):return
 if not await stage("dream34:reward",34):return
 if not await choose("yes"):return
 await proof("dream-quest-03-third-reward")
 if not await choose("ok"):return
 if not check(await Wait.settle(self,world) and Rules.flag(world.session.snapshot(),"ended",34) and 2604 in world.session.snapshot().original_items,"third actual final click writes END34 and original clothes"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_0")):return
 await proof("dream-quest-04-clothes-unavailable-effects")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 print("DREAM CAVE UI: %d failures"%failures);quit(1 if failures else 0)
