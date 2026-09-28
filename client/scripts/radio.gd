extends Node
## 电台: plays the original soundtrack (client/assets/legacy/music, see
## tools/import_music.py) in place of the map and battle music.
##
## Stations: 全部曲目 (every track except the short jingles), 收藏 and the
## player's own playlists. The library (favourites, playlists) is the
## character's (profile `music`, scripts/music_library.gd) and shared by every
## device; whether this device plays the radio, the station, shuffle and the
## last track are this device's own (viewer.cfg), like the playback speed.
##
## The original tracks are loops of about a minute, so each one repeats until
## it has played for MIN_SECONDS and then the next starts at its loop point.
## PREFETCH_SECONDS before that the next track is chosen (shuffle too) and
## fetched in the background, so on the web the change has no download gap.
## While the radio is on, game.set_music() only records what the map or battle
## wants, and turning the radio off plays that again.
signal changed
signal library_changed

const MusicLibrary = preload("res://scripts/music_library.gd")
const MANIFEST := "res://assets/legacy/music/manifest.json"
const MIN_SECONDS := 100.0
const PREFETCH_SECONDS := 10.0
const ALL := "all"
const FAVORITES := "favorites"
const PLAYLIST := "list:"

var world: Node
var tracks: Array = []
var by_id: Dictionary = {}
## The radio replaces the scene music on this device.
var on := false
var paused := false
var station := ALL
var shuffle := false
## Track id playing (or loading) and its entry in the station's list.
var current := ""
var entry := -1
## What the map or battle last asked for, played again when the radio stops.
var scene_stream: AudioStream
var status := ""
## A station to tune to once the library has it (a playlist just created or renamed).
var station_pending := ""
var _stream: AudioStream
var _loops := 0
var _last_position := 0.0
var _library_json := ""
var _history: Array = []
## The station entry chosen to play next and its stream, fetched ahead.
var upcoming := -1
var upcoming_stream: AudioStream
var _upcoming_for := ""

func configure(owner: Node) -> void:
	world = owner
	if FileAccess.file_exists(MANIFEST):
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if manifest is Dictionary:tracks = manifest.get("tracks",[])
	for track in tracks:by_id[str(track.id)] = track
	station = str(world.viewer_pref("radio_station",ALL))
	shuffle = bool(world.viewer_pref("radio_shuffle",false))
	_library_json = JSON.stringify(library())

func available() -> bool:
	return not tracks.is_empty()

## Resumes the radio if this device left it on (called once the game is shown).
func restore() -> void:
	if available() and bool(world.viewer_pref("radio_on",false)) and not on:
		turn_on(str(world.viewer_pref("radio_track","")))

# ---- library (the character's) -----------------------------------------------

func library() -> Dictionary:
	return MusicLibrary.sanitize(world.state.profile.get("music"))

func is_favorite(track: String) -> bool:
	return library().favorites.has(track)

func playlists() -> Array:
	return library().playlists

## Called for every profile event; a changed library redraws the panel.
func on_profile() -> void:
	var json := JSON.stringify(library())
	if json==_library_json:return
	_library_json = json
	if not station_pending.is_empty() and _station_exists(station_pending):
		var wanted := station_pending
		station_pending = ""
		choose_station(wanted)
	if not _station_exists(station):
		station = ALL
		world.set_viewer_pref("radio_station",station)
	library_changed.emit()

## Sends a library change; done runs once the backend accepted it (a remote
## profile event may still be on its way).
func request(command: Dictionary, done: Callable = Callable()) -> void:
	world.link.request(command,func(reply: Dictionary):
		if reply.get("ok",false):
			if done.is_valid():done.call()
		elif not reply.get("stale",false):
			status = str(reply.get("reason","操作失败"))
			changed.emit())

func set_favorite(track: String, favorite: bool) -> void:
	request({"type":"set_music_favorite","track":track,"favorite":favorite})

# ---- stations ------------------------------------------------------------------

func station_title(key: String = station) -> String:
	if key==ALL:return "全部曲目"
	if key==FAVORITES:return "收藏"
	return key.trim_prefix(PLAYLIST)

func stations() -> Array:
	var result: Array = [ALL,FAVORITES]
	for playlist in playlists():result.append(PLAYLIST+str(playlist.name))
	return result

func _station_exists(key: String) -> bool:
	return key in [ALL,FAVORITES] or (key.begins_with(PLAYLIST) and MusicLibrary.find(library(),key.trim_prefix(PLAYLIST)) >= 0)

## Track ids of a station in play order, unknown ids left out.
func station_tracks(key: String = station) -> Array:
	var ids: Array = []
	if key==ALL:
		for track in tracks:
			if str(track.kind)!="jingle":ids.append(str(track.id))
	elif key==FAVORITES:ids = library().favorites
	else:
		var index := MusicLibrary.find(library(),key.trim_prefix(PLAYLIST))
		if index >= 0:ids = library().playlists[index].tracks
	return ids.filter(func(id): return by_id.has(id))

## Tunes to key; one not in the library yet is tuned to when it arrives.
func choose_station(key: String) -> void:
	if not _station_exists(key):
		station_pending = key
		return
	station_pending = ""
	_forget_upcoming()
	station = key
	world.set_viewer_pref("radio_station",station)
	_history.clear()
	if on:
		var list := station_tracks()
		if list.is_empty():
			_stop_playback("「%s」还没有曲子。" % station_title())
		else:
			play_at(randi() % list.size() if shuffle else 0)
	changed.emit()

func set_shuffle(enabled: bool) -> void:
	shuffle = enabled
	_forget_upcoming()
	world.set_viewer_pref("radio_shuffle",shuffle)
	changed.emit()

# ---- playback ------------------------------------------------------------------

func title(track: String) -> String:
	return str(by_id.get(track,{}).get("title",track))

func turn_on(track: String = "") -> void:
	if not available():return
	on = true
	world.set_viewer_pref("radio_on",true)
	var list := station_tracks()
	if list.is_empty():
		_stop_playback("「%s」还没有曲子。" % station_title())
		changed.emit()
		return
	var index := list.find(track)
	if index < 0:index = randi() % list.size() if shuffle else 0
	play_at(index)

func turn_off() -> void:
	if not on:return
	on = false
	paused = false
	current = ""
	entry = -1
	_stream = null
	status = ""
	world.set_viewer_pref("radio_on",false)
	world.music.stream_paused = false
	world.music.stop()
	var scene: AudioStream = scene_stream if scene_stream!=null else world.exploration_music()
	world.set_music(scene)
	changed.emit()

func toggle_pause() -> void:
	if not on:
		turn_on(str(world.viewer_pref("radio_track","")))
		return
	if current.is_empty():
		play_at(maxi(entry,0))
		return
	paused = not paused
	world.music.stream_paused = paused
	changed.emit()

## Plays the station's entry at index (a playlist may list a track twice).
func play_at(index: int) -> void:
	var list := station_tracks()
	if list.is_empty():return
	index = wrapi(index,0,list.size())
	play(str(list[index]),index)

func play(track: String, index: int = -1) -> void:
	if not by_id.has(track):return
	if not on:
		on = true
		world.set_viewer_pref("radio_on",true)
	if index < 0:index = station_tracks().find(track)
	if not current.is_empty() and current!=track:
		_history.append(current)
		if _history.size() > 50:_history.pop_front()
	current = track
	entry = index
	_forget_upcoming()
	paused = false
	status = "正在载入…"
	world.set_viewer_pref("radio_track",track)
	changed.emit()
	var path := "res://assets/legacy/"+str(by_id[track].file)
	var pack: String = world.asset_packs.file_pack(path)
	world.asset_packs.ensure([pack] if not pack.is_empty() else [],func(ok: bool):
		if current!=track or not on:return
		if not ok or not ResourceLoader.exists(path):
			status = "「%s」下载失败。" % title(track)
			changed.emit()
			return
		_start(load(path)),"电台")

func _start(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length()*stream.mix_rate)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif "loop" in stream:
		stream.loop = true
	_stream = stream
	_loops = 0
	_last_position = 0.0
	status = ""
	world.music.stop()
	world.music.stream_paused = false
	world.music.stream = stream
	world.music.play()
	changed.emit()

func next() -> void:
	var list := station_tracks()
	if list.is_empty():
		_stop_playback("「%s」还没有曲子。" % station_title())
		changed.emit()
		return
	var _ready_stream := upcoming_stream # keeps the fetched track loaded until it plays
	var chosen := upcoming if upcoming >= 0 and upcoming < list.size() and _upcoming_for==_upcoming_key() else _pick_next(list)
	play_at(chosen)

func _pick_next(list: Array) -> int:
	if shuffle and list.size() > 1:
		var choice := entry
		while choice==entry or (list[choice]==current and _unique(list) > 1):choice = randi() % list.size()
		return choice
	# The entry may have moved or gone since it started; continue after its track.
	var at := entry if entry >= 0 and entry < list.size() and list[entry]==current else list.find(current)
	return wrapi(at+1,0,list.size())

## What an upcoming choice was made for; a changed station list voids it.
func _upcoming_key() -> String:
	return "%s|%s|%d|%s" % [station,current,entry,",".join(station_tracks())]

func _forget_upcoming() -> void:
	upcoming = -1
	upcoming_stream = null
	_upcoming_for = ""

## Chooses the next entry now and fetches its track in the background (no
## progress bar); the stream is loaded so the change is immediate.
func prepare_next() -> void:
	var list := station_tracks()
	if list.is_empty() or _upcoming_for==_upcoming_key():return
	upcoming = _pick_next(list)
	_upcoming_for = _upcoming_key()
	var track: String = list[upcoming]
	var path := "res://assets/legacy/"+str(by_id[track].file)
	var pack: String = world.asset_packs.file_pack(path)
	var key := _upcoming_for
	world.asset_packs.ensure([pack] if not pack.is_empty() else [],func(ok: bool):
		if ok and key==_upcoming_for and ResourceLoader.exists(path):upcoming_stream = load(path))

func previous() -> void:
	var list := station_tracks()
	if list.is_empty():return
	if shuffle and not _history.is_empty():
		var track: String = _history.pop_back()
		current = ""
		play(track)
		return
	var at := entry if entry >= 0 and entry < list.size() and list[entry]==current else list.find(current)
	play_at(at-1)

func _unique(list: Array) -> int:
	var seen := {}
	for id in list:seen[id] = true
	return seen.size()

func _stop_playback(reason: String) -> void:
	current = ""
	entry = -1
	_stream = null
	status = reason
	world.music.stop()

## How many loops the track plays before the radio moves on.
func loops_for(track: String) -> int:
	var seconds := float(by_id.get(track,{}).get("seconds",MIN_SECONDS))
	return maxi(1,ceili(MIN_SECONDS/maxf(seconds,1.0)))

func _process(_delta: float) -> void:
	if not on or paused or _stream==null or world.music.stream!=_stream or not world.music.playing:return
	var at: float = world.music.get_playback_position()
	var length: float = _stream.get_length()
	var remaining: float = (loops_for(current)-_loops-1)*length+(length-at)
	if remaining <= PREFETCH_SECONDS:prepare_next()
	if at+0.5 < _last_position:
		_loops += 1
		if _loops >= loops_for(current):
			_last_position = 0.0
			next()
			return
	_last_position = at
