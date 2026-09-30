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
 for id in [30001,30016,30101,30108,30205,30307,30403,30511,30703,31003,31103,31301,31302,31401,31501,31603,31806,31911]:
  check(game.world_catalog.info(id).has("path"),"reviewed Giru map %d is imported" % id)
 for id in [5107,9355,9356,9357,30017,30022,30023,30024,30025,30026,30901,30902,30903,30904,30905,31201,31202,31203,31204,31205,31604,31605,31606,31607,31608,31609,31610]:
  check(not game.world_catalog.info(id).has("path"),"unreviewed or unsafe Giru map %d remains deferred" % id)
 var door: Dictionary={}
 for p in game.world_catalog.links(300).values():
  if int(p.to_map)==30101:door=p;break
 check(not door.is_empty(),"original east Giru entrance is present")
 if not door.is_empty():
  check(Vector2i(int(door.cell[0]),int(door.cell[1]))==Vector2i(393,245) and Vector2i(int(door.target[0]),int(door.target[1]))==Vector2i(9,99),"island entrance retains original source and target cells")
  check(game.load_area_id(300,Vector2i(door.cell[0],door.cell[1])),"load original entrance cell")
  game.arrival_lock=Vector2i(-1,-1)
  check(game.handle_arrival(),"original mountain entrance triggers travel")
  check(await Wait.until(self,func():return not game.area_transition_busy),"mountain transition finishes")
  check(int(game.data.map_id)==30101,"mountain transition enters original floor")
  var back: Dictionary={}
  for p in game.world_catalog.links(30101).values():
   if int(p.to_map)==300:back=p;break
  check(not back.is_empty(),"mountain retains original island return")
  if not back.is_empty():
   check(int(back.cell[0]) in [8,9,10] and int(back.cell[1])==99 and Vector2i(int(back.target[0]),int(back.target[1]))==Vector2i(393,245),"return retains original source and target cells")
   check(game.load_area_id(30101,Vector2i(back.cell[0],back.cell[1])),"load original return cell")
   game.arrival_lock=Vector2i(-1,-1)
   check(game.handle_arrival(),"mountain return triggers travel")
   check(await Wait.until(self,func():return not game.area_transition_busy),"return finishes")
   check(int(game.data.map_id)==300,"return reaches Giru")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop()
 game.queue_free()
 print("GIRU SCENERY: %d failures" % failures)
 quit(1 if failures else 0)
