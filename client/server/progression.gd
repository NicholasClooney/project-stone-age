extends RefCounted
## Fixed-point rules from gmsv/char/char.c and char_data.c.
const STATS := ["vitality", "strength", "toughness", "dexterity"]
const DERIVED := ["max_hp", "attack", "defence", "speed"]
const SPECIES := {
	"blue_dragon": {"initial":29,"weights":[27,36,16,20]},
	"golden_tiger": {"initial":25,"weights":[19,29,18,29]},
	"red_rex": {"initial":27,"weights":[23,37,20,25]},
	"wooli": {"initial":10,"weights":[20,12,15,25]},
	"wooli_wooli": {"initial":20,"weights":[22,23,11,23]},
	"woolistan": {"initial":15,"weights":[22,17,19,17]},
}
static var _original_templates: Dictionary = {}
static var _original_loaded := false
static func species_definition(species: String) -> Dictionary:
	if SPECIES.has(species):return SPECIES[species]
	if not species.begins_with("original_"):return {}
	var identifier := species.trim_prefix("original_")
	if not identifier.is_valid_int() or str(int(identifier))!=identifier:return {}
	if not _original_loaded:
		_original_loaded = true
		var path := "res://assets/legacy/encounters/catalog.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:_original_templates = parsed.get("templates",{})
	return _original_templates.get(identifier,{})

# Chosen legal 20-point starter distribution (9/7/0/4); creation UI deferred.
const START := {"vitality":900,"strength":700,"toughness":0,"dexterity":400}
static func derived(base: Dictionary) -> Dictionary:
	var v := int(base.vitality)
	var s := int(base.strength)
	var t := int(base.toughness)
	var d := int(base.dexterity)
	return {"max_hp":maxi(1,int((4*v+s+t+d)/100)),"attack":maxi(1,int((20*s+2*t+2*v+d)/2000)),"defence":maxi(0,int((20*t+2*s+2*v+d)/2000)),"speed":maxi(1,int(d/100))}
static func refresh(actor: Dictionary) -> void:
	var result := derived(actor.base_stats)
	var offset: Dictionary = actor.get("legacy_stat_offset",{})
	for key in DERIVED:
		actor[key] = maxi(0 if key == "defence" else 1,int(result[key])+int(offset.get(key,0)))
	actor.hp = mini(int(actor.hp),int(actor.max_hp))
static func migrate_player(actor: Dictionary) -> void:
	if actor.has("base_stats"):return
	actor.base_stats = START.duplicate()
	for key in STATS:actor.base_stats[key] += int(actor.allocated_stats[key])*100
	_preserve(actor)
static func _preserve(actor: Dictionary) -> void:
	var result := derived(actor.base_stats)
	actor.legacy_stat_offset = {}
	for key in DERIVED:actor.legacy_stat_offset[key] = int(actor[key])-int(result[key])
## offsets fixes the four birth grades (-2..+2 each; [2,2,2,2] is 满档)
## instead of rolling them; everything else is rolled as usual.
static func species_actor(species: String, level: int, seed_value: int, offsets: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data: Dictionary = species_definition(species)
	if data.is_empty():return {}
	var weights: Array = data.weights.duplicate()
	for i in range(4):
		var roll := rng.randi_range(-2,2)
		weights[i] = int(weights[i])+(int(offsets[i]) if offsets.size()==4 else roll)
	var initial: Array = weights.duplicate()
	for i in range(10):initial[rng.randi_range(0,3)] += 1
	var actor := {"base_stats":{},"growth_weights":weights,"growth_rank":5,"growth_seed":seed_value,"hp":1,"learned_skills":[]}
	var total := 0
	for weight in data.weights:total += int(weight)
	for i in range(6):
		if total >= [100,95,90,85,80,0][i]:
			actor.growth_rank = i
			break
	for i in range(4):actor.base_stats[STATS[i]] = int(int(initial[i])*(float(data.initial)+(level-1)*float(data.get("wild_growth",4.5))))
	refresh(actor)
	actor.hp = actor.max_hp
	return actor
static func grow_pet(actor: Dictionary, level: int) -> void:
	var rng := RandomNumberGenerator.new()
	# Stable per-pet/per-level draws survive saving without rerolls.
	rng.seed = int(actor.growth_seed)+level*104729
	var extra := [0,0,0,0]
	for i in range(10):extra[rng.randi_range(0,3)] += 1
	var low := 450+int(actor.growth_rank)*20
	var roll := rng.randi_range(low,low+50)
	for i in range(4):actor.base_stats[STATS[i]] += int((int(actor.growth_weights[i])+extra[i])*roll/100)
	refresh(actor)
# Exact future stats, not an estimate: grow_pet is seeded per pet and level, so
# replaying the same levels here matches later XP-driven levelling (_gain_xp).
static func project_pet(actor: Dictionary, target_level: int) -> Dictionary:
	if not actor.has("base_stats") or actor.get("growth_weights",[]).size()!=4 or not actor.has("growth_seed"):return {}
	var projected: Dictionary=actor.duplicate(true)
	for level in range(int(projected.level)+1,target_level+1):grow_pet(projected,level)
	projected.level=maxi(int(projected.level),target_level)
	return projected

static func migrate_pet(actor: Dictionary, seed_value: int) -> void:
	if actor.has("base_stats"):return
	var generated := species_actor(actor.species,1,seed_value)
	for level in range(2,int(actor.level)+1):grow_pet(generated,level)
	for key in ["base_stats","growth_weights","growth_rank","growth_seed"]:actor[key] = generated[key]
	_preserve(actor)
