extends RefCounted
## Sound for the game scene (scripts/game.gd): the music and effect players,
## map and battle music, UI and battle sounds, and the music and effect
## switches. The players and the settings stay on the game (game.music,
## game.muted and so on); see docs/technical/game-scripts.md.
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

func exploration_music() -> AudioStream:
	var info: Dictionary = game.world_catalog.info(int(game.data.map_id))
	if info.get("music") is String and not str(info.music).is_empty():
		var path := "res://assets/legacy/"+str(info.music)
		if ResourceLoader.exists(path):return load(path)
	if str(info.get("kind",""))=="interior" and game.area_music!=null:return game.area_music
	return game.wilderness_music if int(game.data.map_id)==100 and game.wilderness_music!=null else game.village_music

func set_music(stream: AudioStream) -> void:
	# The radio replaces map and battle music; remember what the scene wants.
	if is_instance_valid(game.radio) and game.radio.on:
		game.radio.scene_stream = stream
		return
	if game.music.stream==stream and game.music.playing:return
	game.music.stop()
	game.music.stream = stream
	if stream is AudioStreamWAV:
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length()*stream.mix_rate)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	game.music.play()

func setup_audio() -> void:
	game.music = AudioStreamPlayer.new()
	game.music.stream = load("res://assets/legacy/sabgm_t0.wav")
	game.music.stream.loop_begin = 0
	game.music.stream.loop_end = int(game.music.stream.get_length()*game.music.stream.mix_rate)
	game.music.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	game.village_music = game.music.stream
	if game.mvp_manifest.get("audio",{}).has("wilderness"):
		game.wilderness_music = load("res://assets/legacy/mvp/"+str(game.mvp_manifest.audio.wilderness))
	game.music.volume_db = linear_to_db(game.volume)
	game.add_child(game.music)
	game.music.play()
	game.effect = AudioStreamPlayer.new()
	for entry in [[201,"sas_01.wav"],[202,"sas_02.wav"],[203,"sas_03.wav"]]:
		game.ui_sounds[entry[0]] = load("res://assets/legacy/"+entry[1])
	if FileAccess.file_exists("res://assets/legacy/battle/manifest.json"):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/battle/manifest.json"))
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
	game.effect.volume_db = -10
	game.add_child(game.effect)

func play_battle_sound(ident: int) -> void:
	if not game.battle_sounds.has(ident):
		var path := str(preload("res://scripts/riding.gd").manifest().get("frame_sounds",{}).get(str(ident),""))
		if not path.is_empty(): game.battle_sounds[ident] = load("res://assets/legacy/riding/"+path)
	if game.ui_sounds.has(ident):
		play_ui_sound(ident)
		return
	if not game.effects_on or not game.battle_sounds.has(ident):
		return
	game.effect.stream = game.battle_sounds[ident]
	game.effect.play()

func play_click() -> void:
	play_ui_sound(201)

func play_ui_sound(ident: int) -> void:
	if not game.effects_on:
		return
	game.last_ui_sound = ident
	game.ui_sound_count += 1
	game.effect.stream = game.ui_sounds[ident]
	game.effect.play()

## M and the 音乐 switches: music on or off on this device.
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

func apply_sound() -> void:
	if is_instance_valid(game.music):game.music.volume_db = -80 if game.muted else linear_to_db(maxf(game.volume,0.0001))
	if is_instance_valid(game.effect):game.effect.volume_db = -10 if game.effects_on else -80
	game.sound_changed.emit()
