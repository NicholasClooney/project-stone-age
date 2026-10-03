extends "res://tests/wild_task_drop_test.gd"
func run()->void:
 for legal in [false,true]:
  var b=fresh();strong(b);mine(b,legal);b.encounter_rng.seed=27
  check(b.handle({"type":"set_automation_settings","settings":{"training":{"select_troops":false,"borrow_troops":false}}}).ok,"public training settings keep this test on actual local troop")
  check(b.handle({"type":"auto_start","kind":"battle","map_id":31801,"cell":[37,48]}).ok,"ordinary training runner starts")
  b.automation.step()
  check(b.battle_open and b.session._pending.has("wild_drop_receipt"),"actual training step freezes seed27 ore source")
  for turn in range(100):
   if not b.battle.snapshot().active:break
   b.automation.step()
  check(not b.battle.snapshot().active and b.battle_state.get("settled",false),"real auto policy wins and commits ordinary battle")
  check(b.session.snapshot().original_items.count(2534)==(1 if legal else 0),"automatic local training respects original arrival")
  check(b.handle({"type":"auto_stop"}).ok and not b.automation.running and not b.battle_open and b.session._pending.is_empty(),"normal training stop closes its already settled compact battle")
  b.free()
 print("WILD TASK DROP AUTO: %d failures"%failures);quit(1 if failures else 0)
