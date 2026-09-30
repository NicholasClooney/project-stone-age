extends RefCounted
## The music library: every original background track, once, as Ogg Vorbis in
## client/assets/legacy/music (tools/import_music.py). Map, battle and radio
## music all play from it. Manifests elsewhere still name the original file
## (world/audio/sabgm_f0.wav, battle/audio/sabgm_b0.wav); path() turns any of
## those into the library's copy by track id, and keeps the given path when the
## library does not have the track (an older import).
##
## Each track loops like the original (music_codec.py): the file ends at the
## original loop end and loops back to `loop_start` seconds, so an intro plays
## once. prepare() sets that on a stream, whatever its format.
##
## music_player() makes the player the music plays through. On the web it
## plays as a stream: Godot mixes it in small chunks, instead of decoding the
## whole track into a Web Audio buffer (about 350 KB per second) as it does
## for sample playback, the web default. Sound effects stay samples.

const FOLDER := "res://assets/legacy/music/"
const MANIFEST := FOLDER+"manifest.json"

## id -> manifest entry; empty until the manifest can be read (on the web,
## once the core pack is mounted).
static var _tracks: Dictionary = {}

static func tracks() -> Dictionary:
	if _tracks.is_empty() and FileAccess.file_exists(MANIFEST):
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if manifest is Dictionary:
			for track in manifest.get("tracks",[]):
				if track is Dictionary:_tracks[str(track.get("id",""))] = track
	return _tracks

## Forgets the manifest read (tests that swap it).
static func reset() -> void:
	_tracks.clear()

## The track id of a music path: its file name without the extension.
static func id_of(path: String) -> String:
	return path.get_file().get_basename()

## The library's copy of the track path names, or path itself.
static func path(original: String) -> String:
	var entry: Dictionary = tracks().get(id_of(original),{})
	if entry.is_empty():return original
	return "res://assets/legacy/"+str(entry.get("file",""))

## Loads a music track (by any of its paths) ready to loop; null when missing.
static func load_track(original: String) -> AudioStream:
	var resolved := path(original)
	if not ResourceLoader.exists(resolved):
		if resolved==original or not ResourceLoader.exists(original):return null
		resolved = original
	var stream: AudioStream = load(resolved)
	prepare(stream)
	return stream

## Where the track loops back to, in seconds (0: the start).
static func loop_start(stream: AudioStream) -> float:
	if stream==null:return 0.0
	return float(tracks().get(id_of(stream.resource_path),{}).get("loop_start",0.0))

## Makes a music stream loop like the original: from its end back to its loop
## start. The library's files end at the loop end; a WAV from an older import
## loops whole.
static func prepare(stream: AudioStream) -> void:
	if stream==null:return
	var start := loop_start(stream)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
		stream.loop_offset = start
	elif stream is AudioStreamWAV:
		var frames := int(round(stream.get_length()*stream.mix_rate))
		stream.loop_begin = clampi(int(round(start*stream.mix_rate)),0,maxi(frames-1,0))
		stream.loop_end = frames
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamMP3:
		stream.loop = true
		stream.loop_offset = start

## A player for music: streamed rather than decoded whole on the web.
static func music_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	return player
