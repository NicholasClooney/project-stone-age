extends SceneTree
## 开发者性能面板: the registry's accounting (textures, audio, manifests,
## freed resources dropping out), number formatting, the panel text, network
## rates and the snapshot JSON, then the panel in the game: F3 and 设置 →
## 开发者 open it, it refreshes only while open, lets the mouse through except
## its buttons, and 导出快照 writes a JSON file.
const PerfRegistry = preload("res://scripts/perf_registry.gd")
const PerfMonitor = preload("res://scripts/perf_monitor.gd")
const PREFS := "user://perf-panel-test.cfg"
const SNAPSHOTS := "user://perf-panel-test-snapshots/"
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event,true)

func picture(width: int, height: int, format: Image.Format) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create(width,height,false,format))

func run() -> void:
	registry()
	formatting()
	await in_game()
	print("PERF PANEL: %d failures" % failures)
	quit(1 if failures else 0)

func registry() -> void:
	PerfRegistry.reset()
	check(PerfRegistry.texture_bytes(64,32,Image.FORMAT_RGBA8)==8192 and PerfRegistry.texture_bytes(64,32,Image.FORMAT_L8)==2048 and PerfRegistry.texture_bytes(64,64,Image.FORMAT_DXT5)==4096,"texture bytes follow the pixel format")
	check(PerfRegistry.texture_bytes(64,64,Image.FORMAT_RGBA8,true)==int(64*64*4*4.0/3.0),"mipmaps add a third")
	check(PerfRegistry.folder_category("res://assets/legacy/riding/")=="riding" and PerfRegistry.folder_category("res://assets/legacy/battle/")=="battle" and PerfRegistry.folder_category("res://assets/legacy/faces/")=="faces" and PerfRegistry.folder_category("res://assets/legacy/characters/")=="characters" and PerfRegistry.folder_category("res://elsewhere/")=="other","sheet folders map to their owners")
	var sheet := picture(64,32,Image.FORMAT_RGBA8)
	var tile := picture(16,16,Image.FORMAT_L8)
	PerfRegistry.track_texture("battle","a",sheet)
	PerfRegistry.track_texture("battle","a",sheet)
	PerfRegistry.track_texture("map","t",tile)
	PerfRegistry.track_texture("map","none",null)
	var sound := AudioStreamWAV.new()
	sound.mix_rate = 1000
	sound.format = AudioStreamWAV.FORMAT_8_BITS
	var samples := PackedByteArray()
	samples.resize(2000)
	sound.data = samples
	PerfRegistry.track_audio("effects",201,sound)
	PerfRegistry.track_manifest("battle",7000)
	PerfRegistry.track_manifest("riding",3000)
	var summary := PerfRegistry.summary()
	check(summary.textures.battle=={"count":1,"bytes":8192},"a texture reported twice counts once, at width × height × 4")
	check(summary.textures.map=={"count":1,"bytes":256} and not summary.textures.has("other"),"an L8 tile is one byte a pixel; null reports are ignored")
	check(summary.texture_bytes==8448,"the texture total adds the categories")
	check(summary.audio.effects.count==1 and summary.audio.effects.bytes==2000 and is_equal_approx(summary.audio.effects.seconds,2.0),"a WAV counts its data bytes and length")
	check(summary.manifests=={"battle":7000,"riding":3000} and summary.manifest_bytes==10000,"manifests keep their JSON sizes")
	check(PerfRegistry.largest_textures(1)==[{"category":"battle","key":"a","bytes":8192,"size":[64,32]}],"the largest textures are listed for snapshots")
	sheet = null
	summary = PerfRegistry.summary()
	check(not summary.textures.has("battle") and summary.texture_bytes==256,"a freed texture drops out without being reported")
	PerfRegistry.forget("map","t")
	check(PerfRegistry.summary().textures.is_empty(),"forget removes an entry")
	tile = null
	PerfRegistry.reset()

func formatting() -> void:
	check(PerfMonitor.format_bytes(512)=="512 B" and PerfMonitor.format_bytes(1536)=="1.5 KB" and PerfMonitor.format_bytes(5*1048576)=="5.0 MB" and PerfMonitor.format_bytes(3*1073741824.0)=="3.00 GB" and PerfMonitor.format_bytes(-1)=="—","bytes read as B, KB, MB and GB")
	var first := {"kind":"remote","messages_in":10,"messages_out":4,"bytes_in":1000,"bytes_out":200,"latency_ms":-1}
	check(PerfMonitor.rates({},first,0.5).messages_in_per_s==0.0,"the first sample has no rates yet")
	var later := {"kind":"remote","messages_in":20,"messages_out":5,"bytes_in":3000,"bytes_out":400,"latency_ms":12}
	var rates := PerfMonitor.rates(first,later,0.5)
	check(rates.messages_in_per_s==20.0 and rates.bytes_in_per_s==4000.0 and rates.messages_out_per_s==2.0 and rates.bytes_out_per_s==400.0 and rates.latency_ms==12 and rates.bytes_in==3000,"rates are per second between samples")
	check(PerfMonitor.rates(first,{},0.5).is_empty(),"no link, no network numbers")
	var sample := {
		"engine":{"fps":60,"frame_ms":16.67,"process_ms":2.5,"physics_ms":0.4,"static_bytes":200*1048576,"static_peak_bytes":250*1048576,"texture_bytes":90*1048576,"buffer_bytes":1048576,"video_bytes":100*1048576,"draw_calls":120,"objects_drawn":300,"objects":5000,"resources":800,"nodes":1500,"orphan_nodes":2},
		"web":{"wasm":512*1048576},
		"packs":{"enabled":true,"known":1100,"mounted":40,"mounted_bytes":60*1048576,"downloaded":3,"downloaded_bytes":2*1048576,"pending":1,"failed":0},
		"network":rates,
		"backend":{"tick_ms":0.25,"tick_avg_ms":0.2},
		"registry":{"textures":{"battle":{"count":3,"bytes":24*1048576},"ui":{"count":200,"bytes":4*1048576}},"texture_bytes":28*1048576,"audio":{"music":{"count":1,"bytes":1048576,"seconds":90.0}},"audio_bytes":1048576,"manifests":{"battle":7000000,"riding":11000000},"manifest_bytes":18000000},
	}
	var text := "\n".join(PerfMonitor.lines(sample))
	for part in ["静态 200.0 MB（峰值 250.0 MB）","显存 100.0 MB · 纹理 90.0 MB · 缓冲 1.0 MB","wasm 堆 512.0 MB","JS 堆 不可用","资源包 已挂载 40 个 60.0 MB","本次下载 3 个 2.0 MB · 等待 1","FPS 60 · 帧 16.7 ms · 逻辑 2.5 ms · 物理 0.4 ms","绘制调用 120","孤立节点 2","【网络】WebSocket","收 20.0 条/s 3.9 KB/s","延迟 12 ms","后台 tick 0.25 ms"]:
		check(text.contains(part),"the panel shows %s" % part)
	var details := PerfMonitor.breakdown_lines(sample)
	check(details[0]=="【纹理 · 估算】共 28.0 MB" and details[1]=="战斗图集 3 张 24.0 MB" and details[2]=="界面 200 张 4.0 MB" and details[3]=="未登记 62.0 MB","the breakdown lists texture owners in order and what nobody reported")
	check(details.has("音乐 1 个 1.0 MB · 90 秒") and details.find("riding 10.5 MB")<details.find("battle 6.7 MB") and details.has("riding 10.5 MB"),"audio and the largest manifests first")
	var local := PerfMonitor.lines({"engine":{},"network":{"kind":"local","messages_in_per_s":3.0,"messages_out_per_s":1.0,"latency_ms":-1}})
	check("\n".join(local).contains("【网络】本机后台") and "\n".join(local).contains("消息 收 3.0/s · 发 1.0/s") and not "\n".join(local).contains("wasm"),"an in-process game shows message rates and no browser numbers")
	var snapshot := PerfMonitor.snapshot(sample,Vector2(1280,800))
	var parsed = JSON.parse_string(JSON.stringify(snapshot))
	check(parsed is Dictionary and parsed.version==ProjectSettings.get_setting("application/config/version") and parsed.viewport==[1280.0,800.0] and parsed.engine.fps==60.0 and parsed.registry.manifests.riding==11000000.0 and parsed.has("time") and parsed.has("platform") and parsed.largest_textures is Array,"a snapshot is JSON with the build version, time, platform and every number")
	check(PerfMonitor.snapshot_name(0)=="perf-19700101-000000.json","snapshot files are named by time")

func in_game() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	game.viewer_prefs_path = PREFS
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.perf_panel==null,"the panel is not built until first used")
	var summary := PerfRegistry.summary()
	check(int(summary.textures.get("ui",{}).get("count",0))>0 and int(summary.textures.get("map",{}).get("count",0))>0,"the loaders report UI art and map tiles")
	check(summary.manifests.has("当前地图") and summary.manifests.has("world") and int(summary.audio.get("effects",{}).get("count",0))>0,"the map, world manifest and sound effects are reported")
	key(KEY_F3)
	await process_frame
	var panel = game.perf_panel
	check(panel!=null and panel.visible and panel.is_processing(),"F3 opens the panel and it refreshes")
	var text: String = panel.main_text.text
	check(text.contains("【内存】") and text.contains("【性能】") and text.contains("【网络】本机后台") and text.contains("后台 tick"),"the panel shows memory, performance, the local link and the backend tick")
	check(panel.breakdown_text.visible and panel.breakdown_text.text.contains("界面") and panel.breakdown_text.text.contains("当前地图"),"the breakdown shows the owners")
	var ignored := true
	for node in [panel.box,panel.main_text,panel.breakdown_text,panel.status,panel.box.get_parent()]:
		if node.mouse_filter!=Control.MOUSE_FILTER_IGNORE:ignored = false
	check(ignored,"the panel's background and text let the mouse through")
	var buttons: Array = panel.find_children("*","Button",true,false)
	check(buttons.size()==3 and buttons.all(func(b): return b.mouse_filter==Control.MOUSE_FILTER_STOP),"only its three buttons take clicks")
	await create_timer(0.6).timeout
	check(float(panel.last_sample.engine.frame_ms)>0.0,"it keeps sampling while open, with the frame time between samples")
	panel.find_child("PerfBreakdown",true,false).pressed.emit()
	check(not panel.breakdown_text.visible,"明细 hides the breakdown")
	panel.find_child("PerfBreakdown",true,false).pressed.emit()
	panel.snapshot_dir = SNAPSHOTS
	var path: String = panel.export_snapshot()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	check(saved is Dictionary and saved.version==ProjectSettings.get_setting("application/config/version") and saved.engine.has("static_bytes") and saved.network.kind=="local" and saved.registry.textures.has("ui"),"导出快照 writes every number as JSON with the version")
	check(panel.status.visible and panel.status.text.contains("已保存"),"and says where")
	if not path.is_empty():DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SNAPSHOTS))
	key(KEY_F3)
	await process_frame
	check(not panel.visible and not panel.is_processing(),"F3 closes it and it stops refreshing")
	# Over 设置: F3 still works, and 设置 → 开发者 has it too.
	game.settings_menu.open_menu()
	await process_frame
	key(KEY_F3)
	await process_frame
	check(panel.visible and game.settings_menu.visible,"F3 works over an open window")
	panel.find_child("PerfClose",true,false).pressed.emit()
	check(not panel.visible,"关闭 hides it")
	game.settings_menu.developer_open = true
	game.settings_menu.rebuild()
	var entry: Button = game.settings_menu.find_child("SettingsPerf",true,false)
	check(entry!=null and entry.text=="性能面板 [F3]","设置 → 开发者 lists 性能面板 with its key")
	entry.pressed.emit()
	await process_frame
	check(panel.visible and not game.settings_menu.visible,"it opens the panel and closes 设置")
	check(game.shortcuts.has("perf") and game.shortcuts.perf[0]==KEY_F3,"性能面板 is a rebindable shortcut, F3 by default")
	panel.close_panel()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
