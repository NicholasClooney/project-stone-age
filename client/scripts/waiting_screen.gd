extends CanvasLayer
## Waiting room shown while asset packs that block play download (the web
## build): the original CG_TITLE_NOW_LOADING screen, the original login-wait
## track sabgm_s1 on a loop, and a progress bar with what is downloading, MB
## done / total and a percentage.
## Both assets come from the tiny `loading` pack the page fetches before core
## (tools/import_loading.py, tools/plan_web_packs.py); until it is mounted the
## screen shows the backdrop colour and the bar only.
## A wait must last DELAY seconds before the screen appears, so cached packs
## never flash it. While it is up the game's music is paused; it resumes when
## the wait ends. Builds that ship assets locally never have a waiting download,
## so the screen never shows there.
## Browsers refuse audio until a user gesture; Godot resumes its audio context
## on the first click, tap or key, and until then the screen asks for one.

const IMAGE := "res://assets/legacy/loading/now-loading.png"
const TRACKS := ["res://assets/legacy/loading/sabgm_s1.ogg","res://assets/legacy/loading/sabgm_s1.wav"]
## The dark red of the image's own background, so letterboxing is invisible.
const BACKDROP := Color8(29,0,0)
const DELAY := 0.3
const FONT := "res://assets/fonts/NotoSansSC.ttf"

var packs: Node
## Returns the game's music player (or null) and the music volume in dB.
var game_music: Callable
var music_volume: Callable
var player: AudioStreamPlayer
var art: TextureRect
var title: Label
var bar: ProgressBar
var amount: Label
var percent: Label
var hint: Label
var shown_count := 0
var _held := false
var _failed := false
var _status := ""
var _waited := 0.0
var _label := ""
var _done := 0
var _total := 0
var _paused_music: AudioStreamPlayer
var _gesture_seen := false

func configure(asset_packs: Node, music_player: Callable = Callable(), volume: Callable = Callable()) -> void:
	packs = asset_packs
	game_music = music_player
	music_volume = volume
	layer = 140
	visible = false
	_build()
	packs.progress.connect(_on_progress)
	load_art()

## Picks up the image and track once the loading pack is mounted.
func load_art() -> void:
	if art.texture==null and ResourceLoader.exists(IMAGE):art.texture = load(IMAGE)
	if player.stream!=null:return
	for path in TRACKS:
		if not ResourceLoader.exists(path):continue
		var stream: AudioStream = load(path)
		if stream is AudioStreamOggVorbis:stream.loop = true
		elif stream is AudioStreamWAV:
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length()*stream.mix_rate)
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		player.stream = stream
		if visible:_start_music()
		return

## Keeps the screen up (after the usual delay) with status text until
## release(), across gaps between downloads: startup uses this.
func hold(status: String) -> void:
	_held = true
	_status = status
	if visible:_refresh()

func release() -> void:
	_held = false
	tick(0.0)

## Shows an error that ends the wait for good (a failed startup download).
func fail(message: String) -> void:
	_failed = true
	_held = true
	_status = message
	_total = 0
	if not visible:_show()
	player.stop()
	_refresh()

func blocking() -> bool:
	return _held or (packs!=null and packs.blocking())

func _process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	if blocking():
		_waited += delta
		if not visible and _waited >= DELAY:_show()
		if visible:_refresh()
	else:
		_waited = 0.0
		_label = ""
		_total = 0
		if visible:_hide()

func _on_progress(label: String, done: int, total: int) -> void:
	_label = label
	_done = done
	_total = total
	if visible:_refresh()

func _show() -> void:
	visible = true
	shown_count += 1
	var music: AudioStreamPlayer = game_music.call() if game_music.is_valid() else null
	if is_instance_valid(music) and not music.stream_paused:
		music.stream_paused = true
		_paused_music = music
	if not _failed:_start_music()
	_refresh()

func _hide() -> void:
	visible = false
	player.stop()
	if is_instance_valid(_paused_music):_paused_music.stream_paused = false
	_paused_music = null

func _start_music() -> void:
	if player.stream==null:return
	player.volume_db = float(music_volume.call()) if music_volume.is_valid() else 0.0
	if not player.playing:player.play()

func _refresh() -> void:
	var downloading: bool = _total > 0 and not _failed and packs!=null and packs.blocking()
	title.text = "正在下载%s…" % _label if downloading else _status
	bar.visible = downloading
	amount.visible = downloading
	percent.visible = downloading
	if downloading:
		bar.value = 100.0*_done/_total
		amount.text = "%.1f / %.1f MB" % [_done/1048576.0,_total/1048576.0]
		percent.text = "%d%%" % int(bar.value)
	if player.playing and music_volume.is_valid():player.volume_db = float(music_volume.call())
	hint.visible = player.stream!=null and not _failed and _needs_gesture()

## True on the web until the page has seen a click, tap or key press.
func _needs_gesture() -> bool:
	if _gesture_seen or not OS.has_feature("web"):return false
	var active = JavaScriptBridge.eval("!!(navigator.userActivation && navigator.userActivation.hasBeenActive)",true)
	if active is bool and active:_gesture_seen = true
	return not _gesture_seen

func _input(event: InputEvent) -> void:
	if _gesture_seen or not event.is_pressed():return
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey or event is InputEventJoypadButton:
		_gesture_seen = true
		if visible:
			hint.hide()
			_start_music()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	art = TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(art)
	var panel := PanelContainer.new()
	# In the image's empty dark area, ahead of the rolling stone wheel and
	# clear of its own "NOW LOADING" lettering (1280x800 canvas).
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = 150
	panel.offset_right = 510
	panel.offset_top = -70
	panel.offset_bottom = 70
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",_box(Color(0.08,0.03,0.02,0.78),Color("9d8354"),16))
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	panel.add_child(column)
	title = _text(20)
	title.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	column.add_child(title)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0,18)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background",_box(Color("3a2a1c"),Color("9d8354"),0))
	bar.add_theme_stylebox_override("fill",_box(Color("e6c284"),Color("e6c284"),0))
	column.add_child(bar)
	var row := HBoxContainer.new()
	column.add_child(row)
	amount = _text(15)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(amount)
	percent = _text(15)
	row.add_child(percent)
	hint = _text(15)
	hint.text = "点击任意处开启音乐"
	hint.add_theme_color_override("font_color",Color("e6c284"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	player = AudioStreamPlayer.new()
	add_child(player)

func _text(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font",load(FONT))
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("f8edc7"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _box(color: Color, border: Color, margin: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(2 if margin > 0 else 1)
	result.set_corner_radius_all(4)
	result.set_content_margin_all(margin)
	return result
