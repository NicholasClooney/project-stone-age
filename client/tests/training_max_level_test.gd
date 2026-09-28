extends SceneTree
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
## A helper set up from the profile's settings, as after starting the game.
func fresh_helper(game):
 var old=game.training_helper
 var helper=preload("res://scripts/training_helper.gd").new()
 helper.configure(game)
 old.get_parent().add_child(helper)
 game.training_helper=helper
 old.queue_free()
 return helper
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game);await process_frame
 var helper=game.training_helper
 helper.open_menu();helper.apply_settings();helper.close_menu()
 check(not game.automation_settings().training.level_explicit and game.automation_settings().training.level==120 and game.automation_overrides().is_empty(),"applying untouched target records automatic default provenance")
 game.session.gm_raise_level(-1,120)
 helper.open_menu()
 check(helper.target_level.value==0 and not helper.running,"reopening after reaching120 defaults to unlimited without starting")
 helper.apply_settings();helper.close_menu()
 game.load_area_id(1002,Vector2i(11,15));helper=game.training_helper
 check(helper.target_level.value==0 and not helper.level_explicit,"automatic unlimited survives map rebuild")
 helper.target_level.value=119;helper.target_level.value=120
 helper.apply_settings()
 game.load_area_id(1000,Vector2i(85,95));helper=game.training_helper;helper.open_menu()
 check(helper.target_level.value==120 and helper.level_explicit,"explicit120 remains120 after rebuild and open")
 helper.close_menu()
 game.link.request({"type":"set_automation_settings","settings":{"training":null}})
 helper=fresh_helper(game)
 check(helper.target_level.value==0,"fresh helper at120 starts with unlimited target")
 helper.target_level.value=80
 helper.open_menu()
 check(helper.target_level.value==80,"manual value chosen before opening is not overwritten")
 helper.close_menu()
 game.link.request({"type":"set_automation_settings","settings":{"training":{"level":120}}})
 helper=fresh_helper(game)
 check(helper.target_level.value==0,"a stored default 120 without a flag stays automatic at cap")
 game.link.request({"type":"set_automation_settings","settings":{"training":{"level":75}}})
 helper=fresh_helper(game)
 check(helper.target_level.value==75 and helper.level_explicit,"a stored custom target without a flag counts as explicit")
 game.music.stop();game.effect.stop();game.queue_free();await process_frame;await create_timer(0.3).timeout
 print("TRAINING MAX LEVEL: %d failures"%failures);quit(1 if failures else 0)
