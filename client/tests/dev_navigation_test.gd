extends SceneTree
var game
var failures := 0
func _initialize():call_deferred("run")
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
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
 game.walk_to(Vector2i(85,95))
 var route=game.path.duplicate()
 game.held.append("north")
 game.get_window().focus_exited.emit()
 check(game.path==route and not route.is_empty() and game.held.is_empty(),"focus loss keeps click route but releases keyboard")
 for i in range(100):game._physics_process(0.5)
 check(game.cell==Vector2i(85,95),"route finishes after losing focus")
 await click(game.find_child("DevBlinkMode",true,false))
 check(game.dev_blink_mode,"dev toggle enables click blink mode")
 game.dev_go_villager()
 await physics_frame
 await physics_frame
 check(game.cell==Vector2i(92,72) and game.dialogue.visible,"villager shortcut teleports and opens real conversation")
 game.close_dialogue()
 game.dev_go_adventure()
 check(int(game.data.map_id)==100 and game.dev_blink_mode and game.path.is_empty(),"adventure teleports and mode survives map rebuild")
 game.dev_go_adventure()
 check(int(game.data.map_id)==1000,"return shortcut teleports to village")
 game.dev_go_shop()
 await physics_frame
 await physics_frame
 check(int(game.data.map_id)==1002 and game.adventure_menu.visible,"shop shortcut teleports to reachable merchant")
 game.close_adventure_menu()
 # The shop hid this newly built toolbar before its first layout. Wait for
 # the visible frame a user would see before computing the button hit point.
 await process_frame
 game.encounter_rng.seed=0
 await click(game.find_child("DevEncounter",true,false))
 check(game.battle_view.visible and game.battle_session.snapshot().active and int(game.data.map_id)==100,"dev encounter enters regular battle from interior")
 var id=game.battle_session.snapshot().get("battle_id","")
 game.dev_encounter()
 check(game.battle_session.snapshot().get("battle_id","")==id and not id.is_empty(),"dev encounter cannot reset active combat")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop()
 game.music.stream=null;game.effect.stream=null
 game.queue_free()
 await process_frame
 # Let the audio mixer release stopped playbacks before engine shutdown.
 await create_timer(0.5).timeout
 await process_frame
 print("DEV NAVIGATION: %d failures" % failures)
 quit(1 if failures else 0)
