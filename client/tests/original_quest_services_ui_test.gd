extends "res://tests/golden_bui_ui_test.gd"
## Actual source map, NPC click, service controls, server answer, and warp.
func service_choice(id:String,text:String="")->bool:
 var controller=world.world_travel.quest_dialogue
 if not await ready(func():return controller.active and not controller.busy,"service dialogue ready"):return false
 var control:Button
 for button in controller.buttons:
  if str(button.name)=="QuestChoice_"+id:control=button;break
 if not check(control!=null,"service choice exists"):return false
 var scroll:ScrollContainer=controller.service_scroll
 scroll.ensure_control_visible(control)
 if not await ready(func():return scroll.get_global_rect().encloses(control.get_global_rect()),"service choice fully reachable in portrait scroll"):return false
 if not check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(control.get_global_rect()),"service choice stays inside portrait viewport"):return false
 await proof("390-click-"+id)
 if id=="submit":controller.service_controls.answer.text=text
 if not await click(control):return false
 return await ready(func():return not controller.busy,"remote service choice acknowledged")
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var backend=Backend.new();root.add_child(backend)
 authority=backend;host=backend
 backend.session._profile.default_companions_claimed=true
 backend.session._profile.no_random_encounters=true
 backend.session.gm_raise_level(-1,30)
 # Establish the floor through the original ticket gate, first-floor service
 # and staircase before the remote UI exercises the second-floor controls.
 var route=preload("res://tests/support/golden_bui_route.gd")
 var quiz:Dictionary=backend.original_quests.npc_by_id("genout/quz_801_18_19@801:18:19")
 if not check(route.near(backend,quiz),"Original gate and first-floor service establish floor801 arrival"):return
 var arrived:Vector2i=backend.automation.position_cell
 backend.session.set_location(801,arrived.x,arrived.y)
 backend.original_quests.services.rng.seed=44
 Session.OriginalEquipment.add(backend.session._profile,2752)
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"isolated source UI server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://golden-service-ui.cfg";root.add_child(world)
 if not await ready(func():return world.link.online and not world.data.is_empty(),"remote service world loaded"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"UI uses only remote authority"):return
 if not await click_source("genout/quz_801_18_19@801:18:19"):return
 await proof("390-source-question-start")
 if not await service_choice("yes"):return
 if not check(not 2752 in world.session.snapshot().original_items,"actual yes consumed one source entry ticket"):return
 await proof("390-source-question-controls")
 for index in range(2):
  var state:Dictionary=backend.original_quests.pending.service_state
  if not await service_choice(str(state.get("answer_choice","submit")),str(state.get("answer_text",""))):return
 if not await ready(func():return int(world.data.map_id)==801 and world.cell==Vector2i(18,15) and not world.moving,"successful original answer warps beyond the source guard"):return
 if not check(world.message.text.contains("2 / 2") and not world.world_travel.quest_dialogue.active,"public score survives map replacement"):return
 await proof("390-source-score-after-warp")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path("user://golden-service-ui.cfg"))
 print("ORIGINAL QUEST SERVICES UI: %d failures"%failures)
 quit(1 if failures else 0)
