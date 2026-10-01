extends Node
## Web audio interruptions (web/audio_session.js; docs/technical/web-client.md).
##
## On the web the page script reports the browser AudioContext's state. When
## the system takes the sound away (a call, Siri, stepping out of the
## environment on Vision Pro) the context leaves "running"; WebKit often keeps
## it "interrupted" until a tap. The radio then shows 暂停 with a note, and its
## 播放 button (or any tap) resumes the context; scene music continues by itself
## once the context runs again. System play/pause controls reach the radio
## through the Media Session API. Elsewhere this node does nothing.
##
## The decisions live in on_context_state / on_system_play / on_system_pause so
## tests can drive them without a browser.
const INTERRUPTED_NOTE := "系统暂停了声音，按播放继续。"

var world: Node
var context_state := ""
## The context left "running" after having run; cleared when it runs again.
var interrupted := false
var _ran := false
var _js = null
## JavaScriptBridge callbacks must stay referenced while the page may call them.
var _callbacks: Array = []

func configure(owner: Node) -> void:
	world = owner
	if OS.has_feature("web"):_connect_page()

func _connect_page() -> void:
	_js = JavaScriptBridge.get_interface("stoneAgeAudio")
	if _js == null:return
	var listener := JavaScriptBridge.create_callback(func(args: Array): _on_page_event(str(args[0]) if args.size() > 0 else ""))
	var play := JavaScriptBridge.create_callback(func(_args: Array): on_system_play())
	var pause := JavaScriptBridge.create_callback(func(_args: Array): on_system_pause())
	_callbacks = [listener,play,pause]
	_js.listener = listener
	_js.setActions(play,pause)
	world.radio.changed.connect(_update_now_playing)
	on_context_state(str(_js.state()))
	_update_now_playing()

func _on_page_event(event: String) -> void:
	if event.begins_with("state:"):on_context_state(event.trim_prefix("state:"))

## A new AudioContext state: running, suspended, interrupted (WebKit) or closed.
## Only a context that has run before counts as interrupted; one that has not
## started yet is the normal wait for the first tap.
func on_context_state(state: String) -> void:
	context_state = state
	if state == "running":
		_ran = true
		interrupted = false
		return
	if not _ran or state == "closed":return
	interrupted = true
	if is_instance_valid(world) and is_instance_valid(world.radio):world.radio.interrupt(INTERRUPTED_NOTE)

## 与其他声音同时播放 (web/audio_session.js setMix): whether the page's audio
## session mixes with other apps' sound ("ambient") or plays like a music app
## through the iPhone's silent switch ("playback"). Only where Safari has
## navigator.audioSession; the page remembers the choice.
func mix_supported() -> bool:
	return _js != null and bool(_js.sessionSupported)

func mix_on() -> bool:
	return mix_supported() and bool(_js.mix)

func set_mix(on: bool) -> void:
	if mix_supported():_js.setMix(on)

## Asks the page to resume the AudioContext; call from a user action (the
## radio's 播放). Every tap already does this in the page script.
func resume_context() -> void:
	if _js != null:_js.resume()

## The system's play control: resume the radio, or turn it on.
func on_system_play() -> void:
	var radio: Node = world.radio
	if not radio.on or radio.paused or radio.current.is_empty():radio.toggle_pause()

## The system's pause control.
func on_system_pause() -> void:
	var radio: Node = world.radio
	if radio.on and not radio.paused and not radio.current.is_empty():radio.toggle_pause()

func _update_now_playing() -> void:
	if _js == null:return
	var radio: Node = world.radio
	if radio.on and not radio.current.is_empty():_js.setNowPlaying(radio.title(radio.current),not radio.paused)
	else:_js.setNowPlaying("",false)
