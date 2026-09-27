extends SceneTree
const Catalog = preload("res://server/encounter_catalog.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures += 1
func _initialize() -> void:
	var catalog = Catalog.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8812
	check(not catalog.data.is_empty(),"original encounter catalog imported")
	check(catalog.area_at(1000,Vector2i(80,90)).probability_max==0,"Samgir village source is safe")
	check(catalog.roll(1000,Vector2i(80,90),rng).is_empty(),"safe village never invents enemy")
	var first: Dictionary = catalog.data.areas[0].duplicate(true)
	first.rect = [10,10,20,20];first.priority=5;first.map_id=999
	var second := first.duplicate(true)
	second.id = -2;second.priority=6
	var synthetic = Catalog.new({"areas":[first,second]})
	check(synthetic.area_at(999,Vector2i(20,20)).id==-2,"inclusive source rectangle and highest z-order")
	second.priority=5
	check(synthetic.area_at(999,Vector2i(10,10)).id==first.id,"first source row wins equal-priority overlap")
	check(synthetic.area_at(999,Vector2i(21,20)).is_empty(),"one cell past rectangle excluded")
	var pressure_fixture := first.duplicate(true)
	pressure_fixture.probability_min=1;pressure_fixture.probability_max=100
	var pressure_catalog = Catalog.new({"areas":[pressure_fixture]})
	var hit_seen := false
	for i in range(100):
		pressure_catalog.pressure=100
		if pressure_catalog.step(999,Vector2i(15,15),rng):
			hit_seen=true
			check(pressure_catalog.pressure==1,"successful encounter resets source pressure to regional minimum")
			break
	check(hit_seen,"high pressure fixture exercises successful encounter reset")
	var malformed := first.duplicate(true)
	malformed.invalid_weights=true
	var malformed_catalog = Catalog.new({"areas":[malformed]})
	check(malformed_catalog.roll(999,Vector2i(15,15),rng).is_empty() and not malformed_catalog.last_error.is_empty(),"malformed source weights never silently redistribute species")
	var levels := {}
	var mixtures := false
	for i in range(200):
		var troop: Dictionary = catalog.roll(100,Vector2i(650,470),rng)
		check_troop(troop,catalog)
		var distinct := {}
		for actor in troop.get("enemies",[]):
			levels[int(actor.level)] = true
			distinct[actor.species] = true
		if distinct.size()>1:mixtures = true
	check(not levels.is_empty(),"Sainas coordinate generates source enemies")
	# Fixed actor fixture checks exact original integer arithmetic independently.
	var actor: Dictionary = catalog.actor(119,rng)
	var definition: Dictionary = catalog.data.templates[str(int(actor.template_id))]
	var factor := int(definition.initial)+(int(actor.level)-1)*int(definition.wild_growth)
	var extras := 0
	for i in range(4):
		var base := int(actor.base_stats[["vitality","strength","toughness","dexterity"][i]])
		extras += base/factor-int(actor.growth_weights[i])
	check(extras==10,"wild spawn distributes ten shared extras exactly")
	var area: Dictionary = catalog.area_at(100,Vector2i(650,470))
	catalog.pressure=100
	catalog.step(100,Vector2i(650,470),rng)
	check(catalog.pressure<=int(area.probability_max),"encounter pressure clamps to regional source range")
	check(not catalog.step(100,Vector2i(650,470),rng,true),"portal tile suppresses random encounter")
	check(catalog._weighted([{"id":1,"weight":0},{"id":2,"weight":1}],rng)==2,"zero-weight slot is never selected")
	print("ENCOUNTER CATALOG: %d failures"%failures)
	quit(1 if failures else 0)
func check_troop(troop: Dictionary, catalog) -> void:
	if troop.is_empty():
		failures += 1
		return
	var count: int = troop.enemies.size()
	if count<1 or count>10:failures += 1
	for actor in troop.enemies:
		var source: Dictionary = catalog.data.enemies[str(actor.source_enemy_id)]
		if actor.level<source.level_min or actor.level>source.level_max:failures += 1
		if actor.hp!=actor.max_hp or actor.hp<1:failures += 1
