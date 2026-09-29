extends SceneTree
## System audio interruptions on the web (web_audio.gd, web/audio_session.js):
## the page reports AudioContext states; an interruption after the sound has
## run pauses the radio with a note, and 播放 resumes it. The browser part is
## covered by tools/test_audio_session.py; here the state changes are simulated.
const PREFS := "user://web-audio-test.cfg"
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	game.viewer_prefs_path = PREFS
	root.add_child(game)
	await process_frame
	await process_frame
	var audio = game.web_audio
	var radio = game.radio
	check(audio != null and not OS.has_feature("web"),"the web audio node exists and stays idle off the web")

	# Before the first tap the context is suspended: that is not an interruption.
	audio.on_context_state("suspended")
	check(not audio.interrupted,"a context that has not run yet is not interrupted")

	radio.turn_on()
	await process_frame
	check(radio.on and not radio.paused and not radio.current.is_empty(),"the radio plays")
	audio.on_context_state("running")
	audio.on_context_state("interrupted")
	check(audio.interrupted,"leaving running after having run is an interruption (WebKit's interrupted)")
	check(radio.paused and game.music.stream_paused and radio.status==audio.INTERRUPTED_NOTE,"the radio shows 暂停 with the note")
	radio.toggle_pause()
	check(not radio.paused and not game.music.stream_paused and radio.status.is_empty(),"播放 resumes the radio and clears the note")
	audio.on_context_state("running")
	check(not audio.interrupted,"the context running again ends the interruption")

	audio.on_context_state("suspended")
	check(radio.paused,"a plain suspended state after running (Chrome, Safari) pauses the radio too")
	audio.on_context_state("running")
	radio.toggle_pause()

	# The system's own controls (Media Session).
	audio.on_system_pause()
	check(radio.paused,"the system pause control pauses the radio")
	audio.on_system_play()
	check(not radio.paused,"the system play control resumes it")

	# With the radio off only scene music plays; it returns by itself once the
	# context runs, so the radio is left off.
	radio.turn_off()
	audio.on_context_state("interrupted")
	check(not radio.on and audio.interrupted,"an interruption leaves a switched-off radio off")
	audio.on_system_play()
	check(radio.on,"the system play control can switch the radio on")
	radio.turn_off()
	audio.on_context_state("closed")
	audio.on_context_state("running")

	# A pause the player chose is not overwritten by a later interruption note.
	radio.turn_on()
	await process_frame
	radio.toggle_pause()
	var chosen: String = radio.status
	audio.on_context_state("interrupted")
	check(radio.paused and radio.status==chosen,"an interruption does not touch a radio the player paused")

	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("WEB AUDIO: %d failures" % failures)
	quit(1 if failures else 0)
