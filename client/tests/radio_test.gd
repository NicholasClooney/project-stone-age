extends SceneTree
## 电台: the library (favourites, playlists) belongs to the character and is
## shared by every device over the WebSocket; whether a device plays the radio,
## its station and track are that device's own. The radio replaces map and
## battle music and turning it off brings the scene's music back.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const GameSession = preload("res://server/game_session.gd")
const MusicLibrary = preload("res://scripts/music_library.gd")
const Wait = preload("res://tests/support/wait.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func until(condition: Callable, seconds: float = Wait.DEADLINE) -> bool:
	return await Wait.until(self,condition,seconds)

func prefs(tag: String) -> String:
	return "user://radio-test-%s.cfg" % tag

func connect_client(port: int, tag: String):
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = "ws://127.0.0.1:%d" % port
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	game.viewer_prefs_path = prefs(tag)
	root.add_child(game)
	check(await until(func():return not game.data.is_empty() and game.link.online) and await Wait.settle(self,game),"a client connects and its startup reaches the backend")
	game.random_encounters = false
	return game

func close_client(game) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.link.close()
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

func session_rules() -> void:
	var session = GameSession.new()
	check(session.set_music_favorite("sabgm_t0",true) and session.set_music_favorite("sabgm_t0",true),"a track is favourited (twice is harmless)")
	check(session.snapshot().music.favorites==["sabgm_t0"],"and listed once")
	check(not session.set_music_favorite("../etc/passwd",true),"an unknown track id is refused")
	check(session.create_music_playlist("  练级  ") and not session.create_music_playlist("练级"),"playlist names are trimmed and unique")
	check(not session.create_music_playlist("   "),"an empty name is refused")
	for track in ["sabgm_f0","sabgm_t1","sabgm_f0"]:session.add_music_to_playlist("练级",track)
	check(session.snapshot().music.playlists[0].tracks==["sabgm_f0","sabgm_t1","sabgm_f0"],"a playlist keeps its order and may repeat a track")
	check(not session.remove_music_from_playlist("练级",1,"sabgm_f0"),"removing checks the entry still holds that track")
	check(session.move_music_in_playlist("练级",1,"sabgm_t1",-1) and session.snapshot().music.playlists[0].tracks==["sabgm_t1","sabgm_f0","sabgm_f0"],"an entry moves up")
	check(session.remove_music_from_playlist("练级",2,"sabgm_f0") and session.snapshot().music.playlists[0].tracks==["sabgm_t1","sabgm_f0"],"an entry is removed")
	check(session.rename_music_playlist("练级","打怪") and session.delete_music_playlist("打怪") and session.snapshot().music.playlists.is_empty(),"a playlist is renamed and deleted")
	var junk := MusicLibrary.sanitize({"favorites":["sabgm_t0",3,"sabgm_t0","bad id"],"playlists":[{"name":"a","tracks":["sabgm_b0",null]},{"name":"a"},"x",{"tracks":[]}]})
	check(junk==({"favorites":["sabgm_t0"],"playlists":[{"name":"a","tracks":["sabgm_b0"]}]}),"a malformed stored library is cleaned on load")

func run() -> void:
	session_rules()
	for tag in ["a","b"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs(tag)))
	var backend = Backend.new()
	root.add_child(backend)
	var port := 0 # any free port; the server reports the one it got
	var server = WsServer.new(backend,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"backend listens on localhost")
	port = server.port
	var a = await connect_client(port,"a")
	var b = await connect_client(port,"b")
	var radio_a = a.radio
	var radio_b = b.radio
	check(radio_a.available() and radio_a.tracks.size() >= 24,"the original soundtrack is imported (%d tracks)" % radio_a.tracks.size())
	check(not radio_a.on and a.music.stream==a.exploration_music(),"the radio starts off, with the map's own music")
	var all: Array = radio_a.station_tracks()
	check(not all.has("sabgm_s0") and all.has("sabgm_t0") and all.size()==radio_a.tracks.filter(func(t):return t.kind!="jingle").size(),"全部曲目 plays every track except the short jingles")

	a.radio_panel.open_panel()
	await process_frame
	check(a.radio_panel.visible and a.radio_panel.find_child("RadioTracks",true,false)!=null,"the 电台 window opens with the track list")
	check(a.radio_panel.find_child("RadioTracks",true,false).get_child(0).get_child_count()==radio_a.tracks.size(),"the list shows every track, jingles included")
	(a.radio_panel.find_child("RadioPlay",true,false) as Button).pressed.emit()
	check(await until(func():return radio_a.on and radio_a.current==all[0] and a.music.playing and a.music.stream.resource_path.ends_with(all[0]+".ogg")),"开启电台 plays the first track")
	check(a.music.stream.loop,"a track loops seamlessly until the radio moves on")
	var village: AudioStream = a.exploration_music()
	var battle_music: AudioStream = load("res://assets/legacy/battle/audio/sabgm_b0.wav")
	a.set_music(battle_music)
	check(a.music.stream.resource_path.ends_with(all[0]+".ogg") and radio_a.scene_stream==battle_music,"a battle does not interrupt the radio; its music is remembered")
	a.set_music(village)
	check(not radio_b.on and b.music.stream==b.exploration_music(),"another device keeps its own music")

	# The track repeats until it has played long enough, then the next starts.
	var loops: int = radio_a.loops_for(all[0])
	check(loops==maxi(1,ceili(radio_a.MIN_SECONDS/float(radio_a.by_id[all[0]].seconds))),"a %d-second track plays %d times" % [roundi(float(radio_a.by_id[all[0]].seconds)),loops])
	radio_a._loops = loops-1
	radio_a._last_position = 9999.0
	radio_a._process(0.0)
	check(await until(func():return radio_a.current==all[1] and a.music.stream.resource_path.ends_with(all[1]+".ogg")),"after its last loop the next track plays")
	radio_a.previous()
	check(await until(func():return radio_a.current==all[0]),"上一首 goes back")

	# Ten seconds before the change the next track is chosen and fetched.
	check(radio_a.upcoming==-1,"nothing is fetched early in a track")
	radio_a._loops = loops-1
	a.music.seek(float(radio_a.by_id[all[0]].seconds)-6.0)
	check(await until(func():return radio_a.upcoming==1 and radio_a.upcoming_stream!=null and radio_a.upcoming_stream.resource_path.ends_with(all[1]+".ogg")),"near the end of its last loop the next track is fetched ahead")
	radio_a.set_shuffle(true)
	check(radio_a.upcoming==-1,"changing shuffle drops the early choice")
	radio_a.prepare_next()
	var shuffled: int = radio_a.upcoming
	check(shuffled >= 0 and shuffled!=radio_a.entry,"with shuffle the next track is chosen ahead too")
	radio_a.next()
	check(await until(func():return radio_a.entry==shuffled and radio_a.current==all[shuffled]),"and it is the one that plays")
	radio_a.set_shuffle(false)
	radio_a.play(all[0])
	check(await until(func():return radio_a.current==all[0]),"a chosen track plays at once")

	# 单曲循环: the track loops past its quota and nothing is fetched ahead.
	(a.radio_panel.find_child("RadioRepeatOne",true,false) as CheckBox).button_pressed = true
	check(radio_a.repeat_one and bool(a.viewer_pref("radio_repeat_one",false)),"单曲循环 switches on and is remembered on this device")
	radio_a._loops = loops-1
	radio_a._last_position = 9999.0
	a.music.seek(float(radio_a.by_id[all[0]].seconds)-6.0)
	for i in range(20):await process_frame
	radio_a._process(0.0)
	check(radio_a.current==all[0] and radio_a.upcoming==-1,"with 单曲循环 the track keeps looping and nothing is fetched ahead")
	radio_a.next()
	check(await until(func():return radio_a.current==all[1]),"下一首 still changes the track")
	check(radio_a.repeat_one,"and the new track loops in turn")
	(a.radio_panel.find_child("RadioRepeatOne",true,false) as CheckBox).button_pressed = false
	check(not radio_a.repeat_one,"单曲循环 switches off")
	radio_a.play(all[0])
	check(await until(func():return radio_a.current==all[0]),"back to the first track")

	# Favourites belong to the character: both devices see them.
	(a.radio_panel.find_child("RadioFavoriteCurrent",true,false) as Button).pressed.emit()
	check(await until(func():return backend.session.snapshot().music.favorites==[all[0]]),"★ saves the favourite in the character's profile")
	check(await until(func():return radio_b.is_favorite(all[0])),"the other device sees the favourite")
	b.radio_panel.open_panel()
	await process_frame
	var b_star: Button = b.radio_panel.find_child("RadioTracks",true,false).get_child(0).get_child(0).find_child("Favorite",true,false)
	check(b_star.text=="★","and its open window shows the star")
	radio_a.set_favorite("sabgm_f0",true)
	check(await until(func():return backend.session.snapshot().music.favorites==[all[0],"sabgm_f0"]),"a second favourite")
	radio_a.choose_station(radio_a.FAVORITES)
	check(await until(func():return radio_a.current==all[0] and radio_a.station_tracks()==[all[0],"sabgm_f0"]),"the 收藏 station plays the favourites")
	radio_a.next()
	check(await until(func():return radio_a.current=="sabgm_f0"),"and moves through them")
	radio_a.next()
	check(await until(func():return radio_a.current==all[0]),"and starts over after the last")

	# A playlist made on one device plays on another.
	var name_box: LineEdit = a.radio_panel.find_child("RadioPlaylistName",true,false)
	name_box.text = "打怪"
	(a.radio_panel.find_child("RadioCreatePlaylist",true,false) as Button).pressed.emit()
	check(await until(func():return MusicLibrary.find(backend.session.snapshot().music,"打怪")==0),"新建歌单 creates the playlist")
	check(await until(func():return radio_a.station=="list:打怪" and radio_a.current.is_empty() and not radio_a.status.is_empty()),"the window switches to the new, still empty playlist")
	for track in ["sabgm_b1","sabgm_d2"]:radio_a.request({"type":"add_music_to_playlist","name":"打怪","track":track})
	check(await until(func():return radio_b.station_tracks("list:打怪")==["sabgm_b1","sabgm_d2"]),"the other device sees the playlist's tracks")
	radio_b.choose_station("list:打怪")
	radio_b.toggle_pause()
	check(await until(func():return radio_b.on and radio_b.current=="sabgm_b1" and b.music.stream.resource_path.ends_with("sabgm_b1.ogg")),"and plays it")
	await process_frame
	var move: Button = b.radio_panel.find_child("RadioTracks",true,false).get_child(0).get_child(1).find_child("MoveUp",true,false)
	move.pressed.emit()
	check(await until(func():return backend.session.snapshot().music.playlists[0].tracks==["sabgm_d2","sabgm_b1"]),"↑ reorders the playlist")
	check(await until(func():return radio_a.station_tracks()==["sabgm_d2","sabgm_b1"]),"for every device")
	radio_b.toggle_pause()
	check(radio_b.paused and b.music.stream_paused,"暂停 pauses")
	radio_b.toggle_pause()
	check(not radio_b.paused and not b.music.stream_paused,"and resumes")

	# Deleting the playlist a device is tuned to falls back to 全部曲目.
	radio_a.request({"type":"delete_music_playlist","name":"打怪"})
	check(await until(func():return radio_b.station==radio_b.ALL and radio_a.station==radio_a.ALL),"deleting a playlist retunes the devices to 全部曲目")

	# Turning the radio off brings back the scene's music.
	(a.radio_panel.find_child("RadioOff",true,false) as Button).pressed.emit()
	check(not radio_a.on and a.music.stream==village and a.music.playing,"关闭电台 plays the map music again")
	a.set_music(battle_music)
	check(a.music.stream==battle_music,"and the game controls the music again")
	a.set_music(village)

	# Each device remembers its own radio.
	check(not bool(a.viewer_pref("radio_on",true)) and bool(b.viewer_pref("radio_on",false)),"on or off is saved per device")
	var track_b: String = radio_b.current
	await close_client(b)
	var reloaded = await connect_client(port,"b")
	check(await until(func():return reloaded.radio.on and reloaded.radio.current==track_b),"a reloaded page resumes its radio")
	check(reloaded.radio.is_favorite(all[0]),"with the character's favourites")

	await close_client(a);await close_client(reloaded)
	server.stop()
	backend.queue_free();server.queue_free()
	await process_frame
	for tag in ["a","b"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs(tag)))
	print("RADIO: %d failures" % failures)
	quit(1 if failures else 0)
