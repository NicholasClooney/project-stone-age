extends SceneTree
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false
 root.add_child(game)
 check(await Wait.until(self,func():return not game.data.is_empty()),"game loads isolated profile")
 game.random_encounters=false
 for id in [101,1200,1201,1212,10101,10204,10402,10601,10701,10901,11006,11107,11215]:
  check(not game.world_catalog.info(id).is_empty(),"reviewed Sainasu map %d is imported" % id)
 check(not game.world_catalog.info(10301).has("path"),"unconnected Kuo cave remains deferred")
 var door: Dictionary={}
 for p in game.world_catalog.links(100).values():
  if int(p.to_map)==10901:door=p;break
 check(not door.is_empty(),"reviewed duplicated original pit entrance has one active destination")
 if not door.is_empty():
  check(game.load_area_id(100,Vector2i(door.cell[0],door.cell[1])),"load original entrance cell")
  game.arrival_lock=Vector2i(-1,-1)
  check(game.handle_arrival(),"original pit entrance triggers travel")
  check(await Wait.until(self,func():return not game.area_transition_busy),"pit transition finishes")
  check(int(game.data.map_id)==10901,"pit transition enters original floor")
  var back: Dictionary={}
  for p in game.world_catalog.links(10901).values():
   if int(p.to_map)==100:back=p;break
  check(not back.is_empty(),"pit retains original island return")
  if not back.is_empty():
   game.load_area_id(10901,Vector2i(back.cell[0],back.cell[1]))
   game.arrival_lock=Vector2i(-1,-1)
   check(game.handle_arrival(),"pit return triggers travel")
   check(await Wait.until(self,func():return not game.area_transition_busy),"return finishes")
   check(int(game.data.map_id)==100,"return reaches Sainasu")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop()
 game.queue_free()
 print("SAINASU SCENERY: %d failures" % failures)
 quit(1 if failures else 0)
