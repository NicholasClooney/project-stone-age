extends SceneTree
const Session=preload("res://server/game_session.gd")
const Battle=preload("res://server/squad_battle_session.gd")
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():
 var session=Session.new();session.clone_squad_enabled=true;session.grant_starter_pets();session.select_pet(0)
 var config:Dictionary=session.start_battle_config()
 config.player_hp=10000;config.player_max_hp=10000
 config.enemies=[{"name":"练习","species":"wooli","sprite":100250,"hp":100000,"max_hp":100000,"attack":1,"defence":0,"speed":1,"reward_xp":20,"reward_gold":0,"can_capture":true}]
 var battle=Battle.new();battle.start_battle(config);battle.set_capture_assist(true)
 battle.set_pet_command("attack")
 var state:Dictionary=battle.submit_action("defend",0)
 var guarded:=0
 for frame in state.turn_frames:
  if frame.actor in ["ally","ally_pet"]:
   check(frame.outcome=="defend" and frame.damage==0,"capture assist guards clone actor even on player-defend turn")
   guarded+=1
 check(guarded==8,"all four clones and all four cloned pets defend")
 check(state.turn_order[0]=="player","main player keeps action priority")
 battle.set_capture_assist(false);state=battle.submit_action("attack",0)
 var attacks:=0
 for frame in state.turn_frames:
  if frame.actor in ["ally","ally_pet"] and frame.outcome!="defend":attacks+=1
 check(attacks==8,"manual takeover restores normal clone and pet attacks")
 battle.set_capture_assist(true)
 battle._state.active=false
 battle.start_battle(config)
 check(not battle.capture_assist,"new battle clears stale capture automation after interruption or defeat")
 print("CAPTURE ASSIST SQUAD: %d failures"%failures)
 quit(1 if failures else 0)
