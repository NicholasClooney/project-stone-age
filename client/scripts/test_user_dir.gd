extends Node
## Test isolation: scripts/run.sh starts every test suite with
## STONE_AGE_TEST_USER_DIR set, and this autoload then points user:// at that
## folder (relative to the OS data folder, for example
## ~/Library/Application Support/Godot/app_userdata/Stone Age tests/<checkout>)
## before the suite's run() starts. Suites in different checkouts and parallel
## suites of one test-all run then never share files, and none of them writes
## next to the real game's save. The game and the server never set the
## variable, so they keep the real user:// folder.

func _init() -> void:
	var folder := OS.get_environment("STONE_AGE_TEST_USER_DIR")
	if folder.is_empty():return
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name",folder)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())

func _ready() -> void:
	queue_free()
