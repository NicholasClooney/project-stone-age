extends RefCounted
## Starting the game scene (scripts/game.gd) on the web: the waiting screen,
## downloading the asset index, core and start-area packs before the map is
## built, startup errors, and the browser console hooks (window.stoneAge and
## window.stoneAgeDev). The packs and screens stay on the game; see
## docs/technical/game-scripts.md.
const WaitingScreen = preload("res://scripts/waiting_screen.gd")
const TroopArt = preload("res://server/troop_art.gd")
const WorldCatalog = preload("res://scripts/world_catalog.gd")
const MusicTracks = preload("res://scripts/music_tracks.gd")
const GameAudio = preload("res://scripts/game/game_audio.gd")
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

func await_packs(packs: Array, label: String) -> bool:
	var waiter := GameScene.PackWaiter.new()
	game.asset_packs.ensure(packs,waiter.finish,label)
	if not waiter.finished:await waiter.done
	return waiter.ok

## Sprite packs for every carried and stored pet, for portraits and previews.
func pet_packs() -> Array:
	var packs: Array = []
	var profile_now: Dictionary = game.session.snapshot()
	for pet in profile_now.pets+profile_now.get("pet_storage",[]):
		var pack: String = game.asset_packs.sprite_pack(pet.get("sprite",""))
		if not packs.has(pack):packs.append(pack)
	return packs

## Pack base URL: --asset-packs=URL, the page's ?packs= parameter, or the
## packs/ folder next to a web build's page. Empty when assets ship locally.
func _asset_pack_url() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--asset-packs="):return argument.trim_prefix("--asset-packs=")
	if not OS.has_feature("web"):return ""
	var chosen = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('packs') || ''",true)
	if chosen is String and not chosen.is_empty():return chosen
	var page = JavaScriptBridge.eval("window.location.href.split('?')[0].replace(/[^/]*$/,'')",true)
	return str(page)+"packs/"

func _download_core() -> bool:
	var waiter := GameScene.PackWaiter.new()
	game.waiting_screen.hold("正在读取素材索引…")
	game.asset_packs.load_index(waiter.finish)
	if not waiter.finished:await waiter.done
	if not waiter.ok:return false
	# The waiting screen's own image and music come first, in a tiny pack.
	if await await_packs(["loading"],"等待画面"):game.waiting_screen.load_art()
	game.waiting_screen.hold("正在准备素材…")
	if not await await_packs(["core"],"核心素材"):return false
	# setup_audio() plays the village music and loads the sounds the MVP
	# manifest names; music comes from the library (scripts/music_tracks.gd).
	var startup_music: Array = [game.asset_packs.file_pack(MusicTracks.path(GameAudio.VILLAGE_MUSIC))]
	var mvp = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/mvp/manifest.json"))
	if mvp is Dictionary:
		for track in mvp.get("audio",{}).values():startup_music.append(game.asset_packs.file_pack(MusicTracks.path("res://assets/legacy/mvp/"+str(track))))
	if not await await_packs(startup_music.filter(func(pack): return not str(pack).is_empty()),"音乐"):return false
	# Catalogs read at construction must see the mounted core pack.
	game.world_catalog = WorldCatalog.new()
	TroopArt.pack_index = game.asset_packs.index.get("sprites",{})
	return true

func _download_start_area() -> bool:
	var profile_now: Dictionary = game.session.snapshot()
	var packs: Array = game.area_packs(1000)
	for pack in game.area_packs(int(profile_now.get("location",{}).get("map_id",1000))):
		if not packs.has(pack):packs.append(pack)
	packs.append(game.asset_packs.character_pack(profile_now.get("character_id","100000")))
	game.waiting_screen.hold("正在准备起始地图…")
	return await await_packs(packs,"起始地图")

## Web only: window.stoneAge mirrors map, cell, connection and pack state
## once a second, for Safari's Web Inspector on another device.
func _publish_web_status() -> void:
	var status := {"map":int(game.data.get("map_id",-1)),"cell":[game.cell.x,game.cell.y],"online":bool(game.link.get("online")) if not game.link.is_local() else true,
		"battle":bool(is_instance_valid(game.battle_view) and game.battle_view.visible),"mounted":game.asset_packs._mounted.size(),"cache_hits":game.asset_packs.cache_hits,"downloaded":game.asset_packs.downloaded_count,"pack_cache":bool(game.asset_packs.store.has_method("persistent") and game.asset_packs.store.persistent()),"pending":game.asset_packs._queued.size()+game.asset_packs._active.size(),"downloading":game.asset_packs._active.values(),"queued":game.asset_packs._queued,"waiters":game.asset_packs._waiters.size(),"waiting_screen":is_instance_valid(game.waiting_screen) and game.waiting_screen.visible,
		"message":str(game.message.text) if is_instance_valid(game.message) else "",
		"radio":str(game.radio.current) if is_instance_valid(game.radio) and game.radio.on else "","music":str(game.music.stream.resource_path) if is_instance_valid(game.music) and game.music.stream!=null else "",
		"music_at":snappedf(game.music.get_playback_position(),0.01) if is_instance_valid(game.music) and game.music.playing else -1.0}
	JavaScriptBridge.eval("window.stoneAge = %s" % JSON.stringify(status))

## Web only: window.stoneAgeDev(name) runs the same actions as the on-screen DEV
## buttons, so a browser session can be driven from the console.
func _install_web_dev_hook() -> void:
	game._dev_callback = JavaScriptBridge.create_callback(_on_web_dev)
	JavaScriptBridge.get_interface("window").stoneAgeDev = game._dev_callback

func _on_web_dev(arguments: Array) -> void:
	var action: String = str(arguments[0]) if not arguments.is_empty() else ""
	match action:
		"explore":game.dev_go_adventure()
		"encounter":game.dev_encounter()
		"village":game.load_area_id(1000,GameScene.SPAWN)
		"escape":game.battle_action("developer_escape")
		"return":game.return_from_battle()
		"pets":game.show_adventure_menu("pets")
		# The radio: on (or the next track), then off again (tools/web_memory_probe.mjs).
		"radio_next":
			if game.radio.on:game.radio.next()
			else:game.radio.turn_on()
		"radio_off":game.radio.turn_off()

func _build_waiting_screen() -> void:
	if OS.has_feature("web"):
		_install_web_dev_hook()
		var status_timer := Timer.new()
		status_timer.wait_time = 1.0
		status_timer.autostart = true
		status_timer.timeout.connect(_publish_web_status)
		game.add_child(status_timer)
	game.waiting_screen = WaitingScreen.new()
	game.add_child(game.waiting_screen)
	game.waiting_screen.configure(game.asset_packs,func():return game.music,func():return -80.0 if game.muted else linear_to_db(maxf(game.volume,0.0001)))

func _show_startup_error(text_value: String) -> void:
	if is_instance_valid(game.waiting_screen):
		game.waiting_screen.fail(text_value)
		return
	var label := game.text(text_value,20)
	label.position = Vector2(50,100)
	game.add_child(label)
