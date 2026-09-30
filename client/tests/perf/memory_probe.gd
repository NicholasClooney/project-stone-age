extends SceneTree
## Memory probe: plays a fixed tour of the real game scene and records, after
## each step, Godot's memory monitors, the process footprint and where the
## memory goes (textures by folder, audio, parsed JSON, the game's own caches).
## Not part of the normal suites. Needs a real renderer for texture numbers:
##
##   STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --script res://tests/perf/memory_probe.gd -- --out=../build/memory-probe.json
##
## It opens a window for about a minute (muted). Like every test it plays
## without persistence (no save, logs or viewer settings are written) and
## builds its own test profile. See docs/technical/memory-baseline.md.
const SheetFrames = preload("res://scripts/sheet_frames.gd")
const BattleArt = preload("res://scripts/battle_art.gd")
const Riding = preload("res://scripts/riding.gd")
const Thumbs = preload("res://scripts/pet_thumbnails.gd")
const AnimatedPortrait = preload("res://scripts/animated_portrait.gd")
const Faces = preload("res://scripts/faces.gd")
const MapFile = preload("res://scripts/map_file.gd")
const LEGACY := "res://assets/legacy/"
const MB := 1048576.0

var game
var rows: Array = []
var assets: Array = []  # [path, group, kind]
var out_path := ""
var started_msec := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	started_msec = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):out_path = argument.trim_prefix("--out=")
	_collect_assets(LEGACY)
	print("[probe] %d imported assets indexed" % assets.size())
	await frames(5)
	sample("00 engine only (before the game scene)")
	game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await frames(30)
	game.random_encounters = false
	sample("01 startup: Samgir village (map 1000) built")
	await setup_save()
	await frames(10)
	sample("02 test save: 3 companions + 12 stored 扬奇洛斯")
	await walk_around(8)
	sample("03 walked around the village")
	# No walk here: the arrival cell is next to the gate back to the village.
	await visit(100)
	sample("04 Samgir wilderness (map 100)")
	await visit(300)
	await walk_around(8)
	sample("05 吉鲁岛 (map 300) + walk")
	await visit(200)
	sample("06 map 200 (largest map JSON)")
	await visit(100)
	sample("07 back to map 100")
	await battle("attack")
	sample("08 battle open (auto attack), before close", true)
	await close_battle()
	sample("09 after the battle closed")
	await battle("capture")
	sample("10 capture battle, before close", true)
	await close_battle()
	sample("11 after the capture battle closed")
	game.show_adventure_menu("pets")
	await frames(20)
	sample("12 pet window open")
	var compare: Node = game.adventure_menu.find_child("PetCompare",true,false)
	if compare != null:compare.pressed.emit()
	await frames(20)
	sample("13 同种比较 open")
	game.close_adventure_menu()
	await frames(20)
	sample("14 pet window closed")
	await encyclopedia()
	await radio()
	game.settings_menu.open_menu()
	await frames(20)
	sample("20 设置 open")
	game.settings_menu.close_menu()
	await frames(10)
	await visit(1000)
	await frames(30)
	sample("21 everything closed, back in the village")
	for i in range(3):
		await visit(100)
		await battle("attack")
		await close_battle()
	await visit(1000)
	await frames(30)
	sample("22 after 3 more battles, back in the village")
	cache_report()
	cpu_copy_check()
	json_costs()
	write_out()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop()
	game.queue_free()
	await frames(5)
	print("[probe] done in %.1f s" % ((Time.get_ticks_msec()-started_msec)/1000.0))
	quit(0)

# ---- tour steps ----------------------------------------------------------------

func frames(count: int) -> void:
	# A windowed run draws after every process frame; awaiting frame_post_draw
	# instead would hang headless (the dummy renderer never draws).
	for i in range(count):await process_frame

func setup_save() -> void:
	game.session.claim_default_companions()
	for i in range(12):game.session.gm_grant_pet(92)
	var pets: Array = game.session.snapshot().pets
	# Keep the three companions carried; the rest go to storage.
	for i in range(pets.size()-1,2,-1):game.session.store_pet(i)
	game.refresh_companion()

func visit(map_id: int) -> void:
	game.paused_input = false
	# Map 100's catalog spawn is the gate back to the village; walk out the
	# village's own exit instead, like the DEV button.
	if map_id == 100 and int(game.data.map_id) == 1000:game.dev_go_adventure()
	elif not game.dev_visit(map_id):print("[probe] could not visit %d" % map_id)
	await frames(40)
	if int(game.data.map_id) != map_id:print("[probe] wanted map %d, on %d" % [map_id,int(game.data.map_id)])

## Walks to a few reachable cells around the character so new ground is drawn.
func walk_around(steps: int) -> void:
	game.paused_input = false
	for offset in [Vector2i(steps,0),Vector2i(0,steps),Vector2i(-steps,0),Vector2i(0,-steps)]:
		var goal: Vector2i = game.cell+offset
		for grow in range(6):
			if game.is_walkable(goal):break
			goal += Vector2i(signi(offset.x),signi(offset.y))
		if not game.is_walkable(goal):continue
		game.walk_to(goal)
		var limit := Time.get_ticks_msec()+4000
		while (game.moving or not game.path.is_empty()) and Time.get_ticks_msec() < limit:await process_frame
	await frames(5)

func battle(action: String) -> void:
	game.paused_input = false
	game.moving = false
	if not game.begin_battle(false,1):
		print("[probe] battle did not start")
		return
	await frames(30)
	for turn in range(12):
		if not game.battle_session.snapshot().active:break
		for i in range(60):game.battle_view._process(0.1)
		await frames(3)
		game.battle_action(action)
		for i in range(80):game.battle_view._process(0.1)
		await frames(3)
	if game.battle_session.snapshot().active:game.battle_action("developer_escape")
	for i in range(200):game.battle_view._process(0.1)
	await frames(10)

func close_battle() -> void:
	for i in range(200):game.battle_view._process(0.1)
	game.return_from_battle()
	await frames(30)

func encyclopedia() -> void:
	var menu = game.pet_encyclopedia
	menu.open_menu()
	await frames(60)
	sample("15 宠物大全 grid (first screen)")
	var bar: VScrollBar = menu.scroll.get_v_scroll_bar() if is_instance_valid(menu.scroll) else null
	if bar != null:
		var y := 0.0
		while y < bar.max_value:
			y += 400.0
			menu.scroll.scroll_vertical = int(y)
			await frames(12)
	await frames(30)
	sample("16 宠物大全 grid scrolled to the end")
	menu._switch("list")
	await frames(40)
	sample("17 宠物大全 list view")
	menu.show_species(92)
	await frames(40)
	sample("18 宠物大全 detail (扬奇洛斯)")
	menu.close_menu()
	await frames(20)

func radio() -> void:
	var tracks: Array = game.radio.station_tracks()
	var played := 0
	for track in tracks:
		if played >= 5:break
		game.radio.play(str(track))
		await frames(30)
		played += 1
	sample("19 radio after switching %d tracks" % played)
	game.radio.turn_off()
	await frames(10)

# ---- measurement -------------------------------------------------------------

func _collect_assets(folder: String) -> void:
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".import"):continue
		var path := folder+file.trim_suffix(".import")
		var extension := path.get_extension().to_lower()
		var kind := "audio" if extension in ["wav","ogg","mp3"] else "texture"
		assets.append([path,_group(path),kind])
	for sub in DirAccess.get_directories_at(folder):_collect_assets(folder+sub+"/")

func _group(path: String) -> String:
	var rest := path.trim_prefix(LEGACY)
	for prefix in ["battle/sheets/","battle/backgrounds/","battle/ui/","riding/sheets/","characters/sheets/","images/","faces/","ui/","mvp/","music/","world/"]:
		if rest.begins_with(prefix):return prefix.trim_suffix("/")
	return rest.get_slice("/",0) if rest.contains("/") else "(root)"

func _rss_kb() -> int:
	var output: Array = []
	OS.execute("ps",["-o","rss=","-p",str(OS.get_process_id())],output)
	return int(str(output[0]).strip_edges()) if not output.is_empty() else -1

## macOS phys_footprint (what the system charges the process, GPU memory included) and its biggest categories.
func _footprint() -> Dictionary:
	var output: Array = []
	OS.execute("footprint",["-p",str(OS.get_process_id())],output)
	var text: String = str(output[0]) if not output.is_empty() else ""
	var result := {"total_mb":-1.0,"top":[]}
	for line in text.split("\n"):
		if line.contains("Footprint:"):result.total_mb = _size_mb(line.get_slice("Footprint:",1).strip_edges())
		elif line.strip_edges().length() > 0 and line.strip_edges()[0].is_valid_int() and result.top.size() < 6:
			var parts := line.strip_edges().split("  ",false)
			if parts.size() >= 5:result.top.append("%s=%s" % [parts[parts.size()-1].strip_edges(),parts[0].strip_edges()])
	return result

static func _size_mb(text: String) -> float:
	var parts := text.split(" ")
	if parts.size() < 2:return -1.0
	var value := float(parts[0])
	match parts[1].substr(0,2):
		"GB":return value*1024.0
		"MB":return value
		"KB":return value/1024.0
	return value/MB

func sample(step: String, in_battle: bool = false) -> void:
	var textures := {}
	var audio := {}
	for asset in assets:
		var path: String = asset[0]
		if not ResourceLoader.has_cached(path):continue
		var resource = ResourceLoader.get_cached_ref(path)
		if resource == null:continue
		if asset[2] == "texture" and resource is Texture2D:
			var entry: Dictionary = textures.get(asset[1],{"count":0,"bytes":0})
			entry.count += 1
			entry.bytes += resource.get_width()*resource.get_height()*4
			textures[asset[1]] = entry
		elif resource is AudioStream:
			var entry: Dictionary = audio.get(asset[1],{"count":0,"stored":0,"pcm16":0,"seconds":0.0})
			entry.count += 1
			entry.stored += _stored_audio_bytes(resource)
			var seconds: float = resource.get_length()
			entry.seconds += seconds
			entry.pcm16 += int(seconds*44100.0)*2*2
			audio[asset[1]] = entry
	var texture_total := 0
	for group in textures:texture_total += int(textures[group].bytes)
	var footprint := _footprint()
	var row := {
		"step":step,
		"seconds":(Time.get_ticks_msec()-started_msec)/1000.0,
		"map":int(game.data.get("map_id",-1)) if is_instance_valid(game) and game.data is Dictionary else -1,
		"static_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/MB,
		"static_max_mb":Performance.get_monitor(Performance.MEMORY_STATIC_MAX)/MB,
		"texture_mb":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/MB,
		"video_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/MB,
		"buffer_mb":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)/MB,
		"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"fps":Performance.get_monitor(Performance.TIME_FPS),
		"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		"rss_mb":_rss_kb()/1024.0,
		"footprint_mb":footprint.total_mb,
		"footprint_top":footprint.top,
		"file_textures_mb":texture_total/MB,
		"textures":textures,
		"audio":audio,
		"caches":_caches(),
		"in_battle":in_battle,
	}
	rows.append(row)
	var groups: Array = textures.keys()
	groups.sort_custom(func(a,b):return int(textures[a].bytes) > int(textures[b].bytes))
	var parts: Array = []
	for group in groups:parts.append("%s %d/%.1f" % [group,int(textures[group].count),float(textures[group].bytes)/MB])
	print("[probe] %s | map %d | static %.1f MB (max %.1f) | tex %.1f MB (files %.1f) | video %.1f | rss %.0f | footprint %.0f MB | objects %d res %d nodes %d orphans %d | draws %d | %s" % [step,row.map,row.static_mb,row.static_max_mb,row.texture_mb,row.file_textures_mb,row.video_mb,row.rss_mb,row.footprint_mb,row.objects,row.resources,row.nodes,row.orphans,row.draw_calls,", ".join(parts)])
	print("[probe]    footprint top: %s | caches %s | audio %s" % [", ".join(footprint.top),JSON.stringify(row.caches),JSON.stringify(audio)])

static func _stored_audio_bytes(stream: AudioStream) -> int:
	if stream is AudioStreamWAV:return stream.data.size()
	if stream is AudioStreamOggVorbis and stream.packet_sequence != null:
		var total := 0
		for packet in stream.packet_sequence.packet_data:
			for part in packet:total += part.size()
		return total
	return 0

## The game's own caches: sizes and the textures they keep alive.
func _caches() -> Dictionary:
	var sheet_bytes := 0
	for path in SheetFrames._sheets:
		var sheet: Texture2D = SheetFrames._sheets[path]
		if sheet != null:sheet_bytes += sheet.get_width()*sheet.get_height()*4
	var thumbs := 0
	var thumb_bytes := 0
	for sprite in Thumbs._made:
		var made = Thumbs._made[sprite]
		if made is Texture2D:
			thumbs += 1
			thumb_bytes += made.get_width()*made.get_height()*4
	return {
		"sheet_frames_sheets":SheetFrames._sheets.size(),
		"sheet_frames_sheet_mb":snappedf(sheet_bytes/MB,0.1),
		"sheet_frames_frames":SheetFrames._frames.size(),
		"map_tiles":game.textures.size() if is_instance_valid(game) else 0,
		"battle_view_textures":game.battle_view.textures.size() if is_instance_valid(game) else 0,
		"portrait_frames":AnimatedPortrait._textures.size(),
		"thumbs":thumbs,
		"thumb_mb":snappedf(thumb_bytes/MB,0.1),
		"battle_manifest_sprites":BattleArt._data.get("characters",{}).size(),
		"riding_manifest_loaded":not Riding._manifest.is_empty(),
		"faces_manifest_loaded":Faces._loaded,
		"battle_sounds":game.battle_sounds.size() if is_instance_valid(game) else 0,
	}

## Which cached textures are held only by the game's static caches, per cache.
func cache_report() -> void:
	var by_folder := {}
	for path in SheetFrames._sheets:
		var folder: String = str(path).get_base_dir()
		var sheet: Texture2D = SheetFrames._sheets[path]
		var entry: Dictionary = by_folder.get(folder,{"count":0,"bytes":0})
		entry.count += 1
		entry.bytes += sheet.get_width()*sheet.get_height()*4 if sheet != null else 0
		by_folder[folder] = entry
	var lines: Array = []
	for folder in by_folder:lines.append("%s: %d sheets, %.1f MB" % [folder,by_folder[folder].count,by_folder[folder].bytes/MB])
	print("[probe] SheetFrames keeps (never freed): %s" % "; ".join(lines))
	rows.append({"step":"cache_report","sheet_frames":by_folder})

## Whether a loaded texture keeps a CPU copy: load a sheet nothing has used,
## compare the static (CPU) growth with the texture memory growth.
func cpu_copy_check() -> void:
	var candidate := ""
	for asset in assets:
		if asset[1] == "riding/sheets" and not ResourceLoader.has_cached(asset[0]):
			candidate = asset[0]
			break
	if candidate.is_empty():return
	var static_before := OS.get_static_memory_usage()
	var texture_before := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var sheet: Texture2D = load(candidate)
	var static_after := OS.get_static_memory_usage()
	var texture_after := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var result := {"step":"cpu_copy_check","path":candidate,"size":[sheet.get_width(),sheet.get_height()],"rgba_mb":sheet.get_width()*sheet.get_height()*4/MB,"static_delta_mb":(static_after-static_before)/MB,"texture_delta_mb":(texture_after-texture_before)/MB}
	print("[probe] cpu copy check: %s" % JSON.stringify(result))
	rows.append(result)
	sheet = null

## What parsing each big JSON costs in memory (Variant dictionaries), against its
## file size; for world/*.map, what the loaded packed map holds.
func json_costs() -> void:
	var files := ["battle/manifest.json","riding/manifest.json","battle/backgrounds.json","characters/catalog.json","encounters/catalog.json","world/manifest.json","world/200.map","world/100.map","world/300.map","world/1000.map","faces/manifest.json","ui/manifest.json","samgir.json"]
	var results: Array = []
	for name in files:
		if FileAccess.file_exists(LEGACY+name):results.append(_parse_cost(name))
	var held := {
		"BattleArt._data (battle manifest + merged pets)":var_to_bytes(BattleArt.data()).size()/MB,
		"Riding manifest":var_to_bytes(Riding._manifest).size()/MB,
		"game.character_catalog":var_to_bytes(game.character_catalog).size()/MB,
		"game.data (current map)":var_to_bytes(game.data).size()/MB,
		"encounter catalog":var_to_bytes(game.encounter_catalog.data).size()/MB,
		"faces manifest":var_to_bytes(Faces._manifest).size()/MB,
		"battle backgrounds catalog":var_to_bytes(game.battle_view.background_selector.catalog).size()/MB,
	}
	for line in results:print("[probe] json %s: file %.1f MB -> parsed %.1f MB static (var_to_bytes %.1f MB)" % [line.file,line.file_mb,line.parsed_mb,line.var_to_bytes_mb])
	print("[probe] held at the end (var_to_bytes MB): %s" % JSON.stringify(held))
	rows.append({"step":"json_costs","files":results,"held":held})

## One file's parse, measured with its text already read; the temporaries go
## when the function returns, so files do not disturb each other.
static func _parse_cost(name: String) -> Dictionary:
	if name.ends_with(".map"):
		var map_before := OS.get_static_memory_usage()
		var map := MapFile.load_map(LEGACY+name)
		var map_after := OS.get_static_memory_usage()
		return {"file":name,"file_mb":MapFile.file_size(LEGACY+name)/MB,"parsed_mb":(map_after-map_before)/MB,"var_to_bytes_mb":var_to_bytes(map).size()/MB}
	var text := FileAccess.get_file_as_string(LEGACY+name)
	var before := OS.get_static_memory_usage()
	var parsed = JSON.parse_string(text)
	var after := OS.get_static_memory_usage()
	return {"file":name,"file_mb":text.to_utf8_buffer().size()/MB,"parsed_mb":(after-before)/MB,"var_to_bytes_mb":var_to_bytes(parsed).size()/MB}

func write_out() -> void:
	if out_path.is_empty():return
	var file := FileAccess.open(out_path,FileAccess.WRITE)
	if file == null:
		print("[probe] cannot write %s" % out_path)
		return
	file.store_string(JSON.stringify(rows,"  "))
	print("[probe] wrote %s" % out_path)
