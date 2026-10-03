extends "res://tests/brothers_golden_ui_test.gd"
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var host=Backend.new();root.add_child(host)
 host.session._profile.default_companions_claimed=true;host.session._profile.no_random_encounters=true
 host.session._profile.pets=[];host.session.gm_grant_pet(95)
 var base:Dictionary=host.session._profile.pets[0].duplicate(true)
 base.level=61;host.session._profile.pets=[base]
 base=base.duplicate(true);base.pet_id="pet-102";base.level=60
 host.session._profile.pets.append(base);host.session._profile.next_pet_id=103
 Rules.set_flag(host.session._profile,"ended",4,true);Rules.set_flag(host.session._profile,"ended",42,true)
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-wind-selection.json"))
 # UI fixture reuses source branches at a reachable known village NPC; source
 # map/route fidelity is tested separately with the complete wind import.
 var npc:Dictionary=fixture.npcs[0].duplicate(true)
 npc.map_id=1000;npc.cell=[69,56];npc.id="wind-selection-ui-fixture"
 host.quest_catalog.npcs.append(npc);host.quest_catalog.items.merge(fixture.items)
 host.quest_catalog.enabled_events.append(42)
 host.automation.position_changed(1000,Vector2i(69,57),true)
 host.session.set_location(1000,69,57)
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Selection UI isolated server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://wind-selection-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Selection remote world ready"):return
 if not check(world.backend==null and await Wait.settle(self,world),"Selection UI has no authority"):return
 var d=world.world_travel.quest_dialogue;d.open(npc.id)
 if not await ready(func():return d.active and not d.busy and is_instance_valid(d.service_controls),"Server candidate control ready"):return
 if not check(d.service_controls.confirm.disabled,"Multiple pets has no default choice"):return
 await proof("390-wind-selection-note")
 var button=d.service_controls.get_node("QuestPet_pet-102")
 if not await click(button):return
 if not check(d.service_controls.selected=="pet-102" and not d.service_controls.confirm.disabled,"Actual click chooses Lv60 UID"):return
 await proof("390-wind-selection-chosen")
 if not await click(d.service_controls.confirm):return
 if not await ready(func():return not d.busy and d.buttons.size()==1,"Selected pet confirmation accepted remotely"):return
 await proof("390-wind-selection-thanks")
 if not await click(d.buttons[0]):return
 if not await ready(func():return not d.active,"Final click commits selection"):return
 if not check(host.session.snapshot().pets.size()==1 and int(host.session.snapshot().pets[0].level)==61,"Clicked UID60 consumed,61 retained"):return
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free()
 await process_frame
 print("WIND SELECTION UI: %d failures"%failures)
 quit(1 if failures else 0)
