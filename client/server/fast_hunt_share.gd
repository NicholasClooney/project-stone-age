extends RefCounted
## 本机极速模式 shared by every server on this computer (LAN profiles, one
## server process per profile; see docs/product/lan-multiplayer-study.md §5a
## and docs/development/lan-profiles.md). All helpers share one thread budget
## (the server's 线程数, or all cores but one), split equally among the hunts
## scanning now: budget / N each, the remainder one thread each to the longest
## running hunts, and never fewer than one.
##
## There is no daemon: each scanning hunt keeps a small file in a registry
## folder that every process of this project sees (user:// is the same for
## every checkout on the computer), refreshes it every second, and computes its
## own share from the files that are fresh. A crashed server's file goes stale
## after STALE_SECONDS and is ignored, then removed.
##
## The thread count never changes results, only speed: automation.gd restarts
## the helper from its last committed roll when its share changes.
const DEFAULT_DIR := "user://fast-hunt/active"
const BEAT_SECONDS := 1.0
const STALE_SECONDS := 5.0
const FORGET_SECONDS := 60.0
## A running helper is restarted for a new share at most this often, so a
## find-pet cycle that flips between scanning and fighting does not thrash.
const REBALANCE_SECONDS := 2.0

var dir := DEFAULT_DIR
## This hunt's registry name: the process id plus an instance id, so several
## backends in one process (tests) do not collide.
var id := ""
## Wall-clock seconds shared by every process (Time.get_unix_time_from_system);
## tests pass a fake.
var clock: Callable = Time.get_unix_time_from_system
## When this hunt joined, -1 while it is not registered.
var since := -1.0
## This hunt's share, the number of hunts sharing and the budget, as of the
## last beat.
var threads := 1
var hunters := 1
var budget := 1
var _beat_at := -INF

func _init(folder: String = DEFAULT_DIR, fake_clock: Callable = Callable(), name: String = "") -> void:
	dir = folder
	if fake_clock.is_valid():clock = fake_clock
	id = name if not name.is_empty() else "%d-%d" % [OS.get_process_id(),get_instance_id()]

## Equal shares of `budget` among `hunts` ([{id, since}]): id -> threads.
## The remainder goes one thread each to the hunts that joined first (ties by
## id); every hunt gets at least one thread.
static func split(total: int, hunts: Array) -> Dictionary:
	var result := {}
	if hunts.is_empty():return result
	var order := hunts.duplicate()
	order.sort_custom(func(a,b):return float(a.since)<float(b.since) or (float(a.since)==float(b.since) and str(a.id)<str(b.id)))
	var base := maxi(0,total)/order.size()
	var extra := maxi(0,total)%order.size()
	for i in range(order.size()):
		result[str(order[i].id)] = maxi(1,base+(1 if i<extra else 0))
	return result

func joined() -> bool:
	return since >= 0.0

## Whether the next beat is due: not registered yet, or BEAT_SECONDS passed.
func due() -> bool:
	return not joined() or float(clock.call())-_beat_at >= BEAT_SECONDS

## Registers (or refreshes) this hunt and recomputes its share from the fresh
## registrations; the caller beats when due().
func beat(total: int) -> void:
	var now := float(clock.call())
	if not joined():since = now
	_beat_at = now
	budget = maxi(1,total)
	_write({"id":id,"pid":OS.get_process_id(),"since":since,"beat":now})
	var active := hunts(now)
	threads = int(split(budget,active).get(id,budget))
	hunters = maxi(1,active.size())

## Leaves the registry: this hunt stopped scanning (or the server exits).
func leave() -> void:
	if joined():
		var path := _path(id)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	since = -1.0
	_beat_at = -INF
	threads = budget
	hunters = 1

## The fresh registrations at `now`, this hunt's own included even if its
## file could not be written. Files older than FORGET_SECONDS are removed.
func hunts(now: float) -> Array:
	var result: Array = []
	var seen := false
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):continue
		var path := dir.path_join(file)
		var json := JSON.new()
		var entry = json.data if json.parse(FileAccess.get_file_as_string(path))==OK else null
		if not entry is Dictionary or not entry.has("id") or not entry.has("beat"):continue
		var age := now-float(entry.beat)
		if age > FORGET_SECONDS:
			DirAccess.remove_absolute(path)
			continue
		if age > STALE_SECONDS:continue
		if str(entry.id)==id:
			seen = true
			entry.since = since
		result.append({"id":str(entry.id),"since":float(entry.get("since",entry.beat))})
	if joined() and not seen:result.append({"id":id,"since":since})
	return result

## For the status: {threads, budget, hunters}.
func summary() -> Dictionary:
	return {"threads":threads,"budget":budget,"hunters":hunters}

func _path(name: String) -> String:
	return dir.path_join(name+".json")

## Written to a temporary file and renamed, so a reader never sees half a file.
func _write(entry: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := _path(id)
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return
	file.store_string(JSON.stringify(entry))
	file.close()
	DirAccess.rename_absolute(path+".tmp",path)
