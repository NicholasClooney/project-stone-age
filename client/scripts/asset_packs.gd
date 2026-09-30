extends Node
## On-demand original assets for builds that ship without them (the web
## build). Packs come from tools/plan_web_packs.py and build_web_packs.gd; the
## index maps maps, sprites, characters and single files to pack names.
## Packs are cached under content-hashed names, so a revisit reads a pack from
## the cache and a rebuilt pack is fetched again. Where and how is the store's
## business (scripts/pack_store.gd natively, scripts/web_pack_store.gd in a
## browser, a fake in tests); this node queues, retries each fetch with
## backoff, reports progress, mounts and prunes.
## Where assets are already present (the desktop game) nothing is enabled and
## every ensure() completes immediately.
signal progress(label: String, done_bytes: int, total_bytes: int)

const PackStore = preload("res://scripts/pack_store.gd")
const WebPackStore = preload("res://scripts/web_pack_store.gd")
## Network downloads at once.
const PARALLEL := 4
## Reads from the cache at once (no network; a web cache read is an IndexedDB read).
const PARALLEL_CACHED := 32
const RETRIES := 3

var enabled := false
var base_url := ""
var index: Dictionary = {}
## Seconds before the first retry; each further retry waits twice as long.
var retry_delay := 1.0
var store: RefCounted = PackStore.new()
var _mounted: Dictionary = {}
## File names the store holds from earlier sessions or this one's downloads.
var _cached: Dictionary = {}
var _queued: Array[String] = []
var _attempts: Dictionary = {}
var _active: Dictionary = {}
var _failed: Dictionary = {}
var _waiters: Array[Dictionary] = []
## Packs fetched over the network this session.
var downloaded_count := 0
var downloaded_bytes := 0
## Packs read from the cache this session (web: from IndexedDB into memory).
var cache_hits := 0

## pack_store: a store to use instead of the platform's (tests).
func configure(url: String, pack_store: RefCounted = null) -> void:
	enabled = true
	base_url = url if url.ends_with("/") else url+"/"
	store = pack_store if pack_store!=null else (WebPackStore.new() if OS.has_feature("web") else PackStore.new())
	store.setup()

## Fetches packs.json and lists the cache, then drops cached packs the index
## no longer names (without reading them).
func load_index(done: Callable) -> void:
	var state := {"index":null,"listed":false,"finished":false}
	var finish := func():
		if state.finished or state.index==null or not state.listed:return
		state.finished = true
		if not state.index is Dictionary:
			done.call(false);return
		index = state.index
		_prune_cache()
		done.call(true)
	store.cached_files(func(files: Array):
		for file in files:_cached[str(file)] = true
		state.listed = true
		finish.call())
	store.fetch_index(self,base_url+"packs.json?"+str(Time.get_unix_time_from_system()),func(parsed):
		state.index = parsed if parsed is Dictionary else false
		finish.call())

## True while a labelled request (one the player is waiting for) is pending.
func blocking() -> bool:
	for waiter in _waiters:
		if not str(waiter.label).is_empty():return true
	return false

func is_ready(packs: Array) -> bool:
	if not enabled:return true
	for name in packs:
		if index.get("packs",{}).has(name) and not _mounted.has(name):return false
	return true

## Calls done(true) once every known pack in packs is mounted, or done(false)
## if one still fails after retries. Unknown names are ignored.
func ensure(packs: Array, done: Callable = Callable(), label: String = "") -> void:
	var missing: Array[String] = []
	if enabled:
		for name in packs:
			var pack := str(name)
			if not index.get("packs",{}).has(pack) or _mounted.has(pack) or missing.has(pack):continue
			_failed.erase(pack)
			if _mount_local(pack):continue
			missing.append(pack)
	if missing.is_empty():
		if done.is_valid():done.call(true)
		return
	_waiters.append({"packs":missing,"done":done,"label":label})
	for pack in missing:
		if not _queued.has(pack) and not _active.values().has(pack):
			if label.is_empty():_queued.append(pack)
			else:_queued.push_front(pack)
	_pump()

## Background download with no waiter, queued after anything requested.
func prefetch(packs: Array) -> void:
	for name in packs:
		var pack := str(name)
		if enabled and index.get("packs",{}).has(pack) and not _mounted.has(pack) and not _queued.has(pack) and not _active.values().has(pack) and not _mount_local(pack):
			_queued.append(pack)
	_pump()

## For 开发者性能面板: mounted packs and their bytes (the pack files, as in
## packs.json), what this session downloaded, and what is still pending.
func stats() -> Dictionary:
	var packs: Dictionary = index.get("packs",{})
	var bytes := 0
	for pack in _mounted:bytes += int(packs.get(pack,{}).get("bytes",0))
	return {"enabled":enabled,"known":packs.size(),"mounted":_mounted.size(),"mounted_bytes":bytes,"downloaded":downloaded_count,"downloaded_bytes":downloaded_bytes,"cache_hits":cache_hits,"cached":_cached.size(),"pending":_queued.size()+_active.size(),"failed":_failed.size()}

# ---- lookups -----------------------------------------------------------------

func map_packs(map_id: int) -> Array:
	return index.get("maps",{}).get(str(map_id),[])

func sprite_pack(ident: Variant) -> String:
	return str(index.get("sprites",{}).get(str(ident),""))

func riding_pack(ident: Variant) -> String:
	return str(index.get("riding",{}).get(str(ident),""))

func character_pack(ident: Variant) -> String:
	return str(index.get("characters",{}).get(str(ident),""))

func file_pack(path: String) -> String:
	return str(index.get("files",{}).get(path,""))

func sprite_packs(idents: Array) -> Array:
	var result: Array = []
	for ident in idents:
		for pack in [sprite_pack(ident),riding_pack(ident),character_pack(ident)]:
			if not pack.is_empty() and not result.has(pack):result.append(pack)
	return result

# ---- downloads ---------------------------------------------------------------

func _pump() -> void:
	while not _queued.is_empty():
		var pack: String = _queued.front()
		if _mounted.has(pack):
			_queued.pop_front();continue
		if _active.size() >= (PARALLEL_CACHED if _is_cached(pack) else PARALLEL):break
		_queued.pop_front()
		_start(pack)
	_report()

func _is_cached(pack: String) -> bool:
	return _cached.has(str(index.packs[pack].file))

func _start(pack: String) -> void:
	var entry: Dictionary = index.packs[pack]
	var cached := _is_cached(pack)
	_active[store.fetch(self,base_url+str(entry.file),str(entry.file),int(entry.bytes),func(ok: bool):_finished(pack,ok,cached))] = pack

func _finished(pack: String, ok: bool, cached: bool) -> void:
	for handle in _active.keys():
		if _active[handle]==pack:_active.erase(handle)
	var entry: Dictionary = index.packs[pack]
	if ok:
		if cached:cache_hits += 1
		else:
			downloaded_count += 1
			downloaded_bytes += int(entry.bytes)
		_cached[str(entry.file)] = true
		ok = _mount_local(pack)
	if not ok:
		# A cached copy that failed may be damaged: fetch from the network next.
		_cached.erase(str(entry.file))
		_attempts[pack] = int(_attempts.get(pack,0))+1
		if int(_attempts[pack]) < RETRIES:
			get_tree().create_timer(retry_delay*pow(2.0,float(_attempts[pack]-1))).timeout.connect(func():
				_queued.push_front(pack);_pump())
			return
		_attempts.erase(pack)
		_failed[pack] = true
	else:_attempts.erase(pack)
	_settle()
	_pump()

func _mount_local(pack: String) -> bool:
	var file := str(index.packs[pack].file)
	if not store.has_local(file):return false
	if not ProjectSettings.load_resource_pack(store.path(file)):
		print("[packs] %s could not be mounted" % pack)
		return false
	_mounted[pack] = true
	return true

func _settle() -> void:
	for waiter in _waiters.duplicate():
		var failed := false
		var pending := false
		for pack in waiter.packs:
			if _failed.has(pack):failed = true
			elif not _mounted.has(pack):pending = true
		if failed or not pending:
			_waiters.erase(waiter)
			if waiter.done.is_valid():waiter.done.call(not failed)

func _report() -> void:
	for waiter in _waiters:
		if str(waiter.label).is_empty():continue
		var total := 0
		var done := 0
		for pack in waiter.packs:
			var bytes := int(index.packs[pack].bytes)
			total += bytes
			if _mounted.has(pack):done += bytes
			else:
				for request in _active:
					if _active[request]==pack:done += request.get_downloaded_bytes()
		progress.emit(str(waiter.label),done,total)
		return

func _process(_delta: float) -> void:
	if not _active.is_empty():_report()

func _prune_cache() -> void:
	var wanted := {}
	for entry in index.get("packs",{}).values():wanted[str(entry.file)] = true
	var stale: Array = []
	for file in _cached:
		if not wanted.has(file):stale.append(file)
	for file in stale:_cached.erase(file)
	if not stale.is_empty():
		print("[packs] dropping %d cached packs the index no longer names" % stale.size())
		store.remove(stale)
