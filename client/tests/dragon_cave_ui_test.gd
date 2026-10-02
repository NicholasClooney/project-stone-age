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
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"dragon portrait server port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://dragon-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"dragon remote world connects"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"portrait client has no backend"):return
 if not await stage("dragon17:flute",26):return
 await proof("dragon-01-original-flute")
 if not await choose("yes") or not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"now",17) and 2505 in world.session.snapshot().original_items,"real guardian click starts17 and gives flute"):return
 # Isolated earned-jade return fixture for UI only; the backend suite wins
 # all three full conditional source troops and settles their original drops.
 for id in [2457,2458,2459]:Session.OriginalEquipment.add(backend.session._profile,id)
 backend.publish();await Wait.settle(self,world)
 if not await stage("dragon17:gate",26):return
 await proof("dragon-02-original-three-jewel-gate")
 if not await choose("yes"):return
 if not await ready(func():return preload("res://server/dragon_cave_helper.gd").inside(backend) and not world.world_travel.quest_dialogue.active,"source gate enters actual reward component"):return
 if not check(await Wait.settle(self,world),"gate save settles"):return
 await proof("dragon-03-through-source-gate")
 if not await stage("dragon17:reward:2",26):return
 if not await choose("yes"):return
 await proof("dragon-04-original-spear-reward")
 if not await choose("ok"):return
 if not check(await Wait.settle(self,world) and Rules.flag(world.session.snapshot(),"ended",17) and 2460 in world.session.snapshot().original_items,"real choice earns source spear and END17"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_0")):return
 await proof("dragon-05-spear-source-effects")
 if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
 if not check(await Wait.settle(self,world) and int(world.session.snapshot().original_equipment.arm)>0,"real spear equip button uses existing ARM slot"):return
 await proof("dragon-06-spear-equipped")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 print("DRAGON CAVE UI: %d failures"%failures);quit(1 if failures else 0)
