extends SceneTree
## 本机极速模式: the native helper (build/fast_hunt) must roll exactly what the
## backend rolls. For thousands of hunt rolls on several areas, the troop, every
## enemy's level, grades, growth seed and base stats, its exact Lv120 stats and
## the slot the hunt would take must be identical in C and GDScript.
const Backend = preload("res://server/backend.gd")
const FastHunt = preload("res://server/fast_hunt.gd")
const EncounterCatalog = preload("res://server/encounter_catalog.gd")
const Progression = preload("res://server/progression.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## Points the backend's hunt at `area` without starting a run.
func prepare(automation, catalog: Dictionary, map_id: int, cell: Vector2i, run_seed: int, filter: Dictionary, flow: bool) -> void:
	var data: Dictionary = catalog.duplicate()
	var area: Dictionary = EncounterCatalog.new(catalog).area_at(map_id,cell)
	data.areas = [area]
	automation.hunt_catalog = EncounterCatalog.new(data)
	automation.hunt_map = map_id
	automation.hunt_cell = cell
	automation.hunt_run_seed = run_seed
	automation.hunt_filter = filter
	automation.flow_phase = "hunt" if flow else "idle"

func area_templates(catalog: Dictionary, area: Dictionary) -> Array:
	var found := {}
	for choice in area.get("groups",[]):
		for entry in catalog.groups.get(str(int(choice.id)),{}).get("enemies",[]):
			var enemy: Dictionary = catalog.enemies.get(str(int(entry.id)),{})
			if not enemy.is_empty():found[int(enemy.template_id)] = true
	return found.keys()

## Compares `count` rolls from `first`; returns the number of differing rolls.
func compare(automation, from_helper: String, first: int, count: int) -> Dictionary:
	var lines := from_helper.split("\n",false)
	var at := 0
	var different := 0
	var enemies := 0
	var projected := 0
	var matches := 0
	for index in range(first,first+count):
		var head := lines[at].split(" ",false)
		at += 1
		var troop: Dictionary = automation.roll_at(index)
		var mismatch := int(head[1])!=index or int(head[3])!=FastHunt.roll_seed(automation.hunt_run_seed,index)
		if head[4]=="empty":
			mismatch = mismatch or not troop.is_empty()
		else:
			var size := int(head[5])
			mismatch = mismatch or troop.get("enemies",[]).size()!=size
			for slot in range(size):
				var parts := lines[at].split(" ",false)
				at += 1
				if mismatch:continue
				var actor: Dictionary = troop.enemies[slot]
				var stats := Progression.project_pet(actor,120)
				var expected := [int(actor.source_enemy_id),int(actor.level),int(actor.growth_weights[0]),int(actor.growth_weights[1]),int(actor.growth_weights[2]),int(actor.growth_weights[3]),
					int(actor.growth_seed),int(actor.base_stats.vitality),int(actor.base_stats.strength),int(actor.base_stats.toughness),int(actor.base_stats.dexterity),
					int(stats.attack),int(stats.defence),int(stats.speed),int(stats.max_hp)]
				var got := [int(parts[1]),int(parts[3]),int(parts[5]),int(parts[6]),int(parts[7]),int(parts[8]),int(parts[10]),int(parts[12]),int(parts[13]),int(parts[14]),int(parts[15]),int(parts[17]),int(parts[18]),int(parts[19]),int(parts[21])]
				if expected!=got:
					mismatch = true
					if different < 3:print("  roll %d slot %d: GDScript %s, helper %s" % [index,slot,expected,got])
				enemies += 1
				if int(actor.level) < 120:projected += 1
		var scan := lines[at].split(" ",false)
		at += 1
		var slot: int = -2 if troop.is_empty() else automation.first_match(troop)
		if slot >= 0:matches += 1
		if int(scan[1])!=slot:
			mismatch = true
			if different < 3:print("  roll %d: GDScript takes slot %d, helper %s" % [index,slot,scan[1]])
		if mismatch:different += 1
	return {"different":different,"enemies":enemies,"projected":projected,"matches":matches}

func run_area(backend, catalog: Dictionary, label: String, map_id: int, cell: Vector2i, filter: Dictionary, flow: bool, count: int) -> Dictionary:
	var automation = backend.automation
	prepare(automation,catalog,map_id,cell,int(hash(label))*7919+count,filter,flow)
	var area: Dictionary = automation.hunt_catalog.area_at(map_id,cell)
	var helper = FastHunt.new()
	# Named per process: another run of this suite must never replace or remove it.
	var input := ProjectSettings.globalize_path("user://fast-hunt-test-%d.in" % OS.get_process_id())
	var file := FileAccess.open(input,FileAccess.WRITE)
	file.store_string(helper._input(automation.hunt_catalog.data,area,filter,flow,automation.filter_for,automation.hunt_run_seed,0,0,{},backend.session.snapshot().get("original_items",[])))
	file.close()
	var output := []
	var code := OS.execute(FastHunt.helper_path(),[input,"--roll","0",str(count)],output)
	DirAccess.remove_absolute(input)
	if code!=0 or output.is_empty():
		check(false,"%s: the helper printed the rolls" % label)
		return {}
	return compare(automation,str(output[0]),0,count)

func run() -> void:
	if not FastHunt.available():
		print("SKIP: %s" % FastHunt.unavailable_reason())
		check(false,"the helper is built for this test (scripts/build-fast-hunt.sh)")
		quit(1);return
	var backend = Backend.new()
	root.add_child(backend)
	var catalog: Dictionary = backend.encounter_catalog.data
	check(FastHunt.roll_seed(123456789,0)!=FastHunt.roll_seed(123456789,1),"every roll has its own seed")

	# The Lv1 blue dragon spot, as the hunt window uses it (grades 满档 only).
	var dragon := {"template":92,"level_one":true,"total":8,"offsets":[2,2,2,2],"limit":0,"rate":0,"usable":[92]}
	var result := run_area(backend,catalog,"blue dragon spot",300,Vector2i(509,93),dragon,false,4000)
	check(result.get("different",-1)==0 and int(result.get("enemies",0))>4000,"吉鲁岛 Lv1 blue dragon spot: 4000 rolls, %d enemies identical in C and GDScript" % int(result.get("enemies",0)))

	# Any capturable newborn at the first level-one spot, with Lv120 predictions
	# (a lax stat filter so both accepted and rejected predictions occur).
	var spot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level-one-spots.json")).spots[0]
	var spot_cell := Vector2i(int(spot.cell[0]),int(spot.cell[1]))
	var templates := area_templates(catalog,backend.encounter_catalog.area_at(int(spot.map_id),spot_cell))
	var newborn := {"template":-1,"level_one":true,"total":-8,"offsets":[-2,-2,-2,-2],"limit":0,"rate":0,"usable":templates}
	# The median predicted sum there, so about half the predictions are rejected.
	prepare(backend.automation,catalog,int(spot.map_id),spot_cell,99,newborn,false)
	var sums: Array = []
	for index in range(300):
		for actor in backend.automation.roll_at(index).get("enemies",[]):
			if int(actor.level)==1 and actor.can_capture:
				var stats := Progression.project_pet(actor,120)
				sums.append(int(stats.attack)+int(stats.defence)+int(stats.speed))
	sums.sort()
	var median: int = sums[sums.size()/2] if not sums.is_empty() else 0
	var lax := {"mode":"any","stop_after":1,"conditions":{"sum":{"enabled":true,"value":median,"strict":false,"keep":0},"speed":{"enabled":true,"value":10000,"strict":true,"keep":0}}}
	for id in templates:backend.automation.flow_stat_filters[int(id)] = lax
	result = run_area(backend,catalog,"level-one spot",int(spot.map_id),spot_cell,newborn,true,3000)
	check(result.get("different",-1)==0 and int(result.matches)>0 and int(backend.automation.flow_predicted_rejects)>0,"%s: 3000 rolls identical, %d taken after Lv120 prediction, %d predictions rejected" % [spot.name,int(result.get("matches",0)),int(backend.automation.flow_predicted_rejects)])
	backend.automation.flow_stat_filters.clear()

	# Lv90-95 wild red rex on map 500: levels above 1 and larger monsters.
	var rex_area: Dictionary = {}
	for area in catalog.areas:
		if int(area.map_id)==500 and 303 in area_templates(catalog,area):rex_area = area;break
	var rex_cell := Vector2i(int(rex_area.rect[0]),int(rex_area.rect[1]))
	var any := {"template":-1,"level_one":false,"total":-8,"offsets":[],"limit":0,"rate":0,"usable":area_templates(catalog,rex_area)}
	result = run_area(backend,catalog,"red rex area",500,rex_cell,any,false,2000)
	check(result.get("different",-1)==0 and int(result.projected)>0,"map 500 (red rex Lv90-95): 2000 rolls identical")

	# An added rare Lv.1 (data/rare-encounters.json): 左迪洛斯 in the same area,
	# hunted at Lv.1. The helper reads the same merged catalog.
	var blue_rex := {"template":302,"level_one":true,"total":-8,"offsets":[],"limit":0,"rate":0,"usable":[302]}
	result = run_area(backend,catalog,"added Lv1 blue rex",500,Vector2i(400,400),blue_rex,false,3000)
	check(result.get("different",-1)==0 and int(result.get("matches",0))>0,"map 500 added Lv.1 左迪洛斯: 3000 rolls identical, the hunt takes %d" % int(result.get("matches",0)))

	# A 补充 Lv.1 in a scaled area (吉鲁岛 311, ×33): 邦浦洛斯 next to its Lv43-45 row.
	var grey_dragon := {"template":93,"level_one":true,"total":-8,"offsets":[],"limit":0,"rate":0,"usable":[93]}
	result = run_area(backend,catalog,"added Lv1 grey dragon",300,Vector2i(402,307),grey_dragon,false,3000)
	check(result.get("different",-1)==0 and int(result.get("matches",0))>0,"吉鲁岛 311 added Lv.1 邦浦洛斯: 3000 rolls identical, the hunt takes %d" % int(result.get("matches",0)))

	# 60 areas across the world, 150 rolls each: groups with large monsters
	# (the five-slot swap), empty rolls and every level range.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var total_different := 0
	var total_enemies := 0
	var areas := 0
	var tries := 0
	while areas < 60 and tries < 2000:
		tries += 1
		var area: Dictionary = catalog.areas[rng.randi_range(0,catalog.areas.size()-1)]
		if int(area.probability_max)<=0:continue
		var cell := Vector2i(int(area.rect[0]),int(area.rect[1]))
		if int(backend.encounter_catalog.area_at(int(area.map_id),cell).get("id",-1))!=int(area.id):continue
		var everything := {"template":-1,"level_one":false,"total":-8,"offsets":[],"limit":0,"rate":0,"usable":area_templates(catalog,area)}
		var part := run_area(backend,catalog,"area %d" % int(area.id),int(area.map_id),cell,everything,false,150)
		if part.is_empty():total_different += 150;continue
		total_different += int(part.different)
		total_enemies += int(part.enemies)
		areas += 1
	check(areas==60 and total_different==0,"60 random areas, 9000 rolls and %d enemies identical in C and GDScript" % total_enemies)

	# Real source item gates, including all-gated empty rolls and wood drop RNG.
	for area_id in [88,267,436,453,56]:
		var group_id: int = {88:414,267:414,436:605,453:607,56:711}[area_id]
		var gate_area: Dictionary = {}
		var gate_cell := Vector2i.ZERO
		for area in catalog.areas:
			if int(area.id)!=area_id:continue
			for x in range(int(area.rect[0]),int(area.rect[2])+1):
				for y in range(int(area.rect[1]),int(area.rect[3])+1):
					var cell := Vector2i(x,y)
					if int(backend.encounter_catalog.area_at(int(area.map_id),cell).get("id",-1))==area_id:
						gate_area = area;gate_cell = cell;break
				if not gate_area.is_empty():break
			break
		check(not gate_area.is_empty(),"real source area for gate %d exists" % group_id)
		if gate_area.is_empty():continue
		var gate: Dictionary = catalog.groups[str(group_id)]
		var inventories: Array = [[],[int(gate.requires_item)] if int(gate.requires_item)>=0 else [int(gate.excludes_item)]]
		if int(gate.requires_item)>=0 and int(gate.excludes_item)>=0:inventories.append([int(gate.requires_item),int(gate.excludes_item)])
		for items in inventories:
			backend.session._profile.original_items = items.duplicate()
			var gate_filter := {"template":-1,"level_one":false,"total":-8,"offsets":[],"limit":0,"rate":0,"usable":area_templates(catalog,gate_area)}
			var part := run_area(backend,catalog,"gate %d items %s" % [group_id,items],int(gate_area.map_id),gate_cell,gate_filter,false,3000)
			check(part.get("different",-1)==0,"gate %d held %s: 3000 fixed-seed rolls identical" % [group_id,items])
	backend.session._profile.original_items = []

	backend.queue_free()
	await process_frame
	print("FAST HUNT: %d failures" % failures)
	quit(1 if failures else 0)
