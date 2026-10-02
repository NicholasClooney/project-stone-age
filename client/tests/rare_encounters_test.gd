extends SceneTree
## Rare Lv.1 encounters (data/rare-encounters.json, merged into the encounter
## catalog by tools/import_encounters.py): every added pet is in its area's
## troop table at Lv.1 with the documented weight, seeded rolls meet it, and a
## seeded 自动抓宠 hunt finds one that the battle authority captures.
## Real catalog, real rolls and battle; nothing is faked.
## See docs/reverse-engineering/rare-level-one-encounters.md.
const Backend = preload("res://server/backend.gd")
const Catalog = preload("res://server/encounter_catalog.gd")
const Session = preload("res://server/game_session.gd")
const Battle = preload("res://server/battle_session.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## The weight roll() chooses groups by: existing groups without an item gate.
func ordinary_total(catalog: Dictionary, area: Dictionary) -> int:
	var total := 0
	for choice in area.groups:
		var group: Dictionary = catalog.groups.get(str(int(choice.id)),{})
		if not group.is_empty() and int(group.requires_item) < 0 and int(group.excludes_item) < 0:total += int(choice.weight)
	return total

func run() -> void:
	var spec := read_json("res://data/rare-encounters.json")
	var catalog = Catalog.new()
	var data: Dictionary = catalog.data
	var landing := {}
	for spot in read_json("res://data/training-spots.json").get("spots",[]):landing["%d/%d" % [int(spot.map_id),int(spot.area_id)]] = Vector2i(int(spot.cell[0]),int(spot.cell[1]))
	check(data.get("provenance",{}).has("rare_encounters") and int(data.provenance.rare_encounters.encounters) == spec.encounters.size(),"the imported catalog carries the %d rare encounters" % spec.encounters.size())

	# The reference: 漆黑的洞窟 地下18楼's original Lv.1 布林帖斯 group.
	var reference: Dictionary = spec.reference
	var b18: Dictionary = catalog.area_at(int(reference.map_id),landing["%d/%d" % [int(reference.map_id),int(reference.area_id)]])
	var original: Array = b18.groups.filter(func(choice):return int(choice.id) == int(reference.group_id))
	check(original.size() == 1 and int(original[0].weight) == 1 and ordinary_total(data,b18) == int(reference.area_weight_total) and not b18.has("weight_scale"),"reference: 地下18楼 group 751 (Lv.1 布林帖斯) is 1 of 101, untouched")

	# Every addition: its area, weight, Lv.1 capturable enemy and companion.
	var bad: Array = []
	var lowest := 1.0
	var highest := 0.0
	for item in spec.encounters:
		var key := "%d/%d" % [int(item.map_id),int(item.area_id)]
		var why := ""
		if not landing.has(key):why += " no landing cell"
		var area: Dictionary = catalog.area_at(int(item.map_id),landing.get(key,Vector2i(-1,-1)))
		if int(area.get("id",-1)) != int(item.area_id):
			bad.append("%s: area %s" % [item.name,key])
			continue
		var choices: Array = area.groups.filter(func(choice):return int(choice.id) == int(item.group_id))
		if choices.size() != 1 or int(choices[0].weight) != 1:why += " area weight"
		var share := 1.0/ordinary_total(data,area)
		lowest = minf(lowest,share)
		highest = maxf(highest,share)
		if share < 0.005 or share > 0.015:why += " share %.3f" % share
		var group: Dictionary = data.groups.get(str(int(item.group_id)),{})
		var members: Array = group.get("enemies",[])
		if members.is_empty() or int(members[0].id) != int(item.enemy_id) or int(members[0].weight) != 1:why += " Lv.1 member"
		if item.companion_id != null and (members.size() != 2 or int(members[1].id) != int(item.companion_id) or int(members[1].weight) != 1):why += " companion"
		if str(group.get("rare",{}).get("origin","")) != str(item.origin):why += " origin"
		var enemy: Dictionary = data.enemies.get(str(int(item.enemy_id)),{})
		if int(enemy.get("template_id",-1)) != int(item.template_id) or int(enemy.get("level_min",0)) != 1 or int(enemy.get("level_max",0)) != 1 or int(enemy.get("pet_flag",0)) == 0:why += " enemy row"
		var rng := RandomNumberGenerator.new()
		rng.seed = int(item.group_id)
		var actor: Dictionary = catalog.actor(int(item.enemy_id),rng)
		var template: Dictionary = data.templates[str(int(item.template_id))]
		if int(actor.level) != 1 or not actor.can_capture or int(actor.get("capture_parameter",-99)) != int(template.capture_resistance):why += " actor"
		if not why.is_empty():bad.append(str(item.name)+why)
	check(bad.is_empty(),"%d added pets: each in its area at Lv.1, capturable, area weight 1 (%.2f%%–%.2f%% of the area), companion 1:1, capture difficulty from the template%s" % [spec.encounters.size(),lowest*100,highest*100,"" if bad.is_empty() else ": "+"；".join(bad)])

	# 补充 rows sit next to the same pet at a higher level in that area.
	var not_there: Array = []
	for item in spec.encounters:
		if str(item.origin) != "original_area":continue
		var area: Dictionary = catalog.area_at(int(item.map_id),landing["%d/%d" % [int(item.map_id),int(item.area_id)]])
		var higher := false
		for choice in area.groups:
			var group: Dictionary = data.groups.get(str(int(choice.id)),{})
			if group.has("rare"):continue
			for member in group.get("enemies",[]):
				var row: Dictionary = data.enemies.get(str(int(member.id)),{})
				if int(row.get("template_id",-1)) == int(item.template_id) and int(row.get("level_min",0)) > 1:higher = true
		if not higher:not_there.append(str(item.name))
	check(not_there.is_empty(),"every 补充 Lv.1 is in an area that has the same pet at a higher level%s" % ("" if not_there.is_empty() else ": "+"、".join(not_there)))

	# Every classic pet (data/classic-pets.json) with a reachable wild spot has a Lv.1 spot.
	var wild := {}
	for spot in read_json("res://data/training-spots.json").get("spots",[]):
		for name in spot.get("monsters",[]):wild[str(name)] = true
	var level_one := {}
	for spot in read_json("res://data/level-one-spots.json").get("spots",[]):level_one[int(spot.template_id)] = true
	var missing: Array = []
	var classic := 0
	for pet in read_json("res://data/classic-pets.json").get("pets",[]):
		if pet.template_id == null or not wild.has(str(data.templates[str(int(pet.template_id))].name)):continue
		# 乌力乌力 is the grown 乌力 (met from Lv.20); its Lv.1 is the 乌力 itself.
		if str(pet.name) == "乌力乌力":continue
		classic += 1
		if not level_one.has(int(pet.template_id)):missing.append(str(pet.name))
	check(missing.is_empty(),"all %d classic pets with a wild spot also have a Lv.1 spot%s" % [classic,"" if missing.is_empty() else "; missing: "+"、".join(missing)])

	# Scaled areas keep their original ratios: every original weight is a multiple of the scale.
	var unscaled: Array = []
	for item in spec.areas:
		for area in data.areas:
			if int(area.map_id) != int(item.map_id) or int(area.id) != int(item.area_id):continue
			if int(area.get("weight_scale",0)) != int(item.scale):unscaled.append(item.area_id)
			for choice in area.groups:
				if int(choice.id) < 90000 and int(choice.weight)%int(item.scale) != 0:unscaled.append(item.area_id)
	check(unscaled.is_empty(),"%d areas scaled by whole factors, original group ratios unchanged" % spec.areas.size())

	# Seeded rolls meet every added pet at Lv.1 in its area.
	var unmet: Array = []
	var rolls := 0
	for item in spec.encounters:
		var cell: Vector2i = landing["%d/%d" % [int(item.map_id),int(item.area_id)]]
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000+int(item.group_id)
		var met := false
		for attempt in range(3000):
			rolls += 1
			for actor in catalog.roll(int(item.map_id),cell,rng).get("enemies",[]):
				if int(actor.template_id) == int(item.template_id) and int(actor.level) == 1 and int(actor.source_enemy_id) == int(item.enemy_id):met = true
			if met:break
		if not met:unmet.append(str(item.name))
	check(unmet.is_empty(),"seeded rolls meet every added Lv.1 pet (%d rolls in all)%s" % [rolls,"" if unmet.is_empty() else "; never met: "+"、".join(unmet)])

	# Each addition with a companion also has a group of the Lv.1 pet alone, so
	# 只进无其他敌人的遇敌 (troops of Lv.1 enemies only) meets it too.
	var lonely: Array = []
	var alone_count := 0
	for item in spec.encounters:
		if item.companion_id == null:
			if item.has("alone_group_id"):lonely.append("%s: alone already" % item.name)
			continue
		alone_count += 1
		var cell: Vector2i = landing["%d/%d" % [int(item.map_id),int(item.area_id)]]
		var area: Dictionary = catalog.area_at(int(item.map_id),cell)
		var choices: Array = area.groups.filter(func(choice):return int(choice.id) == int(item.get("alone_group_id",-1)))
		var group: Dictionary = data.groups.get(str(int(item.get("alone_group_id",-1))),{})
		var rare: Dictionary = group.get("rare",{})
		if choices.size() != 1 or int(choices[0].weight) != 1 or group.get("enemies",[]).map(func(member):return [int(member.id),int(member.weight)]) != [[int(item.enemy_id),1]] or not bool(rare.get("alone",false)) or str(rare.get("origin","")) != str(item.origin):
			lonely.append("%s: group" % item.name);continue
		var rng := RandomNumberGenerator.new()
		rng.seed = 8000+int(item.group_id)
		var met := false
		for attempt in range(3000):
			var troop: Dictionary = catalog.roll(int(item.map_id),cell,rng)
			if int(troop.get("group_id",-1)) != int(item.alone_group_id):continue
			var enemies: Array = troop.get("enemies",[])
			met = not enemies.is_empty() and enemies.size() <= 3 and enemies.all(func(actor):return int(actor.level) == 1 and int(actor.template_id) == int(item.template_id))
			if not met:lonely.append("%s: troop %s" % [item.name,enemies.size()])
			break
		if not met and not lonely.has("%s: troop" % item.name):lonely.append("%s: never met" % item.name)
	check(lonely.is_empty(),"%d added pets also come alone (only Lv.1 copies of the pet), area weight 1, marked%s" % [alone_count,"" if lonely.is_empty() else ": "+"；".join(lonely)])

	# A seeded 自动抓宠 hunt (GDScript scan) finds a Lv.1 左迪洛斯 in 五十年前波拉岛 ...
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	backend.automation.client_attached = false
	backend.encounter_rng.seed = 515151
	var cell: Vector2i = landing["500/639"]
	var started: Dictionary = backend.handle({"type":"auto_start","kind":"hunt","map_id":500,"cell":[cell.x,cell.y],"filter":{"template":302,"level_one":true,"total":-8,"offsets":[],"auto_capture":false,"limit":0,"fast":false}})
	check(started.get("ok",false),"a 左迪洛斯 Lv.1 hunt starts at 五十年前波拉岛 %s" % started.get("reason",""))
	var deadline := Time.get_ticks_msec()+120000
	while backend.automation.hunt_running and Time.get_ticks_msec() < deadline:
		backend._process(0.016)
		await process_frame
	var hit: Dictionary = backend.automation.hunt_last_hit
	var found: Dictionary = hit.get("actor",{})
	check(not found.is_empty() and int(found.template_id) == 302 and int(found.level) == 1 and found.can_capture and backend.battle_open,"the hunt meets a capturable Lv.1 左迪洛斯 after %d rolls and opens the battle" % backend.automation.hunt_rolls)
	backend.queue_free()

	# ... and the battle authority captures it (seeded battles until one
	# succeeds), its HP first shaved to 1 as 自动抓宠 does before capturing.
	var target: Dictionary = found.duplicate(true)
	if not target.is_empty():target.hp = 1
	var captured := {}
	var tries := 0
	for seed_value in range(1,200):
		if found.is_empty():break
		tries += 1
		var session = Session.new()
		var config: Dictionary = session.start_wild_battle_config({"area_id":639,"group_id":91002,"enemies":[target.duplicate(true)]})
		var battle = Battle.new()
		battle.rng_seed = seed_value
		battle.start_battle(config)
		var state: Dictionary = {}
		for turn in range(6):
			state = battle.submit_action("capture",0)
			if not bool(state.get("active",true)):break
		if str(state.get("outcome","")) == "captured" and session.apply_battle_result(state):
			captured = session.snapshot().pets[0]
			break
	check(not captured.is_empty() and str(captured.species) == "original_302" and int(captured.level) == 1 and captured.base_stats == found.base_stats,"the Lv.1 左迪洛斯 is captured (battle seed %d) with its wild stats" % tries)
	# Family completion includes original pet_flag=0 rows cloned explicitly.
	# Exercise real capture + settlement, including the unchanged -1 parameter.
	var family_failed: Array = []
	for item in spec.encounters:
		if int(item.group_id) < 91100 or int(item.group_id) > 91110:continue
		var actor_rng := RandomNumberGenerator.new()
		actor_rng.seed = 9000+int(item.template_id)
		var newborn: Dictionary = catalog.actor(int(item.enemy_id),actor_rng)
		newborn.hp = 1
		var success := false
		for seed_value in range(1,30):
			var real_session = Session.new()
			real_session.gm_raise_level(-1,120)
			real_session.gm_heal()
			var real_battle = Battle.new()
			real_battle.rng_seed = seed_value
			real_battle.start_battle(real_session.start_wild_battle_config({"area_id":int(item.area_id),"group_id":int(item.group_id),"enemies":[newborn.duplicate(true)]}))
			var result: Dictionary = real_battle.submit_action("capture",0)
			if str(result.get("outcome","")) != "captured":continue
			if not real_session.apply_battle_result(result):continue
			var pet: Dictionary = real_session.snapshot().pets[0]
			success = str(pet.species) == "original_%d" % int(item.template_id) and int(pet.level) == 1 and pet.base_stats == newborn.base_stats
			if success:break
		if not success:family_failed.append(item.name)
	check(family_failed.is_empty(),"eleven added family pets capture and settle with original newborn stats, including -1 capture parameters: %s" % str(family_failed))
	await process_frame
	print("RARE ENCOUNTERS: %d failures" % failures)
	quit(1 if failures else 0)
