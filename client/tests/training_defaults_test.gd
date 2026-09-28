extends SceneTree
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game);await process_frame
 var helper=game.training_helper
 check(helper.speed.selected==3 and helper.multiplier.selected==2 and helper.compact.button_pressed,"fresh controls default to8x playback10x XP compact battle")
 check(helper.hp_floor.value==10 and helper.target_level.value==120 and helper.battle_limit.value==1000,"fresh safety and limits default10percent120level1000battles")
 helper.open_menu()
 check(not helper.running and game.battle_view.playback_speed==1 and game.session.experience_multiplier==1 and game.automation_overrides().is_empty(),"opening defaults does not start automation or change live manual battle multipliers")
 helper.apply_settings();helper.close_menu()
 check(game.battle_view.playback_speed==8 and game.session.experience_multiplier==10,"applying defaults synchronizes runtime multipliers")
 game.load_area_id(1002,Vector2i(11,15));helper=game.training_helper
 check(helper.settings.xp==10 and helper.settings.speed==8.0 and game.automation_overrides().is_empty() and helper.compact.button_pressed and game.battle_view.playback_speed==8,"applied defaults survive map rebuild")
 helper.speed.select(1);helper.multiplier.select(0);helper.compact.button_pressed=false;helper.hp_floor.value=45;helper.target_level.value=75;helper.battle_limit.value=23
 helper.apply_settings()
 var custom:Dictionary=helper.settings.duplicate(true)
 game.load_area_id(1000,Vector2i(85,95));helper=game.training_helper
 check(helper.settings==custom and helper.speed.selected==1 and helper.multiplier.selected==0 and not helper.compact.button_pressed and helper.hp_floor.value==45 and helper.target_level.value==75 and helper.battle_limit.value==23,"custom choices remain unchanged across map rebuild")
 check(game.battle_view.playback_speed==2 and game.session.experience_multiplier==1 and not helper.running,"custom runtime values persist without automatic restart")
 game.music.stop();game.effect.stop();game.queue_free();await process_frame;await create_timer(0.3).timeout
 print("TRAINING DEFAULTS: %d failures"%failures);quit(1 if failures else 0)
