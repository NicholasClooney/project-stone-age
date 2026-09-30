extends PanelContainer
## The 电台 window (playback is radio.gd). It floats above the field without
## pausing it, so the player can walk, fight and use other panels while
## choosing music; the header drags it and 收起 folds it to the player bar.
## Open with the toolbar's 音乐 button; it also holds this device's music
## switch and volume (the same settings as 设置 → 声音). Folded or not is
## this device's own.
const WIDTH := 400.0
const LIST_HEIGHT := 250.0
const KIND_NAMES := {"town":"村镇","field":"原野","dungeon":"洞窟","battle":"战斗","theme":"主题","jingle":"短曲"}
var world: Node
var radio: Node
var folded := false
var body: VBoxContainer
var _dragging := false
var _placed := false
var new_name: LineEdit

func configure(owner: Node, player: Node) -> void:
	world = owner
	radio = player
	name = "RadioPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 55
	custom_minimum_size.x = WIDTH
	add_theme_stylebox_override("panel",world.box(Color("20292f",0.95),Color("b29b65")))
	folded = bool(world.viewer_pref("radio_folded",false))
	radio.changed.connect(_refresh)
	radio.library_changed.connect(_refresh)
	world.sound_changed.connect(_sync_sound)
	hide()

func open_panel() -> void:
	rebuild()
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show()
	if not _placed:
		_placed = true
		await get_tree().process_frame
		relayout()

## Bottom left, above the classic bottom bar and clear of the automation bars.
func relayout() -> void:
	var screen: Vector2 = world.get_viewport_rect().size
	position = Vector2(12,maxf(90.0,screen.y-size.y-44))

func close_panel() -> void:
	hide()
	world.play_click()

func _refresh() -> void:
	if not visible:return
	if world._typing_in(self):return
	world.rebuild_keeping_scroll(self)

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation",6)
	add_child(body)
	_header()
	_sound_row()
	if not radio.available():
		var missing: Label = world.text("没有电台曲目：请先运行 tools/import_music.py（见 docs/development/original-data-setup.md）。",12)
		missing.name = "RadioMissing"
		missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		missing.custom_minimum_size.x = WIDTH-24
		body.add_child(missing)
		reset_size()
		return
	_now_playing()
	if not folded:
		_station_row()
		_track_list()
	reset_size()

func _header() -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	var heading: Label = world.text("音乐 ♪ 电台",16)
	heading.name = "RadioHeading"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.mouse_filter = Control.MOUSE_FILTER_STOP
	heading.mouse_default_cursor_shape = Control.CURSOR_MOVE
	heading.tooltip_text = "拖动移动窗口"
	heading.gui_input.connect(_drag)
	row.add_child(heading)
	var fold: Button = world.button("展开" if folded else "收起",func():
		folded = not folded
		world.set_viewer_pref("radio_folded",folded)
		var bottom := position.y+size.y
		rebuild()
		# Keep the bottom edge where it was, so folding does not jump the bar.
		await get_tree().process_frame
		position.y = clampf(bottom-size.y,0.0,world.get_viewport_rect().size.y-size.y))
	fold.name = "RadioFold"
	row.add_child(fold)
	var close: Button = world.button("×",close_panel)
	close.name = "RadioClose"
	close.tooltip_text = "关闭窗口（电台继续播放）"
	row.add_child(close)

func _drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var screen: Vector2 = world.get_viewport_rect().size
		position = (position+event.relative).clamp(Vector2.ZERO,(screen-size).max(Vector2.ZERO))
		accept_event()

## The music switch (M) and music volume, saved on this device.
func _sound_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	body.add_child(row)
	var music_on := CheckBox.new()
	music_on.name = "RadioMusicOn"
	music_on.text = "音乐 [M]"
	music_on.focus_mode = Control.FOCUS_NONE
	music_on.add_theme_font_size_override("font_size",13)
	music_on.button_pressed = not world.muted
	music_on.toggled.connect(func(on: bool):
		if on==world.muted:world.toggle_mute())
	row.add_child(music_on)
	row.add_child(world.text("音量",13))
	var slider := HSlider.new()
	slider.name = "RadioVolume"
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.value = world.volume
	slider.value_changed.connect(world.set_music_volume)
	row.add_child(slider)

## Follows M, 设置 and other windows without rebuilding (a drag keeps going).
func _sync_sound() -> void:
	if not visible:return
	var music_on := find_child("RadioMusicOn",true,false) as CheckBox
	if music_on:music_on.set_pressed_no_signal(not world.muted)
	var slider := find_child("RadioVolume",true,false) as HSlider
	if slider and not is_equal_approx(slider.value,world.volume):slider.set_value_no_signal(world.volume)

func _now_playing() -> void:
	var line: Label = world.text("",14)
	line.name = "RadioNowPlaying"
	line.clip_text = true
	line.custom_minimum_size.x = WIDTH-24
	if not radio.on:line.text = "电台已关闭，正在播放场景音乐"
	elif radio.current.is_empty():line.text = "电台 · %s" % radio.station_title()
	else:line.text = "♪ %s%s · %s" % [radio.title(radio.current),"（暂停）" if radio.paused else "",radio.station_title()]
	body.add_child(line)
	if not radio.status.is_empty():
		var note: Label = world.text(radio.status,12)
		note.name = "RadioStatus"
		note.add_theme_color_override("font_color",Color("e6c284"))
		body.add_child(note)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",4)
	body.add_child(controls)
	var previous: Button = world.button("◀ 上一首",radio.previous)
	previous.name = "RadioPrevious"
	previous.disabled = not radio.on
	controls.add_child(previous)
	var play_text := "▶ 开启电台" if not radio.on else ("▶ 播放" if radio.paused or radio.current.is_empty() else "暂停")
	var play: Button = world.button(play_text,radio.toggle_pause)
	play.name = "RadioPlay"
	controls.add_child(play)
	var next: Button = world.button("下一首 ▶",radio.next)
	next.name = "RadioNext"
	next.disabled = not radio.on
	controls.add_child(next)
	var favorite: Button = world.button("★" if radio.is_favorite(radio.current) else "☆",func():
		radio.set_favorite(radio.current,not radio.is_favorite(radio.current)))
	favorite.name = "RadioFavoriteCurrent"
	favorite.tooltip_text = "收藏正在播放的曲子"
	favorite.disabled = radio.current.is_empty()
	controls.add_child(favorite)
	var off: Button = world.button("关闭电台",radio.turn_off)
	off.name = "RadioOff"
	off.tooltip_text = "回到地图和战斗的原版音乐"
	off.disabled = not radio.on
	controls.add_child(off)

func _station_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	body.add_child(row)
	row.add_child(world.text("频道",13))
	var picker := OptionButton.new()
	picker.name = "RadioStation"
	picker.focus_mode = Control.FOCUS_NONE
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_theme_font_size_override("font_size",13)
	picker.get_popup().add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	var keys: Array = radio.stations()
	for i in range(keys.size()):
		var key: String = keys[i]
		var count: int = radio.station_tracks(key).size()
		picker.add_item("%s（%d）" % [radio.station_title(key),count],i)
		if key==radio.station:picker.select(i)
	picker.item_selected.connect(func(index: int): radio.choose_station(keys[index]))
	row.add_child(picker)
	var shuffle := CheckBox.new()
	shuffle.name = "RadioShuffle"
	shuffle.text = "随机"
	shuffle.focus_mode = Control.FOCUS_NONE
	shuffle.add_theme_font_size_override("font_size",13)
	shuffle.button_pressed = radio.shuffle
	shuffle.toggled.connect(radio.set_shuffle)
	row.add_child(shuffle)
	var repeat := CheckBox.new()
	repeat.name = "RadioRepeatOne"
	repeat.text = "单曲循环"
	repeat.tooltip_text = "一直循环当前这首；上一首、下一首和点曲子照样可以换"
	repeat.focus_mode = Control.FOCUS_NONE
	repeat.add_theme_font_size_override("font_size",13)
	repeat.button_pressed = radio.repeat_one
	repeat.toggled.connect(radio.set_repeat_one)
	row.add_child(repeat)
	var manage := HBoxContainer.new()
	manage.add_theme_constant_override("separation",4)
	body.add_child(manage)
	new_name = LineEdit.new()
	new_name.name = "RadioPlaylistName"
	new_name.placeholder_text = "新歌单名称" if not radio.station.begins_with(radio.PLAYLIST) else "新名称（新建或改名）"
	new_name.max_length = radio.MusicLibrary.MAX_NAME
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_name.add_theme_font_size_override("font_size",13)
	new_name.text_submitted.connect(func(_text: String): _create_playlist())
	manage.add_child(new_name)
	var create: Button = world.button("新建歌单",_create_playlist)
	create.name = "RadioCreatePlaylist"
	manage.add_child(create)
	if radio.station.begins_with(radio.PLAYLIST):
		var current_name: String = radio.station_title()
		var rename: Button = world.button("改名",func():
			var wanted := new_name.text.strip_edges()
			if wanted.is_empty():return
			new_name.release_focus()
			var key: String = radio.PLAYLIST+radio.MusicLibrary.clean_name(wanted)
			radio.request({"type":"rename_music_playlist","name":current_name,"new_name":wanted},func(): radio.choose_station(key)))
		rename.name = "RadioRenamePlaylist"
		manage.add_child(rename)
		var remove: Button = world.button("删除歌单",func(): _confirm_delete(current_name))
		remove.name = "RadioDeletePlaylist"
		manage.add_child(remove)

func _create_playlist() -> void:
	var wanted := new_name.text.strip_edges()
	if wanted.is_empty():return
	new_name.release_focus()
	var key: String = radio.PLAYLIST+radio.MusicLibrary.clean_name(wanted)
	radio.request({"type":"create_music_playlist","name":wanted},func(): radio.choose_station(key))

## Deleting asks once more inside the window (no system dialogs on the web).
func _confirm_delete(playlist: String) -> void:
	var row := HBoxContainer.new()
	row.name = "RadioConfirmDelete"
	body.add_child(row)
	body.move_child(row,3 if radio.status.is_empty() else 4)
	row.add_child(world.text("删除歌单「%s」？" % playlist,13))
	var yes: Button = world.button("删除",func():
		radio.choose_station(radio.ALL)
		radio.request({"type":"delete_music_playlist","name":playlist}))
	yes.name = "RadioConfirmDeleteYes"
	row.add_child(yes)
	row.add_child(world.button("取消",func(): row.queue_free()))

func _track_list() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "RadioTracks"
	scroll.custom_minimum_size = Vector2(WIDTH-24,LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",2)
	scroll.add_child(rows)
	var in_playlist: bool = radio.station.begins_with(radio.PLAYLIST)
	var playlist_name: String = radio.station_title()
	# 全部曲目 lists every track, the short jingles too, so any can be kept;
	# the station itself skips the jingles.
	var entries: Array = []
	if radio.station==radio.ALL:
		for track in radio.tracks:entries.append(str(track.id))
	else:entries = radio.station_tracks()
	if entries.is_empty():
		rows.add_child(world.text("点曲子旁的 ☆ 收藏。" if radio.station==radio.FAVORITES else "在「全部曲目」里用 ＋ 把曲子加进这个歌单。",13))
	for i in range(entries.size()):
		var track: String = entries[i]
		var info: Dictionary = radio.by_id[track]
		var row := HBoxContainer.new()
		row.name = "Track%d" % i
		row.add_theme_constant_override("separation",3)
		rows.add_child(row)
		var playing: bool = radio.on and radio.current==track and (radio.entry==i or radio.station==radio.ALL)
		var play: Button = world.button(("♪ " if playing else "▶ ")+str(info.title),func():
			if radio.station==radio.ALL:radio.play(track)
			else:radio.play(track,i))
		play.name = "Play"
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.tooltip_text = "%s · %d 秒 · %s" % [KIND_NAMES.get(str(info.kind),""),roundi(float(info.seconds)),str(info.id)]
		if playing:play.add_theme_color_override("font_color",Color("ffd98a"))
		row.add_child(play)
		var kind: Label = world.text(KIND_NAMES.get(str(info.kind),""),12)
		kind.add_theme_color_override("font_color",Color("b6aa8a"))
		row.add_child(kind)
		var favorite: bool = radio.is_favorite(track)
		var star: Button = world.button("★" if favorite else "☆",func(): radio.set_favorite(track,not favorite))
		star.name = "Favorite"
		star.tooltip_text = "取消收藏" if favorite else "收藏"
		row.add_child(star)
		if in_playlist:
			var up: Button = world.button("↑",func(): radio.request({"type":"move_music_in_playlist","name":playlist_name,"position":i,"track":track,"step":-1}))
			up.name = "MoveUp"
			up.disabled = i==0
			row.add_child(up)
			var down: Button = world.button("↓",func(): radio.request({"type":"move_music_in_playlist","name":playlist_name,"position":i,"track":track,"step":1}))
			down.name = "MoveDown"
			down.disabled = i==entries.size()-1
			row.add_child(down)
			var remove: Button = world.button("×",func(): radio.request({"type":"remove_music_from_playlist","name":playlist_name,"position":i,"track":track}))
			remove.name = "Remove"
			remove.tooltip_text = "移出歌单"
			row.add_child(remove)
		elif not radio.playlists().is_empty():
			var add := MenuButton.new()
			add.name = "AddToPlaylist"
			add.text = "＋"
			add.flat = false
			add.tooltip_text = "加入歌单"
			add.add_theme_font_size_override("font_size",13)
			add.add_theme_stylebox_override("normal",world.box(Color("574431"),Color("9d8354")))
			add.add_theme_stylebox_override("hover",world.box(Color("775b3c"),Color("e6c284")))
			add.add_theme_stylebox_override("pressed",world.box(Color("775b3c"),Color("e6c284")))
			add.get_popup().add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
			var names: Array = []
			for playlist in radio.playlists():
				names.append(str(playlist.name))
				add.get_popup().add_item("加入「%s」" % playlist.name,names.size()-1)
			add.get_popup().id_pressed.connect(func(id: int): radio.request({"type":"add_music_to_playlist","name":names[id],"track":track}))
			row.add_child(add)
