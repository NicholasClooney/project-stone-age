extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## Real scene/player lifecycles, silent PCM and Dummy output; no audible device.
const Wait = preload("res://tests/support/wait.gd")
var game
var failures := 0
var completions := 0

func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures += 1

func silent_stream(seconds: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(int(seconds*8000))
	data.fill(128)
	stream.data = data
	return stream

func start() -> void:
	game.session.heal()
	check(game.begin_battle(false,1),"real backend opens battle")
	game.battle_view.set_process(false)
	game.battle_view._process(game.battle_view.feedback_until+0.1)

func close() -> void:
	game.battle_session.developer_escape()
	game.battle_view._process(game.battle_view.feedback_until+0.1)
	game.return_from_battle()
	check(not game.battle_view.visible and not game.state.battle_open,"real close returns control without waiting for audio")

func all_effects_done() -> bool:
	if game.effect.playing:return false
	for voice in game.effect_voices:
		if voice.playing:return false
	return true

func map_playing() -> bool:
	return not game._audio._closing and game.music.playing and game.music.stream==game.exploration_music()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	check(await Wait.until(self,func():return is_instance_valid(game.battle_view)),"scene ready")
	game.set_physics_process(false)
	game.switch_area(true,Vector2i(45,45))
	check(await Wait.until(self,func():return not game.area_transition_busy),"fixture in wilderness")
	game.set_music_volume(1.0)
	game.muted = false
	game.apply_sound()
	start()
	check(await Wait.until(self,all_effects_done),"opening cues finish")
	var effect := silent_stream(1.5)
	game._audio.play_effect(effect)
	var old_voice: AudioStreamPlayer = game.effect
	old_voice.finished.connect(func():completions+=1,CONNECT_ONE_SHOT)
	game._audio.play_effect(effect)
	check(game.effect!=old_voice and old_voice.playing,"identical sounds keep distinct uninterrupted voices")
	var began := Clock.ticks_msec()
	close()
	check(old_voice.playing and game._audio._fade_level==122,"close preserves SE and starts source full-volume fade at122")
	check(await Wait.until(self,func():return game.music.volume_db < -1.0),"actual frame processing reduces music volume")
	check(await Wait.until(self,map_playing),"ordinary music fades then map plays")
	var elapsed := (Clock.ticks_msec()-began)/1000.0
	check(elapsed>=0.70 and elapsed<10.0,"source122+1 ticks at6ms gives nominal0.738s, with scheduler allowance: %.3f"%elapsed)
	check(await Wait.until(self,func():return completions==1),"pre-close SE emits real finished after map return")

	# Actual winning result emits its existing SE; no new victory BGM is added.
	var winning: Dictionary = game.session.start_battle_config("wooli",false,1)
	winning.player_attack = 999
	winning.player_speed = 100
	check(game.open_battle_config(winning),"authority-issued winning fixture opens")
	game.battle_view.set_process(false)
	game.battle_view._process(game.battle_view.feedback_until+0.1)
	game.battle_action("attack")
	game.battle_view._process(game.battle_view.feedback_until+0.1)
	check(game.battle_session.snapshot().outcome=="win","real authority resolves ordinary victory")
	check(game.music.stream.resource_path.get_file().get_basename()=="sabgm_b0" and not game._audio._result_voices.is_empty(),"ordinary victory keeps battle BGM and tracks its result SE")
	game.return_from_battle()
	check(await Wait.until(self,map_playing),"ordinary victory SE and fade complete before map")

	# Actual capture cue starts the library jingle; an accelerated animation's
	# restore cue is not allowed to cut it off. No fabricated finished signals.
	start()
	game.battle_view.capture_music_requested.emit(true)
	var jingle: AudioStream = game.music.stream
	check(jingle!=null and not jingle.loop and game.music.playback_type==AudioServer.PLAYBACK_TYPE_STREAM,"capture jingle plays once through the streamed music player")
	check(game.music_track("res://assets/legacy/battle/audio/sabgm_s0.wav").loop,"one-shot does not mutate the cached/radio stream")
	game.battle_view.capture_music_requested.emit(false)
	check(game.music.stream==jingle and game.music.playing,"early happy255 restore waits for actual jingle end")
	game.battle_view.capture_music_requested.emit(true)
	game.battle_view.capture_music_requested.emit(false)
	check(game.music.stream==jingle and game._audio._capture_return!=jingle,"repeated accelerated captures share one performance and retain original return track")
	close()
	game.battle_view.capture_music_requested.emit(false)
	check(game.music.stream==jingle and game.music.playing,"late animation cue cannot replace map-return tail")
	game.toggle_mute()
	check(game.music.volume_db<=-80 and game.music.playing,"music mute preserves completion lifecycle")
	check(await Wait.until(self,map_playing),"muted jingle naturally completes before map music")
	game.toggle_mute()

	start()
	game.battle_view.capture_music_requested.emit(true)
	jingle = game.music.stream
	check(await Wait.until(self,func():return not game.music.playing),"one-shot finishes even before animation restore cue")
	check(game.music.stream==jingle,"finished jingle waits for original animation restore cue")
	game.battle_view.capture_music_requested.emit(false)
	check(game.music.playing and game.music.stream!=jingle,"happy255 cue restores the original battle track after completed jingle")
	close()
	check(await Wait.until(self,map_playing),"restored battle music also fades on close")

	# Begin the next battle while both an old jingle and SE are still playing.
	start()
	game.battle_view.capture_music_requested.emit(true)
	jingle = game.music.stream
	game._audio.play_effect(silent_stream(1.0))
	old_voice = game.effect
	close()
	start()
	check(game.music.stream!=jingle and game.music.playing and old_voice.playing,"new real battle cuts old music but preserves old SE")
	game.battle_view.capture_music_requested.emit(false)
	check(game.music.stream.resource_path.get_file().get_basename()=="sabgm_b0","stale restore cue cannot recover previous music")
	close()
	check(await Wait.until(self,map_playing),"new battle's own close restores map")

	# Fill the finite pool: new cues are dropped instead of stealing tails or
	# queuing a backlog. Existing players produce genuine finished signals.
	check(await Wait.until(self,all_effects_done),"voice pool drained")
	var admitted := 0
	var finished := [0]
	for i in range(40):
		if game._audio.play_effect(silent_stream(0.4)):
			admitted += 1
			game.effect.finished.connect(func():finished[0]+=1,CONNECT_ONE_SHOT)
	check(admitted==7 and game.effect_voices.size()==6,"at most seven SE voices, overload omits new cues")
	game.set_effects_volume(0.3)
	check(is_equal_approx(game.effect.volume_db,-10+linear_to_db(0.3)) and game.effect_voices.all(func(v):return is_equal_approx(v.volume_db,game.effect.volume_db)),"effects volume changes every current and spare voice")
	game.set_effects_on(false)
	check(game.effect.volume_db<=-80 and game.effect_voices.all(func(v):return v.volume_db<=-80),"mute and volume reach every retained voice")
	check(await Wait.until(self,func():return finished[0]==admitted),"all admitted muted effects finish naturally without voice theft")
	game.set_effects_on(true)
	for i in range(15):
		start()
		game.battle_view.capture_music_requested.emit(true)
		close()
	check(game.effect_voices.size()==6 and game._audio.get_child_count()==0 and game.music.finished.get_connections().size()==1,"rapid consecutive battles keep one music player/callback and fixed SE pool")
	check(await Wait.until(self,map_playing),"final rapid-battle jingle drains and leaves map music")
	check(await Wait.until(self,all_effects_done),"rapid battles leave no playing residual SE")

	# Interruption does not advance the fade from a wall clock; resumption
	# continues the same owner. A closed context cannot strand completion.
	start()
	close()
	var before_level: int = game._audio._fade_level
	game.web_audio.on_context_state("running")
	game.web_audio.on_context_state("interrupted")
	game._audio._process(10.0)
	check(game._audio._fade_level==before_level,"interrupted AudioContext holds fade steps")
	game.web_audio.on_context_state("running")
	check(await Wait.until(self,map_playing),"running AudioContext lets real frame-driven fade finish")
	start()
	game.battle_view.capture_music_requested.emit(true)
	close()
	game.web_audio.on_context_state("closed")
	check(await Wait.until(self,map_playing),"permanently closed context cannot strand the music owner")
	game.web_audio.on_context_state("running")

	# Missing audio cannot leave a waiting transition; device mixing contract
	# is exercised by web_audio_test / test_audio_session.py alongside this.
	start()
	game.music.stop()
	game.music.stream = null
	close()
	check(await Wait.until(self,map_playing),"absent/stopped track cannot deadlock map recovery")
	game.stop_sounds()
	check(not game._audio.is_processing(),"explicit scene shutdown cancels recovery callbacks")
	game.queue_free()
	check(await Wait.until(self,func():return not is_instance_valid(game)),"scene and all retained players freed")
	print("BATTLE AUDIO TAIL: %d failures"%failures)
	quit(1 if failures else 0)
