extends RefCounted
## 本机极速模式: runs the pet hunt scan in the native helper (tools/fast_hunt,
## built to build/fast_hunt) on every CPU core, for automation.gd.
##
## Every hunt roll i uses its own RandomNumberGenerator seeded with
## roll_seed(run_seed, i), in both the GDScript scan and the helper, so the two
## search the same rolls and a roll can be replayed on its own. The helper only
## searches: automation.gd re-rolls a reported hit in GDScript and acts only on
## that result. The helper exists where a C compiler built it (macOS, Linux);
## elsewhere, or if it fails, the GDScript scan runs instead.
const StatFilter = preload("res://scripts/pet_stat_filter.gd")
const METRICS := ["sum","attack","defence","speed"]
const POLL_MSEC := 100
## splitmix64 constants as signed 64-bit ints (GDScript integer arithmetic wraps).
const GAMMA := -7046029254386353131 # 0x9E3779B97F4A7C15
const MIX_1 := -4658895280553007687 # 0xBF58476D1CE4E5B9
const MIX_2 := -7723592293110705685 # 0x94D049BB133111EB

## Tests point this elsewhere (a missing path simulates no helper).
static var helper_override := ""
## A cap on worker threads for tests, so suites running side by side are not
## starved; 0 (the game) leaves the server's 线程数 setting alone.
static var threads := 0

var pid := -1
var input_path := ""
var status_path := ""
var _polled_msec := 0

## The seed of hunt roll `index`: splitmix64 of run_seed + (index+1) * gamma.
## Logical right shifts are masked because GDScript's >> is arithmetic.
static func roll_seed(run_seed: int, index: int) -> int:
	var z := run_seed + (index+1)*GAMMA
	z = (z ^ ((z >> 30) & 0x3FFFFFFFF))*MIX_1
	z = (z ^ ((z >> 27) & 0x1FFFFFFFFF))*MIX_2
	return z ^ ((z >> 31) & 0x1FFFFFFFF)

static func helper_path() -> String:
	if not helper_override.is_empty():return helper_override
	return ProjectSettings.globalize_path("res://").path_join("../build/fast_hunt").simplify_path()

## "" when the helper can run here, else why not (shown in 自动抓极品).
static func unavailable_reason() -> String:
	if OS.has_feature("web"):return "网页版在浏览器里运行，没有本机辅助程序。"
	if not OS.get_name() in ["macOS","Linux","FreeBSD"]:return "本机极速模式只支持 macOS 和 Linux。"
	if not FileAccess.file_exists(helper_path()):return "本机辅助程序未编译（需要 C 编译器，运行 scripts/build-fast-hunt.sh）。"
	return ""

static func available() -> bool:
	return unavailable_reason().is_empty()

## The thread count handed to the helper: the server's 线程数 setting
## (server_settings.gd; 0 lets the helper use all cores but one), capped by
## `threads` when a test sets it.
static func effective_threads(chosen: int) -> int:
	var count := maxi(0,chosen)
	if threads > 0:count = threads if count==0 else mini(count,threads)
	return count

func running() -> bool:
	return pid > 0

## Writes the area, filter and stat conditions and starts the helper at roll
## `start`. False when it could not start (the caller scans in GDScript).
func launch(catalog: Dictionary, area: Dictionary, filter: Dictionary, flow: bool, stat_filter_for: Callable, run_seed: int, start: int, thread_count: int = 0) -> bool:
	stop()
	var folder := "user://fast-hunt"
	DirAccess.make_dir_recursive_absolute(folder)
	var tag := "%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	input_path = ProjectSettings.globalize_path(folder.path_join(tag+".in"))
	status_path = ProjectSettings.globalize_path(folder.path_join(tag+".status"))
	var file := FileAccess.open(input_path,FileAccess.WRITE)
	if file == null:return false
	file.store_string(_input(catalog,area,filter,flow,stat_filter_for,run_seed,start,thread_count))
	file.close()
	pid = OS.create_process(helper_path(),[input_path,status_path])
	_polled_msec = 0
	if pid <= 0:
		pid = -1
		_remove_files()
		return false
	return true

## The helper's latest report, {} when there is nothing new to read yet.
## kind is progress, hit, stop or limit; "exited" when the helper ended
## without a final report.
func poll(force := false) -> Dictionary:
	if not running():return {}
	var now := Time.get_ticks_msec()
	if not force and now-_polled_msec < POLL_MSEC:return {}
	_polled_msec = now
	var report := _read()
	if report.is_empty() or str(report.kind)=="progress":
		if not OS.is_process_running(pid):
			report = _read()
			if report.is_empty() or str(report.kind)=="progress":
				pid = -1
				_remove_files()
				return {"kind":"exited"}
	if not report.is_empty() and str(report.kind)!="progress":
		pid = -1
		_remove_files()
	return report

func stop() -> void:
	if pid > 0 and OS.is_process_running(pid):OS.kill(pid)
	pid = -1
	_remove_files()

func _read() -> Dictionary:
	if status_path.is_empty() or not FileAccess.file_exists(status_path):return {}
	var parts := FileAccess.get_file_as_string(status_path).strip_edges().split(" ",false)
	if parts.size() < 8:return {}
	return {"kind":parts[0],"index":int(parts[1]),"slot":int(parts[2]),"inspected":int(parts[3]),"best":int(parts[4]),
		"predicted_rejects":int(parts[5]),"best_sum":int(parts[6]),"best_attack":int(parts[7])}

func _remove_files() -> void:
	for path in [input_path,status_path,status_path+".tmp"]:
		if not path.is_empty() and FileAccess.file_exists(path):DirAccess.remove_absolute(path)

## The helper's input: see tools/fast_hunt/fast_hunt.c. Only the candidate
## groups roll() chooses among, in the same order and with the same weights.
func _input(catalog: Dictionary, area: Dictionary, filter: Dictionary, flow: bool, stat_filter_for: Callable, run_seed: int, start: int, thread_count: int = 0) -> String:
	var lines: PackedStringArray = ["fasthunt 1","run_seed %d" % run_seed,"start %d" % start,"limit %d" % int(filter.get("limit",0)),"threads %d" % effective_threads(thread_count),"max_enemies %d" % int(area.get("max_enemies",1))]
	var groups: Array = []
	var enemy_ids := {}
	for choice in area.get("groups",[]):
		var group: Dictionary = catalog.groups.get(str(int(choice.id)),{})
		if group.is_empty() or int(group.requires_item)>=0 or int(group.excludes_item)>=0:continue
		var entries: PackedStringArray = []
		for entry in group.get("enemies",[]):
			entries.append("%d %d" % [int(entry.id),int(entry.weight)])
			enemy_ids[int(entry.id)] = true
		groups.append("%d %d %d %d %s" % [int(choice.id),int(choice.weight),1 if group.get("invalid_weights",false) else 0,group.get("enemies",[]).size()," ".join(entries)])
	lines.append("groups %d" % groups.size())
	lines.append_array(groups)
	var enemies: PackedStringArray = []
	var template_ids := {}
	for id in enemy_ids:
		var enemy: Dictionary = catalog.enemies.get(str(id),{})
		if enemy.is_empty():continue
		enemies.append("%d %d %d %d %d %d" % [id,int(enemy.template_id),int(enemy.level_min),int(enemy.level_max),int(enemy.max_count),int(enemy.pet_flag)])
		template_ids[int(enemy.template_id)] = true
	lines.append("enemies %d" % enemies.size())
	lines.append_array(enemies)
	var templates: PackedStringArray = []
	for id in template_ids:
		var template: Dictionary = catalog.templates.get(str(id),{})
		if template.is_empty():continue
		var w: Array = template.weights
		templates.append("%d %d %d %d %d %d %d %d" % [id,int(template.initial),int(template.wild_growth),int(template.size),int(w[0]),int(w[1]),int(w[2]),int(w[3])])
	lines.append("templates %d" % templates.size())
	lines.append_array(templates)
	var offsets: Array = filter.get("offsets",[])
	var has_offsets := offsets.size()==4
	var usable: Array = filter.get("usable",[])
	var usable_text: PackedStringArray = []
	for id in usable:usable_text.append(str(int(id)))
	lines.append("filter %d %d %d %d %d %d %d %d %d %s" % [int(filter.get("template",-1)),1 if bool(filter.get("level_one",true)) else 0,int(filter.get("total",-8)),
		1 if has_offsets else 0,int(offsets[0]) if has_offsets else 0,int(offsets[1]) if has_offsets else 0,int(offsets[2]) if has_offsets else 0,int(offsets[3]) if has_offsets else 0,
		usable.size()," ".join(usable_text)])
	lines.append("flow %d" % (1 if flow else 0))
	lines.append("stat_filters %d" % usable.size())
	for id in usable:
		var chosen: Dictionary = stat_filter_for.call(int(id))
		var conditions: Dictionary = chosen.get("conditions",{})
		var parts: PackedStringArray = ["%d %d %d" % [int(id),1 if StatFilter.enabled(chosen) else 0,1 if chosen.get("mode","all")=="any" else 0]]
		for metric in METRICS:
			var condition: Dictionary = conditions.get(metric,{})
			parts.append("%d %s %d" % [1 if bool(condition.get("enabled",false)) else 0,str(float(condition.get("value",0))),1 if bool(condition.get("strict",false)) else 0])
		lines.append(" ".join(parts))
	return "\n".join(lines)+"\n"
