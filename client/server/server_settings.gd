extends RefCounted
## Settings of the computer the backend runs on, not of a character: they stay
## in the backend's own user://server-settings.cfg (never the profile or a
## client's viewer.cfg). Clients change them through backend commands and read
## them from the automation status, so every device shows the same values.
##
## fast_hunt/threads: worker threads for 本机极速模式 (tools/fast_hunt); 0 lets
## the helper choose (all cores but one), otherwise 1 to the core count.
const PATH := "user://server-settings.cfg"
## Tests point this at their own file.
static var path_override := ""

static func _path() -> String:
	return path_override if not path_override.is_empty() else PATH

static func cores() -> int:
	return maxi(1,OS.get_processor_count())

static func fast_hunt_threads() -> int:
	var config := ConfigFile.new()
	if config.load(_path())!=OK:return 0
	var value = config.get_value("fast_hunt","threads",0)
	return int(value) if valid_threads(value) else 0

## An integer (a whole float, as JSON sends numbers) from 0 to the core count.
static func valid_threads(value: Variant) -> bool:
	if not (value is int or (value is float and is_finite(value) and value==floorf(value))):return false
	return int(value) >= 0 and int(value) <= cores()

## Saves the thread count; "" on success, else the reason it was refused.
static func set_fast_hunt_threads(value: Variant) -> String:
	if not valid_threads(value):return "线程数须为 0（自动）到 %d 的整数。" % cores()
	var config := ConfigFile.new()
	config.load(_path())
	config.set_value("fast_hunt","threads",int(value))
	return "" if config.save(_path())==OK else "无法保存服务器设置。"
