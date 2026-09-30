extends RefCounted
## Where AssetPacks (scripts/asset_packs.gd) keeps pack files and how it gets
## them: the shell around its queue. This one is for native builds started with
## --asset-packs: each pack is downloaded straight into user://packs/, which is
## also the cache across runs. scripts/web_pack_store.gd keeps packs out of
## user:// in a browser. Tests replace the store with a fake.

var dir := "user://packs/"

## Before the first request.
func setup() -> void:
	DirAccess.make_dir_recursive_absolute(dir)

## Calls done(files) with the file names kept from earlier sessions, including
## leftovers the index may no longer name.
func cached_files(done: Callable) -> void:
	done.call(Array(DirAccess.get_files_at(dir)))

## Fetches the pack index and calls done(parsed), null when unavailable.
func fetch_index(owner: Node, url: String, done: Callable) -> void:
	var request := make_request()
	owner.add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		request.queue_free()
		var parsed = JSON.parse_string(body.get_string_from_utf8()) if result==HTTPRequest.RESULT_SUCCESS and code==200 else null
		if not parsed is Dictionary:print("[packs] index unavailable: result %d, HTTP %d" % [result,code])
		done.call(parsed if parsed is Dictionary else null))
	if request.request(url)!=OK:
		print("[packs] index request to %s could not start" % url)
		request.queue_free()
		done.call(null)

## Where the pack file is mounted from.
func path(file: String) -> String:
	return dir+file

## True when the file can be mounted without fetching it.
func has_local(file: String) -> bool:
	return FileAccess.file_exists(path(file))

## Starts fetching url into path(file) and calls done(ok) once the file is
## complete (bytes long) or the request failed. Returns the request, which
## reports get_downloaded_bytes() for progress.
func fetch(owner: Node, url: String, file: String, bytes: int, done: Callable) -> Object:
	var request := make_request()
	var part := path(file)+".part"
	request.download_file = part
	owner.add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
		request.queue_free()
		var size := file_size(part)
		var ok := result==HTTPRequest.RESULT_SUCCESS and code==200 and size==bytes
		if ok:ok = DirAccess.rename_absolute(part,path(file))==OK
		else:print("[packs] %s failed: result %d, HTTP %d, %d of %d bytes" % [file,result,code,size,bytes])
		if not ok and FileAccess.file_exists(part):DirAccess.remove_absolute(part)
		done.call(ok))
	var error := request.request(url,headers(file,bytes))
	if error!=OK:
		print("[packs] %s could not start: error %d" % [file,error])
		(func():
			request.queue_free()
			done.call(false)).call_deferred()
	return request

func headers(_file: String, _bytes: int) -> PackedStringArray:
	return PackedStringArray()

## Forgets cached files (names from cached_files()).
func remove(files: Array) -> void:
	for file in files:DirAccess.remove_absolute(dir+str(file))

static func make_request() -> HTTPRequest:
	var request := HTTPRequest.new()
	# A browser already decodes gzip transfers; decoding again would fail.
	request.accept_gzip = not OS.has_feature("web")
	# The default 64 KiB is read once per frame (about 4 MB/s at 60 fps), so a
	# 30 MB core pack took seconds even from localhost.
	request.download_chunk_size = 4*1024*1024
	return request

static func file_size(file_path: String) -> int:
	var file := FileAccess.open(file_path,FileAccess.READ)
	return -1 if file==null else int(file.get_length())
