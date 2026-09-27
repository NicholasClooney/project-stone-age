extends SceneTree
const Hunt = preload("res://scripts/pet_hunt_rules.gd")
const Catalog = preload("res://server/encounter_catalog.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1
func _initialize() -> void:
	var data := {"templates": {"7": {"id":7,"name":"fixture", "weights":[20,30,20,25]}}, "enemies": {"1":{"template_id":7,"pet_flag":1,"max_count":1,"level_min":1,"level_max":3}}, "groups":{"1":{"enemies":[{"id":1,"weight":10}],"requires_item":-1,"excludes_item":-1}}, "areas":[{"id":1,"priority":1,"map_id":99,"rect":[0,0,10,10],"probability_max":20,"groups":[{"id":1,"weight":10}]}]}
	var actor := {"template_id":7,"can_capture":true,"level":1,"growth_weights":[22,32,22,25]}
	check(Hunt.quality(actor,data).total_offset==6,"quality uses actual hidden newborn weights against source nominal")
	check(Hunt.matches(actor,7,true,6,[],data),"sum +6 accepts legal joint quality")
	check(not Hunt.matches(actor,7,true,8,[],data),"sum +8 rejects non-perfect four-stat roll")
	check(not Hunt.matches(actor,7,true,6,[0,0,0,1],data),"per-stat floors reject weak requested stat")
	check(not Hunt.matches(actor,8,true,6,[],data),"species filter exact")
	actor.level=2
	check(not Hunt.matches(actor,7,true,6,[],data) and Hunt.matches(actor,7,false,6,[],data),"level-one optional gate")
	actor.can_capture=false
	check(not Hunt.matches(actor,7,false,6,[],data),"uncapturable actors never qualify")
	actor.can_capture=true
	actor.growth_weights=[23,32,22,25]
	check(not Hunt.quality(actor,data).valid,"out-of-source growth range fails closed")
	actor.growth_weights=[22.5,32,22,25]
	check(not Hunt.quality(actor,data).valid,"fractional edited weights fail closed")
	check(not Hunt.quality({},data).valid,"missing actor or template fails closed")
	check(is_equal_approx(Hunt.tail_probability(4),0.112) and is_equal_approx(Hunt.tail_probability(6),0.024) and is_equal_approx(Hunt.tail_probability(8),0.0016),"exact shared four-weight tail probabilities: 11.2%, 2.4%, 0.16%")
	check(Hunt.tail_probability(9)==0 and Hunt.tail_probability(-8)==1,"impossible and unrestricted quality thresholds")
	check(Hunt.tail_probability(-8,[2,2,2,2])==1.0/625.0,"four per-stat maxima form one real possible tuple")
	var catalog = Catalog.new(data)
	check(Hunt.candidates(catalog,99,Vector2i(10,10),true).size()==1,"inclusive current area enumerates capturable source species")
	check(Hunt.candidates(catalog,99,Vector2i(11,10),true).is_empty(),"outside area cannot invent target")
	data.enemies["1"].level_min=2
	check(Hunt.candidates(catalog,99,Vector2i(5,5),true).is_empty(),"level-one target cannot be created in level-two habitat")
	data.enemies["1"].level_min=1
	data.enemies["1"].pet_flag=0
	check(Hunt.candidates(catalog,99,Vector2i(5,5),true).is_empty(),"non-pet spawn omitted")
	data.enemies["1"].pet_flag=1
	data.groups["1"].invalid_weights=true
	check(Hunt.candidates(catalog,99,Vector2i(5,5),true).is_empty(),"incomplete group source weights omitted")
	data.groups["1"].invalid_weights=false
	data.groups["1"].requires_item=5
	check(Hunt.candidates(catalog,99,Vector2i(5,5),true).is_empty(),"quest/item group deferred")
	data.groups["1"].requires_item=-1
	data.groups["1"].enemies[0].weight=0
	check(Hunt.candidates(catalog,99,Vector2i(5,5),true).is_empty(),"zero weight enemy omitted")
	data.groups["1"].enemies[0].weight=10
	var upper: Dictionary=data.areas[0].duplicate(true)
	upper.priority=2;upper.probability_max=0
	data.areas.append(upper)
	check(Hunt.candidates(catalog,99,Vector2i(5,5),true).is_empty(),"higher-priority safe overlay overrides underlying habitat")
	var real = Catalog.new()
	var options: Array=Hunt.candidates(real,100,Vector2i(637,493),true)
	var ids := []
	for item in options:ids.append(int(item.id))
	check(ids.has(113) and ids.has(114),"Samgir wilderness uses source level-one 昆依 and 凯比特 habitat")
	check(Hunt.candidates(real,1000,Vector2i(80,90),true).is_empty(),"actual safe Samgir village offers no invented targets")
	var rng:=RandomNumberGenerator.new();rng.seed=27182
	var measured:=0
	for i in range(50):
		var troop: Dictionary=real.roll(100,Vector2i(637,493),rng)
		for enemy in troop.get("enemies",[]):
			var score:Dictionary=Hunt.quality(enemy,real.data)
			if score.valid:measured+=1
			else:failures+=1
	check(measured>0,"real encounter actor generation preserves source quality domain")
	print("PET HUNT RULES: %d failures"%failures)
	quit(1 if failures else 0)
