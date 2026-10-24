extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## scripts/nav_grid.gd against the whole-map AStarGrid2D it replaces, on real
## imported maps: the same routes (length, ends, reachability) at a fraction
## of the memory.
const NavGrid = preload("res://scripts/nav_grid.gd")
const MapFile = preload("res://scripts/map_file.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func both(id: int) -> Array:
	var data: Dictionary = MapFile.load_map("res://assets/legacy/world/%d.map" % id)
	var width := int(data.width)
	var whole := AStarGrid2D.new()
	var nav = NavGrid.new()
	for grid in [whole,nav]:
		grid.region = Rect2i(0,0,width,int(data.height))
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.update()
	var blocked: PackedByteArray = data.blocked
	var open: Array[Vector2i] = []
	for index in range(blocked.size()):
		var point := Vector2i(index%width,index/width)
		if blocked[index] != 0:
			whole.set_point_solid(point)
			nav.set_point_solid(point)
		elif index % 97 == 0:open.append(point)
	return [whole,nav,open,data]

## Octile length of a route, the cost both grids minimise.
static func cost(path: Array) -> float:
	var total := 0.0
	for i in range(1,path.size()):
		total += 1.0 if (path[i]-path[i-1]).abs().x+(path[i]-path[i-1]).abs().y == 1 else sqrt(2.0)
	return total

func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for id in [1000,100,300]:
		var set := both(id)
		var whole: AStarGrid2D = set[0]
		var nav = set[1]
		var open: Array = set[2]
		check(nav.memory_bytes() == int(set[3].width)*int(set[3].height),"map %d: one byte a cell (%.1f MB)" % [id,nav.memory_bytes()/1e6])
		var same := 0
		var tried := 0
		var slow := 0.0
		for i in range(60):
			var from: Vector2i = open[rng.randi_range(0,open.size()-1)]
			var to: Vector2i = from+Vector2i(rng.randi_range(-60,60),rng.randi_range(-60,60)) if i < 45 else open[rng.randi_range(0,open.size()-1)]
			if not whole.is_in_boundsv(to) or whole.is_point_solid(to):continue
			tried += 1
			var expected := whole.get_id_path(from,to)
			var started := Clock.ticks_usec()
			var got: Array = nav.get_id_path(from,to)
			slow = maxf(slow,(Clock.ticks_usec()-started)/1000.0)
			if expected.is_empty() == got.is_empty() and (expected.is_empty() or (got.front() == from and got.back() == to and absf(cost(got)-cost(expected)) < 0.01)):same += 1
			else:print("  differs %s→%s: whole %d steps (%.2f), nav %d (%.2f)" % [from,to,expected.size(),cost(expected),got.size(),cost(got)])
		check(tried > 30 and same == tried,"map %d: %d/%d routes as short as the whole-map grid's (slowest %.0f ms)" % [id,same,tried,slow])
	var nav = NavGrid.new()
	nav.region = Rect2i(0,0,10,10)
	nav.update()
	nav.set_point_solid(Vector2i(3,3))
	check(nav.is_point_solid(Vector2i(3,3)) and not nav.is_point_solid(Vector2i(4,4)) and not nav.is_point_solid(Vector2i(20,20)),"solid flags, and outside the map is not solid")
	nav.set_point_solid(Vector2i(3,3),false)
	check(not nav.is_point_solid(Vector2i(3,3)),"a cell can be opened again (temporary door blocks)")
	print("NAV GRID: %d failures" % failures)
	quit(1 if failures else 0)
