extends SceneTree
## The web build's waiting screen: short waits never show it, a longer wait
## shows it with the bar following AssetPacks.progress, the game's music pauses
## while it is up and resumes after, startup holds and failures keep it up, and
## the in-process game never creates it.
const AssetPacks = preload("res://scripts/asset_packs.gd")
const WaitingScreen = preload("res://scripts/waiting_screen.gd")
const MB := 1048576
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## A labelled request the player waits for, as ensure() records it.
func wait_for(packs: Node, pack: String, label: String) -> Dictionary:
	var waiter := {"packs":[pack],"done":Callable(),"label":label}
	packs._waiters.append(waiter)
	return waiter

func run() -> void:
	var packs = AssetPacks.new()
	root.add_child(packs)
	packs.index = {"packs":{"core":{"file":"core-x.pck","bytes":8*MB},"map-100":{"file":"map-100-x.pck","bytes":2*MB}}}
	var music := AudioStreamPlayer.new()
	var tone := AudioStreamWAV.new()
	tone.data = PackedByteArray();tone.data.resize(22050)
	tone.loop_mode = AudioStreamWAV.LOOP_FORWARD;tone.loop_end = 22050
	music.stream = tone
	root.add_child(music)
	music.play()
	# Let playback actually start, as the area music has long before any wait.
	await process_frame
	await process_frame
	var screen = WaitingScreen.new()
	root.add_child(screen)
	screen.configure(packs,func():return music,func():return -6.0)
	screen.set_process(false)

	screen.tick(1.0)
	check(not screen.visible,"nothing waiting, no screen")
	packs._waiters.append({"packs":["map-100"],"done":Callable(),"label":""})
	screen.tick(1.0)
	check(not screen.visible and not packs.blocking(),"a background prefetch does not block play")
	packs._waiters.clear()

	var short := wait_for(packs,"map-100","地图 萨姆吉尔村")
	screen.tick(0.1);screen.tick(0.1)
	packs._waiters.erase(short)
	screen.tick(0.1)
	check(not screen.visible and screen.shown_count==0,"a wait shorter than the delay never flashes the screen")

	var long := wait_for(packs,"core","核心素材")
	screen.tick(0.2)
	check(not screen.visible,"hidden during the first 0.3 s of a wait")
	screen.tick(0.15)
	check(screen.visible and screen.shown_count==1,"a longer wait shows the screen")
	# stream_paused reads the live playback; under heavy parallel load the Dummy
	# driver can drop it, so also check what the screen will restore.
	check(screen._paused_music==music and (music.stream_paused or not music.playing),"the game's music pauses while it is up")
	if screen.player.stream!=null:
		check(screen.player.playing and is_equal_approx(screen.player.volume_db,-6.0),"the waiting music plays at the game's volume")
	else:
		print("SKIP: waiting music not imported (tools/import_loading.py)")
	packs.progress.emit("核心素材",2*MB,8*MB)
	check(screen.title.text.contains("核心素材") and screen.bar.visible and is_equal_approx(screen.bar.value,25.0),"the bar shows what is downloading and its share")
	check(screen.amount.text=="2.0 / 8.0 MB" and screen.percent.text=="25%","MB done / total and a percentage")
	packs.progress.emit("核心素材",6*MB,8*MB)
	screen.tick(0.1)
	check(is_equal_approx(screen.bar.value,75.0) and screen.percent.text=="75%" and screen.amount.text=="6.0 / 8.0 MB","the bar advances with the download")
	check(screen.title.text.begins_with("正在下载"),"a pack not in this device's cache is downloading")
	packs._cached["core-x.pck"] = true
	packs.progress.emit("核心素材",7*MB,8*MB)
	check(screen.title.text=="正在从本地缓存读取核心素材…" and screen.bar.visible,"one in the cache says it is read from the local cache")
	packs._cached.erase("core-x.pck")
	check(not screen.hint.visible,"no audio hint outside the browser")
	packs._waiters.erase(long)
	screen.tick(0.016)
	check(not screen.visible and not screen.player.playing,"the screen and its music stop when the wait ends")
	check(not music.stream_paused,"the game's music resumes")

	# Startup keeps the screen up across the gaps between downloads.
	screen.hold("正在读取素材索引…")
	screen.tick(0.35)
	check(screen.visible and screen.title.text=="正在读取素材索引…" and not screen.bar.visible,"a startup hold shows status text without a bar")
	var start := wait_for(packs,"map-100","起始地图")
	packs.progress.emit("起始地图",1*MB,2*MB)
	check(screen.bar.visible and screen.title.text.contains("起始地图"),"downloads during the hold show their progress")
	packs._waiters.erase(start)
	screen.tick(0.016)
	check(screen.visible and not screen.bar.visible,"the hold keeps the screen between downloads")
	screen.release()
	check(not screen.visible,"release hides it once nothing is waiting")
	screen.fail("起始地图素材下载失败")
	screen.tick(1.0)
	check(screen.visible and screen.title.text=="起始地图素材下载失败" and not screen.player.playing,"a failed startup stays on screen, silent, with the error")
	screen.queue_free();packs.queue_free();music.queue_free()

	# The in-process game ships its assets: no pack downloads, no waiting screen.
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	await process_frame
	check(not game.asset_packs.enabled and game.waiting_screen==null and not game.data.is_empty(),"the local game starts without a waiting screen")
	# In a running game (past startup) a wait shows only the progress panel over
	# the map: no image, no waiting music, the area music keeps playing.
	game._build_waiting_screen()
	var game_screen = game.waiting_screen
	game_screen.set_process(false)
	game_screen.enter_game()
	var was_playing: bool = game.music.playing
	var pending := wait_for(game.asset_packs,"map-100","地图 萨姆吉尔村")
	game_screen.tick(0.5)
	game.asset_packs.progress.emit("地图 萨姆吉尔村",1*MB,4*MB)
	check(game_screen.visible and game_screen.bar.visible and game_screen.percent.text=="25%","a wait in play shows the progress bar")
	check(not game_screen.art.visible and not game_screen._backdrop.visible,"in play the map stays visible: no loading image or backdrop")
	check(game_screen._paused_music==null and not game.music.stream_paused and game.music.playing==was_playing and not game_screen.player.playing,"in play the area music keeps playing and no waiting music starts")
	check(game_screen._root.mouse_filter==Control.MOUSE_FILTER_IGNORE and not game_screen.hint.visible,"the in-game bar does not block clicks or ask for audio")
	# The loading music follows this device's saved 音乐音量 / 音乐 switch even
	# before the device settings are restored for play.
	var prefs := "user://waiting-volume-test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	game.viewer_prefs_path = prefs
	game.set_viewer_pref("volume",0.1)
	game.set_viewer_pref("music_on",true)
	game._device_settings_live = false
	check(is_equal_approx(float(game_screen.music_volume.call()),linear_to_db(0.1)),"before play the waiting music uses the saved volume (%.1f dB)" % float(game_screen.music_volume.call()))
	game.set_viewer_pref("music_on",false)
	check(float(game_screen.music_volume.call())<=-79.0,"and is silent when the saved 音乐 switch is off")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	game.asset_packs._waiters.erase(pending)
	game_screen.tick(0.016)
	check(not game_screen.visible,"the bar goes away when the wait ends")
	game.set_process(false);game.set_physics_process(false)
	game.music.stop();game.effect.stop()
	game.music.stream=null;game.effect.stream=null
	game_screen.player.stop();game_screen.player.stream=null
	game.queue_free()
	await process_frame;await process_frame
	await create_timer(0.5).timeout
	quit(1 if failures else 0)
