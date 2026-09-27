extends SceneTree
const Game=preload("res://server/game_session.gd")
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func stripped(profile:Dictionary)->Dictionary:
 var result:=profile.duplicate(true)
 result.erase("gm_modified");result.player.erase("gm_modified")
 for pet in result.pets:pet.erase("gm_modified")
 return result
func _initialize():call_deferred("run")
func run():
 var session=Game.new()
 session.claim_default_companions()
 session.gm_grant_points(7)
 session.gm_set_base_stat(0,"strength",7,true)
 session.gm_set_base_stat(1,"dexterity",3,true)
 session._profile.pets[0].legacy_stat_offset={"max_hp":3,"attack":0,"defence":0,"speed":0}
 var original:=stripped(session.snapshot())
 check(session.gm_clear_modified(0) and not session.snapshot().pets[0].get("gm_modified",false) and session.snapshot().pets[1].gm_modified and session.snapshot().gm_modified,"selected pet clear preserves remaining actor and aggregate flags")
 check(stripped(session.snapshot())==original,"selected clear preserves every nonflag value including legacy correction")
 check(session.gm_clear_modified(-1) and session.snapshot().gm_modified,"player clear retains aggregate while another pet modified")
 check(session.gm_clear_modified(1) and not session.snapshot().gm_modified,"last selected actor clear recomputes aggregate false")
 session.gm_heal(-2)
 original=stripped(session.snapshot())
 check(session.gm_clear_modified() and not session.snapshot().gm_modified and session.snapshot().pets.all(func(p):return not p.get("gm_modified",false)),"all clear covers player and complete real pet collection")
 check(stripped(session.snapshot())==original,"all clear changes no stats HP XP points inventory growth or riding")
 var before:Dictionary=session.snapshot()
 check(not session.gm_clear_modified(999) and session.snapshot()==before,"invalid target rejected without mutation")
 session._pending={"test":true}
 check(not session.gm_clear_modified(-1) and not session.gm_clear_modified() and session.snapshot()==before,"pending battle blocks both reset operations")
 session._pending={}
 var path:="user://gm-flag-reset-test.json"
 # Remove artificial legacy fixture only for normal validated save fixture.
 session._profile.pets[0].erase("legacy_stat_offset")
 check(session.save_game(path),"cleared profile saves")
 var restored=Game.new()
 check(restored.load_game(path) and not restored.snapshot().gm_modified and restored.snapshot().gm_bonus_points==7,"cleared flags and retained bonus points survive reload")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path));DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game);await process_frame
 game.session.gm_grant_points(3)
 var menu=game.dev_gm_menu
 menu.open_menu()
 check(not menu.clear_selected_button.disabled and not menu.clear_all_button.disabled,"both reset buttons available outside battle")
 menu.clear_selected_button.pressed.emit()
 check(not game.session.snapshot().player.get("gm_modified",false) and menu.feedback.text.contains("不代表自然培养"),"selected button clears current actor with explicit provenance explanation")
 game.session._pending={"test":true};menu._refresh_actor()
 check(menu.clear_selected_button.disabled and menu.clear_all_button.disabled,"both buttons disabled for pending settlement")
 game.session._pending={};menu.close_menu()
 game.session.claim_default_companions()
 var pet:Dictionary=game.session.snapshot().pets[0]
 pet.erase("gm_modified")
 pet.legacy_stat_offset={"max_hp":0,"attack":0,"defence":0,"speed":0}
 var pets=game.adventure_menu
 pets.open_menu("pets")
 pets.pet_growth_panel(pet,Vector2.ZERO)
 check(not pets.panel.get_child(-1).text.contains("旧档修正"),"zero legacy offset does not falsely warn modified")
 pet.legacy_stat_offset.attack=1
 pets.pet_growth_panel(pet,Vector2.ZERO)
 check(pets.panel.get_child(-1).text.contains("旧档修正"),"real legacy correction retains warning after flag clear")
 pets.hide()
 game.music.stop();game.effect.stop();game.queue_free();await process_frame;await create_timer(0.3).timeout
 print("GM FLAG RESET: %d failures"%failures);quit(1 if failures else 0)
