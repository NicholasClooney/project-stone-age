extends RefCounted
## A graceful stop asked for from outside (scripts/stop-server.sh): the file at
## `path` appears, the server notices within a second, removes it and quits
## after writing everything down (server_main.gd). Godot runs no _finalize on
## SIGTERM or on SIGINT in the background, so a signal cannot do this.

const INTERVAL_MSEC := 1000

var path := ""
var clock: Callable = Time.get_ticks_msec
var _checked_msec := -1

func _init(request_path: String = "") -> void:
	path = request_path

## A request left over from before this server started is not for it.
func clear() -> void:
	if not path.is_empty() and FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## True once when the request file is there (it is removed); looks at most
## once per INTERVAL_MSEC.
func poll() -> bool:
	if path.is_empty():return false
	var now := int(clock.call())
	if _checked_msec>=0 and now-_checked_msec<INTERVAL_MSEC:return false
	_checked_msec = now
	if not FileAccess.file_exists(path):return false
	clear()
	return true
