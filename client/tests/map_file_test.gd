extends SceneTree
## Packed maps (scripts/map_file.gd): a world/<id>.map file loads the same
## tiles, walkability, objects and paths as the map JSON it came from, and
## the ground layer and props read the packed grids.
const MapFile = preload("res://scripts/map_file.gd")
const LegacyGround = preload("res://scripts/legacy_ground.gd")
const LEGACY := "res://assets/legacy/"
var failures := 0

func check(value: bool, note: String) -> void:
	if value:print("PASS: "+note)
	else:
		failures += 1
		push_error("FAIL: "+note)

func _initialize() -> void:
	synthetic_json()
	# samgir.json and shop.json are the importers' JSON of maps 1000 and 1002;
	# world/1000.map and world/1002.map were converted from the same data.
	for pair in [["samgir.json","world/1000.map"],["shop.json","world/1002.map"]]:
		if FileAccess.file_exists(LEGACY+pair[0]) and FileAccess.file_exists(LEGACY+pair[1]):same_map(pair[0],pair[1])
		else:check(false,"imported %s and %s" % pair)
	for id in [100,200,300]:
		whole_map(id)
	check(MapFile.load_map(LEGACY+"world/missing.map").is_empty(),"a missing map loads as empty")
	quit(1 if failures else 0)

func synthetic_json() -> void:
	var data := MapFile.from_json({"map_id":7,"width":3,"height":2,
		"ground":[[2,1,126271],[0,0,13],[1,0,14],[0,1,15],[2,0,16]],
		"blocked":[1,0,0,1,0,1],"objects":[[2,1,4910],[0,0,5161]],"images":{}})
	check(data.ground==PackedInt32Array([13,14,16,15,0,126271]),"JSON ground triples become a row-order grid with 0 for no tile")
	check(data.blocked==PackedByteArray([1,0,0,1,0,1]),"JSON walkability becomes one byte per cell")
	check(data.objects==PackedInt32Array([2,1,4910,0,0,5161]),"objects keep their order as x, y, id triples")
	check(MapFile.object_count(data)==2,"object count")
	var ground := LegacyGround.new()
	ground.fill(data.ground)
	check(ground.ident_at(0)=="13" and ground.ident_at(5)=="126271","the ground layer names tiles by image id")
	check(ground.ident_at(4)=="" and ground.ident_at(-1)=="" and ground.ident_at(6)=="","no tile or outside the map reads as no tile")
	ground.free()

func same_map(json_name: String, map_name: String) -> void:
	var old := MapFile.load_map(LEGACY+json_name)
	var packed := MapFile.load_map(LEGACY+map_name)
	var label := "%s = %s" % [map_name,json_name]
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY+json_name))
	check(not packed.is_empty() and int(packed.width)==int(old.width) and int(packed.height)==int(old.height),label+": size")
	check(packed.ground==old.ground,label+": every ground tile")
	check(packed.blocked==old.blocked,label+": every walkable cell")
	check(packed.objects==old.objects,label+": every object in order")
	check(packed.images==raw.images and int(packed.map_id)==int(raw.map_id),label+": tile metadata and id")
	# Straight from the JSON arrays, as the game read them before.
	var width := int(raw.width)
	var tiles_ok := true
	for entry in raw.ground:
		tiles_ok = tiles_ok and packed.ground[int(entry[1])*width+int(entry[0])]==int(entry[2])
	var count := 0
	for id in packed.ground:if id!=0:count += 1
	check(tiles_ok and count==raw.ground.size(),label+": tiles match the JSON triples, nothing extra")
	var walk_ok := true
	for index in range(raw.blocked.size()):
		walk_ok = walk_ok and (int(raw.blocked[index])!=0)==(packed.blocked[index]!=0)
	check(walk_ok,label+": walkability matches the JSON flags")
	var before := navigation(raw.blocked,width,int(raw.height))
	var after := navigation(packed.blocked,width,int(raw.height))
	var open: Array = []
	for index in range(packed.blocked.size()):
		if packed.blocked[index]==0:open.append(Vector2i(index%width,index/width))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var paths_ok := open.size()>1
	var found := 0
	for i in range(24):
		var a: Vector2i = open[rng.randi_range(0,open.size()-1)]
		var b: Vector2i = open[rng.randi_range(0,open.size()-1)]
		var path := after.get_id_path(a,b)
		paths_ok = paths_ok and path==before.get_id_path(a,b)
		if not path.is_empty():found += 1
	check(paths_ok and found>0,label+": the same paths between %d pairs of cells (%d reachable)" % [24,found])

func whole_map(id: int) -> void:
	var catalog = preload("res://scripts/world_catalog.gd").new()
	var path: String = catalog.file(id)
	var data := MapFile.load_map(path)
	var cells := int(data.get("width",0))*int(data.get("height",0))
	check(path.ends_with(".map") and cells>0,"map %d loads from %s" % [id,path])
	if data.is_empty():return
	check(data.ground.size()==cells and data.blocked.size()==cells and data.objects.size()%3==0,"map %d grids cover every cell" % id)
	var named := true
	for tile in data.ground:
		if tile!=0 and not data.images.has(str(tile)):named = false
	for i in range(2,data.objects.size(),3):
		if not data.images.has(str(data.objects[i])):named = false
	check(named,"map %d: every tile and object has image metadata" % id)
	var spawn: Array = catalog.info(id).spawn
	check(data.blocked[int(spawn[1])*int(data.width)+int(spawn[0])]==0,"map %d spawn is walkable" % id)

func navigation(blocked, width: int, height: int) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0,0,width,height)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for index in range(blocked.size()):
		if int(blocked[index])!=0:grid.set_point_solid(Vector2i(index%width,index/width))
	return grid
