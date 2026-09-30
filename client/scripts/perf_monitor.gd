extends RefCounted
## The numbers behind 开发者性能面板 (scripts/perf_panel.gd), kept apart from
## the panel so a probe script or test can take the same measurements:
## sample() reads the engine, the browser (web only), asset packs, the
## network link, the in-process backend and scripts/perf_registry.gd once;
## lines() and snapshot() turn a sample into panel text and a JSON-ready
## Dictionary. Nothing here runs unless someone asks for a sample.
## See docs/technical/perf-panel.md for what each number means.
const PerfRegistry = preload("res://scripts/perf_registry.gd")

## Counters from the previous sample, for per-second rates.
var _previous_net: Dictionary = {}
var _previous_msec := -1
var _previous_frames := -1

## Everything at once. world is the game scene (or null for a bare probe).
func sample(world: Object = null) -> Dictionary:
	var now := Time.get_ticks_msec()
	var frames := Engine.get_process_frames()
	var seconds := float(now-_previous_msec)/1000.0 if _previous_msec>=0 else 0.0
	var result := {"engine":engine(),"web":web(),"registry":PerfRegistry.summary()}
	result.engine.frame_ms = snappedf(seconds*1000.0/float(frames-_previous_frames),0.01) if seconds>0.0 and frames>_previous_frames else 0.0
	_previous_msec = now
	_previous_frames = frames
	if world!=null:
		var packs = world.get("asset_packs")
		if packs!=null and packs.has_method("stats"):result.packs = packs.stats()
		var link = world.get("link")
		var counters: Dictionary = link.stats() if link!=null and link.has_method("stats") else {}
		result.network = rates(_previous_net,counters,seconds)
		_previous_net = counters
		var state = world.get("state")
		var automation = state.get("automation") if state!=null else null
		var hunt: Dictionary = automation.get("hunt",{}) if automation is Dictionary else {}
		if bool(hunt.get("fast",false)):result.fast_hunt = {"threads":int(hunt.get("threads_used",0)),"budget":int(hunt.get("budget",0)),"hunters":int(hunt.get("hunters",1))}
		var backend = world.get("backend")
		if backend!=null and "tick_usec" in backend:
			result.backend = {"tick_ms":snappedf(float(backend.tick_usec)/1000.0,0.001),"tick_avg_ms":snappedf(float(backend.tick_avg_usec)/1000.0,0.001)}
	return result

## Godot's own monitors (docs: Performance).
static func engine() -> Dictionary:
	return {
		"fps":Performance.get_monitor(Performance.TIME_FPS),
		"process_ms":snappedf(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,0.01),
		"physics_ms":snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,0.01),
		"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"static_peak_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"texture_bytes":int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"buffer_bytes":int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		"video_bytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects_drawn":int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}

## The page evaluates this inside the engine's own scope (not the global one),
## where Emscripten keeps wasmMemory and HEAP8. performance.memory is Chrome's;
## Safari has none.
const WEB_PROBE := "(function(){var r={wasm:0};try{if(typeof wasmMemory!=='undefined'&&wasmMemory)r.wasm=wasmMemory.buffer.byteLength;}catch(e){}try{if(!r.wasm&&typeof HEAP8!=='undefined'&&HEAP8)r.wasm=HEAP8.length;}catch(e){}try{if(!r.wasm&&typeof Module!=='undefined'&&Module.HEAP8)r.wasm=Module.HEAP8.length;}catch(e){}var m=(typeof performance!=='undefined'&&performance.memory)||null;if(m){r.js_used=m.usedJSHeapSize;r.js_total=m.totalJSHeapSize;r.js_limit=m.jsHeapSizeLimit;}return JSON.stringify(r);})()"

## Web only: {wasm, js_used?, js_total?, js_limit?} in bytes; {} elsewhere.
static func web() -> Dictionary:
	if not OS.has_feature("web"):return {}
	var text = JavaScriptBridge.eval(WEB_PROBE,false)
	var parsed = JSON.parse_string(str(text)) if text is String else null
	if not parsed is Dictionary:return {}
	var result := {}
	for key in parsed:result[key] = int(parsed[key])
	return result

## Per-second rates between two link counter sets ({messages_in, messages_out,
## bytes_in, bytes_out, latency_ms}); the first sample has no rates yet.
static func rates(previous: Dictionary, current: Dictionary, seconds: float) -> Dictionary:
	if current.is_empty():return {}
	var result := {"kind":str(current.get("kind","")),"latency_ms":int(current.get("latency_ms",-1))}
	for key in ["messages_in","messages_out","bytes_in","bytes_out"]:
		result[key] = int(current.get(key,0))
		result[key+"_per_s"] = snappedf(float(int(current.get(key,0))-int(previous.get(key,0)))/seconds,0.1) if seconds>0.0 and previous.has(key) else 0.0
	return result

# ---- text --------------------------------------------------------------------

static func format_bytes(bytes: float) -> String:
	if bytes<0:return "—"
	if bytes<1024:return "%d B" % int(bytes)
	if bytes<1024*1024:return "%.1f KB" % (bytes/1024.0)
	if bytes<1024.0*1024*1024:return "%.1f MB" % (bytes/1048576.0)
	return "%.2f GB" % (bytes/1073741824.0)

## The main column: memory, performance, network.
static func lines(data: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var e: Dictionary = data.get("engine",{})
	out.append("【内存】")
	out.append("静态 %s（峰值 %s）" % [format_bytes(e.get("static_bytes",0)),format_bytes(e.get("static_peak_bytes",0))])
	out.append("显存 %s · 纹理 %s · 缓冲 %s" % [format_bytes(e.get("video_bytes",0)),format_bytes(e.get("texture_bytes",0)),format_bytes(e.get("buffer_bytes",0))])
	var web: Dictionary = data.get("web",{})
	if not web.is_empty():
		out.append("wasm 堆 %s" % (format_bytes(web.wasm) if int(web.get("wasm",0))>0 else "不可用"))
		if web.has("js_used"):out.append("JS 堆 %s / %s（上限 %s）" % [format_bytes(web.js_used),format_bytes(web.get("js_total",0)),format_bytes(web.get("js_limit",0))])
		else:out.append("JS 堆 不可用（仅 Chrome 提供）")
	var packs: Dictionary = data.get("packs",{})
	if bool(packs.get("enabled",false)):
		out.append("资源包 已挂载 %d 个 %s" % [int(packs.mounted),format_bytes(packs.mounted_bytes)])
		out.append("　本次下载 %d 个 %s · 等待 %d%s" % [int(packs.downloaded),format_bytes(packs.downloaded_bytes),int(packs.pending)," · 失败 %d" % int(packs.failed) if int(packs.get("failed",0))>0 else ""])
	out.append("【性能】")
	out.append("FPS %d · 帧 %.1f ms · 逻辑 %.1f ms · 物理 %.1f ms" % [int(e.get("fps",0)),float(e.get("frame_ms",0)),float(e.get("process_ms",0)),float(e.get("physics_ms",0))])
	out.append("绘制调用 %d · 绘制对象 %d" % [int(e.get("draw_calls",0)),int(e.get("objects_drawn",0))])
	out.append("对象 %d · 节点 %d · 资源 %d · 孤立节点 %d" % [int(e.get("objects",0)),int(e.get("nodes",0)),int(e.get("resources",0)),int(e.get("orphan_nodes",0))])
	var net: Dictionary = data.get("network",{})
	if not net.is_empty():
		out.append("【网络】%s" % ("本机后台" if net.kind=="local" else "WebSocket"))
		if net.kind=="local":
			out.append("消息 收 %.1f/s · 发 %.1f/s" % [float(net.messages_in_per_s),float(net.messages_out_per_s)])
		else:
			out.append("收 %.1f 条/s %s/s · 发 %.1f 条/s %s/s" % [float(net.messages_in_per_s),format_bytes(net.bytes_in_per_s),float(net.messages_out_per_s),format_bytes(net.bytes_out_per_s)])
			out.append("延迟 %s · 累计 收 %s 发 %s" % ["%d ms" % int(net.latency_ms) if int(net.latency_ms)>=0 else "—",format_bytes(net.bytes_in),format_bytes(net.bytes_out)])
	var backend: Dictionary = data.get("backend",{})
	if not backend.is_empty():
		out.append("后台 tick %.2f ms（平均 %.2f ms）" % [float(backend.tick_ms),float(backend.tick_avg_ms)])
	var fast: Dictionary = data.get("fast_hunt",{})
	if not fast.is_empty():
		out.append("极速筛选 线程 %d/%d%s" % [int(fast.threads),int(fast.budget),"（%d 人共享）" % int(fast.hunters) if int(fast.hunters)>1 else ""])
	return out

## The breakdown column: tracked textures, audio and manifests by owner.
static func breakdown_lines(data: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var registry: Dictionary = data.get("registry",{})
	var textures: Dictionary = registry.get("textures",{})
	out.append("【纹理 · 估算】共 %s" % format_bytes(registry.get("texture_bytes",0)))
	for entry in PerfRegistry.TEXTURES:
		if textures.has(entry[0]):out.append("%s %d 张 %s" % [entry[1],int(textures[entry[0]].count),format_bytes(textures[entry[0]].bytes)])
	var engine_textures := int(data.get("engine",{}).get("texture_bytes",0))
	if engine_textures>0:out.append("未登记 %s" % format_bytes(maxi(0,engine_textures-int(registry.get("texture_bytes",0)))))
	var audio: Dictionary = registry.get("audio",{})
	out.append("【音频】共 %s" % format_bytes(registry.get("audio_bytes",0)))
	for entry in PerfRegistry.AUDIO:
		if audio.has(entry[0]):out.append("%s %d 个 %s · %d 秒" % [entry[1],int(audio[entry[0]].count),format_bytes(audio[entry[0]].bytes),int(audio[entry[0]].seconds)])
	var manifests: Dictionary = registry.get("manifests",{})
	out.append("【清单 JSON】共 %s" % format_bytes(registry.get("manifest_bytes",0)))
	var names: Array = manifests.keys()
	names.sort_custom(func(a,b): return int(manifests[a])>int(manifests[b]))
	for name in names:out.append("%s %s" % [name,format_bytes(manifests[name])])
	return out

# ---- snapshot ----------------------------------------------------------------

## A sample with what is needed to compare it later: version, time, platform,
## window size and the largest textures.
static func snapshot(data: Dictionary, viewport_size: Vector2 = Vector2.ZERO) -> Dictionary:
	var result := data.duplicate(true)
	result.version = str(ProjectSettings.get_setting("application/config/version",""))
	result.engine_version = Engine.get_version_info().string
	result.platform = OS.get_name()+(" web" if OS.has_feature("web") else "")
	result.renderer = str(ProjectSettings.get_setting("rendering/renderer/rendering_method",""))
	result.time = Time.get_datetime_string_from_system(true)
	result.unix_time = int(Time.get_unix_time_from_system())
	result.viewport = [int(viewport_size.x),int(viewport_size.y)]
	result.largest_textures = PerfRegistry.largest_textures()
	return result

static func snapshot_name(unix_time: int) -> String:
	return "perf-%s.json" % Time.get_datetime_string_from_unix_time(unix_time).replace(":","").replace("-","").replace("T","-")
