extends SceneTree
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func travel(game, source: int, cell: Vector2i, target: int, arrival: Vector2i):
 check(game.load_area_id(source,cell),"load original door %d %s" % [source,cell])
 game.arrival_lock=Vector2i(-1,-1)
 check(game.handle_arrival(),"original door triggers travel")
 check(await Wait.until(self,func():return not game.area_transition_busy),"transition finishes")
 check(int(game.data.map_id)==target and game.cell==arrival,"original destination and arrival retained")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false
 root.add_child(game)
 check(await Wait.until(self,func():return not game.data.is_empty()),"game loads isolated profile")
 game.random_encounters=false
 for id in [40,41,42,400,6000,6004,6005,6006,6009]:
  check(game.world_catalog.info(id).has("path"),"reviewed Seimu map %d imported" % id)
 check(game.world_catalog.info(400).get("dev_only",false),"island 400 stays developer only")
 check(not game.world_catalog.info(6012).has("path"),"room without original doors stays deferred")
 check(game.world_catalog.links(42).get(Vector2i(45,59),{}).is_empty(),"ambiguous dream cave door stays disabled")
 var hospital=false
 var invented=false
 for p in game.world_catalog.links(6000).values():
  if int(p.to_map)==6005:
   hospital= hospital or Vector2i(p.cell[0],p.cell[1])==Vector2i(44,67)
   invented= invented or Vector2i(p.cell[0],p.cell[1])==Vector2i(43,67)
 check(hospital and not invented,"hospital keeps only original incoming door")
 await travel(game,400,Vector2i(33,98),6000,Vector2i(30,79))
 await travel(game,6000,Vector2i(30,80),400,Vector2i(33,99))
 await travel(game,6000,Vector2i(32,68),40,Vector2i(6,3))
 check(not game.handle_arrival(),"arrival on reverse door does not bounce back")
 check(int(game.data.map_id)==40,"arrival suppression keeps player inside gate")
 await travel(game,40,Vector2i(6,3),6000,Vector2i(32,68))
 check(not game.handle_arrival(),"village arrival suppresses same-cell reverse gate")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop()
 game.queue_free()
 print("SEIMU SCENERY: %d failures" % failures)
 quit(1 if failures else 0)
