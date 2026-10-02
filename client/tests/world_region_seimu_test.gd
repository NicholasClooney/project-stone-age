extends SceneTree
const Clock=preload("res://server/original_world_clock.gd")
var clock_seconds:=Clock.ERA
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
 var inner:Dictionary=game.world_catalog.links(42).get(Vector2i(45,59),{})
 check(int(inner.get("to_map",0))==42 and point(inner.get("target",[-1,-1]))==Vector2i(31,44),"dream internal door retains active MapWarpPoint first match2803, not later2835")
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
 await dream_gates(game)
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop()
 game.queue_free()
 print("SEIMU SCENERY: %d failures" % failures)
 quit(1 if failures else 0)

func point(values:Array)->Vector2i:return Vector2i(int(values[0]),int(values[1]))
func dream_gates(game)->void:
 var previous:Callable=Clock.clock
 Clock.clock=func():return clock_seconds
 # Actual source MapWarpPoint rows2746/2748/2749/2751/2801. A includes evening.
 for entry in [[Vector2i(97,119),41,"A",300,301,2746],[Vector2i(98,119),41,"M",930,931,2748],[Vector2i(97,120),41,"M",930,931,2749],[Vector2i(96,119),41,"M",930,931,2751],[Vector2i(87,101),42,"N",700,701,2801]]:
  var door:Dictionary=game.world_catalog.links(400).get(entry[0],{})
  check(door.get("requires_time","")==entry[2] and int(door.get("time_source_line",0))==entry[5] and int(door.get("to_map",0))==entry[1] and point(door.get("target",[-1,-1]))==Vector2i(11,8),"dream entrance retains reviewed source phase and destination")
  clock_seconds=Clock.ERA+int(ceil(float(entry[4])*5400.0/1024.0))
  check(game.load_area_id(400,entry[0]),"load closed original entrance")
  game.arrival_lock=Vector2i(-1,-1)
  game.handle_arrival()
  check(await Wait.until(self,func():return not game.area_transition_busy and not game.paused_input),"closed gate request completes")
  check(int(game.data.map_id)==400 and game.cell==entry[0] and game.message.text.contains("尚未开放"),"real arrival refuses closed source phase")
  clock_seconds=Clock.ERA+int(ceil(float(entry[3])*5400.0/1024.0))
  await travel(game,400,entry[0],entry[1],Vector2i(11,8))
 await travel(game,42,Vector2i(45,59),42,Vector2i(31,44))
 Clock.clock=previous
