extends SceneTree
const Battle = preload("res://server/battle_session.gd")
var failures := 0
var views: Array = []
var sounds: Array = [[],[]]
func _initialize(): call_deferred("run")
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func advance(view, seconds: float):
 var frames := roundi(seconds*60.0)
 for i in range(frames):view._process(1.0/60.0)
func run():
 var authority=Battle.new()
 var initial=authority.start_battle({"player_hp":200,"player_max_hp":200,"player_attack":5,"player_speed":20,"enemies":[{"name":"乌力","species":"wooli","sprite":100250,"hp":200,"max_hp":200,"attack":3,"speed":1,"defence":1}],"capture_slots":3})
 for i in range(2):
  var view=load("res://scripts/battle_view.gd").new()
  root.add_child(view)
  view.set_process(false)
  view.sound_requested.connect(func(ident):sounds[i].append(ident))
  views.append(view)
  view.open_battle(initial)
 var original_time_scale:=Engine.time_scale
 for speed in [1.0,2.0,4.0,8.0]:
  for view in views:view.open_battle(initial)
  views[0].playback_speed=1.0
  views[1].playback_speed=speed
  advance(views[0],4.0)
  advance(views[1],4.0/speed)
  check(is_equal_approx(views[0].elapsed,views[1].elapsed),"%.0fx entry follows same presentation timeline"%speed)
  check(views[0].actors[0].point.is_equal_approx(views[1].actors[0].point),"%.0fx actor entry reaches same original formation"%speed)
  check(views[0].command_panel.position.is_equal_approx(views[1].command_panel.position),"%.0fx menu slides share actor clock"%speed)
  check(not views[1].is_animating(),"%.0fx battle entry unlocks commands"%speed)
 # Supply identical authoritative turn once; presentation must never reroll it.
 var result=authority.submit_action("attack",0)
 sounds=[[],[]]
 for view in views:
  view.pending_action="attack"
  view.show_state(result)
 var clock0:float=views[0].battle_effects.clock
 var clock1:float=views[1].battle_effects.clock
 advance(views[0],4.0)
 advance(views[1],0.5)
 check(is_equal_approx(views[0].battle_effects.clock-clock0,views[1].battle_effects.clock-clock1),"impact, damage and word effects advance on same accelerated timeline")
 check(views[0].displayed_hp==views[1].displayed_hp,"8x HP impact cues settle identically")
 check(views[0].actors[0].point.is_equal_approx(views[1].actors[0].point),"8x attack run and return reaches same point")
 check(sounds[0]==sounds[1],"8x retains every scheduled and animation-frame sound cue")
 check(views[0].state==views[1].state and authority.snapshot()==result,"presentation speed leaves authority and RNG outcome unchanged")
 check(Engine.time_scale==original_time_scale,"world/global time scale remains unchanged")
 var before:float=views[1].battle_effects.clock
 views[1].battle_effects._process(1.0)
 check(views[1].battle_effects.clock==before,"effects never receive duplicate engine process advancement")
 views[1].hide()
 before=views[1].elapsed
 views[1]._process(1.0)
 check(views[1].elapsed==before,"closed battles do not advance")
 views[1].playback_speed=100
 check(views[1].playback_speed==8,"presentation speed is bounded at 8x")
 views[1].playback_speed=NAN
 check(views[1].playback_speed==1,"invalid presentation speed safely resets")
 views[1].show()
 var tiny_before: float=views[1].elapsed
 views[1]._process(0.0000001)
 check(views[1].elapsed>tiny_before,"sub-microsecond remainder advances instead of hanging completion")
 for view in views:view.queue_free()
 await process_frame
 print("BATTLE SPEED: %d failures"%failures)
 quit(1 if failures else 0)
