extends Node
## Walk-only navigator. Map changes occur exclusively through normal world portals
## or the original permit guard's explicit dialogue confirmation.
var world: Node
var active := false
var destination_map := -1
var destination := Vector2i(-1,-1)
var last_error := ""
var waiting_guard := false
var guard_close_wait := 0.0
var guard_destination := Vector2i(-1,-1)
var final_cell := Vector2i(-1,-1)
var planned_map := -1
var used_gates: Dictionary = {}
func configure(owner: Node) -> void:world=owner
func cancel(reason: String = "") -> void:
	active=false
	waiting_guard=false
	final_cell=Vector2i(-1,-1)
	last_error=reason
func map_route(origin: int, target: int, permit: bool) -> Array[int]:
	if origin==target:return [origin]
	var queue: Array[int]=[origin]
	var previous: Dictionary={origin:-1}
	while not queue.is_empty():
		var current: int=queue.pop_front()
		for link in world.world_catalog.links(current).values():
			var next:=int(link.to_map)
			if previous.has(next) or (not permit and next==10202 and next!=target):continue
			previous[next]=current
			if next==target:
				var route: Array[int]=[target]
				while route[0]!=origin:route.push_front(int(previous[route[0]]))
				return route
			queue.append(next)
	return []
func request(map_id: int, cell: Vector2i) -> bool:
	cancel()
	if world.battle_view.visible or world.area_transition_busy:return false
	if world.world_catalog.info(map_id).is_empty():
		last_error="地图尚未导入。"
		return false
	var route:=map_route(int(world.data.map_id),map_id,world.session.has_travel_pass())
	if route.is_empty():
		last_error="没有可步行的路线；跨岛海底通道需要通行证。"
		return false
	destination_map=map_id
	destination=cell
	planned_map=-1
	used_gates.clear()
	active=true
	world.clear_input()
	return _plan_leg()
func _path_to(target: Vector2i) -> Array[Vector2i]:
	var start: Vector2i=world.target_cell if world.moving else world.cell
	var changed: Array[Vector2i]=[]
	# Do not accidentally enter a different door on the route to our selected one.
	for point in world.world_catalog.links(int(world.data.map_id)):
		if point!=target and point!=start and not world.navigation.is_point_solid(point):
			world.navigation.set_point_solid(point,true)
			changed.append(point)
	var path: Array[Vector2i]=[]
	if world.is_walkable(target):path=world.navigation.get_id_path(start,target)
	for point in changed:world.navigation.set_point_solid(point,false)
	return path
func _plan_leg() -> bool:
	if not active:return false
	var map_id:=int(world.data.map_id)
	planned_map=map_id
	var best: Array[Vector2i]=[]
	if map_id==destination_map:
		var exact_walkable: bool=world.is_walkable(destination) and not world.world_catalog.links(map_id).has(destination)
		for radius in range(0,1 if exact_walkable else 5):
			for y in range(-radius,radius+1):
				for x in range(-radius,radius+1):
					if maxi(absi(x),absi(y))!=radius:continue
					var candidate:=destination+Vector2i(x,y)
					if world.world_catalog.links(map_id).has(candidate):continue
					var path:=_path_to(candidate)
					if not path.is_empty() and (best.is_empty() or path.size()<best.size()):best=path
			if not best.is_empty():break
		if not best.is_empty():final_cell=best.back()
	else:
		var route:=map_route(map_id,destination_map,world.session.has_travel_pass())
		if route.size()<2:return _fail("路线中断：没有可用的原始出入口。")
		for point in world.world_catalog.links(map_id):
			if int(world.world_catalog.links(map_id)[point].to_map)!=route[1]:continue
			var path:=_path_to(point)
			if not path.is_empty() and (best.is_empty() or path.size()<best.size()):best=path
	if best.is_empty():
		if map_id==10202:
			if world.session.has_travel_pass():return _approach_guard()
			return _fail("穿过海底关卡需要通行证。")
		return _fail("无法步行到此处；请选择同一可达区域的地面。")
	best.pop_front()
	world.path=best
	world.marker_cell=final_cell if map_id==destination_map else (best.back() if not best.is_empty() else world.cell)
	world.message.text="自动寻路：%s (%d,%d)" % [world.world_catalog.info(destination_map).name,destination.x,destination.y]
	world.queue_redraw()
	return true
func _approach_guard() -> bool:
	for i in range(world.world_travel.entries.size()):
		var entry: Dictionary=world.world_travel.entries[i]
		if entry.get("role","")!="gate":continue
		var guard:=Vector2i(entry.cell[0],entry.cell[1])
		if used_gates.has(guard):continue
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if not _path_to(guard+offset).is_empty():
				used_gates[guard]=true
				guard_close_wait=0.0
				waiting_guard=true
				guard_destination=Vector2i(entry.destination[0],entry.destination[1])
				world.world_travel.approach(i)
				return true
	return _fail("无法接近海底通道守卫。")
func _fail(reason: String) -> bool:
	cancel(reason)
	world.message.text=reason
	return false
func _process(delta: float) -> void:
	if not active or world.area_transition_busy or world.paused_input or world.moving or not world.path.is_empty():return
	if world.battle_view.visible:
		cancel("战斗中断了自动寻路。")
		return
	if waiting_guard:
		if world.cell!=guard_destination:
			_cancel_guard(delta)
			return
		waiting_guard=false
		_plan_leg()
	elif int(world.data.map_id)==destination_map and world.cell==final_cell:
		cancel()
	else:_plan_leg()
func _cancel_guard(delta: float) -> void:
	# The helper opens its dialogue on its next process callback; don't cancel
	# while it still owns the approach completion.
	if is_instance_valid(world.world_travel) and world.world_travel.pending>=0:return
	guard_close_wait+=delta
	if guard_close_wait>=0.3:_fail("已停止：需要确认守卫的通行对话。")
