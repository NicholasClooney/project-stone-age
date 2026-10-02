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
 for id in [201,3020,4020,21015,851]:
  check(game.world_catalog.info(id).has("path"),"reviewed Jyaruga map %d imported" % id)
 for id in [3008,3021,3022,3208,3308,4008,20001,21103]:
  check(not game.world_catalog.info(id).has("path"),"unconnected/special map %d remains deferred" % id)
 await travel(game,200,Vector2i(328,660),201,Vector2i(6,19))
 await travel(game,201,Vector2i(6,19),200,Vector2i(328,660))
 await travel(game,3000,Vector2i(112,80),3020,Vector2i(4,12))
 await travel(game,3020,Vector2i(4,12),3000,Vector2i(112,80))
 await travel(game,4000,Vector2i(82,107),4020,Vector2i(4,12))
 await travel(game,4020,Vector2i(4,12),4000,Vector2i(82,107))
 # Golden Bui advanced entrance: active mapwarp1268 precedes duplicate1270.
 var entry:Dictionary=game.world_catalog.links(4020).get(Vector2i(11,9),{})
 check(int(entry.get("to_map",0))==851 and point(entry.get("target",[-1,-1]))==Vector2i(30,29),"reviewed Golden Bui advanced hall keeps original first-match arrival")
 await travel(game,4020,Vector2i(11,9),851,Vector2i(30,29))
 await travel(game,851,Vector2i(30,29),4020,Vector2i(11,9))
 await travel(game,4020,Vector2i(12,9),851,Vector2i(28,29))
 await travel(game,851,Vector2i(28,29),4020,Vector2i(12,9))
 await travel(game,851,Vector2i(29,29),4020,Vector2i(11,9))
 await travel(game,21014,Vector2i(14,14),21015,Vector2i(9,17))
 check(not game.handle_arrival(),"arrival on original return door is suppressed")
 check(int(game.data.map_id)==21015,"arrival does not immediately bounce to floor14")
 game.walk_to(Vector2i(9,16))
 check(await Wait.until(self,func():return game.cell==Vector2i(9,16) and not game.moving),"leave return door by ordinary movement")
 game.walk_to(Vector2i(9,17))
 check(await Wait.until(self,func():return int(game.data.map_id)==21014 and not game.area_transition_busy),"reenter return door travels to floor14")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop()
 game.queue_free()
 print("JYARUGA INTERIORS: %d failures" % failures)
 quit(1 if failures else 0)

func point(values:Array)->Vector2i:return Vector2i(int(values[0]),int(values[1]))
