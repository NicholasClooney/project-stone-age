extends RefCounted
## The map's walking grid at one byte a cell, standing in for the AStarGrid2D
## the game used to keep for a whole map (about 62 bytes a cell: 42 MB for
## 萨伊那斯, 62 MB for 加鲁卡). The same calls as AStarGrid2D's that the game
## uses: region, diagonal_mode, the heuristics, clear(), update(),
## set_point_solid(), is_point_solid(), is_in_boundsv() and get_id_path().
##
## A path search builds a temporary AStarGrid2D over the cells between the
## two ends plus a margin, copies the solid cells in by runs, solves, and lets
## it go; a route that leaves that window is retried in a window twice as
## wide, up to the whole map, so results match a whole-map grid.
const FIRST_MARGIN := 48
## The last search window is kept for the next search inside it (a run of
## nearby clicks, a route's retries) while it is at most this many cells.
const KEEP_CELLS := 320*320

var region := Rect2i()
var diagonal_mode := AStarGrid2D.DIAGONAL_MODE_ALWAYS
var default_compute_heuristic := AStarGrid2D.HEURISTIC_EUCLIDEAN
var default_estimate_heuristic := AStarGrid2D.HEURISTIC_EUCLIDEAN
var _solid := PackedByteArray()
## Searches made and the cells their windows covered, for tests and the
## performance panel.
var searches := 0
var searched_cells := 0
## y -> solid runs of that row as [start, end, start, end, ...] (absolute
## x), built on first use and dropped when a cell of the row changes.
var _runs: Dictionary = {}
var _kept: AStarGrid2D
var _kept_version := -1
## Bumped whenever a cell's solid flag changes.
var _version := 0

func clear() -> void:
	region = Rect2i()
	_solid = PackedByteArray()
	_drop_kept()

func _drop_kept() -> void:
	_kept = null
	_runs.clear()
	_version += 1

## Every cell walkable again, sized to region (as AStarGrid2D.update()).
func update() -> void:
	_solid = PackedByteArray()
	_solid.resize(maxi(0,region.size.x*region.size.y))
	_drop_kept()

func is_in_boundsv(point: Vector2i) -> bool:
	return region.has_point(point)

func _index(point: Vector2i) -> int:
	return (point.y-region.position.y)*region.size.x+point.x-region.position.x

func set_point_solid(point: Vector2i, solid: bool = true) -> void:
	if not is_in_boundsv(point) or _solid.is_empty():return
	var value := 1 if solid else 0
	var index := _index(point)
	if _solid[index] == value:return
	_solid[index] = value
	_version += 1
	_runs.erase(point.y)
	# The kept window follows small changes (a door, a resident) in place.
	if _kept != null and _kept_version == _version-1 and _kept.region.has_point(point):
		_kept.set_point_solid(point,solid)
		_kept_version = _version

func is_point_solid(point: Vector2i) -> bool:
	if not is_in_boundsv(point) or _solid.is_empty():return false
	return _solid[_index(point)] != 0

## Bytes the grid holds (one a cell).
func memory_bytes() -> int:
	return _solid.size()+(_kept.region.get_area()*62 if _kept != null else 0)

func get_id_path(from: Vector2i, to: Vector2i, allow_partial_path: bool = false) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if not is_in_boundsv(from) or not is_in_boundsv(to) or _solid.is_empty():return none
	# Start with a window about as wide as the trip, not a fixed one.
	var margin := maxi(FIRST_MARGIN,maxi(absi(to.x-from.x),absi(to.y-from.y))/2)
	while true:
		var window := Rect2i(Vector2i(mini(from.x,to.x),mini(from.y,to.y)),Vector2i.ZERO).expand(Vector2i(maxi(from.x,to.x)+1,maxi(from.y,to.y)+1)).grow(margin).intersection(region)
		var path := _search(window,from,to,allow_partial_path)
		# Any route leaving the window walks at least to its edge and back, so
		# a route found inside that is no longer than that is the shortest.
		if window == region or (not path.is_empty() and path.back() == to and path.size()-1 <= _edge_steps(from,window)+_edge_steps(to,window)):return path
		margin *= 2
	return none

## Fewest steps from a cell out through an edge of the window that is not
## the map's own edge.
func _edge_steps(point: Vector2i, window: Rect2i) -> int:
	var best := 1 << 30
	if window.position.x > region.position.x:best = mini(best,point.x-window.position.x+1)
	if window.position.y > region.position.y:best = mini(best,point.y-window.position.y+1)
	if window.end.x < region.end.x:best = mini(best,window.end.x-point.x)
	if window.end.y < region.end.y:best = mini(best,window.end.y-point.y)
	return best

func _row_runs(y: int) -> PackedInt32Array:
	if _runs.has(y):return _runs[y]
	var runs := PackedInt32Array()
	var row := (y-region.position.y)*region.size.x
	var x := 0
	var width := region.size.x
	while x < width:
		if _solid[row+x] == 0:
			x += 1
			continue
		var start := x
		while x < width and _solid[row+x] != 0:x += 1
		runs.append(region.position.x+start)
		runs.append(region.position.x+x)
	_runs[y] = runs
	return runs

func _search(window: Rect2i, from: Vector2i, to: Vector2i, partial: bool) -> Array[Vector2i]:
	if _kept != null and _kept_version == _version and _kept.region.encloses(window):
		return _kept.get_id_path(from,to,partial)
	searches += 1
	searched_cells += window.size.x*window.size.y
	var grid := AStarGrid2D.new()
	grid.region = window
	grid.diagonal_mode = diagonal_mode
	grid.default_compute_heuristic = default_compute_heuristic
	grid.default_estimate_heuristic = default_estimate_heuristic
	grid.update()
	# Solid cells go in a run at a time: far fewer calls than one per cell.
	for y in range(window.position.y,window.end.y):
		var runs := _row_runs(y)
		for i in range(0,runs.size(),2):
			var start := maxi(runs[i],window.position.x)
			var end := mini(runs[i+1],window.end.x)
			if start < end:grid.fill_solid_region(Rect2i(start,y,end-start,1),true)
	if window.get_area() <= KEEP_CELLS:
		_kept = grid
		_kept_version = _version
	return grid.get_id_path(from,to,partial)
