extends SceneTree
const Battle = preload("res://server/battle_session.gd")
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
 print(("PASS: " if ok else "FAIL: ")+message)
 if not ok: failures+=1
func run():
 var view=load("res://scripts/battle_view.gd").new()
 root.add_child(view)
 await process_frame
 view.set_process(false)
 var initial=Battle.new().start_battle({"player_hp":150,"player_max_hp":200,"enemy_hp":300,"enemy_max_hp":350})
 view.open_battle(initial)
 view._process(view.feedback_until+0.1)
 view.update_hover_info(view.target_buttons[0].get_rect().get_center())
 check(view.hover_info.visible and "150/200" in view.hover_info.text,"own sprite hover shows exact HP even when not a selectable attack target")
 view.update_hover_info(view.hp_bars[1].position)
 check(view.hover_info.visible and "350/350" in view.hover_info.text,"enemy health meter hover shows single-player numeric HP")
 view.state.enemies[0].hp=1
 view.update_hover_info(view.hp_bars[1].position)
 check("350/350" in view.hover_info.text,"hover uses currently displayed HP, never future turn result")
 view.displayed_hp[1]=123
 view.update_hover_info(view.hp_bars[1].position)
 check("123/350" in view.hover_info.text,"hover follows impact-timed HP")
 view.update_riding_health({"ride_pet":0,"pets":[{"name":"红暴龙","hp":75,"max_hp":100}]})
 view.update_hover_info(view.hp_bars[0].position)
 check("红暴龙" in view.hover_info.text and "75/100" in view.hover_info.text,"rider hover also includes real riding pet health")
 view.update_hover_info(Vector2(400,40))
 check(not view.hover_info.visible and view.report.visible,"moving away hides hover and restores the turn report")
 view.feedback_until=view.elapsed+1.0
 view.update_hover_info(Vector2(400,40))
 check(not view.report.visible,"leaving hover during animation keeps the report hidden")
 view.feedback_until=view.elapsed
 view.result_panel.show()
 view.update_hover_info(view.hp_bars[0].position)
 check(not view.hover_info.visible,"result overlay suppresses actor hover")
 view.queue_free()
 await process_frame
 print("BATTLE HOVER: %d failures" % failures)
 quit(1 if failures else 0)
