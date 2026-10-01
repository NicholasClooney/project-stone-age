extends SceneTree
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
func check(ok: bool, label: String):
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok: failures += 1
func _initialize(): call_deferred("run")
func travel(game, source: int, cell: Vector2i, target: int, arrival: Vector2i):
 check(game.load_area_id(source,cell), "load original portal")
 game.arrival_lock=Vector2i(-1,-1)
 check(game.handle_arrival(), "original portal triggers")
 check(await Wait.until(self,func():return not game.area_transition_busy), "transition completes")
 check(int(game.data.map_id)==target and game.cell==arrival, "original destination retained")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false
 root.add_child(game)
 check(await Wait.until(self,func():return not game.data.is_empty()), "isolated game loads")
 game.random_encounters=false
 check(game.world_catalog.info(20508).name=="哈恩的锻冶场", "original forge map imported")
 await travel(game,20501,Vector2i(8,53),20508,Vector2i(7,24))
 check(not game.handle_arrival(), "arrival does not immediately bounce")
 game.walk_to(Vector2i(11,11))
 check(await Wait.until(self,func():return game.cell==Vector2i(11,11) and not game.moving), "original doorway reaches Hahn neighbor")
 await travel(game,20508,Vector2i(7,24),20501,Vector2i(8,53))
 await travel(game,20508,Vector2i(8,24),20501,Vector2i(8,53))
 await travel(game,20508,Vector2i(20,11),200,Vector2i(396,821))
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop(); game.effect.stop(); game.queue_free()
 print("EARLY WOOD MAP: %d failures" % failures)
 quit(1 if failures else 0)
