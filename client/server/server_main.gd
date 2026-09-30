extends SceneTree
## Headless backend for remote clients, run from this same project:
##   scripts/serve.sh [--port=8781] [--bind=*] [--save=user://single-player.json]
##     [--shutdown-file=<path>]
## It loads the same save as the desktop game, ticks automation on its own and
## saves after settlements. Do not run the desktop game on the same save at the
## same time; both would write it.
## Stop it with scripts/stop-server.sh: it creates the shutdown file
## (--shutdown-file, default <save>.shutdown) and the server quits within a
## second, after recording the stop, saving and writing the restart-resume
## file. SIGTERM and SIGINT skip that (Godot runs no _finalize on them); the
## resume file kept current while a run goes on (backend.gd) covers them.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const ShutdownRequest = preload("res://server/shutdown_request.gd")

var backend
var server
var shutdown_request
var _stopped := false

func _initialize() -> void:
	var options := {"port":"8781","bind":"*","save":"user://single-player.json"}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var pair := argument.trim_prefix("--").split("=",true,1)
			options[pair[0]] = pair[1]
	backend = Backend.new()
	root.add_child(backend)
	var path := str(options.save)
	if FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"):
		if not backend.load_profile(path):
			printerr("Save %s could not be read; refusing to start so it is not overwritten." % ProjectSettings.globalize_path(path))
			quit(1)
			return
	backend.save_path = path
	backend.keep_resume_current = true
	var request_path := str(options.get("shutdown-file",path.get_basename()+".shutdown"))
	shutdown_request = ShutdownRequest.new(request_path)
	shutdown_request.clear()
	# A hunt, find-pet cycle or 自动练级 running at the last shutdown goes on.
	backend.load_resume()
	server =WsServer.new(backend,int(options.port),str(options.bind))
	if options.has("tls-cert") and options.has("tls-key"):
		var key := CryptoKey.new()
		var certificate := X509Certificate.new()
		if key.load(str(options["tls-key"]))!=OK or certificate.load(str(options["tls-cert"]))!=OK:
			printerr("Could not read TLS key or certificate.")
			quit(1)
			return
		server.tls_options = TLSOptions.server(key,certificate)
	root.add_child(server)
	var error: Error = server.start()
	if error!=OK:
		printerr("Could not listen on port %s (error %d)." % [options.port,error])
		quit(1)
		return
	print("StoneAge backend listening on %s://%s:%s, save %s" % ["wss" if server.tls_options!=null else "ws",options.bind,options.port,ProjectSettings.globalize_path(path)])
	print("Stop gracefully by creating %s (scripts/stop-server.sh)." % ProjectSettings.globalize_path(request_path))

func _process(_delta: float) -> bool:
	if shutdown_request!=null and not _stopped and shutdown_request.poll():
		print("Shutdown requested; saving and quitting.")
		_stop()
		quit(0)
	return false

func _stop() -> void:
	if _stopped or backend==null:return
	_stopped = true
	backend.shut_down()

func _finalize() -> void:
	_stop()
