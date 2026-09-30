extends SceneTree
## Headless backend for remote clients, run from this same project:
##   scripts/serve.sh [--port=8781] [--bind=*] [--save=user://single-player.json]
##     [--accounts=user://lan/accounts.json] [--shutdown-file=<path>]
##     [--fast-threads=N]
## --fast-threads fixes this server's 本机极速模式 线程数 instead of the shared
## setting. Several servers can run side by side (one per LAN profile,
## scripts/profiles.sh); each holds `<save>.lock` so no two open the same save
## (server/save_lock.gd), and releases it when it stops. They share the
## computer's helper threads (server/fast_hunt_share.gd).
## --accounts hosts every profile of that accounts file in this one server
## (server/profile_hub.gd, docs/development/lan-profiles.md): devices log in
## with a name and PIN, each profile has its own save (and lock), and --save
## is not used. The file may be missing: the first character created from a
## client is then the admin.
## It loads the same save as the desktop game, ticks automation on its own and
## saves after settlements. Do not run the desktop game on the same save at the
## same time; both would write it.
## Stop it with scripts/stop-server.sh: it creates the shutdown file
## (--shutdown-file, default <save>.shutdown) and the server quits within a
## second, after recording the stop, saving and writing the restart-resume
## file (every profile's, with --accounts). SIGTERM and SIGINT skip that
## (Godot runs no _finalize on them); the resume file kept current while a run
## goes on (backend.gd) covers them.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const ShutdownRequest = preload("res://server/shutdown_request.gd")
const SaveLock = preload("res://server/save_lock.gd")
const FastHuntShare = preload("res://server/fast_hunt_share.gd")
const ServerSettings = preload("res://server/server_settings.gd")
const ProfileHub = preload("res://server/profile_hub.gd")

var backend
var hub
var server
var shutdown_request
var _stopped := false
var locked_path := ""

func _initialize() -> void:
	var options := {"port":"8781","bind":"*","save":"user://single-player.json"}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var pair := argument.trim_prefix("--").split("=",true,1)
			options[pair[0]] = pair[1]
	if options.has("fast-threads") and int(options["fast-threads"]) > 0:
		ServerSettings.threads_override = mini(int(options["fast-threads"]),ServerSettings.cores())
	var request_path := ""
	var what := ""
	if options.has("accounts"):
		var accounts_path := str(options.accounts)
		hub = ProfileHub.new(accounts_path)
		hub.name = "ProfileHub"
		root.add_child(hub)
		if not hub.start():
			printerr(hub.last_error)
			quit(1)
			return
		request_path = str(options.get("shutdown-file",accounts_path.get_basename()+".shutdown"))
		what = "accounts %s (%d profiles)" % [ProjectSettings.globalize_path(accounts_path),hub.accounts.profiles().size()]
	else:
		var path := str(options.save)
		var refused := SaveLock.acquire(path)
		if not refused.is_empty():
			printerr(refused)
			quit(1)
			return
		locked_path = path
		backend = Backend.new()
		root.add_child(backend)
		# Every server on this computer shares the helper threads.
		backend.automation.fast_share = FastHuntShare.new()
		if FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"):
			if not backend.load_profile(path):
				printerr("Save %s could not be read; refusing to start so it is not overwritten." % ProjectSettings.globalize_path(path))
				quit(1)
				return
		backend.save_path = path
		backend.keep_resume_current = true
		request_path = str(options.get("shutdown-file",path.get_basename()+".shutdown"))
		# A hunt, find-pet cycle or 自动练级 running at the last shutdown goes on.
		backend.load_resume()
		what = "save %s" % ProjectSettings.globalize_path(path)
	shutdown_request = ShutdownRequest.new(request_path)
	shutdown_request.clear()
	server = WsServer.new(hub if hub!=null else backend,int(options.port),str(options.bind))
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
	print("StoneAge backend listening on %s://%s:%s, %s" % ["wss" if server.tls_options!=null else "ws",options.bind,options.port,what])
	print("Stop gracefully by creating %s (scripts/stop-server.sh)." % ProjectSettings.globalize_path(request_path))

func _process(_delta: float) -> bool:
	if shutdown_request!=null and not _stopped and shutdown_request.poll():
		print("Shutdown requested; saving and quitting.")
		_stop()
		quit(0)
	return false

## Both ways out (a shutdown request, or _finalize): save, write the resume
## file, stop the helper and leave the thread share, then give up the save
## lock. With --accounts, every open profile does all of that.
func _stop() -> void:
	if _stopped:return
	_stopped = true
	if hub!=null:hub.shut_down()
	if backend!=null:
		backend.shut_down()
		backend.automation.fast_hunt.stop()
		backend.automation.fast_share.leave()
	if not locked_path.is_empty():SaveLock.release(locked_path)

func _finalize() -> void:
	_stop()
