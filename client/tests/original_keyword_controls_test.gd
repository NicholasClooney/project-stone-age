extends "res://tests/brothers_golden_ui_test.gd"
func type_phrase(controller,phrase:String)->void:
 var field:LineEdit=controller.service_controls.answer
 field.grab_focus()
 for character in phrase:
  var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0)
  root.push_input(key,true)
 check(field.text==phrase,"actual LineEdit receives original phrase through input events")
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-keyword-gates.json"))
 var npc:Dictionary=fixture.npcs[0]
 var backend=Backend.new();root.add_child(backend)
 backend.quest_catalog.npcs.append_array(fixture.npcs);backend.quest_catalog.enabled_events.append_array([9,20,21,22])
 backend.session._profile.default_companions_claimed=true;backend.session._profile.no_random_encounters=true
 backend.session.gm_raise_level(-1,30)
 backend.session._profile.location={"map_id":100,"x":443,"y":126}
 backend.automation.position_changed(100,Vector2i(443,126))
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"keyword controls remote server"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://keyword-controls.cfg";root.add_child(world)
 if not await ready(func():return world.link.online and not world.data.is_empty(),"keyword remote world loaded"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"keyword UI has no Backend"):return
 var controller=world.world_travel.quest_dialogue
 controller.open(str(npc.id))
 if not await ready(func():return controller.active and not controller.busy,"server keyword prompt shown"):return
 if not check(controller.buttons.map(func(button):return str(button.name))==["QuestChoice_submit","QuestChoice_no"],"actual controls contain submit and cancel instead of yes"):return
 var before:Dictionary=backend.session.snapshot()
 type_phrase(controller,"错误口令")
 if not await click(controller.buttons[0]):return
 if not await ready(func():return not controller.active and world.message.text.contains("有什么事"),"wrong submitted phrase displays original rejection"):return
 if not check(backend.session.snapshot()==before,"wrong input does not change authoritative profile"):return
 controller.open(str(npc.id))
 if not await ready(func():return controller.active and not controller.busy,"cancel prompt ready"):return
 if not await click(controller.buttons[1]):return
 if not await ready(func():return not controller.active,"actual cancel closes original input"):return
 if not check(backend.session.snapshot()==before,"cancel preserves profile and location"):return
 controller.open(str(npc.id))
 if not await ready(func():return controller.active and not controller.busy,"correct phrase prompt ready"):return
 type_phrase(controller,str(npc.branches[0].keyword))
 var submit:Button=controller.buttons[0]
 controller.service_scroll.ensure_control_visible(submit)
 if not await click(submit):return
 if not await ready(func():return int(world.data.map_id)==11101 and not world.moving,"real portrait submit click sends phrase and enters source cave"):return
 if not check(int(backend.session.snapshot().location.map_id)==11101,"clicked phrase uses authoritative original Warp"):return
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 print("ORIGINAL KEYWORD CONTROLS: %d failures"%failures)
 quit(1 if failures else 0)
