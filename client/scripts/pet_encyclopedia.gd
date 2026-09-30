extends RefCounted
## 宠物大全's data: every pet species of the encounter catalog, grouped into
## families (系), with its template stats, precomputed Lv.120 potential, wild
## locations and a teleport cell for each. Pure data in, plain dictionaries
## out; the window (scripts/pet_encyclopedia_menu.gd) only presents it.
##
## Sources: data/pet_families.json (tools/build_pet_families.py, the original
## client's pet album), data/species_potential.json
## (tools/build_species_potential.py), data/training-spots.json (verified
## landing cells) and the encounter catalog. See docs/development/pet-encyclopedia.md.
##
## The catalog also holds later pets with no original stats (tools/
## import_encounters.py, template 10000 + album number, `stats_known` false):
## their entries have stats_known false, source "8.0", rank -1 and no potential.
const FAMILIES_PATH := "res://data/pet_families.json"
const POTENTIAL_PATH := "res://data/species_potential.json"
const SPOTS_PATH := "res://data/training-spots.json"
const PETS_PATH := "res://assets/legacy/pets/catalog.json"
## The classic pets players remember (docs/product/classic-pets.md).
const CLASSIC_PATH := "res://data/classic-pets.json"
## 宠物大全's ownership filter values.
const OWNERSHIP := ["all","owned","unowned"]
const SpecialPets = preload("res://scripts/special_pets.gd")
const PetComparison = preload("res://scripts/pet_comparison.gd")
## Growth rank from the template's weight sum (progression.gd species_actor):
## rank r levels up with a roll of 450+20r to 500+20r percent.
const RANK_LIMITS := [100,95,90,85,80,0]
const WEIGHT_NAMES := ["体力","腕力","耐力","速度"]
const ELEMENT_NAMES := ["地","水","火","风"]
## List columns that sort (key -> caption); "sum" is the default, highest first.
const SORT_KEYS := {"name":"名字","family":"系","sum":"三围合","top01":"前0.1%","attack":"攻","defence":"防","speed":"敏","hp":"血","rank":"成长级","catchable":"可抓","where":"出现"}

## Entry id (the representative template) -> entry dictionary.
var species: Dictionary = {}
## Entry ids in album order (family by family).
var order: Array = []
## [{id, name, species: [entry ids]}] in album order.
var families: Array = []
## Any template id of a pet -> its entry id.
var by_template: Dictionary = {}
## The classic list in its file's order: each record as in classic-pets.json
## plus entry_id (-1 when our data has no such pet).
var classic: Array = []
## [{id, name}] classic categories in display order.
var classic_categories: Array = []

static var _shared = null

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed != null else {}

## The game's encyclopedia, built once from the shipped data files.
static func shared(catalog: Dictionary, maps: Dictionary):
	if _shared == null:
		var spots: Dictionary = read_json(SPOTS_PATH)
		_shared = new(catalog,read_json(FAMILIES_PATH),read_json(POTENTIAL_PATH),spots.get("spots",[]),maps,read_json(PETS_PATH))
		_shared.load_classic(read_json(CLASSIC_PATH))
	return _shared

## catalog: the encounter catalog data; family_data / potential: the two data
## files; spots: training-spots.json spots; maps: world manifest maps (names);
## pets: pets/catalog.json (aliases of the starter species).
func _init(catalog: Dictionary, family_data: Dictionary = {}, potential: Dictionary = {}, spots: Array = [], maps: Dictionary = {}, pets: Dictionary = {}) -> void:
	var templates: Dictionary = catalog.get("templates",{})
	var aliases := _aliases(pets)
	var landing := {}
	for spot in spots:landing["%d/%d" % [int(spot.map_id),int(spot.area_id)]] = spot.cell
	var rows := _wild_rows(catalog)
	var placed := {}
	var groups: Array = family_data.get("families",[]).duplicate(true)
	var loose: Array = []
	for group in groups:
		for id in group.get("templates",[]):placed[int(id)] = true
	for key in templates:
		if int(templates[key].get("pet_flag",0)) != 0 and not placed.has(int(key)):loose.append(int(key))
	if not loose.is_empty():
		loose.sort()
		groups.append({"id":999,"name":"其他","templates":loose})
	for group in groups:
		var family := {"id":int(group.get("id",0)),"name":str(group.get("name","")),"species":[]}
		var signatures := {}
		for raw in group.get("templates",[]):
			var template: Dictionary = templates.get(str(int(raw)),{})
			if template.is_empty() or int(template.get("pet_flag",0)) == 0 or by_template.has(int(raw)):continue
			var signature := "%s|%s|%s|%s|%s" % [template.name,template.sprite,template.get("initial",""),template.get("weights",[]),template.get("wild_growth",4)]
			if signatures.has(signature):
				species[signatures[signature]].ids.append(int(raw))
				continue
			var entry := _entry(template,family)
			signatures[signature] = entry.id
			species[entry.id] = entry
			family.species.append(entry.id)
		for entry_id in family.species:_finish(species[entry_id],rows,landing,maps,potential,aliases)
		# The representative may have changed: re-key by it.
		var keyed: Array = []
		for entry_id in family.species:
			var entry: Dictionary = species[entry_id]
			if entry.id != entry_id:
				species.erase(entry_id)
				species[entry.id] = entry
			keyed.append(entry.id)
			for id in entry.ids:by_template[int(id)] = entry.id
		family.species = keyed
		if not keyed.is_empty():
			families.append(family)
			order.append_array(keyed)
	# Species sharing a name (巴朵兰恩 303 and its stronger 724) carry their
	# template number so the grid and variants can tell them apart.
	var named := {}
	for id in order:named[species[id].name] = int(named.get(species[id].name,0))+1
	for id in order:species[id].tag = "#%d" % int(id) if int(named[species[id].name]) > 1 else ""

func _entry(template: Dictionary, family: Dictionary) -> Dictionary:
	if not bool(template.get("stats_known",true)):
		return {"id":int(template.id),"ids":[int(template.id)],"name":str(template.name),"sprite":int(template.sprite),"family":family.id,"family_name":family.name,
			"stats_known":false,"source":str(template.get("source","")),"album":int(template.get("album",-1)),
			"initial":0,"raw_growth":"","wild_growth":0,"weights":[],"weight_sum":0,"rank":-1,"elements":[0,0,0,0],"capture_resistance":0,"alias":""}
	var weights: Array = template.get("weights",[0,0,0,0]).map(func(value):return int(value))
	var total := 0
	for weight in weights:total += int(weight)
	var rank := 5
	for i in range(RANK_LIMITS.size()):
		if total >= int(RANK_LIMITS[i]):
			rank = i
			break
	return {"id":int(template.id),"ids":[int(template.id)],"name":str(template.name),"sprite":int(template.sprite),"family":family.id,"family_name":family.name,
		"initial":int(template.initial),"raw_growth":str(template.get("raw_growth",template.get("wild_growth",4))),"wild_growth":int(template.get("wild_growth",4)),
		"weights":weights,"weight_sum":total,"rank":rank,"elements":template.get("elements",[0,0,0,0]).map(func(value):return int(value)),
		"capture_resistance":int(template.get("capture_resistance",0)),"alias":"","stats_known":true,"source":str(template.get("source",""))}

## Locations, catchability and potential once all merged templates are known.
## The representative is the merged template seen most in the wild (then the
## lowest id), so 红暴 is 303 like the starter and GM lists.
func _finish(entry: Dictionary, rows: Dictionary, landing: Dictionary, maps: Dictionary, potential: Dictionary, aliases: Dictionary) -> void:
	var best: int = entry.ids[0]
	for id in entry.ids:
		var count: int = rows.get(int(id),[]).size()
		var best_count: int = rows.get(best,[]).size()
		if count > best_count or (count == best_count and int(id) < best):best = int(id)
	entry.id = best
	var by_area := {}
	for id in entry.ids:
		for row in rows.get(int(id),[]):
			var key := "%d/%d" % [int(row.map_id),int(row.area_id)]
			if not by_area.has(key):
				var info: Dictionary = maps.get(str(int(row.map_id)),{})
				var cell: Array = landing.get(key,[])
				by_area[key] = {"map_id":int(row.map_id),"area_id":int(row.area_id),"map_name":str(info.get("name","")),"imported":not info.is_empty(),
					"template_id":int(id),"level_min":int(row.level_min),"level_max":int(row.level_max),"capturable":bool(row.capturable),"cell":cell.duplicate()}
			else:
				var place: Dictionary = by_area[key]
				place.level_min = mini(int(place.level_min),int(row.level_min))
				place.level_max = maxi(int(place.level_max),int(row.level_max))
				if bool(row.capturable) and not place.capturable:
					place.capturable = true
					place.template_id = int(id)
	var places: Array = by_area.values()
	for place in places:place.reason = _travel_reason(place)
	places.sort_custom(func(a,b):
		if a.capturable != b.capturable:return a.capturable
		if a.reason.is_empty() != b.reason.is_empty():return a.reason.is_empty()
		if int(a.level_min) != int(b.level_min):return int(a.level_min) < int(b.level_min)
		if int(a.map_id) != int(b.map_id):return int(a.map_id) < int(b.map_id)
		return int(a.area_id) < int(b.area_id))
	entry.locations = places
	entry.catchable = places.any(func(place):return place.capturable)
	entry.wild_lowest = 0
	for place in places:
		if place.capturable and (entry.wild_lowest == 0 or int(place.level_min) < int(entry.wild_lowest)):entry.wild_lowest = int(place.level_min)
	var data: Dictionary = {}
	for id in [entry.id]+entry.ids:
		data = potential.get("species",{}).get(str(int(id)),{})
		if not data.is_empty():break
	entry.potential = data.get("lv1",{})
	entry.wild_potential = data.get("wild",{})
	for id in [entry.id]+entry.ids:
		if aliases.has(int(id)):
			entry.alias = aliases[int(id)]
			break

static func _travel_reason(place: Dictionary) -> String:
	if not place.capturable:return "这里的不可捕获"
	if not place.imported:return "地图未导入"
	if place.cell.size() != 2:return "该区域敌群缺素材，暂不能传送"
	return ""

## Names players use: 蓝人龙 and the other starters, 机暴, 年兽 and the rest
## of the GM special-pet list.
static func _aliases(pets: Dictionary) -> Dictionary:
	var result := {}
	for entry in SpecialPets.LIST:
		var caption := str(entry[1])
		if caption.contains(" · "):result[int(entry[0])] = caption.get_slice(" · ",0)
	for key in pets:
		var pet = pets[key]
		if pet is Dictionary and pet.has("template_id") and not str(pet.get("alias","")).is_empty():result[int(pet.template_id)] = str(pet.alias)
	return result

## Attaches the classic list (classic-pets.json): each found entry gets
## `classic` (its record) and, when it has no player name yet, the record's
## 俗称 as alias; records whose template is missing keep entry_id -1.
func load_classic(data: Dictionary) -> void:
	classic.clear()
	classic_categories = data.get("categories",[]).duplicate(true)
	for raw in data.get("pets",[]):
		var record: Dictionary = raw.duplicate(true)
		var template = record.get("template_id",null)
		var entry: Dictionary = entry_for(int(template)) if template != null else {}
		record.entry_id = int(entry.id) if not entry.is_empty() else -1
		if not entry.is_empty() and not entry.has("classic"):
			entry.classic = record
			if str(entry.alias).is_empty():entry.alias = str(record.get("alias",""))
		classic.append(record)

## Every ordinary wild row per template: the same areas and groups the hunt
## uses (pet_hunt_rules.gd candidates), capturable or not.
static func _wild_rows(catalog: Dictionary) -> Dictionary:
	var result := {}
	var groups: Dictionary = catalog.get("groups",{})
	var enemies: Dictionary = catalog.get("enemies",{})
	var templates: Dictionary = catalog.get("templates",{})
	for area in catalog.get("areas",[]):
		if int(area.get("probability_max",0)) <= 0 or area.get("invalid_weights",false):continue
		if int(area.get("event_now",-1)) > 0 or int(area.get("event_end",-1)) > 0:continue
		for choice in area.get("groups",[]):
			if int(choice.get("weight",0)) <= 0:continue
			var group: Dictionary = groups.get(str(int(choice.id)),{})
			if group.is_empty() or group.get("invalid_weights",false):continue
			if int(group.get("requires_item",-1)) >= 0 or int(group.get("excludes_item",-1)) >= 0:continue
			var valid := true
			for entry in group.get("enemies",[]):
				var enemy: Dictionary = enemies.get(str(int(entry.id)),{})
				if enemy.is_empty() or not templates.has(str(int(enemy.get("template_id",-1)))):valid = false
			if not valid:continue
			for entry in group.get("enemies",[]):
				var enemy: Dictionary = enemies[str(int(entry.id))]
				var low := int(enemy.get("level_min",0))
				var high := int(enemy.get("level_max",0))
				if int(entry.get("weight",0)) <= 0 or int(enemy.get("max_count",0)) <= 0 or low < 1 or high < low:continue
				var id := int(enemy.template_id)
				if not result.has(id):result[id] = []
				result[id].append({"map_id":int(area.map_id),"area_id":int(area.id),"level_min":low,"level_max":high,"capturable":int(enemy.get("pet_flag",0)) != 0})
	return result

# ---- queries -----------------------------------------------------------------

## The wild areas of one map where a pet can be met and caught at Lv.1, from
## the same locations as 野外出现地点: [{area_id, cell (verified landing, or
## [] when none), names: [pet names in album order]}], by area id.
func level_one_areas(map_id: int) -> Array:
	var by_area := {}
	for id in order:
		var entry: Dictionary = species[id]
		for place in entry.get("locations",[]):
			if int(place.map_id) != map_id or not place.capturable or int(place.level_min) > 1:continue
			var area := int(place.area_id)
			if not by_area.has(area):by_area[area] = {"area_id":area,"cell":place.cell.duplicate(),"names":[]}
			var name := str(entry.name)
			if not by_area[area].names.has(name):by_area[area].names.append(name)
	var result: Array = by_area.values()
	result.sort_custom(func(a,b):return int(a.area_id) < int(b.area_id))
	return result

func entry_for(template_id: int) -> Dictionary:
	return species.get(by_template.get(template_id,-1),{})

## The entry of a pet the player owns (starters count as their templates).
func entry_for_pet(pet: Dictionary) -> Dictionary:
	var key := PetComparison.species_key(pet)
	if not key.begins_with("original_"):return {}
	var id := key.trim_prefix("original_")
	return entry_for(int(id)) if id.is_valid_int() else {}

## Entry ids whose name or alias contains text (all when empty), optionally
## only species that can be caught in the wild, only classic ones, and only
## ones the player owns ("owned") or not ("unowned"; owned is owned_counts),
## in album order.
func filtered(text: String = "", catchable_only: bool = false, classic_only: bool = false, ownership: String = "all", owned: Dictionary = {}) -> Array:
	var wanted := text.strip_edges()
	var result: Array = []
	for id in order:
		var entry: Dictionary = species[id]
		if catchable_only and not entry.catchable:continue
		if classic_only and not entry.has("classic"):continue
		if not _owned_matches(owned.has(id),ownership):continue
		if not wanted.is_empty() and not _matches(entry,wanted):continue
		result.append(id)
	return result

static func _owned_matches(has: bool, ownership: String) -> bool:
	return ownership == "all" or (ownership == "owned") == has

static func _matches(entry: Dictionary, wanted: String) -> bool:
	for text in [entry.name,entry.alias,entry.family_name,entry.get("classic",{}).get("alias","")]:
		if str(text).contains(wanted):return true
	return false

## The classic records to show, in the file's order, with the same filters as
## filtered. A record our data lacks (entry_id -1) is never owned or
## catchable, and is matched on its own name, 俗称 and family.
func classic_filtered(text: String = "", catchable_only: bool = false, ownership: String = "all", owned: Dictionary = {}) -> Array:
	var wanted := text.strip_edges()
	var result: Array = []
	for record in classic:
		var id := int(record.entry_id)
		if id < 0:
			if catchable_only or ownership == "owned":continue
			if not wanted.is_empty() and not [record.name,record.get("alias",""),record.get("family","")].any(func(value):return str(value).contains(wanted)):continue
		else:
			var entry: Dictionary = species[id]
			if catchable_only and not entry.catchable:continue
			if not _owned_matches(owned.has(id),ownership):continue
			if not wanted.is_empty() and not _matches(entry,wanted) and not str(record.name).contains(wanted):continue
		result.append(record)
	return result

## The value a list column sorts by (bigger is better; see ranked).
static func sort_value(entry: Dictionary, key: String) -> Variant:
	var potential: Dictionary = entry.get("potential",{})
	match key:
		"name":return str(entry.name)
		"family":return int(entry.family)
		"sum":return float(potential.get("mean_sum",-1.0))
		"top01":return int(potential.get("top01",-1))
		"attack":return float(potential.get("mean_attack",-1.0))
		"defence":return float(potential.get("mean_defence",-1.0))
		"speed":return float(potential.get("mean_speed",-1.0))
		"hp":return float(potential.get("mean_hp",-1.0))
		"rank":return -int(entry.rank) if int(entry.rank) >= 0 else -100
		"catchable":return 1 if entry.catchable else 0
		"where":return -int(entry.wild_lowest) if int(entry.wild_lowest) > 0 else -100000
	return 0

## ids sorted by one column in its natural order: numbers best first (成长级 0
## before 5, the lowest wild level first), names and families in album/A-Z
## order; reverse flips it. Ties fall back to 三围合 (highest first), then
## the template id.
static func ranked(entries: Dictionary, ids: Array, key: String = "sum", reverse: bool = false) -> Array:
	var result := ids.duplicate()
	var ascending := key == "name" or key == "family"
	result.sort_custom(func(a, b):
		var x = sort_value(entries[a],key)
		var y = sort_value(entries[b],key)
		if x != y:return ((x < y) if ascending else (x > y)) != reverse
		var sx: float = sort_value(entries[a],"sum")
		var sy: float = sort_value(entries[b],"sum")
		if sx != sy:return sx > sy
		return int(a) < int(b))
	return result

## How many pets of each entry the player has: {entry id: {carried, stored}}.
func owned_counts(profile: Dictionary) -> Dictionary:
	var result := {}
	for location in ["pets","pet_storage"]:
		for pet in profile.get(location,[]):
			var entry := entry_for_pet(pet)
			if entry.is_empty():continue
			if not result.has(entry.id):result[entry.id] = {"carried":0,"stored":0}
			result[entry.id]["carried" if location == "pets" else "stored"] += 1
	return result

## The player's pets of one entry and their best Lv.120 三围合 and attack
## (exact projections, PetComparison.expected): {count, best_sum, best_sum_pet,
## best_attack, best_attack_pet}.
func owned_best(profile: Dictionary, entry: Dictionary) -> Dictionary:
	var result := {"count":0,"best_sum":-1,"best_sum_pet":"","best_attack":-1,"best_attack_pet":""}
	for location in ["pets","pet_storage"]:
		for pet in profile.get(location,[]):
			var own := entry_for_pet(pet)
			if own.is_empty() or own.id != entry.id:continue
			result.count += 1
			var stats: Dictionary = PetComparison.expected(pet)
			var total := int(stats.get("attack",0))+int(stats.get("defence",0))+int(stats.get("speed",0))
			if total > int(result.best_sum):
				result.best_sum = total
				result.best_sum_pet = str(pet.get("name",""))
			if int(stats.get("attack",0)) > int(result.best_attack):
				result.best_attack = int(stats.get("attack",0))
				result.best_attack_pet = str(pet.get("name",""))
	return result

## The location 瞬移去抓 in the list uses: the first reachable one where it is
## caught, preferring Lv.1 (locations are already in that order).
static func best_location(entry: Dictionary) -> Dictionary:
	var fallback := {}
	for place in entry.get("locations",[]):
		if not str(place.reason).is_empty():continue
		if int(place.level_min) <= 1:return place
		if fallback.is_empty():fallback = place
	return fallback

## One line about where the species lives, for the list and the grid tooltip.
static func where_text(entry: Dictionary) -> String:
	var places: Array = entry.get("locations",[])
	if places.is_empty():return "无野外出现"
	if not entry.catchable:return "野外出现，不可捕获"
	var maps := {}
	for place in places:
		if place.capturable:maps[str(place.map_name) if not str(place.map_name).is_empty() else str(place.map_id)] = true
	var lowest := int(entry.wild_lowest)
	var head := "Lv.1起" if lowest <= 1 else "野生最低 Lv.%d" % lowest
	return "%s · %s" % [head,"、".join(maps.keys().slice(0,2))+("等%d处" % maps.size() if maps.size() > 2 else "")]

## The classic list's line about catching it: where here, or why not.
static func classic_where_text(record: Dictionary, entry: Dictionary) -> String:
	if entry.is_empty():return "资料里没有这只宠物"
	if entry.catchable:return where_text(entry)
	if not bool(record.get("original_wild",true)):return "原版不能野外捕捉 · "+str(record.get("obtained",""))
	return where_text(entry)+" · 原版可野外捕捉"

static func rank_text(rank: int) -> String:
	if rank < 0:return "未知"
	return "%d级（权重和≥%d）" % [rank,int(RANK_LIMITS[clampi(rank,0,5)])] if rank < 5 else "5级（权重和<80）"

## What 瞬移去抓 does for a location: the cell and the hunt target, or an error.
static func catch_plan(place: Dictionary) -> Dictionary:
	var reason := str(place.get("reason",""))
	if not reason.is_empty():return {"error":reason}
	return {"map_id":int(place.map_id),"area_id":int(place.area_id),"cell":Vector2i(int(place.cell[0]),int(place.cell[1])),"template_id":int(place.template_id),"level_one":int(place.level_min) <= 1}
