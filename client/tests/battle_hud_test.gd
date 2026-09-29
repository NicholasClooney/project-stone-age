extends SceneTree
var game
var failures := 0
func _initialize():call_deferred("run")
func check(ok: bool, message: String):
 print(("PASS: " if ok else "FAIL: ")+message)
 if not ok:failures+=1
func click(control: Control):
 var p=control.get_global_rect().get_center()
 for down in [true,false]:
  var e=InputEventMouseButton.new()
  e.position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down
  root.push_input(e,true)
 await process_frame
func run():
 game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false
 root.add_child(game)
 await process_frame
 await process_frame
 # Critically injured fixture bounds a loss under native guard probabilities.
 game.session._profile.player.hp=1
 # Fix the opponent for HUD/defeat checks; source encounters have dedicated coverage.
 game.switch_area(true,Vector2i(45,45))
 check(game.begin_battle(false,1),"HUD fixture opens a battle")
 var view=game.battle_view
 view._process(view.feedback_until+0.1)
 game.effect.stop()
 view._request_action("attack")
 check(game.effect.playing and game.effect.stream==game.ui_sounds[217],"combat selection plays original menu sound")
 game.set_effects_on(false)
 game.effect.stop()
 view._request_action("attack")
 check(not game.effect.playing,"switching sound effects off suppresses combat menu sounds")
 game.set_effects_on(true)
 var hud=game.classic_hud
 var move=InputEventMouseMotion.new()
 move.position=Vector2(650,790)
 root.push_input(move,true)
 await create_timer(0.3).timeout
 check(hud.taskbar.visible,"bottom menu reveals over battle")
 var turn=game.battle_session.snapshot().turn
 for i in [0,1,2,3]:
  await click(hud.task_buttons[i])
  check(not hud.map_panel.visible and not game.adventure_menu.visible,"field tab stays unavailable in battle")
 await click(hud.task_buttons[6])
 check(game.settings_menu.visible,"system tab opens 设置 during battle")
 view._request_action("defend")
 check(game.battle_session.snapshot().turn==turn,"设置 blocks combat commands")
 await click(hud.task_buttons[6])
 check(not game.settings_menu.visible and game.paused_input,"system toggle closes 设置 without unpausing world")
 # Finish a real losing battle, then let the deferred automatic return run.
 for i in range(60):
  if not game.battle_session.snapshot().active:break
  game.battle_action("defend")
 check(game.battle_session.snapshot().outcome=="defeat","defending until defeated produces a real loss")
 view._process(maxf(0,view.feedback_until-view.elapsed)+0.1)
 await process_frame
 await process_frame
 check(int(game.data.map_id)==1000 and not game.battle_view.visible and not game.paused_input,"defeat automatically returns to village without confirmation")
 game.music.stop();game.effect.stop()
 await create_timer(0.3).timeout
 game.queue_free()
 await process_frame
 await process_frame
 print("BATTLE HUD: %d failures" % failures)
 quit(1 if failures else 0)
