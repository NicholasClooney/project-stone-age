extends RefCounted
## Forecast the original rank-based random growth distribution, never mutate a pet.
const Rules = preload("res://server/progression.gd")
# Numerators over base hundredths; optimize each output separately.
const COEFFICIENTS := {"max_hp":[4,1,1,1],"attack":[2,20,2,1],"defence":[2,2,20,1],"speed":[0,0,0,1]}
const DENOMINATORS := {"max_hp":100,"attack":2000,"defence":2000,"speed":100}
static func _best_allocation(weights:Array, factor:int, divisor:int, coefficients:Array) -> int:
	var best := 0
	# All286 legal distributions share a TOTAL of ten extras, not ten each.
	for v in range(11):
		for s in range(11-v):
			for t in range(11-v-s):
				var extras := [v,s,t,10-v-s-t]
				var score := 0
				for i in range(4):score += int((int(weights[i])+extras[i])*factor/divisor)*int(coefficients[i])
				best=maxi(best,score)
	return best
static func _weighted_base(base:Dictionary, coefficients:Array) -> int:
	var total:=0
	for i in range(4):total+=int(base[Rules.STATS[i]])*int(coefficients[i])
	return total
static func individual_upper(pet:Dictionary, target_level:int) -> Dictionary:
	var result:Dictionary={}
	var steps:=maxi(0,target_level-int(pet.level))
	var factor:=500+clampi(int(pet.growth_rank),0,5)*20
	for key in Rules.DERIVED:
		var per_level:=_best_allocation(pet.growth_weights,factor,100,COEFFICIENTS[key])
		var numerator:=_weighted_base(pet.base_stats,COEFFICIENTS[key])+steps*per_level
		result[key]=maxi(0 if key=="defence" else 1,int(numerator/int(DENOMINATORS[key]))+int(pet.get("legacy_stat_offset",{}).get(key,0)))
	return result
static func species_upper(species:String, target_level:int=120) -> Dictionary:
	var data:Dictionary=Rules.species_definition(species)
	if data.is_empty():return {}
	var total:=0
	var weights:Array=[]
	for weight in data.weights:
		total+=int(weight)
		weights.append(int(weight)+2)
	var rank:=5
	for i in range(6):
		if total >= [100,95,90,85,80,0][i]:
			rank=i
			break
	var result:Dictionary={}
	for key in Rules.DERIVED:
		var initial:=_best_allocation(weights,int(data.initial),1,COEFFICIENTS[key])
		var growth:=_best_allocation(weights,500+rank*20,100,COEFFICIENTS[key])
		result[key]=maxi(0 if key=="defence" else 1,int((initial+maxi(0,target_level-1)*growth)/int(DENOMINATORS[key])))
	return result
static func expected_increment(weight: int, rank: int) -> float:
	# Ten independent picks among four attributes: binomial(10, 1/4).
	# Average the original integer truncation over every rank-factor draw.
	var combinations := [1,10,45,120,210,252,210,120,45,10,1]
	var total := 0.0
	var low := 450+clampi(rank,0,5)*20
	for extra in range(11):
		var probability := float(combinations[extra])*pow(0.25,extra)*pow(0.75,10-extra)
		for roll in range(low,low+51):
			total += probability*int((weight+extra)*roll/100)/51.0
	return total
# Exact joint one-level moments: the four extras share ten draws and the
# rank roll is shared too. Squaring the derived weighted sum keeps covariance.
static var _moment_cache: Dictionary = {}
static func joint_moments(weights: Array, rank: int) -> Dictionary:
	var cache_key := str(weights)+":"+str(rank)
	if _moment_cache.has(cache_key):return _moment_cache[cache_key]
	var factorial := [1.0,1.0,2.0,6.0,24.0,120.0,720.0,5040.0,40320.0,362880.0,3628800.0]
	var result: Dictionary = {}
	for key in Rules.DERIVED:result[key]={"mean":0.0,"second":0.0}
	var low := 450+clampi(rank,0,5)*20
	for v in range(11):
		for s in range(11-v):
			for t in range(11-v-s):
				var extras := [v,s,t,10-v-s-t]
				var probability: float = factorial[10]/pow(4.0,10)/51.0
				for e in extras:probability/=factorial[e]
				for roll in range(low,low+51):
					var values := []
					for i in range(4):values.append(int((int(weights[i])+extras[i])*roll/100))
					for key in Rules.DERIVED:
						var value := 0.0
						for i in range(4):value+=values[i]*COEFFICIENTS[key][i]
						value/=float(DENOMINATORS[key])
						result[key].mean+=probability*value
						result[key].second+=probability*value*value
	for key in Rules.DERIVED:
		result[key]["variance"]=maxf(0.0,result[key].second-result[key].mean*result[key].mean)
	_moment_cache[cache_key]=result
	return result

static func species_average(species: String, target_level: int) -> Dictionary:
	var data: Dictionary=Rules.species_definition(species)
	if data.is_empty():return {}
	var rank := 5
	var total := 0
	for weight in data.weights:total+=int(weight)
	for i in range(6):
		if total >= [100,95,90,85,80,0][i]:
			rank=i
			break
	var expected_base: Dictionary={}
	for i in range(4):
		var mean := 0.0
		for variation in range(-2,3):mean+=expected_increment(int(data.weights[i])+variation,rank)/5.0
		expected_base[Rules.STATS[i]]=(float(data.weights[i])+2.5)*int(data.initial)+maxi(0,target_level-1)*mean
	return Rules.derived(expected_base)

static func forecast(pet: Dictionary, target_level: int = 120) -> Dictionary:
	var steps := maxi(0,target_level-int(pet.get("level",1)))
	var base: Dictionary = pet.get("base_stats",{}).duplicate(true)
	if base.is_empty() or not pet.has("growth_weights"):return {}
	var expected := base.duplicate(true)
	var lower := base.duplicate(true)
	var increment := {}
	var low := 450+clampi(int(pet.get("growth_rank",0)),0,5)*20
	for i in range(4):
		var key: String = Rules.STATS[i]
		var weight := int(pet.growth_weights[i])
		var mean := expected_increment(weight,int(pet.get("growth_rank",0)))
		expected[key] = float(base[key])+steps*mean
		lower[key] = int(base[key])+steps*int(weight*low/100)
		increment[key] = mean/100.0
	var predicted := Rules.derived(expected)
	var minimum := Rules.derived(lower)
	var maximum := individual_upper(pet,maxi(target_level,int(pet.level)))
	for key in Rules.DERIVED:
		var offset := int(pet.get("legacy_stat_offset",{}).get(key,0))
		var floor_value := 0 if key=="defence" else 1
		predicted[key] = maxi(floor_value,int(predicted[key])+offset)
		minimum[key] = maxi(floor_value,int(minimum[key])+offset)
	var moments := joint_moments(pet.growth_weights,int(pet.get("growth_rank",0)))
	var likely: Dictionary = {}
	for key in Rules.DERIVED:
		# Normal approximation to independent level draws, rounded outwards.
		# For few remaining levels the screen explicitly calls this approximate.
		var center: float = float(_weighted_base(base,COEFFICIENTS[key]))/float(DENOMINATORS[key])+steps*moments[key].mean+int(pet.get("legacy_stat_offset",{}).get(key,0))
		var radius := 1.64485362695147*sqrt(steps*moments[key].variance)
		var floor_value := 0 if key=="defence" else 1
		likely[key]=[maxi(floor_value,int(floor(center-radius))),maxi(floor_value,int(floor(center+radius)))]
		if steps==0:likely[key]=[predicted[key],predicted[key]]
	return {"likely":likely,"species_average":species_average(str(pet.get("species","")),maxi(target_level,int(pet.level))),"target_level":maxi(target_level,int(pet.get("level",1))),"expected":predicted,"minimum":minimum,"maximum":maximum,"species_maximum":species_upper(str(pet.get("species","")),maxi(target_level,int(pet.level))),"base_increment":increment,"steps":steps}
static func category(pet: Dictionary) -> String:
	match str(pet.get("species","")):
		"blue_dragon","original_92":return "人龙"
		"golden_tiger","original_194":return "老虎"
		"red_rex","mechanical_rex","original_303":return "暴龙"
		"wooli","wooli_wooli","woolistan","original_1","original_2","original_3":return "乌力"
	return "其他"
