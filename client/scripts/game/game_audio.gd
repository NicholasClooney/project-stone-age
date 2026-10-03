extends Node
## Sound for the game scene (scripts/game.gd): the music and effect players,
## map and battle music, UI and battle sounds, and the music and effect
## switches. The players and the settings stay on the game (game.music,
## game.muted and so on); see docs/technical/game-scripts.md.
const PerfRegistry = preload("res://scripts/perf_registry.gd")
const MusicTracks = preload("res://scripts/music_tracks.gd")
## The village music, and the wilderness music the MVP manifest names.
const VILLAGE_MUSIC := "res://assets/legacy/sabgm_t0.wav"
# t_music.cpp:690,3481–3486: decrement the source volume index once per
# main loop, then stop on the next check. gamemain.cpp:288,942 + version.h:627
# use a nominal 6 ms loop (not a 60 Hz audio timer). See the audio audit.
const SOURCE_AUDIO_TICK := 0.006
const BATTLE_FADE_LEVEL := 122
var game: GameScene
var _capture_stream: AudioStream
var _capture_return: AudioStream
var _capture_restore_requested := false
var _closing := false
var _pending_music: AudioStream
var _fade_level := -1
var _fade_initial := 0
var _fade_elapsed := 0.0
var _fade_stream: AudioStream
var _resume_radio := false
var _result_voices: Array[AudioStreamPlayer] = []

func _init(owner: GameScene) -> void:
	game = owner

## The map's own music. Tracks load when a map asks for them and are freed
## once nothing plays or remembers them (the previous map's music goes when
## the next map's starts); only paths are kept for the village and wilderness.
func exploration_music() -> AudioStream:
	var info: Dictionary = game.world_catalog.info(int(game.data.map_id))
	var own := map_music(int(game.data.map_id))
	if not own.is_empty():
		var stream := MusicTracks.load_track("res://assets/legacy/"+own)
		if stream!=null:return stream
	# A map without music markers keeps the track before it (original
	# play_map_bgm only changes the music at a marker).
	if str(info.get("kind","")) in ["interior","dungeon","training"] and game.area_music!=null:return game.area_music
	var wilderness := MusicTracks.load_track(game.wilderness_music) if int(game.data.map_id)==100 and not game.wilderness_music.is_empty() else null
	return wilderness if wilderness!=null else MusicTracks.load_track(game.village_music)

## The cave track caves without their own markers play (洞穴默认音乐).
const CAVE_MUSIC := "world/audio/sabgm_d2.wav"

## The music a map plays, relative to assets/legacy: its markers' track, or
## for a cave (dungeon) without markers the cave track while 洞穴默认音乐 is
## on (not the original: there the previous track goes on), else "".
func map_music(map_id: int) -> String:
	var info: Dictionary = game.world_catalog.info(map_id)
	if info.get("music") is String and not str(info.music).is_empty():return str(info.music)
	if game.cave_music and str(info.get("kind","")) in ["dungeon","training"] and map_id not in [100,200,300,500]:return CAVE_MUSIC
	return ""

## A music track by any of its paths (scripts/music_tracks.gd).
func music_track(path: String) -> AudioStream:
	return MusicTracks.load_track(path)

func set_music(stream: AudioStream) -> void:
	if _closing:
		_pending_music = stream
		return
	_play_music(stream)

func _play_music(stream: AudioStream) -> void:
	# The radio replaces map and battle music; remember what the scene wants.
	if is_instance_valid(game.radio) and game.radio.on and not game.radio.suspended:
		game.radio.scene_stream = stream
		return
	if game.music.stream==stream and game.music.playing:return
	game.music.stop()
	game.music.stream = stream
	PerfRegistry.track_audio("music",stream.resource_path if stream!=null else "",stream)
	MusicTracks.prepare(stream)
	if stream!=null:game.music.play()

## New music owns the same player; no old timer can restore a previous battle.
## Effects belong to the game, and are deliberately not stopped here.
func begin_battle_music(stream: AudioStream) -> void:
	_clear_transition()
	if not _radio_owns_music():game.music.stop()
	_play_music(stream)
	apply_sound()

func _radio_owns_music() -> bool:
	return is_instance_valid(game.radio) and game.radio.on and not game.radio.suspended

## oft.cpp:8675–8677/8732–8737 starts s0 once and requests restoration after
## happy255. The view retains that animation cue. Project change: when sped
## up, that request cannot cut the jingle short; a map return takes priority.
func capture_music(celebrating: bool) -> void:
	if not game.battle_view.visible or _closing:return
	if not celebrating:
		if _capture_stream==null:return
		_capture_restore_requested = true
		_finish_capture_if_ready()
		return
	if _radio_owns_music():return
	# Several accelerated captures may celebrate before one jingle finishes.
	# Reuse that performance, retaining the original battle track just once.
	if _capture_stream!=null and game.music.stream==_capture_stream and game.music.playing:
		_capture_restore_requested = false
		return
	if _capture_stream==null:_capture_return = game.music.stream
	var original := music_track("res://assets/legacy/battle/audio/sabgm_s0.wav")
	if original==null:return
	_capture_stream = original.duplicate()
	if _capture_stream is AudioStreamOggVorbis or _capture_stream is AudioStreamMP3:
		_capture_stream.loop = false
	elif _capture_stream is AudioStreamWAV:
		_capture_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_capture_restore_requested = false
	game.music.stop()
	game.music.stream = _capture_stream
	game.music.play()
	set_process(true)

func close_battle_music() -> void:
	_closing = true
	_pending_music = exploration_music()
	if _radio_owns_music():
		_finish_close()
		return
	if _capture_stream==null:
		# Original ordinary battle track has volume 122; the game's continuous
		# slider maps to the original 0..15 music setting for the step count.
		_fade_initial = int(BATTLE_FADE_LEVEL*int(round(game.volume*15.0))/15)
		_fade_level = _fade_initial
		_fade_elapsed = 0.0
		_fade_stream = game.music.stream
	set_process(true)

func _clear_transition() -> void:
	_capture_stream = null
	_capture_return = null
	_capture_restore_requested = false
	_closing = false
	_pending_music = null
	_fade_level = -1
	_fade_stream = null
	_resume_radio = false
	_result_voices.clear()
	set_process(false)

func _finish_capture_if_ready() -> void:
	if _capture_stream==null or (game.music.stream==_capture_stream and game.music.playing):return
	if not _closing and not _capture_restore_requested:return
	var previous := _capture_return
	_capture_stream = null
	_capture_return = null
	_capture_restore_requested = false
	if not _closing:
		_play_music(previous)
		set_process(false)

func _on_music_finished() -> void:
	_finish_capture_if_ready()
	_try_finish_close()

func _try_finish_close() -> void:
	if not _closing or _capture_stream!=null or _fade_level>=0:return
	for voice in _result_voices:
		if voice.playing:return
	_finish_close()

func _finish_close() -> void:
	var next := _pending_music
	var resume := _resume_radio
	_clear_transition()
	if resume and is_instance_valid(game.radio) and game.radio.suspended:
		game.radio.scene_stream = next
		game.radio.resume()
	else:_play_music(next)
	apply_sound()

func _process(delta: float) -> void:
	# Paused players/context do not finish by a guessed wall-clock deadline.
	# A permanently closed context cannot emit finished: discard its music.
	var context := str(game.web_audio.context_state) if is_instance_valid(game.web_audio) else ""
	if context=="closed":
		game.music.stop()
		_capture_restore_requested = true
		_fade_level = -1
		_result_voices.clear()
	elif game.music.stream_paused or context in ["suspended","interrupted"]:return
	_finish_capture_if_ready()
	if _fade_level>=0:
		if game.music.stream!=_fade_stream or not game.music.playing:
			_fade_level = -1
		else:
			_fade_elapsed += delta
			var ticks := int(_fade_elapsed/SOURCE_AUDIO_TICK)
			_fade_elapsed -= ticks*SOURCE_AUDIO_TICK
			_fade_level -= ticks
			if _fade_level<0:game.music.stop()
			apply_sound()
	_try_finish_close()

## 后台搜宠 (hunt.showcase) is capturing or training a pet on screen, or has
## the next one queued: its battles are watched with battle music first. While
## it only searches, the radio or the map music plays.
func showcase_music_active() -> bool:
	var flow: Dictionary = game.state.automation.get("flow",{})
	if not bool(flow.get("show_battles",flow.get("showcase",false))):return false
	var phase := str(flow.get("phase","idle"))
	return phase in ["capture","train"] or (phase in ["hunt","restart"] and int(flow.get("queue_size",0))>0)

## A watched battle starts: the radio steps aside (keeping its place).
## Each battle now finishes its audio before the map music resumes.
func begin_showcase_music() -> void:
	game.showcase_music = true
	if is_instance_valid(game.radio):game.radio.suspend()

## The run ended or 后台搜宠 was switched off: the radio plays on where it
## was, or the map music returns.
func end_showcase_music() -> void:
	if not game.showcase_music:return
	game.showcase_music = false
	if _closing or game.battle_view.visible:
		_resume_radio = is_instance_valid(game.radio) and game.radio.suspended
		if _closing:_pending_music = exploration_music()
	elif is_instance_valid(game.radio) and game.radio.suspended:game.radio.resume()
	elif not game.battle_view.visible:set_music(exploration_music())

func setup_audio() -> void:
	game.add_child(self)
	set_process(false)
	game.music = MusicTracks.music_player()
	game.village_music = VILLAGE_MUSIC
	if game.mvp_manifest.get("audio",{}).has("wilderness"):
		game.wilderness_music = "res://assets/legacy/mvp/"+str(game.mvp_manifest.audio.wilderness)
	game.music.stream = MusicTracks.load_track(game.village_music)
	game.music.volume_db = linear_to_db(game.volume)
	game.add_child(game.music)
	game.music.finished.connect(_on_music_finished)
	game.music.play()
	game.effect = AudioStreamPlayer.new()
	for entry in [[201,"sas_01.wav"],[202,"sas_02.wav"],[203,"sas_03.wav"]]:
		game.ui_sounds[entry[0]] = load("res://assets/legacy/"+entry[1])
	if preload("res://scripts/battle_art.gd").present():
		var manifest: Dictionary = preload("res://scripts/battle_art.gd").index()
		for ident in manifest.get("frame_sounds",{}):
			game.battle_sounds[int(ident)] = load("res://assets/legacy/battle/"+str(manifest.frame_sounds[ident]))
		if manifest.audio.has("battle_cancel"):
			game.ui_sounds[217] = load("res://assets/legacy/battle/"+str(manifest.audio.battle_cancel))
	if game.ui_sounds.has(217):game.battle_sounds[217] = game.ui_sounds[217]
	if game.mvp_manifest.get("audio",{}).has("menu_denied"):
		game.battle_sounds[220] = load("res://assets/legacy/mvp/"+str(game.mvp_manifest.audio.menu_denied))
	if game.mvp_manifest.get("audio",{}).has("battle_enter"):
		game.battle_sounds[215] = load("res://assets/legacy/mvp/"+str(game.mvp_manifest.audio.battle_enter))
	game.effect.stream = game.ui_sounds[201]
	if game.music.stream!=null:PerfRegistry.track_audio("music",game.music.stream.resource_path,game.music.stream)
	for sounds in [game.ui_sounds,game.battle_sounds]:
		for ident in sounds:PerfRegistry.track_audio("effects",ident,sounds[ident])
	game.effect.volume_db = -10
	game.add_child(game.effect)

func play_battle_sound(ident: int) -> void:
	if not game.battle_sounds.has(ident):
		var path := str(preload("res://scripts/riding.gd").index().get("frame_sounds",{}).get(str(ident),""))
		if not path.is_empty():
			game.battle_sounds[ident] = load("res://assets/legacy/riding/"+path)
			PerfRegistry.track_audio("effects",ident,game.battle_sounds[ident])
	if game.ui_sounds.has(ident):
		if play_ui_sound(ident):_remember_result_sound(ident)
		return
	if not game.effects_on or not game.battle_sounds.has(ident):
		return
	if play_effect(game.battle_sounds[ident]):_remember_result_sound(ident)

func _remember_result_sound(ident: int) -> void:
	if ident in [202,211] and game.effects_on and game.battle_view.visible and game.battle_view.result_sound_played and not _result_voices.has(game.effect):
		_result_voices.append(game.effect)

func play_click() -> void:
	play_ui_sound(201)

func play_ui_sound(ident: int) -> bool:
	if not game.effects_on:
		return false
	game.last_ui_sound = ident
	game.ui_sound_count += 1
	return play_effect(game.ui_sounds.get(ident))

const EFFECT_VOICES := 6

## The current voice is always game.effect. Swap ownership instead of
## restarting a copy at a guessed playback position (web samples have their
## own clock). No already-playing sound is stolen, even for the same stream.
## At capacity, omit the new cue; a queue would build up stale battle sounds.
func play_effect(stream: AudioStream) -> bool:
	if stream==null:return false
	if game.effect.playing:
		var voice := _spare_voice()
		if voice==null:return false
		game.effect_voices.erase(voice)
		game.effect_voices.append(game.effect)
		game.effect = voice
	_result_voices.erase(game.effect)
	game.effect.volume_db = -10+linear_to_db(maxf(game.effects_volume,0.0001)) if game.effects_on else -80
	game.effect.stream = stream
	game.effect.play()
	return game.effect.playing

func _spare_voice() -> AudioStreamPlayer:
	for voice in game.effect_voices:
		if not voice.playing:return voice
	if game.effect_voices.size()<EFFECT_VOICES:
		var voice := AudioStreamPlayer.new()
		game.add_child(voice)
		return voice
	return null

## Opens or closes the 电台 window (设置, 游戏助手, its shortcut).
func toggle_radio() -> void:
	if not is_instance_valid(game.radio_panel):return
	if game.radio_panel.visible:game.radio_panel.close_panel()
	else:game.radio_panel.open_panel()

## The 音乐 switches (设置, the 电台 window, the 音乐开关 shortcut): music on or off on this device.
func toggle_mute() -> void:
	game.muted = not game.muted
	game._save_device("music_on",not game.muted)
	apply_sound()

func set_music_volume(value: float) -> void:
	game.volume = clampf(value,0.0,1.0)
	game._save_device("volume",game.volume)
	apply_sound()

func set_effects_on(on: bool) -> void:
	game.effects_on = on
	game._save_device("effects_on",on)
	apply_sound()

func set_effects_volume(value: float) -> void:
	game.effects_volume = clampf(value,0.0,1.0)
	game._save_device("effects_volume",game.effects_volume)
	apply_sound()

## Full effects volume is the original's -10 dB below the music player.
func apply_sound() -> void:
	if is_instance_valid(game.music):
		var fade_db := 0.0
		if _fade_level>=0 and _fade_initial>0:
			# t_music.cpp:1859–1863 uses 100*log_base100(index/127) dB.
			fade_db = 50.0*log(maxf(float(_fade_level)/_fade_initial,0.0001))/log(10.0)
		game.music.volume_db = -80 if game.muted else linear_to_db(maxf(game.volume,0.0001))+fade_db
	if is_instance_valid(game.effect):game.effect.volume_db = -10+linear_to_db(maxf(game.effects_volume,0.0001)) if game.effects_on else -80
	for voice in game.effect_voices:
		if is_instance_valid(voice):voice.volume_db = game.effect.volume_db
	game.sound_changed.emit()
