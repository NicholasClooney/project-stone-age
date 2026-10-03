extends "res://tests/clear_capture_remote_test.gd"
## Real GameScene and input over local and WebSocket sessions. Headless checks
## interaction/authority, not pixels. Internal setup remains on the test side.
func run()->void:
 root.size=Vector2i(1280,900)
 for remote in [false,true]:await window_flow(remote)
 print("WILD AUTHORITY UI: %d failures"%failures);quit(1 if failures else 0)
func window_flow(remote:bool)->void:
 var b
 var server
 var script=load("res://scripts/game.gd")
 if remote:
  b=Backend.new();b.set_process(false);root.add_child(b)
  b.automation.position_changed(100,Vector2i(637,493))
  server=WsServer.new(b,0,"127.0.0.1");root.add_child(server)
  check(server.start()==OK,"remote UI port zero server")
  script.server_url_override="ws://127.0.0.1:%d"%server.port
 var game=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 game.profile_persistence=false;game.viewer_prefs_path="user://wild-authority-ui-%s.cfg"%remote;root.add_child(game)
 check(await Wait.until(self,func():return not game.data.is_empty() and (game.link.is_local() or game.link.online)) and await Wait.settle(self,game),"local/remote world ready %s"%remote)
 if not remote:b=game.backend
 b.automation.auto_tick=false;b.set_process(false)
 check((game.backend==null)==remote,"remote scene has no Backend reference")
 game.random_encounters=false
 if int(game.data.map_id)!=100:check(game.load_area_id(100,Vector2i(637,493)),"test scene loads ordinary field")
 check(await Wait.settle(self,game) and await Wait.until(self,func():return not game.paused_input and not game.area_transition_busy),"scene initial position synchronizes")
 check(b.automation.position_map==100 and b.automation.position_cell==game.cell,"UI starts at authoritative actual location")
 game.link.request({"type":"set_automation_settings","settings":{"training":{"select_troops":false,"borrow_troops":false},"hunt":{"fast":false,"rate":1,"total":8,"offsets":[2,2,2,2],"level_one":true,"train_after_capture":false}}})
 check(await Wait.settle(self,game),"explicit public settings settled")
 var helper=game.training_helper;helper.open_menu()
 helper.hp_floor.value=23;helper.battle_limit.value=7
 await click(helper.start_button)
 check(await Wait.settle(self,game) and b.automation.running,"actual training button starts authoritative runner")
 check(int(b.session.automation_settings().training.hp)==23 and int(b.session.automation_settings().training.limit)==7,"normal window settings use validated public API")
 await click(helper.stop_button)
 check(await Wait.settle(self,game) and not b.automation.running,"actual stop ends training")
 if b.battle_open:
  b.abandon_battle();b.publish()
  check(await Wait.settle(self,game),"test battle cleanup broadcasts")
  game.battle_view.hide();game.paused_input=false
 helper.close_menu()
 check(await Wait.until(self,func():return not game.paused_input),"training window releases input")
 helper.open_menu();check(int(helper.hp_floor.value)==23 and int(helper.battle_limit.value)==7,"saved training fields survive panel reopen")
 helper.close_menu()
 var menu=game.pet_hunt_menu;menu.open_menu();menu.level_one.button_pressed=true
 check(menu.choose_target(113),"actual field lists original Lv1 target")
 menu.total.value=8
 await click(menu.start_button)
 check(await Wait.settle(self,game) and (b.automation.hunt_running or b.automation.flow_active()),"actual hunt button starts at server location")
 check(b.automation.hunt_map==100 and b.automation.hunt_cell==game.cell,"hunt freezes only authoritative point")
 await click(menu.stop_button)
 check(await Wait.settle(self,game) and not b.automation.hunt_running and not b.automation.flow_active(),"actual hunt stop is still usable")
 menu.close_menu();menu.open_menu()
 check(int(menu.total.value)==8,"normal hunt setting survives reopen")
 menu.close_menu()
 game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop()
 if remote:game.link.close()
 game.queue_free()
 if remote:server.stop();server.queue_free();b.queue_free()
 await process_frame
