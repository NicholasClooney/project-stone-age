extends RefCounted
## Audited original groups borrowed without moving the player. This is a
## convenience pool, never added to natural encounter or hunt catalogs.
const Art=preload("res://server/troop_art.gd")
const MapFile=preload("res://scripts/map_file.gd")
const Background=preload("res://scripts/battle_background.gd")
const FILE="res://data/training-borrow-pool.json"
static var _maps: Dictionary={}

static func should_borrow(participant: Dictionary, local_best: float) -> bool:
	# Only an actual trained carried pet. Mount/player fallback does not borrow.
	if str(participant.get("kind",""))!="pet" or int(participant.get("remaining_xp",0))<=0:return false
	return local_best<=0.0 or float(participant.remaining_xp)>5.0*local_best

static func valid_rng(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=2:return false
	for key in ["seed","state"]:
		if not value.get(key) is String or not value[key].is_valid_int() or str(int(value[key]))!=value[key]:return false
	return true

static func available(catalog, world, profile: Dictionary) -> Array:
	var result:=[]
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not parsed is Dictionary:return result
	var held: Array=profile.get("original_items",[])
	var bg=Background.new()
	for row in parsed.get("groups",[]):
		var map_id:=int(row.map_id);var info: Dictionary=world.info(map_id)
		if info.is_empty() or not world.field(map_id) or not FileAccess.file_exists(world.file(map_id)):continue
		var cell:=Vector2i(int(row.cell[0]),int(row.cell[1]))
		var area: Dictionary=catalog.area_at(map_id,cell)
		if int(area.get("id",-1))!=int(row.area_id) or int(area.get("source_line",-1))!=int(row.source.encount_line):continue
		if int(area.get("probability_max",0))<=0 or bool(area.get("invalid_weights",false)) or int(area.get("event_now",-1))>0 or int(area.get("event_end",-1))>0:continue
		if not area.get("groups",[]).any(func(choice):return int(choice.id)==int(row.group_id) and int(choice.get("weight",0))>0):continue
		var group: Dictionary=catalog.data.get("groups",{}).get(str(int(row.group_id)),{})
		if int(group.get("source_line",-1))!=int(row.source.group_line) or group.has("rare") or bool(group.get("invalid_weights",false)):continue
		var requires:=int(group.get("requires_item",-1));var excludes:=int(group.get("excludes_item",-1))
		if (requires>=0 and not requires in held) or (excludes>=0 and excludes in held):continue
		var expected_ids:=[];var actual_ids:=[];var sprites:=[];var valid:=true
		for audited in row.enemies:
			expected_ids.append(int(audited.id))
		for choice in group.get("enemies",[]):
			actual_ids.append(int(choice.id))
			var enemy: Dictionary=catalog.data.get("enemies",{}).get(str(int(choice.id)),{})
			var template: Dictionary=catalog.data.get("templates",{}).get(str(int(enemy.get("template_id",-1))),{})
			var audit: Dictionary={}
			for entry in row.enemies:
				if int(entry.id)==int(choice.id):audit=entry;break
			if audit.is_empty() or int(enemy.get("source_line",-1))!=int(audit.enemy_line) or int(template.get("source_line",-1))!=int(audit.enemybase_line) or int(template.get("id",-1))!=int(audit.template_id) or int(template.get("sprite",-1))!=int(audit.sprite):valid=false;break
			if int(enemy.get("level_min",0))!=int(audit.level_min) or int(enemy.get("level_max",0))!=int(audit.level_max) or int(enemy.level_min)<80 or int(enemy.level_max)>105 or int(enemy.get("max_count",0))<=0 or not str(enemy.get("condition","")).is_empty() or enemy.has("clone_of"):valid=false;break
			sprites.append({"sprite":int(template.sprite)})
		expected_ids.sort();actual_ids.sort()
		if not valid or actual_ids!=expected_ids or not Art.can_render(sprites):continue
		var path: String=world.file(map_id)
		if not _maps.has(path):_maps[path]=MapFile.load_map(path)
		var map_data: Dictionary=_maps[path]
		if map_data.is_empty() or cell.x<0 or cell.y<0 or cell.x>=int(map_data.width) or cell.y>=int(map_data.height):continue
		var at:=cell.y*int(map_data.width)+cell.x
		if map_data.blocked[at]!=0:continue
		var bitmap:=int(map_data.ground[at]);var fields: Array=bg.choices(bg.ground_of(bitmap))
		var textures:=[]
		for field in fields:
			var texture:=Background.ROOT+str(bg.catalog.get("backgrounds",{}).get(str(field),""))
			if not FileAccess.file_exists(texture):valid=false;break
			textures.append(texture)
		if not valid:continue
		var admitted: Dictionary=row.duplicate(true)
		admitted.area=area;admitted.ground_bitmap=bitmap;admitted.fields=fields;admitted.textures=textures
		admitted.source_music=str(info.get("music", "")) if info.get("music")!=null else ""
		result.append(admitted)
	return result

static func roll(catalog, candidates: Array, rng: RandomNumberGenerator, held: Array) -> Dictionary:
	if candidates.is_empty():return {}
	var row: Dictionary=candidates[rng.randi_range(0,candidates.size()-1)]
	var troop: Dictionary=catalog.roll_group(row.area,int(row.group_id),rng,held)
	if troop.is_empty():return {}
	var background:=rng.randi_range(0,2)
	troop.training_borrow={"map_id":int(row.map_id),"map_name":str(row.map_name),"cell":row.cell.duplicate(),"area_id":int(row.area_id),"group_id":int(row.group_id),"ground_bitmap":int(row.ground_bitmap),"field":int(row.fields[background]),"texture":str(row.textures[background]),"source_music":row.source_music}
	return troop
