extends "res://tests/munde_cave_walking_test.gd"
func run()->void:
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 if not check(await Wait.until(self,func():return not game.data.is_empty()),"Saton isolated GameScene loads"):quit(1);return
 game.random_encounters=false
 if not check(game.load_area_id(100,Vector2i(131,421)),"public south-island original entrance approach"):quit(1);return
 if not check(await Wait.settle(self,game),"public entrance position settles"):quit(1);return
 game.walk_to(Vector2i(132,421))
 if not check(await Wait.until(self,func():return int(game.data.map_id)==10701 and not game.area_transition_busy),"actual public portal enters original cave"):quit(1);return
 for floor_id in range(10701,10706):
  if floor_id in [10701,10703,10705]:
   var goal:Vector2i={10701:Vector2i(22,51),10703:Vector2i(5,63),10705:Vector2i(43,41)}[floor_id]
   if not check(game.navigation.get_id_path(game.cell,goal).size()>1,"original collision connects entrance to source guard"):break
   game.walk_to(goal)
   if not check(await Wait.until(self,func():return game.cell==goal and game.path.is_empty(),180.0),"actual production walk reaches original guard neighbour"):break
  if floor_id==10705:break
  var door:Dictionary={}
  for p in game.world_catalog.links(floor_id).values():
   if int(p.to_map)==floor_id+1 and game.navigation.get_id_path(game.cell,Vector2i(int(p.cell[0]),int(p.cell[1]))).size()>1:door=p;break
  if not check(not door.is_empty(),"reachable original forward staircase exists"):break
  game.walk_to(Vector2i(int(door.cell[0]),int(door.cell[1])))
  if not check(await Wait.until(self,func():return int(game.data.map_id)==floor_id+1 and not game.area_transition_busy,180.0),"actual staircase enters next original floor"):break
  if not check(game.cell==Vector2i(int(door.target[0]),int(door.target[1])),"exact source staircase landing"):break
 check(int(game.data.map_id)==10705 and game.cell==Vector2i(43,41),"all four natural stairs connect three original guardian neighbours")
 check(game.backend.quest_arrival.has_arrival(game.backend,10705,game.cell),"natural GameScene walk retains server-owned original-route evidence")
 game.music.stop();game.effect.stop();game.queue_free();await process_frame
 print("SATON CAVE WALKING: %d failures"%failures);quit(1 if failures else 0)
