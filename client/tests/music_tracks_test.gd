extends SceneTree
## The music library (scripts/music_tracks.gd) and the radio's handling of its
## streams (scripts/radio.gd): original loop points, streamed playback, the
## next track fetched ahead, 单曲循环, 后台搜宠 taking the player, and tracks
## freed once nothing plays them. The radio runs against a fake game with a
## fake music player, so playback position is set by the test, not by time.
const MusicTracks = preload("res://scripts/music_tracks.gd")
const Radio = preload("res://scripts/radio.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## Stands in for AudioStreamPlayer: the members radio.gd uses, with a position
## the test moves by hand.
class FakeMusic extends Node:
	var stream: AudioStream
	var playing := false
	var stream_paused := false
	var position := 0.0
	var plays := 0
	func play(from: float = 0.0) -> void:
		playing = true
		position = from
		plays += 1
	func stop() -> void:
		playing = false
		position = 0.0
	func seek(to: float) -> void:position = to
	func get_playback_position() -> float:return position

## What radio.gd reads from the game: prefs, the profile, packs (all local
## here), the music player and the scene's music.
class FakeWorld extends Node:
	var music := FakeMusic.new()
	var prefs := {}
	var state := {"profile":{}}
	var asset_packs := FakePacks.new()
	var link = null
	var scene: AudioStream
	func viewer_pref(key: String, fallback: Variant) -> Variant:return prefs.get(key,fallback)
	func set_viewer_pref(key: String, value: Variant) -> void:prefs[key] = value
	func exploration_music() -> AudioStream:return scene
	func set_music(stream: AudioStream) -> void:
		music.stop()
		music.stream = stream
		music.play()

class FakePacks extends RefCounted:
	func file_pack(_path: String) -> String:return ""
	func ensure(_packs: Array, done: Callable, _label: String = "") -> void:done.call(true)

func run() -> void:
	library()
	await radio_streams()
	print("MUSIC TRACKS: %d failures" % failures)
	quit(1 if failures else 0)

func library() -> void:
	var tracks := MusicTracks.tracks()
	check(tracks.size() >= 24,"the library lists the original tracks (%d)" % tracks.size())
	check(MusicTracks.path("res://assets/legacy/world/audio/sabgm_f0.wav")=="res://assets/legacy/music/sabgm_f0.ogg","a map's original file name plays the library's Ogg Vorbis")
	check(MusicTracks.path("res://assets/legacy/battle/audio/sabgm_b0.wav")=="res://assets/legacy/music/sabgm_b0.ogg","so does the battle music")
	check(MusicTracks.path("res://assets/legacy/battle/audio/sae_23.wav")=="res://assets/legacy/battle/audio/sae_23.wav","a sound effect keeps its own file")

	# sabgm_f0 has an intro: the original loops from its smpl loop start.
	var f0: Dictionary = tracks.sabgm_f0
	check(float(f0.loop_start) > 20.0 and float(f0.loop_start) < float(f0.seconds),"sabgm_f0 records its original loop start (%.2f s of %.2f s)" % [float(f0.loop_start),float(f0.seconds)])
	var stream := MusicTracks.load_track("res://assets/legacy/world/audio/sabgm_f0.wav")
	check(stream is AudioStreamOggVorbis,"the track loads as Ogg Vorbis")
	check(stream.loop and is_equal_approx(stream.loop_offset,float(f0.loop_start)),"it loops back to the original loop start, not the top")
	check(absf(stream.get_length()-float(f0.seconds)) < 0.05,"and ends at the original loop end (%.2f s)" % stream.get_length())
	var d0 := MusicTracks.load_track("res://assets/legacy/music/sabgm_d0.ogg")
	check(d0.loop and is_zero_approx(d0.loop_offset),"a track without an intro loops whole")
	check(MusicTracks.load_track("res://assets/legacy/world/audio/sabgm_zz.wav")==null,"a missing track is null")

	# An older import's WAV loops from the same point.
	var wav := AudioStreamWAV.new()
	wav.mix_rate = 22050
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(22050*12)
	wav.data = data
	wav.resource_path = "res://assets/legacy/world/audio/sabgm_t1.wav"
	MusicTracks.prepare(wav)
	check(wav.loop_mode==AudioStreamWAV.LOOP_FORWARD and wav.loop_begin==roundi(float(tracks.sabgm_t1.loop_start)*22050) and wav.loop_end==22050*12,"a WAV copy loops from the loop start to its end")

	var player := MusicTracks.music_player()
	check(player.playback_type==AudioServer.PLAYBACK_TYPE_STREAM,"music plays as a stream (the web decodes samples whole)")
	player.free()

func radio_streams() -> void:
	var world := FakeWorld.new()
	root.add_child(world)
	world.add_child(world.music)
	world.scene = MusicTracks.load_track("res://assets/legacy/world/audio/sabgm_d2.wav")
	world.set_music(world.scene)
	var radio: Node = Radio.new()
	radio.configure(world)
	world.add_child(radio)
	world.scene = null
	var list: Array = radio.station_tracks()
	var village_ref: WeakRef = weakref(world.music.stream)

	radio.turn_on()
	check(radio.on and radio.current==list[0] and world.music.stream==radio._stream and world.music.playing,"the radio plays the first track")
	check(radio.scene_stream!=null and radio.scene_stream.resource_path.ends_with("sabgm_d2.ogg"),"and remembers the map's music to play when it stops")
	check(radio._stream.loop and is_equal_approx(radio._stream.loop_offset,MusicTracks.loop_start(radio._stream)),"a radio track loops from its original loop start")

	# The quota: the first pass plus loops from the loop start.
	var track: Dictionary = radio.by_id[radio.current]
	var loops: int = radio.loops_for(radio.current)
	var loop_length := float(track.seconds)-float(track.get("loop_start",0.0))
	check(float(track.seconds)+(loops-1)*loop_length >= radio.MIN_SECONDS,"%s plays %d times: at least %d seconds" % [radio.current,loops,roundi(radio.MIN_SECONDS)])
	var intro := {"seconds":60.0,"loop_start":30.0}
	radio.by_id["sabgm_test"] = intro
	check(radio.loops_for("sabgm_test")==3,"a 60 s track looping from 30 s plays 3 times to pass 100 s (whole loops would say 2)")
	radio.by_id.erase("sabgm_test")

	# Ten seconds before the change the next track is fetched, measured with
	# the shorter later loops.
	var length: float = radio._stream.get_length()
	radio._loops = loops-1
	radio._last_position = 0.0
	world.music.position = length-12.0
	radio._process(0.0)
	check(radio.upcoming==-1,"12 s before the end nothing is fetched yet")
	world.music.position = length-9.0
	radio._process(0.0)
	check(radio.upcoming==1 and radio.upcoming_stream!=null and radio.upcoming_stream.resource_path.ends_with(str(list[1])+".ogg"),"9 s before the end the next track is fetched")
	if loops > 1:
		radio._loops = loops-2
		radio.upcoming = -1
		radio._forget_upcoming()
		world.music.position = length-9.0
		radio._process(0.0)
		check(radio.upcoming==-1,"a loop before the last is too early (one more loop of %.0f s to go)" % loop_length)
		radio._loops = loops-1
		radio._process(0.0)
	var first_ref: WeakRef = weakref(radio._stream)
	var upcoming_ref: WeakRef = weakref(radio.upcoming_stream)

	# The loop wraps to the loop start: the position jumps back, the quota is met.
	world.music.position = MusicTracks.loop_start(radio._stream)+0.1
	radio._last_position = length-0.05
	radio._process(0.0)
	check(radio.current==list[1] and world.music.stream==upcoming_ref.get_ref(),"after its last loop the fetched track plays")
	check(first_ref.get_ref()==null,"the finished track is freed")
	check(village_ref.get_ref()!=null,"the map's music is kept while the radio may hand back to it")

	# 单曲循环: loops past the quota, nothing fetched.
	radio.set_repeat_one(true)
	radio._loops = 99
	world.music.position = radio._stream.get_length()-1.0
	radio._process(0.0)
	check(radio.current==list[1] and radio.upcoming==-1,"单曲循环 keeps the track and fetches nothing")
	radio.set_repeat_one(false)

	# 后台搜宠 takes the player; the radio resumes where it was.
	world.music.position = 12.5
	radio.suspend()
	world.set_music(MusicTracks.load_track("res://assets/legacy/battle/audio/sabgm_b0.wav"))
	check(radio.suspended and radio._stream!=null and world.music.stream!=radio._stream,"battle music takes the player; the radio keeps its track")
	radio.resume()
	check(world.music.stream==radio._stream and is_equal_approx(world.music.position,12.5),"the radio resumes its track where it was")

	# Off: the map's music comes back and the radio lets go of its tracks.
	var playing_ref: WeakRef = weakref(radio._stream)
	world.music.position = radio._stream.get_length()-9.0
	radio._loops = radio.loops_for(radio.current)-1
	radio._process(0.0)
	var next_ref: WeakRef = weakref(radio.upcoming_stream)
	check(next_ref.get_ref()!=null,"the next track is fetched ahead again")
	radio.turn_off()
	check(world.music.stream!=null and world.music.stream.resource_path.ends_with("sabgm_d2.ogg"),"turning the radio off plays the map's music again")
	check(radio.scene_stream==null and radio.upcoming_stream==null and radio._stream==null,"the radio holds no stream once off")
	check(playing_ref.get_ref()==null and next_ref.get_ref()==null,"its current and fetched tracks are freed")

	# A new map's music replaces the old one, which is freed.
	var old_ref: WeakRef = weakref(world.music.stream)
	world.set_music(MusicTracks.load_track("res://assets/legacy/world/audio/sabgm_f1.wav"))
	check(old_ref.get_ref()==null,"the previous map's music is freed when the next map's starts")
	world.queue_free()
	await process_frame
