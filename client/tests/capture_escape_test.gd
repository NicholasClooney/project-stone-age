extends SceneTree
const Authority = preload("res://server/battle_session.gd")
var view
var failures := 0
var music: Array[bool] = []
var sounds: Array[int] = []
func _initialize(): call_deferred("run")
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok: failures+=1
func advance(time: float):
 while view.elapsed<time:
  var step=minf(1.0/60.0,time-view.elapsed)
  view.battle_effects._process(step)
  view._process(step)
func picture(name: String):
 if DisplayServer.get_name()=="headless": return
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://../artifacts/"+name+".png")
func begin(authority, weaken: bool = false):
 var initial=authority.start_battle({"player_hp":100,"player_max_hp":100,"player_attack":8,"player_speed":20,"enemy_speed":1,"enemy_attack":2,"enemy_max_hp":30,"pet":{"species":"wooli","name":"乌力","sprite":100250,"hp":40,"max_hp":40,"attack":1,"speed":1}})
 if weaken:
  authority.set_pet_command("defend")
  initial=authority.submit_action("attack")
 view.open_battle(initial)
 advance(view.feedback_until+0.01)
 music.clear();sounds.clear()
func run():
 view=load("res://scripts/battle_view.gd").new()
 root.add_child(view)
 await process_frame
 view.set_process(false)
 view.battle_effects.set_process(false)
 view.capture_music_requested.connect(func(value):music.append(value))
 view.sound_requested.connect(func(value):sounds.append(value))
 for success in [false,true]:
  var authority=Authority.new()
  begin(authority,success)
  authority.set_pet_command("defend")
  view.pending_action="capture"
  view.show_state(authority.submit_action("capture"))
  check((view.state.outcome=="captured")==success,"capture outcome comes from authority")
  var motions=view.actors[0].motions.duplicate(true)
  var arrival=float(motions[1].end)
  check(float(motions[1].at)-float(motions[0].end)>1.0,"capture attack and pause precede slow retreat")
  check(float(motions[1].end)-float(motions[1].at)>float(motions[0].end)-float(motions[0].at),"capture return is slower than approach")
  advance((float(motions[1].at)+arrival)/2)
  check(view.actors[1].point.distance_to(view.actors[1].home)>10 and view.elapsed<view.actors[1].spin_end,"target spins and follows during return")
  check(sounds.has(250),"capture hit plays original unarmed damage sound")
  check(not view.result_panel.visible and not view.report.visible and not view.hint.visible and view.is_animating(),"capture blocks results and new input while returning")
  await picture("capture-follow")
  advance(arrival+0.01)
  if success:
   check(view.actors[0].temporary.begins_with("7_") and music==[true],"successful capture celebrates with original happy pose and BGM")
   await picture("capture-celebration")
  else:
   check(view.actors[0].temporary.begins_with("8_") and music.is_empty(),"failed capture shows anger without success music")
   await picture("capture-breakaway")
  advance(view.feedback_until+0.01)
  check(not view.is_animating(),"capture choreography releases input only after sequence")
  if success:
   check(not view.actors[1].sprite.visible and not view.hp_bars[1].visible and music==[true,false],"captured enemy disappears and battle music restores after celebration")
   check(view.result_panel.visible,"capture result appears after target disappears")
  else:
   check(view.actors[1].point.is_equal_approx(view.actors[1].home) and view.actors[1].sprite.visible,"failed target returns home before later actions finish")
 for success in [false,true]:
  var found=false
  for seed_value in range(1,100):
   var authority=Authority.new()
   authority.rng_seed=seed_value
   begin(authority)
   var next=authority.submit_action("escape")
   if (next.outcome=="escaped")!=success: continue
   found=true
   view.pending_action="escape"
   view.show_state(next)
   var start=view.elapsed
   advance(start+0.8)
   check(view.actors[0].point.is_equal_approx(view.actors[0].home) and view.actors[0].temporary=="4_7","escape starts running in place facing away")
   check(not view.result_panel.visible and view.is_animating(),"escape result waits for animation")
   if success:
    advance(start+2.0)
    check(view.actors[0].point.x>view.actors[0].home.x and view.actors[2].point.x>view.actors[2].home.x,"successful escape moves player and companion off stage")
    await picture("escape-retreat")
   else:
    advance(start+176.0/60.0+0.01)
    check(view.actors[0].temporary=="9_7" and view.actors[0].point.is_equal_approx(view.actors[0].home),"failed escape slows into original sad pose without displacement")
    await picture("escape-failure")
   advance(view.feedback_until+0.01)
   check(not view.is_animating(),"escape input lock ends after all actors finish")
   if success:
    check(not view.actors[0].sprite.visible and not view.actors[2].sprite.visible and view.result_panel.visible,"both escapees hide before result is available")
   else:
    check(view.actors[0].sprite.visible and view.state.active,"failed escape resumes active combat")
   break
  check(found,"tested seeded escape outcome")
 for avatar in ["100002","100007","100012"]:
  view.set_actor_art(0,avatar)
  var authority=Authority.new()
  begin(authority,true)
  view.pending_action="capture"
  view.show_state(authority.submit_action("capture"))
  advance(float(view.actors[0].motions[1].end)+0.01)
  check(sounds.has(251) and view.actors[0].temporary=="7_3","equipped avatar "+avatar+" retains club capture sound and celebration")
 var solo=Authority.new()
 var solo_state=solo.start_battle({"player_hp":100,"player_max_hp":100})
 view.open_battle(solo_state)
 advance(view.feedback_until+0.01)
 for i in range(3):
  var escaped=solo.submit_action("escape")
  if escaped.outcome=="escaped":
   view.pending_action="escape"
   view.show_state(escaped)
   break
 check(is_finite(view.feedback_until),"solo escape ignores absent pet slot when scheduling completion")
 advance(view.feedback_until+0.01)
 check(view.result_panel.visible,"solo escape releases input and shows result")
 begin(Authority.new())
 check(view.actors[0].sprite.visible and view.actors[1].sprite.visible,"new battle resets capture and escape visibility")
 view.queue_free()
 await process_frame
 print("CAPTURE / ESCAPE: %d failures" % failures)
 quit(1 if failures else 0)
