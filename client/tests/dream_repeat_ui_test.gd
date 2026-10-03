extends "res://tests/yam_axe_ui_test.gd"
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var backend=Backend.new();root.add_child(backend)
 backend.session._profile.default_companions_claimed=true
 backend.session._profile.no_random_encounters=true
 backend.session.gm_raise_level(-1,35)
 # UI-only original repeat fixture; source and unlimited transactions have
 # separate Backend tests. No claim of natural maze traversal in this shot.
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"repeat mobile server port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://dream-repeat-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"repeat remote world connects"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"repeat client has no backend"):return
 if not await stage("dream34:repeat-request",34):return
 await proof("dream-repeat-01-free-light")
 if not await choose("yes") or not await choose("ok"):return
 if not check(2603 in world.session.snapshot().original_items,"real free-light click commits"):return
 backend.automation.position_changed(41,Vector2i(34,39))
 backend._emit({"type":"position","map_id":41,"cell":[34,39],"client":"server"});backend.publish()
 if not await ready(func():return int(world.data.map_id)==41 and world.cell==Vector2i(34,39),"repeat reward room fixture displayed"):return
 if not await stage("dream34:repeat-reward",34):return
 if not await choose("yes"):return
 await proof("dream-repeat-02-random-thanks")
 if not await choose("ok"):return
 if not check(await Wait.settle(self,world) and not 2603 in world.session.snapshot().original_items,"actual random reward confirmation consumes one light"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_0")):return
 await proof("dream-repeat-03-one-source-item")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 print("DREAM REPEAT UI: %d failures"%failures);quit(1 if failures else 0)
