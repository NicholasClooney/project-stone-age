extends RefCounted
## Test driver only: traverses production GameScene movement and original portals.
const Wait=preload("res://tests/support/wait.gd")
const Dream=preload("res://server/dream_cave_helper.gd")
const Clock=preload("res://server/original_world_clock.gd")
static func enter_and_reach(tree:SceneTree,game,target:Vector2i)->bool:
 var original:Callable=Clock.clock
 Clock.clock=func():return Clock.ERA+int(ceil(930.0*5400.0/1024.0))
 var reached:bool=await _enter_and_reach(tree,game,target)
 Clock.clock=original
 return reached
static func _enter_and_reach(tree:SceneTree,game,target:Vector2i)->bool:
 var overview=game.dev_map_overview
 overview.open_map();overview.walk_mode=false
 if not overview.select_poi({"map_id":400,"cell":Vector2i(99,119)}):return false
 if not await Wait.until(tree,func():return int(game.data.map_id)==400 and game.cell==Vector2i(99,119) and not game.area_transition_busy):return false
 if not await Wait.settle(tree,game):return false
 game.walk_to(Vector2i(98,119))
 if not await Wait.until(tree,func():return int(game.data.map_id)==41 and game.cell==Vector2i(11,8) and not game.area_transition_busy):return false
 if not await Wait.settle(tree,game):return false
 print("PASS: production walk enters original M gate at hour930")
 return await reach(tree,game,target)
static func reach(tree:SceneTree,game,target:Vector2i)->bool:
 var map_id:=int(game.data.map_id)
 var start:=Dream.region(map_id,game.cell)
 var goal:=Dream.region(map_id,target)
 var queue:Array=[start];var paths:Dictionary={start:[]};var cursor:=0
 while cursor<queue.size() and not paths.has(goal):
  var current:int=queue[cursor];cursor+=1
  for link in game.world_catalog.links(map_id).values():
   if int(link.to_map)!=map_id:continue
   var source:=Vector2i(link.cell[0],link.cell[1]);var arrival:=Vector2i(link.target[0],link.target[1])
   if Dream.region(map_id,source)!=current:continue
   var next:=Dream.region(map_id,arrival)
   if next<0 or paths.has(next):continue
   paths[next]=paths[current]+[link];queue.append(next)
 if not paths.has(goal):return false
 for link in paths[goal]:
  var source:=Vector2i(link.cell[0],link.cell[1]);var arrival:=Vector2i(link.target[0],link.target[1])
  # An original arrival can itself be another warp tile. The game deliberately
  # locks it until a real step leaves; step off and back instead of forcing warp.
  if game.cell==source:
   var away:=Vector2i(-1,-1)
   for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
    var point:Vector2i=source+offset
    if game.is_walkable(point) and not game.world_catalog.links(map_id).has(point):away=point;break
   if away.x<0:return false
   game.walk_to(away)
   if not await Wait.until(tree,func():return game.cell==away and not game.moving):return false
  var path:Array[Vector2i]=game.travel_router._path_to(source)
  print("ROUTE from=",game.cell," source=",source," target=",arrival," path=",path.size())
  if path.is_empty():return false
  # The test selects adjacent click destinations from the existing router;
  # only production walk_to writes movement state. The last step is a warp.
  path.pop_front()
  for point in path:
   game.walk_to(point)
   if point!=source and not await Wait.until(tree,func():return game.cell==point and not game.moving):
    print("ADJACENT stalled requested=",point," current=",game.cell," message=",game.message.text," moving=",game.moving," busy=",game.area_transition_busy)
    return false
  if not await Wait.until(tree,func():return game.cell==arrival and not game.moving and not game.area_transition_busy):
   print("ROUTE stalled cell=",game.cell," map=",game.data.map_id," moving=",game.moving," busy=",game.area_transition_busy," path=",game.path," message=",game.message.text)
   return false
  if not await Wait.settle(tree,game):return false
  print("PASS: production original maze warp ",source," -> ",arrival)
 game.walk_to(target)
 return await Wait.until(tree,func():return game.cell==target and not game.moving and not game.area_transition_busy) and await Wait.settle(tree,game)
