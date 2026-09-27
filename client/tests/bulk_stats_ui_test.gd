extends SceneTree
var failures:=0
func check(ok: bool, message: String):
 print(("PASS: " if ok else "FAIL: ")+message)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 await process_frame;await process_frame
 game.session._profile.player.level=120
 game.adventure_menu.open_menu("status")
 var menu=game.adventure_menu
 var amount=menu.panel.get_node("AllocationAmount")
 amount.value=100
 menu.panel.get_node("Allocate_strength").pressed.emit()
 await process_frame;await process_frame
 check(game.session.snapshot().player.allocated_stats.strength==100,"UP allocates selected batch through real UI")
 check(menu.panel.get_node("AllocationAmount").value==100,"batch size survives UI refresh")
 menu.panel.get_node("Distribute_toughness").button_pressed=false
 menu.panel.get_node("DistributeStats").pressed.emit()
 await process_frame;await process_frame
 var player: Dictionary=game.session.snapshot().player
 check(player.stat_points==0 and player.allocated_stats.toughness==0,"UI distributes all remaining points only to selected stats")
 check(player.allocated_stats.vitality==86 and player.allocated_stats.strength==186 and player.allocated_stats.dexterity==85,"UI remainder follows displayed order")
 check(not menu.panel.has_node("DistributeStats"),"helper hides when points exhausted")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null
 game.queue_free();await process_frame;await create_timer(0.5).timeout
 print("BULK STATS UI: %d failures"%failures)
 quit(1 if failures else 0)
