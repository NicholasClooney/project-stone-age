extends Node
## On-demand original assets for builds that ship without them (the web
## build). Packs come from tools/plan_web_packs.py and build_web_packs.gd; the
## index maps maps, sprites, characters and single files to pack names.
## Downloads are cached in user:// under content-hashed names, so a revisit
## mounts from cache and a rebuilt pack is fetched again. Each download is
## retried with backoff before a request reports failure.
## Where assets are already present (the desktop game) nothing is enabled and
## every ensure() completes immediately.
signal progress(label: String, done_bytes: int, total_bytes: int)

const CACHE := "user://packs/"
const PARALLEL := 4
const RETRIES := 3

var enabled := false
var base_url := ""
var index: Dictionary = {}
var _mounted: Dictionary = {}
var _queued: Array[String] = []
var _attempts: Dictionary = {}
var _active: Dictionary = {}
var _failed: Dictionary = {}
var _waiters: Array[Dictionary] = []
## Packs fetched over the network this session (not mounted from the cache).
var downloaded_count := 0
var downloaded_bytes := 0

func configure(url: String) -> void:
	enabled = true
	base_url = url if url.ends_with("/") else url+"/"
	DirAccess.make_dir_recursive_absolute(CACHE)

## Fetches packs.json, then drops cached packs the index no longer names.
func load_index(done: Callable) -> void:
	var request := _new_request()
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		request.queue_free()
		var parsed = JSON.parse_string(body.get_string_from_utf8()) if result==HTTPRequest.RESULT_SUCCESS and code==200 else null
		if not parsed is Dictionary:
			print("[packs] index unavailable: result %d, HTTP %d" % [result,code])
			done.call(false);return
		index = parsed
		_prune_cache()
		done.call(true))
	if request.request(base_url+"packs.json?"+str(Time.get_unix_time_from_system()))!=OK:
		print("[packs] index request to %s could not start" % base_url)
		request.queue_free();done.call(false)

func _new_request() -> HTTPRequest:
	var request := HTTPRequest.new()
	# A browser already decodes gzip transfers; decoding again would fail.
	request.accept_gzip = not OS.has_feature("web")
	return request

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
			if _mount_cached(pack):continue
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
		if enabled and index.get("packs",{}).has(pack) and not _mounted.has(pack) and not _queued.has(pack) and not _active.values().has(pack) and not _mount_cached(pack):
			_queued.append(pack)
	_pump()

## For 开发者性能面板: mounted packs and their bytes (the pack files, as in
## packs.json), what this session downloaded, and what is still pending.
func stats() -> Dictionary:
	var packs: Dictionary = index.get("packs",{})
	var bytes := 0
	for pack in _mounted:bytes += int(packs.get(pack,{}).get("bytes",0))
	return {"enabled":enabled,"known":packs.size(),"mounted":_mounted.size(),"mounted_bytes":bytes,"downloaded":downloaded_count,"downloaded_bytes":downloaded_bytes,"pending":_queued.size()+_active.size(),"failed":_failed.size()}

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
	while _active.size() < PARALLEL and not _queued.is_empty():
		var pack: String = _queued.pop_front()
		if _mounted.has(pack):continue
		_start(pack)
	_report()

func _start(pack: String) -> void:
	var entry: Dictionary = index.packs[pack]
	var request := _new_request()
	request.download_file = CACHE+str(entry.file)+".part"
	add_child(request)
	_active[request] = pack
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):_finished(request,pack,result,code))
	var error := request.request(base_url+str(entry.file))
	if error!=OK:
		print("[packs] %s could not start: error %d" % [pack,error])
		_finished(request,pack,HTTPRequest.RESULT_CANT_CONNECT,0)

func _finished(request: HTTPRequest, pack: String, result: int, code: int) -> void:
	_active.erase(request)
	request.queue_free()
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:print("[packs] %s failed: result %d, HTTP %d" % [pack,result,code])
	var entry: Dictionary = index.packs[pack]
	var part := CACHE+str(entry.file)+".part"
	var ok := result==HTTPRequest.RESULT_SUCCESS and code==200 and FileAccess.file_exists(part) and FileAccess.get_file_as_bytes(part).size()==int(entry.bytes)
	if ok:
		DirAccess.rename_absolute(part,CACHE+str(entry.file))
		downloaded_count += 1
		downloaded_bytes += int(entry.bytes)
		ok = _mount_cached(pack)
	if not ok:
		if FileAccess.file_exists(part):DirAccess.remove_absolute(part)
		_attempts[pack] = int(_attempts.get(pack,0))+1
		if int(_attempts[pack]) < RETRIES:
			get_tree().create_timer(pow(2.0,float(_attempts[pack]-1))).timeout.connect(func():
				_queued.push_front(pack);_pump())
			return
		_attempts.erase(pack)
		_failed[pack] = true
	_settle()
	_pump()

func _mount_cached(pack: String) -> bool:
	var path := CACHE+str(index.packs[pack].file)
	if not FileAccess.file_exists(path):return false
	if not ProjectSettings.load_resource_pack(path):
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
	for file in DirAccess.get_files_at(CACHE):
		if not wanted.has(file):DirAccess.remove_absolute(CACHE+file)
