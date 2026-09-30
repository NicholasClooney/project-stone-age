extends SceneTree
## AssetPacks (scripts/asset_packs.gd) with its store faked: the real queue,
## retries, progress, mounting (real .pck files) and pruning, over a store
## whose "network" and "cache" are dictionaries, like web/pack_store.js keeps
## packs in IndexedDB and fetches only what it lacks. Also the web store's
## migration, which must delete user://packs/ and nothing else in user://.
## docs/technical/web-client.md, "Pack cache".
const AssetPacks = preload("res://scripts/asset_packs.gd")
const WebPackStore = preload("res://scripts/web_pack_store.gd")
const SOURCE := "user://asset-packs-test/source/"
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## A request of the fake store: half the bytes after one frame, the file after three.
class FakeRequest extends Node:
	var bytes := 0
	var got := 0
	var frames := 0
	var finish: Callable
	func get_downloaded_bytes() -> int:return got
	func _process(_delta: float) -> void:
		frames += 1
		if frames==1:got = bytes/2
		elif frames==3:
			set_process(false)
			queue_free()
			finish.call()

## Stands in for web_pack_store.gd: `cache` is the IndexedDB store, `network`
## the server, `dir` the MEMFS folder packs are mounted from.
class FakeStore extends RefCounted:
	var dir := "user://asset-packs-test/mounted/"
	var index: Dictionary = {}
	var network: Dictionary = {}
	var cache: Dictionary = {}
	## file -> how many more fetches of it fail.
	var fail: Dictionary = {}
	var network_requests: Array = []
	var cache_reads: Array = []
	var removed: Array = []
	var active := 0
	var most_active := 0
	func setup() -> void:DirAccess.make_dir_recursive_absolute(dir)
	func fetch_index(_owner: Node, _url: String, done: Callable) -> void:done.call(index.duplicate(true))
	func cached_files(done: Callable) -> void:done.call(cache.keys())
	func path(file: String) -> String:return dir+file
	func has_local(file: String) -> bool:return FileAccess.file_exists(path(file))
	func remove(files: Array) -> void:
		for file in files:
			cache.erase(file);removed.append(file)
	func fetch(owner: Node, _url: String, file: String, bytes: int, done: Callable) -> Node:
		var request := FakeRequest.new()
		request.bytes = bytes
		active += 1
		most_active = maxi(most_active,active)
		var hit: bool = cache.has(file) and cache[file].size()==bytes
		if hit:cache_reads.append(file)
		else:network_requests.append(file)
		request.finish = func():
			active -= 1
			if int(fail.get(file,0))>0:
				fail[file] = int(fail[file])-1
				done.call(false);return
			var data: PackedByteArray = cache[file] if hit else network[file]
			if not hit:cache[file] = data
			var out := FileAccess.open(path(file),FileAccess.WRITE)
			out.store_buffer(data)
			out.close()
			done.call(true)
		owner.add_child(request)
		return request

## Writes a real pack holding res://asset_packs_test/<name>.txt.
func make_pack(store: FakeStore, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(SOURCE)
	var text := FileAccess.open(SOURCE+name+".txt",FileAccess.WRITE)
	text.store_string(name)
	text.close()
	var packer := PCKPacker.new()
	var pck := SOURCE+name+".pck"
	packer.pck_start(pck)
	packer.add_file("res://asset_packs_test/%s.txt" % name,SOURCE+name+".txt")
	packer.flush()
	var file := name+"-hash.pck"
	store.network[file] = FileAccess.get_file_as_bytes(pck)
	store.index.packs[name] = {"file":file,"bytes":store.network[file].size()}

func packs_node(store: FakeStore) -> Node:
	var packs = AssetPacks.new()
	packs.retry_delay = 0.01
	root.add_child(packs)
	packs.configure("http://packs.test/",store)
	return packs

func until_done(result: Dictionary, frames: int = 600) -> void:
	for i in frames:
		if result.has("ok"):return
		await process_frame

func load_index(packs: Node) -> bool:
	var result := {}
	packs.load_index(func(ok: bool):result.ok = ok)
	await until_done(result)
	return bool(result.get("ok",false))

func ensure(packs: Node, names: Array, label: String = "") -> bool:
	var result := {}
	packs.ensure(names,func(ok: bool):result.ok = ok,label)
	await until_done(result)
	return bool(result.get("ok",false))

func mounted(name: String) -> bool:
	return FileAccess.get_file_as_string("res://asset_packs_test/%s.txt" % name)==name

func run() -> void:
	await sessions()
	await retries()
	await parallel()
	migration()
	print("ASSET PACKS: %d failures" % failures)
	quit(1 if failures else 0)

## First visit downloads and stores; a second session reads from the cache and
## never touches the network; the index dropping a pack prunes it unread.
func sessions() -> void:
	var store := FakeStore.new()
	store.index = {"packs":{}}
	for name in ["core","map-1","map-2"]:make_pack(store,name)
	store.cache["gone-old.pck"] = PackedByteArray([1,2,3])
	var first := packs_node(store)
	check(await load_index(first),"the index loads")
	check(store.removed==["gone-old.pck"] and not store.cache.has("gone-old.pck"),"a cached pack the index no longer names is dropped without being read")
	var reports: Array = []
	first.progress.connect(func(label: String, done: int, total: int):reports.append([label,done,total]))
	check(await ensure(first,["core","map-1"],"核心素材"),"a miss is downloaded and mounted")
	check(mounted("core") and mounted("map-1"),"downloaded packs are mounted (their files load)")
	check(store.network_requests.size()==2 and store.cache.has("core-hash.pck") and store.cache.has("map-1-hash.pck"),"a downloaded pack is stored in the cache")
	check(first.downloaded_count==2 and first.cache_hits==0,"stats count network downloads")
	var total := int(store.index.packs.core.bytes)+int(store.index.packs["map-1"].bytes)
	var partial := reports.filter(func(r):return r[0]=="核心素材" and r[1]>0 and r[1]<r[2])
	check(not partial.is_empty() and reports.all(func(r):return r[2]==total),"progress reports bytes part way through, against the packs' total")
	first.queue_free()
	# The mounted folder is MEMFS on the web: gone after the page closes.
	for file in DirAccess.get_files_at(store.dir):DirAccess.remove_absolute(store.dir+file)
	store.network_requests.clear()
	store.index.packs.erase("map-2")
	var second := packs_node(store)
	check(await load_index(second),"the index loads again")
	check(await ensure(second,["core","map-1"],"核心素材"),"cached packs are ready")
	check(store.network_requests.is_empty() and store.cache_reads.size()==2,"a second visit reads cached packs from the store, not the network")
	check(second.cache_hits==2 and second.downloaded_count==0,"stats count cache reads apart from downloads")
	check(second.stats().cached==2,"the stats know how many packs the cache holds")
	check(await ensure(second,["core"]),"a mounted pack is ready at once")
	check(store.cache_reads.size()==2,"a mounted pack is not read again")
	second.queue_free()

## Each fetch is retried with backoff; a pack failing every time fails its waiter.
func retries() -> void:
	var store := FakeStore.new()
	store.index = {"packs":{}}
	for name in ["retry-a","retry-b"]:make_pack(store,name)
	var packs := packs_node(store)
	await load_index(packs)
	store.fail["retry-a-hash.pck"] = 2
	check(await ensure(packs,["retry-a"]),"a pack that fails twice mounts on the third try")
	check(store.network_requests.count("retry-a-hash.pck")==3 and mounted("retry-a"),"three attempts, then mounted")
	store.fail["retry-b-hash.pck"] = 3
	check(not await ensure(packs,["retry-b"]),"three failures fail the request")
	check(packs.stats().failed==1 and not packs._mounted.has("retry-b"),"the failed pack is reported")
	check(await ensure(packs,["retry-b"]),"asking again tries again")
	packs.queue_free()

## At most PARALLEL network downloads, PARALLEL_CACHED cache reads at once.
func parallel() -> void:
	var store := FakeStore.new()
	store.index = {"packs":{}}
	var names: Array = []
	for i in AssetPacks.PARALLEL_CACHED+4:
		names.append("many-%d" % i)
		make_pack(store,names[-1])
	var packs := packs_node(store)
	await load_index(packs)
	check(await ensure(packs,names),"more packs than either limit download")
	check(store.most_active==AssetPacks.PARALLEL,"no more than %d downloads at once" % AssetPacks.PARALLEL)
	packs.queue_free()
	for file in DirAccess.get_files_at(store.dir):DirAccess.remove_absolute(store.dir+file)
	store.most_active = 0
	var again := packs_node(store)
	await load_index(again)
	check(await ensure(again,names),"the same packs load from the cache")
	check(store.most_active==AssetPacks.PARALLEL_CACHED,"cache reads run %d at once" % AssetPacks.PARALLEL_CACHED)
	again.queue_free()

## The web store's migration removes the old IDBFS pack cache (user://packs/)
## and keeps everything else in user://: viewer settings, logins, saves.
func migration() -> void:
	DirAccess.make_dir_recursive_absolute("user://packs/nested")
	for file_path in ["user://packs/core-abc.pck","user://packs/map-1-def.pck.part","user://packs/nested/x","user://viewer.cfg","user://lan/accounts.json","user://packs-notes.txt"]:
		DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
		var file := FileAccess.open(file_path,FileAccess.WRITE)
		file.store_string("x")
		file.close()
	var store := WebPackStore.new()
	check(store.dir=="/tmp/packs/" and not store.dir.begins_with("user://"),"web packs are mounted from outside user:// (not IDBFS)")
	store.migrate()
	check(not DirAccess.dir_exists_absolute("user://packs"),"migration deletes user://packs/ with everything in it")
	check(FileAccess.file_exists("user://viewer.cfg") and FileAccess.file_exists("user://lan/accounts.json") and FileAccess.file_exists("user://packs-notes.txt"),"migration keeps every other file in user://")
	store.migrate()
	check(FileAccess.file_exists("user://viewer.cfg"),"running it again is harmless")
	check(store.headers("a.pck",1).is_empty(),"without the page script no header is added (packs download uncached)")
