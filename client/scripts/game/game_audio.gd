extends RefCounted
## Sound for the game scene (scripts/game.gd): the music and effect players,
## map and battle music, UI and battle sounds, and the music and effect
## switches. The players and the settings stay on the game (game.music,
## game.muted and so on); see docs/technical/game-scripts.md.
const PerfRegistry = preload("res://scripts/perf_registry.gd")
const MusicTracks = preload("res://scripts/music_tracks.gd")
## The village music, and the wilderness music the MVP manifest names.
const VILLAGE_MUSIC := "res://assets/legacy/sabgm_t0.wav"
var game: GameScene

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
	# The radio replaces map and battle music; remember what the scene wants.
	if is_instance_valid(game.radio) and game.radio.on and not game.radio.suspended:
		game.radio.scene_stream = stream
		return
	if game.music.stream==stream and game.music.playing:return
	game.music.stop()
	game.music.stream = stream
	PerfRegistry.track_audio("music",stream.resource_path if stream!=null else "",stream)
	MusicTracks.prepare(stream)
	game.music.play()

## 后台搜宠 (hunt.showcase) is capturing or training a pet on screen, or has
## the next one queued: its battles are watched with battle music first. While
## it only searches, the radio or the map music plays.
func showcase_music_active() -> bool:
	var flow: Dictionary = game.state.automation.get("flow",{})
	if not bool(flow.get("showcase",false)):return false
	var phase := str(flow.get("phase","idle"))
	return phase in ["capture","train"] or (phase in ["hunt","restart"] and int(flow.get("queue_size",0))>0)

## A watched battle starts: the radio steps aside (keeping its place) and the
## battle music loops across battles until the run ends.
func begin_showcase_music() -> void:
	game.showcase_music = true
	if is_instance_valid(game.radio):game.radio.suspend()

## The run ended or 后台搜宠 was switched off: the radio plays on where it
## was, or the map music returns.
func end_showcase_music() -> void:
	if not game.showcase_music:return
	game.showcase_music = false
	if is_instance_valid(game.radio) and game.radio.suspended:game.radio.resume()
	elif not game.battle_view.visible:set_music(exploration_music())

func setup_audio() -> void:
	game.music = MusicTracks.music_player()
	game.village_music = VILLAGE_MUSIC
	if game.mvp_manifest.get("audio",{}).has("wilderness"):
		game.wilderness_music = "res://assets/legacy/mvp/"+str(game.mvp_manifest.audio.wilderness)
	game.music.stream = MusicTracks.load_track(game.village_music)
	game.music.volume_db = linear_to_db(game.volume)
	game.add_child(game.music)
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
		play_ui_sound(ident)
		return
	if not game.effects_on or not game.battle_sounds.has(ident):
		return
	play_effect(game.battle_sounds[ident])

func play_click() -> void:
	play_ui_sound(201)

func play_ui_sound(ident: int) -> void:
	if not game.effects_on:
		return
	game.last_ui_sound = ident
	game.ui_sound_count += 1
	play_effect(game.ui_sounds[ident])

const EFFECT_VOICES := 6

## Plays a sound effect on game.effect (always the newest sound). A different
## sound still playing there moves to a spare voice and finishes from where it
## was, so a capture or hit is not cut off by the next click or battle sound.
func play_effect(stream: AudioStream) -> void:
	if game.effect.playing and game.effect.stream!=stream:
		var voice := _spare_voice()
		voice.stream = game.effect.stream
		voice.volume_db = game.effect.volume_db
		voice.play(game.effect.get_playback_position())
	game.effect.stream = stream
	game.effect.play()

func _spare_voice() -> AudioStreamPlayer:
	for voice in game.effect_voices:
		if not voice.playing:return voice
	if game.effect_voices.size()<EFFECT_VOICES:
		var voice := AudioStreamPlayer.new()
		game.add_child(voice)
		game.effect_voices.append(voice)
		return voice
	# All busy: the one closest to its end gives way.
	var best: AudioStreamPlayer = game.effect_voices[0]
	for voice in game.effect_voices:
		if voice.get_playback_position()>best.get_playback_position():best = voice
	return best

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
	if is_instance_valid(game.music):game.music.volume_db = -80 if game.muted else linear_to_db(maxf(game.volume,0.0001))
	if is_instance_valid(game.effect):game.effect.volume_db = -10+linear_to_db(maxf(game.effects_volume,0.0001)) if game.effects_on else -80
	for voice in game.effect_voices:
		if is_instance_valid(voice):voice.volume_db = game.effect.volume_db
	game.sound_changed.emit()
