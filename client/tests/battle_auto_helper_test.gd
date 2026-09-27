extends SceneTree
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game)
 await process_frame
 game.session.grant_starter_pets()
 game.session.select_pet(0)
 var config:Dictionary=game.session.start_battle_config()
 config.enemies=[{"name":"不抓这只","species":"wooli","sprite":100250,"level":10,"hp":1000,"max_hp":1000,"attack":1,"defence":1,"speed":1,"can_capture":true},{"name":"指定目标","species":"wooli","sprite":100250,"level":10,"hp":1000,"max_hp":1000,"attack":1,"defence":1,"speed":1,"can_capture":true}]
 game.open_battle_config(config)
 var helper=game.training_helper;helper.set_process(false)
 helper.start_capture_battle(1)
 check(helper.running and helper.single_battle and helper.capture_target==1,"hunt handoff locks exact target in opt-in single-battle automation")
 check(game.battle_session.capture_assist,"capture guard flag enabled before automatic actions")
 var before:int=game.battle_session.snapshot().turn
 helper.advance()
 check(game.battle_session.snapshot().turn==before,"automatic commands wait for original entry animation")
 for i in range(100):game.battle_view._process(0.2)
 helper.advance()
 var state:Dictionary=game.battle_session.snapshot()
 check(state.selected_target==1 and int(state.enemies[0].hp)==1000,"capture helper acts only on designated target")
 helper.stop_training("test")
 check(not helper.running and not game.battle_session.capture_assist and game.battle_view.visible,"stop clears clone guard and preserves current battle for manual control")
 for i in range(100):game.battle_view._process(0.2)
 helper.open_battle_menu()
 check(helper.visible and helper.start_button.text=="本场自动战斗","manual battles expose unified one-battle settings")
 helper.close_menu()
 check(game.paused_input,"closing battle settings does not unlock world movement")
 game.battle_action("developer_escape")
 for i in range(100):game.battle_view._process(0.2)
 game.return_from_battle()
 game.session=preload("res://server/game_session.gd").new()
 game.session.grant_starter_pets()
 game.battle_session=preload("res://server/battle_session.gd").new()
 game.load_area_id(100,Vector2i(637,493))
 helper=game.training_helper;helper.set_process(false)
 var pet:Dictionary=game.session.snapshot().pets[0]
 check(helper.start_pet_training(str(pet.pet_id),int(pet.level)),"pet-specific training starts from stable identity")
 check(game.session.clone_squad_enabled and helper.settings.speed==8 and helper.settings.xp==10 and helper.settings.compact and helper.settings.level==0,"pet training enables mirrors and requested assists independently of player level")
 helper.advance()
 check(not helper.running and helper.stop_reason=="目标宠物已达到等级目标" and game.session._pending.is_empty(),"pet-level goal stops before rolling another encounter")
 game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free()
 await process_frame;await create_timer(0.2).timeout
 print("BATTLE AUTO HELPER: %d failures"%failures)
 quit(1 if failures else 0)
