extends SceneTree
const Growth = preload("res://scripts/pet_growth.gd")
const Rules = preload("res://server/progression.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures += 1
func _initialize() -> void:
	# Independent exact rational sum over 11 binomial outcomes and 51 factors.
	check(absf(Growth.expected_increment(20,5)-128.9030206343707)<0.000001,"forecast includes original per-level integer truncation")
	var pet := Rules.species_actor("wooli",1,100)
	pet.level=1;pet.species="wooli"
	var before:=pet.duplicate(true)
	var projected:=Growth.forecast(pet,120)
	check(projected.steps==119 and projected.expected.max_hp>pet.max_hp,"level120 forecast applies remaining119 growth draws")
	check(pet==before,"forecast never mutates pet or RNG seed")
	check(Growth.forecast(pet,1).expected==Rules.derived(pet.base_stats),"same-level forecast equals current source stats")
	var total:=0.0
	for seed_value in range(1000):
		var sample:=pet.duplicate(true)
		sample.growth_seed=seed_value
		Rules.grow_pet(sample,2)
		total += int(sample.base_stats.vitality)-int(pet.base_stats.vitality)
	check(absf(total/1000.0-float(projected.base_increment.vitality)*100.0)<3.0,"forecast matches1000 independent native growth samples")
	check(Growth.category({"species":"golden_tiger"})=="老虎" and Growth.category({"species":"blue_dragon"})=="人龙" and Growth.category({"species":"red_rex"})=="暴龙","collection categories distinguish requested families")
	check(Growth.species_upper("wooli",120)=={"max_hp":1346,"attack":211,"defence":231,"speed":267},"source species upper matches independent legal-allocation fixture")
	check(Growth.species_upper("wooli",1)=={"max_hp":18,"attack":2,"defence":3,"speed":3},"newborn species maximum uses plus-two rolls and only ten shared extras")
	check(Growth.species_upper("blue_dragon",120)=={"max_hp":1510,"attack":347,"defence":231,"speed":206},"rank-one species ceiling preserves per-attribute truncation at factor5.20")
	var upper:Dictionary=Growth.species_upper("wooli",120)
	var conditional:Dictionary=Growth.individual_upper(pet,120)
	for key in Rules.DERIVED:
		check(int(conditional[key])<=int(upper[key]) and int(projected.expected[key])<=int(conditional[key]),"expected <= individual ceiling <= species ceiling: "+key)
	# Wrong all-four-plus-ten model gives HP1563; actual legal maximum is1346.
	check(upper.max_hp<1563,"does not award forty growth extras where source allows ten")
	check(Growth.species_upper("wooli",140).max_hp>upper.max_hp,"level120 is comparison target, not source cap140")
	var modified:=pet.duplicate(true)
	modified.gm_modified=true
	modified.base_stats.vitality+=1000000
	var gm_forecast:=Growth.forecast(modified,120)
	check(gm_forecast.expected.max_hp>gm_forecast.species_maximum.max_hp and gm_forecast.species_maximum==upper,"GM stats can exceed natural bounds without redefining species maximum")
	check(Growth.species_upper("missing",120).is_empty(),"unknown species does not invent a theoretical maximum")
	print("PET GROWTH: %d failures" % failures)
	quit(1 if failures else 0)
