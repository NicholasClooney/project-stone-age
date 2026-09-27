extends RefCounted
## Ordinary pinned-source encounters. No fallback species or invented placements.
const Rules = preload("res://server/progression.gd")
var data: Dictionary = {}
var pressure := 0
var last_error := ""

func _init(catalog: Dictionary = {}) -> void:
	data = catalog
	if data.is_empty() and FileAccess.file_exists("res://assets/legacy/encounters/catalog.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/encounters/catalog.json"))
		if parsed is Dictionary:data = parsed

func area_at(map_id: int, cell: Vector2i) -> Dictionary:
	var selected := {}
	for area in data.get("areas",[]):
		var r: Array = area.rect
		if int(area.map_id)==map_id and cell.x>=r[0] and cell.y>=r[1] and cell.x<=r[2] and cell.y<=r[3] and int(area.priority)>int(selected.get("priority",0)):
			selected = area
	return selected

func step(map_id: int, cell: Vector2i, rng: RandomNumberGenerator, is_portal := false) -> bool:
	var area := area_at(map_id,cell)
	if area.is_empty() or is_portal:return false
	pressure = clampi(pressure,clampi(int(area.probability_min),0,100),clampi(int(area.probability_max),0,100))
	var hit := rng.randi_range(0,119)<pressure
	if hit:pressure = clampi(int(area.probability_min),0,100)
	else:pressure = mini(pressure+1,int(area.probability_max))
	return hit

func _weighted(entries: Array, rng: RandomNumberGenerator) -> int:
	var total := 0
	for entry in entries:total += maxi(0,int(entry.weight))
	if total<=0:return -1
	var roll := rng.randi_range(0,total-1)
	for entry in entries:
		roll -= maxi(0,int(entry.weight))
		if roll<0:return int(entry.id)
	return -1

func roll(map_id: int, cell: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	last_error = ""
	var area := area_at(map_id,cell)
	if area.is_empty() or int(area.probability_max)<=0:return {}
	if area.get("invalid_weights",false):
		last_error = "source area %d has missing/negative group probabilities"%int(area.id)
		return {}
	if int(area.get("event_now",-1))>0 or int(area.get("event_end",-1))>0:
		last_error = "event-conditioned encounter deferred"
		return {}
	var candidates := []
	for choice in area.groups:
		var group: Dictionary = data.groups.get(str(int(choice.id)),{})
		if not group.is_empty() and int(group.requires_item)<0 and int(group.excludes_item)<0:candidates.append(choice)
	var group_id := _weighted(candidates,rng)
	if group_id<0:return {}
	var group: Dictionary = data.groups[str(group_id)]
	if group.get("invalid_weights",false):
		last_error = "source group %d has missing/negative enemy probabilities"%group_id
		return {}
	var entries := []
	var maximum := 0
	for choice in group.enemies:
		var enemy: Dictionary = data.enemies.get(str(int(choice.id)),{})
		if enemy.is_empty() or not data.templates.has(str(int(enemy.template_id))):
			last_error = "unresolved source enemy %s" % choice.id
			return {}
		entries.append(choice)
		maximum += int(enemy.max_count)
	maximum = mini(clampi(int(area.max_enemies),1,10),maximum)
	if maximum<=0:return {}
	var count := rng.randi_range(1,maximum)
	var ids := []
	var big_count := 0
	for attempt in range(100):
		if ids.size()>=count:break
		var enemy_id := _weighted(entries,rng)
		var enemy: Dictionary = data.enemies[str(enemy_id)]
		var multiplicity := 0
		for choice in entries:
			if int(choice.id)==enemy_id:multiplicity += 1
		if ids.count(enemy_id)>=int(enemy.max_count)*multiplicity:continue
		var template: Dictionary = data.templates[str(int(enemy.template_id))]
		if int(template.size)==1:
			if big_count>=5:
				count -= 1
				continue
			if ids.size()>4:
				var swap := -1
				for i in range(5):
					var prior: Dictionary = data.enemies[str(ids[i])]
					if int(data.templates[str(int(prior.template_id))].size)==0:
						swap = i
						break
				if swap<0:continue
				ids.append(ids[swap]);ids[swap] = enemy_id
			else:ids.append(enemy_id)
			big_count += 1
		else:ids.append(enemy_id)
	var actors := []
	for enemy_id in ids:actors.append(actor(enemy_id,rng))
	return {"area_id":int(area.id),"group_id":group_id,"enemies":actors}

func actor(enemy_id: int, rng: RandomNumberGenerator) -> Dictionary:
	var enemy: Dictionary = data.enemies[str(enemy_id)]
	var template: Dictionary = data.templates[str(int(enemy.template_id))]
	var level := rng.randi_range(int(enemy.level_min),int(enemy.level_max))
	var weights: Array = template.weights.duplicate()
	for i in range(4):weights[i] = int(weights[i])+rng.randi_range(-2,2)
	var initial := weights.duplicate()
	for i in range(10):initial[rng.randi_range(0,3)] += 1
	var result := {"source_enemy_id":enemy_id,"template_id":int(template.id),"species":"original_%d"%int(template.id),"name":template.name,"sprite":int(template.sprite),"level":level,"base_stats":{},"growth_weights":weights,"growth_seed":rng.randi(),"growth_rank":5,"hp":1,"learned_skills":[],"source_experience":int(enemy.experience),"can_capture":int(enemy.pet_flag)!=0,"elements":template.elements.duplicate(),"size":int(template.size)}
	if template.has("capture_resistance"):result.capture_parameter=int(template.capture_resistance)
	var total := 0
	for weight in template.weights:total += int(weight)
	for i in range(6):
		if total>=[100,95,90,85,80,0][i]:
			result.growth_rank = i
			break
	for i in range(4):result.base_stats[Rules.STATS[i]] = int(initial[i])*(int(template.initial)+(level-1)*int(template.wild_growth))
	result.reward_xp = experience(enemy,template,level,int(result.growth_rank))
	result.reward_gold = 0 # Per-enemy coins: none. Session applies pinned BATTLEGOLD once.
	Rules.refresh(result)
	result.hp = result.max_hp
	return result

func experience(enemy: Dictionary, template: Dictionary, level: int, rank: int) -> int:
	if int(enemy.experience)!=-1:return maxi(0,int(enemy.experience))
	var table: Array = data.get("experience_table",[])
	if level<1 or level>table.size():return 0
	var modifiers := int(template.get("critical",0))+int(template.get("counter",0))+int(template.get("capture_resistance",0))
	for value in template.get("resistances",[]):modifiers += int(value)
	var alpha := modifiers/100.0+float(template.get("rare",0))
	return maxi(1,int(float(table[level-1])+([2.5,2.0,1.5,1.0,0.5,0.0][clampi(rank,0,5)]+alpha)*level))
