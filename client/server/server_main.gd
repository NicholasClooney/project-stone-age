extends SceneTree
## Headless backend for remote clients, run from this same project:
##   scripts/serve.sh [--port=8781] [--bind=*] [--save=user://single-player.json]
## It loads the same save as the desktop game, ticks automation on its own and
## saves after settlements. Do not run the desktop game on the same save at the
## same time; both would write it.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")

var backend
var server

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

func _finalize() -> void:
	if backend==null:return
	backend.record_shutdown()
	backend.save()
