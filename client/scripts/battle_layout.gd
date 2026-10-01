extends RefCounted
## Presentation coordinates only. Native homes and queued motions stay untouched.
var vertical := false
var enemy_center := Vector2.ZERO
var friend_center := Vector2.ONE
var enemy_shift := Vector2.ZERO
var friend_shift := Vector2.ZERO
var bounds := Rect2()
var enemy_edge := 0.0
var friend_edge := 1.0
var factor := 1.0
var origin := Vector2.ZERO

func point(native: Vector2) -> Vector2:
	if not vertical: return native
	var axis := friend_center-enemy_center
	var projection := (native-enemy_center).dot(axis)/maxf(axis.length_squared(),1.0)
	var weight := clampf((projection-enemy_edge)/maxf(friend_edge-enemy_edge,0.001),0.0,1.0)
	return native+enemy_shift.lerp(friend_shift,weight)

func solve(entries: Array, available: Rect2) -> void:
	vertical = false
	if entries.is_empty(): return
	var camps := [Rect2(),Rect2()]
	var seen := [false,false]
	for entry in entries:
		var side := int(entry.side)
		var box: Rect2 = entry.box
		camps[side] = camps[side].merge(box) if seen[side] else box
		seen[side] = true
	enemy_center = camps[0].get_center()
	friend_center = camps[1].get_center()
	enemy_edge = -INF
	friend_edge = INF
	var axis := friend_center-enemy_center
	for entry in entries:
		var projection := (Vector2(entry.home)-enemy_center).dot(axis)/maxf(axis.length_squared(),1.0)
		if int(entry.side)==0: enemy_edge = maxf(enemy_edge,projection)
		else: friend_edge = minf(friend_edge,projection)
	if friend_edge<=enemy_edge: enemy_edge = 0.0; friend_edge = 1.0
	bounds = camps[0].merge(camps[1]) if seen[0] and seen[1] else camps[0] if seen[0] else camps[1]
	# Keep native scale until an individual camp itself requires shrinking.
	var camp_size := Vector2(maxf(camps[0].size.x,camps[1].size.x),maxf(camps[0].size.y,camps[1].size.y))
	var camp_factor := minf(1.0,minf(available.size.y/600.0,minf(available.size.x/maxf(camp_size.x,1),available.size.y/maxf(camp_size.y,1))))
	if seen[0] and seen[1] and (bounds.size.x*camp_factor>available.size.x or bounds.size.y*camp_factor>available.size.y or camps[0].intersects(camps[1])):
		var gap := 32.0
		var upper := Vector2(0,-(camps[1].size.y+gap)/2.0)
		var lower := Vector2(0,(camps[0].size.y+gap)/2.0)
		enemy_shift = upper-enemy_center
		friend_shift = lower-friend_center
		var candidate := Rect2()
		var first := true
		for entry in entries:
			var box: Rect2 = entry.box
			box.position += point_vertical(entry.home)-Vector2(entry.home)
			candidate = box if first else candidate.merge(box)
			first = false
		# A wide party can benefit more from the original diagonal arrangement.
		var diagonal_fit := minf(available.size.x/bounds.size.x,available.size.y/bounds.size.y)
		var vertical_fit := minf(available.size.x/candidate.size.x,available.size.y/candidate.size.y)
		if vertical_fit>diagonal_fit or camps[0].intersects(camps[1]):
			vertical = true
			bounds = candidate
	factor = minf(1.0,minf(available.size.x/maxf(bounds.size.x,1),available.size.y/maxf(bounds.size.y,1)))
	origin = available.get_center()-bounds.get_center()*factor

func point_vertical(native: Vector2) -> Vector2:
	var before := vertical
	vertical = true
	var result := point(native)
	vertical = before
	return result
