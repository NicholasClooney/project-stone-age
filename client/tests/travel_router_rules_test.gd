extends SceneTree
const Router=preload("res://scripts/travel_router.gd")
const Catalog=preload("res://scripts/world_catalog.gd")
class RouteWorld:
	extends Node
	var world_catalog=Catalog.new()
	var navigation=AStarGrid2D.new()
	var data={"map_id":1002}
	var state={"profile":{"player":{"level":1}}}
	var moving=false
	var cell=Vector2i(1,1)
	var target_cell=cell
	func is_walkable(point:Vector2i)->bool:return Rect2i(0,0,5,5).has_point(point)
var failures:=0
func check(value:bool,note:String)->void:
	if value:print("PASS: "+note)
	else:failures+=1;push_error("FAIL: "+note)
func _initialize()->void:
	var world=RouteWorld.new()
	var router=Router.new()
	router.configure(world)
	check(router.map_route(1000,3000,false).is_empty(),"no crossislandroute withoutpermit")
	var route:Array=router.map_route(1000,3000,true)
	check(10201 in route and 10202 in route and 10203 in route,"crossislandroute usesall originalunderseafloors")
	check(not router.map_route(1000,10202,false).is_empty(),"walking up to permitguard doesnotrequirepermit")
	check(router.map_route(1002,1000,false)==[1002,1000],"shopdoor route uses originalpair")
	check(router.map_route(10202,10204,true).is_empty(),"adult entrance remains unavailable below source level30")
	world.state.profile.player.level=30
	check(router.map_route(10202,10204,true)==[10202,10204],"source level30 enables original adult entrance route")
	world.world_catalog.portals={"1002":{Vector2i(2,1):{"to_map":99}}}
	world.navigation.region=Rect2i(0,0,5,5)
	world.navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
	world.navigation.update()
	var path:Array=router._path_to(Vector2i(3,1))
	check(not path.is_empty() and Vector2i(2,1) not in path,"localroute avoidsunintended doorway")
	check(not world.navigation.is_point_solid(Vector2i(2,1)),"temporarydoorblocking restored")
	check(not router._path_to(Vector2i(2,1)).is_empty(),"intendeddoor remainsreachable")
	check(router._path_to(Vector2i(9,9)).is_empty(),"outofbounds destination rejectedwithouttypedarrayerror")
	router.free();world.free()
	print("TRAVEL ROUTER RULES: %d failures" % failures)
	quit(1 if failures else 0)
