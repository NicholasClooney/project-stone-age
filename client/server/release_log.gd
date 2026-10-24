extends RefCounted
const Clock=preload("res://scripts/clock.gd")
## A pet log file: one JSON line per entry, newest last, in its own file next
## to the save so loading the save never reads it. The backend keeps three:
## 放生记录 (<save>.release-log.jsonl, entry below), 抓宠记录
## (<save>.capture-log.jsonl, capture_entry) and 停止记录
## (<save>.stop-log.jsonl, entries from automation.gd _record_stop).
## The backend appends after each command or tick that released pets; the
## file is only read to answer the release_log command or to count its lines
## once before the first append. Over CAP + SLACK lines it is rewritten with
## the newest CAP, so a long hunt never rewrites it on every release.
## Without a file (no save, as in most tests) entries stay in memory, same cap.
##
## _count stays -1 until the first append: nothing reads the file before then.
##
## Entry: {time, pet_id, name, template_id, species, level, attack, defence,
## speed, max_hp, sum, lv120 (judged Lv120 stats when under Lv120), offsets,
## full, where (随身/仓库), source (手动/保留规则/自动整理/未达标整理),
## reason, beaten_by: [{pet_id, name, attack, defence, speed, max_hp, sum}]}.
const PetComparison = preload("res://scripts/pet_comparison.gd")
const CAP := 5000
const SLACK := 500
const MAX_PAGE := 100

var path := ""
## CAP and SLACK for this log; tests lower them.
var cap := CAP
var slack := SLACK
var _memory: Array = []
var _count := -1

## One entry for a pet about to be released. judged: the stats the release was
## decided on (the Lv120 projection for younger pets), or {} for current stats.
static func entry(pet: Dictionary, where: String, source: String, reason: String, beaten_by: Array = [], judged: Dictionary = {}) -> Dictionary:
	var quality: Dictionary = PetComparison.quality(pet)
	var result := {"time":int(Clock.unix_time()), "pet_id":str(pet.get("pet_id", "")), "name":str(pet.get("name", "")),
		"template_id":int(pet.get("template_id", -1)), "species":PetComparison.species_key(pet), "level":int(pet.get("level", 1)),
		"attack":int(pet.get("attack", 0)), "defence":int(pet.get("defence", 0)), "speed":int(pet.get("speed", 0)), "max_hp":int(pet.get("max_hp", 0)),
		"offsets":quality.get("offsets", []), "full":bool(quality.get("full", false)), "where":where, "source":source, "reason":reason, "beaten_by":beaten_by}
	result.sum = int(result.attack) + int(result.defence) + int(result.speed)
	# Starter pets carry a species name only; 同种比较's grouping gives the template.
	if int(result.template_id) < 0 and str(result.species).trim_prefix("original_").is_valid_int():result.template_id = int(str(result.species).trim_prefix("original_"))
	if int(result.level) < 120 and not judged.is_empty():
		result.lv120 = {"attack":int(judged.get("attack", 0)), "defence":int(judged.get("defence", 0)), "speed":int(judged.get("speed", 0)), "max_hp":int(judged.get("max_hp", 0))}
	return result

## One 抓宠记录 entry: the pet as it joined (level and stats at capture),
## its exact Lv120 stats (lv120), where (map id and name, cell), the source
## (找宠流程, 自动抓宠, 手动捕获, GM发放) and, for the find-pet cycle, its run id.
## Optional capture_decision is already frozen by the server before joining:
## tags, resolved thresholds, per-metric competition ranks/original maxima,
## and measured queue admission/departure data. Historical entries omit it.
static func capture_entry(pet: Dictionary, lv120: Dictionary, map_id: int, map_name: String, cell: Vector2i, source: String, run: String, decision: Dictionary = {}) -> Dictionary:
	var result := entry(pet, "", source, "", [], lv120)
	result.erase("where")
	result.erase("reason")
	result.erase("beaten_by")
	if int(result.level) >= 120:result.erase("lv120")
	if not decision.is_empty():result["capture_decision"] = decision.duplicate(true)
	result.merge({"map_id":map_id, "map_name":map_name, "cell":[cell.x, cell.y], "run":run}, true)
	return result

## A beater as the log shows it: id, name and the stats it was compared on.
static func beater(pet: Dictionary, judged: Dictionary = {}) -> Dictionary:
	var source: Dictionary = judged if not judged.is_empty() else pet
	var result := {"pet_id":str(pet.get("pet_id", "")), "name":str(pet.get("name", ""))}
	for key in ["attack", "defence", "speed", "max_hp"]:result[key] = int(source.get(key, 0))
	result.sum = int(result.attack) + int(result.defence) + int(result.speed)
	return result

func append(entries: Array) -> void:
	if entries.is_empty():return
	if path.is_empty():
		_memory.append_array(entries)
		if _memory.size() > cap + slack:_memory = _memory.slice(_memory.size() - cap)
		return
	if _count < 0:_count = _read_lines().size()
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		push_warning("放生记录无法写入 %s" % path)
		return
	file.seek_end()
	for item in entries:file.store_line(JSON.stringify(item))
	file.close()
	_count += entries.size()
	if _count > cap + slack:_rewrite_newest()

func _rewrite_newest() -> void:
	var lines := _read_lines()
	lines = lines.slice(maxi(0, lines.size() - cap))
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:return
	for line in lines:file.store_line(line)
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	_count = lines.size()

func _read_lines() -> PackedStringArray:
	if path.is_empty() or not FileAccess.file_exists(path):return PackedStringArray()
	return FileAccess.get_file_as_string(path).split("\n", false)

## All entries, oldest first.
func entries() -> Array:
	if path.is_empty():return _memory.duplicate(true)
	var result := []
	for line in _read_lines():
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:result.append(parsed)
	return result

## One page, newest first, optionally one species (template id; -1 for all)
## and one find-pet run (run id; "" for all), with the species in the log and
## their counts, and the runs newest first (up to 20) with their counts.
## sort: one of SORT_KEYS orders by that stat (the Lv120 one when the entry
## has it, as the release was judged), highest first unless ascending; ties
## stay newest first. uncaught: only hits let go before their capture
## (未捕获 · 排队已满 / 门槛已提高).
const SORT_KEYS := ["sum", "attack", "defence", "speed", "max_hp"]
func page(number: int, size: int, template_id: int = -1, run: String = "", sort: String = "", ascending: bool = false, uncaught: bool = false) -> Dictionary:
	var all := entries()
	all.reverse()
	var runs := []
	var run_index := {}
	for item in all:
		var id := str(item.get("run", ""))
		if id.is_empty():continue
		if not run_index.has(id):
			run_index[id] = runs.size()
			runs.append({"run":id, "count":0, "time":int(item.get("time", 0))})
		runs[run_index[id]].count += 1
		runs[run_index[id]].time = int(item.get("time", 0))
	var species := {}
	for item in all:
		var key := str(int(item.get("template_id", -1)))
		if not species.has(key):species[key] = {"template_id":int(item.get("template_id", -1)), "name":str(item.get("name", "")), "count":0}
		species[key].count += 1
	var chosen := all if template_id < 0 else all.filter(func(item):return int(item.get("template_id", -1)) == template_id)
	if not run.is_empty():chosen = chosen.filter(func(item):return str(item.get("run", "")) == run)
	if uncaught:chosen = chosen.filter(func(item):return bool(item.get("uncaught", false)))
	if sort in SORT_KEYS:
		var keyed := []
		for i in range(chosen.size()):keyed.append([sort_value(chosen[i], sort), i, chosen[i]])
		keyed.sort_custom(func(a, b):
			if a[0] != b[0]:return a[0] < b[0] if ascending else a[0] > b[0]
			return a[1] < b[1])
		chosen = keyed.map(func(item):return item[2])
	size = clampi(size, 1, MAX_PAGE)
	var pages := maxi(1, ceili(chosen.size() / float(size)))
	number = clampi(number, 0, pages - 1)
	return {"entries":chosen.slice(number * size, (number + 1) * size), "total":chosen.size(), "page":number, "pages":pages, "species":species.values(), "runs":runs.slice(0, 20)}

## The value an entry sorts by: its Lv120 stats when logged under Lv120.
static func sort_value(item: Dictionary, key: String) -> int:
	var stats: Dictionary = item.get("lv120", item)
	if key == "sum":return int(stats.get("attack", 0)) + int(stats.get("defence", 0)) + int(stats.get("speed", 0))
	return int(stats.get(key, 0))
