extends SceneTree
## 洞穴默认音乐: a cave without its own music markers plays the cave track
## while the setting is on; off, it keeps the track before it, as the
## original play_map_bgm only changes music at a marker.
const Wait = preload("res://tests/support/wait.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func playing(game) -> String:
	return str(game.music.stream.resource_path) if game.music.stream != null else ""

func go(game, map_id: int) -> bool:
	var info: Dictionary = game.world_catalog.info(map_id)
	if not game.load_area_id(map_id,Vector2i(int(info.spawn[0]),int(info.spawn[1]))):return false
	return await Wait.until(self,func():return int(game.data.map_id) == map_id and not game.area_transition_busy)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	var cave := 20701
	check(not (game.world_catalog.info(cave).get("music") is String) and str(game.world_catalog.info(cave).kind) == "dungeon","拉多拉的大洞窟 has no music markers of its own")
	check(game.cave_music and game._audio.map_music(cave) == game._audio.CAVE_MUSIC,"with 洞穴默认音乐 on (the default) it plays the cave track")
	check(game._audio.map_music(200) != game._audio.CAVE_MUSIC and game._audio.map_music(300) != game._audio.CAVE_MUSIC,"fields and 吉鲁岛 are not caves")
	check(await go(game,200),"to 加鲁卡")
	var field := playing(game)
	check(await go(game,cave),"into 拉多拉的大洞窟")
	check(playing(game).contains("sabgm_d2"),"the cave plays the cave track (%s)" % playing(game))
	game.set_cave_music(false)
	check(not game.cave_music and game._audio.map_music(cave) == "","turned off, a cave without markers has no track of its own")
	check(await go(game,200) and await go(game,cave),"field and back into the cave")
	check(playing(game) == field,"and keeps the field's track, as the original (%s)" % playing(game))
	game.set_cave_music(true)
	game.queue_free()
	await process_frame
	print("CAVE MUSIC: %d failures" % failures)
	quit(1 if failures else 0)
