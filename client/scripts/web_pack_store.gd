extends "res://scripts/pack_store.gd"
## The web build's pack store (docs/technical/web-client.md, "Pack cache").
## user:// is IDBFS there, which the engine copies whole into memory at every
## start, so packs stay out of it:
## - web/pack_store.js keeps them in an IndexedDB database of its own and
##   answers pack downloads (tagged with its header) from there when it has
##   them, so a cached pack never reaches the network;
## - the pack being mounted is written to /tmp/packs/, plain MEMFS that is not
##   persisted, so only packs this session mounts are in memory. Godot reopens
##   a mounted pack for every file it loads, so the file stays until the page
##   closes;
## - migrate() removes what an older build left in user://packs/.
## Without the page script (an old page, or no IndexedDB) packs are simply
## downloaded every visit.

const OLD_DIR := "user://packs/"
const HEADER := "X-Stone-Age-Pack"

var _js: JavaScriptObject
## JavaScriptBridge callbacks must stay referenced until JavaScript calls them.
var _callbacks: Array = []
## Files the page's store holds (from cached_files()).
var _stored: Dictionary = {}

## A pack read from the page's store; forwards progress to the network
## request that replaces it when the stored copy turns out unusable.
class CacheRead extends RefCounted:
	var got := 0
	var request: Node
	var callback: JavaScriptObject
	func get_downloaded_bytes() -> int:
		return request.get_downloaded_bytes() if is_instance_valid(request) else got

func _init() -> void:
	dir = "/tmp/packs/"
	if OS.has_feature("web"):_js = JavaScriptBridge.get_interface("stoneAgePackStore")
	if _js==null and OS.has_feature("web"):print("[packs] no page pack store: packs are downloaded every visit")

## True when web/pack_store.js caches packs across visits.
func persistent() -> bool:
	return _js!=null

func setup() -> void:
	migrate()
	super.setup()

func cached_files(done: Callable) -> void:
	if _js==null:
		done.call([]);return
	# JavaScript calls back outside the frame; continue in it.
	var callback := JavaScriptBridge.create_callback(func(arguments: Array):
		var files = JSON.parse_string(str(arguments[0])) if not arguments.is_empty() else null
		files = files if files is Array else []
		for file in files:_stored[str(file)] = true
		done.call_deferred(files))
	_callbacks.append(callback)
	_js.list(callback)

## A stored pack is copied from the page's store straight into /tmp/packs/
## (JavaScript hands the bytes over in one piece; no HTTP request, which
## Godot advances only once a frame). Anything else is downloaded; the page
## script stores the response.
func fetch(owner: Node, url: String, file: String, bytes: int, done: Callable) -> Object:
	if _js==null or not _stored.has(file):return super.fetch(owner,url,file,bytes,done)
	var handle := CacheRead.new()
	handle.callback = JavaScriptBridge.create_callback(func(arguments: Array):
		var status := str(arguments[0]) if not arguments.is_empty() else ""
		(func():_read(owner,url,file,bytes,done,handle,status)).call_deferred())
	_js.read(file,bytes,handle.callback)
	return handle

func _read(owner: Node, url: String, file: String, bytes: int, done: Callable, handle: CacheRead, status: String) -> void:
	handle.callback = null
	if status=="ok":
		var data = JavaScriptBridge.eval("window.stoneAgePackStore.take(%s)" % JSON.stringify(file),true)
		if data is PackedByteArray and data.size()==bytes:
			var out := FileAccess.open(path(file),FileAccess.WRITE)
			if out!=null:
				out.store_buffer(data)
				out.close()
				handle.got = bytes
				done.call(true)
				return
	# Missing or damaged: download it instead (the page script stores it again).
	_stored.erase(file)
	handle.request = super.fetch(owner,url,file,bytes,done)

func headers(file: String, bytes: int) -> PackedStringArray:
	if _js==null:return PackedStringArray()
	return PackedStringArray(["%s: %s %d" % [HEADER,file,bytes]])

func remove(files: Array) -> void:
	if _js!=null and not files.is_empty():_js.remove(JSON.stringify(files))

## Deletes user://packs/ (and nothing else in user://): packs an older build
## cached there. The page script has normally deleted their IndexedDB copies
## before the engine read IDBFS; if the engine read them first, the copies in
## memory go here and IDBFS drops them at its next sync.
func migrate() -> void:
	var removed := remove_tree(OLD_DIR)
	if removed>0:print("[packs] removed %d old cached files from user://packs/" % removed)

## Deletes folder and everything in it; returns how many files it held.
static func remove_tree(folder: String) -> int:
	if not DirAccess.dir_exists_absolute(folder):return 0
	var count := 0
	for sub in DirAccess.get_directories_at(folder):count += remove_tree(folder.path_join(sub))
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
		count += 1
	DirAccess.remove_absolute(folder)
	return count
