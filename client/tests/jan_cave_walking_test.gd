extends "res://tests/munde_cave_walking_test.gd"
func run()->void:
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 if not check(await Wait.until(self,func():return not game.data.is_empty()),"isolated Jan world loads"):quit(1);return
 game.random_encounters=false
 var outside:Dictionary=preload("res://server/jan_cave_helper.gd").public_entrance(game.backend.quest_helper,game.backend)
 if not check(not outside.is_empty() and game.load_area_id(200,Vector2i(int(outside.cell[0]),int(outside.cell[1]))),"public outside approach fixture grants no cave scope"):quit(1);return
 if not check(await Wait.settle(self,game),"public position settles"):quit(1);return
 game.walk_to(Vector2i(285,926))
 if not check(await Wait.until(self,func():return int(game.data.map_id)==20601 and not game.area_transition_busy,180.0),"actual client steps through original public portal"):quit(1);return
 if not check(await Wait.settle(self,game) and game.backend.quest_arrival.has_arrival(game.backend,20601,game.cell),"only actual portal grants first-floor arrival"):quit(1);return
 for level in range(20601,20604):
  var door:Dictionary={}
  for p in game.world_catalog.links(level).values():
   if int(p.to_map)==level+1:door=p;break
  if not check(not door.is_empty(),"original staircase exists %d"%level):break
  var cell:=Vector2i(int(door.cell[0]),int(door.cell[1]))
  if not check(game.navigation.get_id_path(game.cell,cell).size()>1,"source collision connects original stairs"):break
  game.walk_to(cell)
  if not check(await Wait.until(self,func():return int(game.data.map_id)==level+1 and not game.area_transition_busy,180.0),"actual world walk enters next floor"):break
  check(game.cell==Vector2i(int(door.target[0]),int(door.target[1])),"exact original stair landing")
 check(int(game.data.map_id)==20604,"three original stairs reach first keyword floor")
 check(await Wait.settle(self,game) and game.backend.quest_arrival.has_arrival(game.backend,20604,game.cell),"all original stair steps preserve legitimate arrival")
 # The full remote UI suite continues through all three original keywords,
 # actual guard combat and both Sarah portals without any interior placement.
 game.music.stop();game.effect.stop();game.queue_free();await process_frame
 print("JAN CAVE WALKING: %d failures"%failures);quit(1 if failures else 0)
