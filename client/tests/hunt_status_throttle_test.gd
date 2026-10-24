extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## Real encounter/core queue, real clock and two WebSocket devices. Progress
## coalesces without dropping transitions, records or restart counters.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const WsLink = preload("res://network/ws_link.gd")
const State = preload("res://network/client_state.gd")
const Wait = preload("res://tests/support/wait.gd")
const ConditionsOff = preload("res://tests/support/conditions_off.gd")
const Ticker = preload("res://scripts/showcase_ticker.gd")
var failures := 0
var messages: Array = []
var log_messages: Array = []
var links: Array = []
var states: Array = []

func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1
func _process(delta: float) -> bool:
	for link in links:link.poll(delta)
	return false
func settle() -> void:
	for link in links:
		var answered := [false]
		link.request({"type":"ping"},func(_reply):answered[0]=true)
		check(await Wait.until(self,func():return answered[0]),"device round trip settles")
func run() -> void:
	var backend = Backend.new();root.add_child(backend);backend.set_process(false)
	backend.handle({"type":"grant_starter_pets"})
	var rng := RandomNumberGenerator.new();rng.seed=4242
	var actor: Dictionary = {}
	for i in range(400):
		for candidate in backend.encounter_catalog.roll(100,Vector2i(637,493),rng).get("enemies",[]):
			if int(candidate.level)==1 and candidate.can_capture:actor=candidate;break
		if not actor.is_empty():break
	check(not actor.is_empty(),"real seeded encounter supplies a newborn")
	if actor.is_empty():quit(1);return
	var id := int(actor.template_id)
	backend.handle({"type":"set_automation_settings","settings":ConditionsOff.patch([id]).merged({"hunt":{"fast":false,"showcase":true,"queue":3,"total":-8,"offsets":[-2,-2,-2,-2]}})})
	backend.handle({"type":"report_position","map_id":100,"cell":[637,493]})
	check(backend.handle({"type":"auto_start","kind":"find_pet","map_id":100,"cell":[637,493]}).ok,"real find-pet workflow starts")
	var server = WsServer.new(backend,0,"127.0.0.1");root.add_child(server)
	check(server.start()==OK,"server uses an ephemeral port")
	for i in range(2):
		var state = State.new();states.append(state)
		var link = WsLink.new("ws://127.0.0.1:%d" % server.port);links.append(link)
		link.message.connect(state.apply);link.connect_now()
	check(await Wait.until(self,func():return links.all(func(link):return link.online)),"two remote devices connect")
	await settle()
	backend.event.connect(func(message):
		if message.type=="auto_status":messages.append(message.duplicate(true))
		if message.type=="pet_log_changed":log_messages.append(message.duplicate(true)))
	var sent_at := Clock.ticks_msec()
	backend.automation._emit_status()
	messages.clear()
	var automation = backend.automation
	for i in range(30):
		var variant: Dictionary=actor.duplicate(true);variant.growth_seed=7000+i*37
		automation._showcase_enqueue(100+i,0,{"enemies":[variant]},{"valid":true,"offsets":[0,0,0,0],"total_offset":0})
	check(messages.is_empty(),"burst queue churn builds/sends no progress snapshots inside one second")
	check(automation.showcase_dropped_count==27 and automation.showcase_dropped_species=={str(id):27},"all queue removals counted per species")
	check(backend.session.release_events.size()==27 and backend.session.release_events.all(func(e):return e.uncaught and e.source=="排队已满" and not e.beaten_by.is_empty() and e.has("run_seed")),"all detailed release reasons, beaters and replay seeds survive")
	check(automation.showcase_log.is_empty(),"queue churn adds no individual information lines")
	backend._record_releases()
	check(log_messages.size()==1 and backend.release_log.entries().size()==27,"every detail persists while one records invalidation is sent")
	for i in range(3):
		automation._showcase_enqueue(200+i,0,{"enemies":[actor]},{"valid":true,"offsets":[0,0,0,0],"total_offset":0})
		backend._record_releases()
	check(log_messages.size()==1 and backend.release_log.entries().size()==30,"further uncaught records persist immediately without notification churn")
	var other = Backend.new();root.add_child(other);other.set_process(false)
	check(other.automation.showcase_dropped_count==0 and other.automation.showcase_dropped_species.is_empty(),"another profile has independent removal counters")
	other.queue_free()
	var resume: Dictionary=automation.resume_state()
	check(int(resume.flow.get("showcase_dropped_count",-1))==30 and resume.flow.showcase_dropped_species=={str(id):30},"resume snapshot keeps counts")
	check(await Wait.until(self,func():
		automation.tick_battle(0.0)
		backend._record_releases()
		return messages.size()==1 and log_messages.size()==2),"pending progress flushes using the real clock")
	check(Clock.ticks_msec()-sent_at>=1000,"progress flush waits for its one-second deadline")
	await settle()
	check(log_messages.size()==2 and log_messages.back().revision==backend.pet_log_revision,"records invalidation eventually carries the newest revision")
	check(states.all(func(state):return int(state.automation.flow.queue_dropped)==30),"both devices receive the same accumulated count")
	var lines: Array=Ticker.shown_lines(states[0].automation)
	check(lines.size()==1 and str(lines[0].text).contains("排队淘汰 30 只") and str(lines[0].text).contains(str(actor.name)),"one named species summary replaces individual drops")
	automation.hunt_rolls+=1;automation._emit_status(true)
	check(messages.size()==1,"next progress change remains pending")
	automation.stop_cycle("测试暂停")
	check(messages.size()>1 and messages.back().status.flow.phase=="paused" and not messages.back().status.hunt.running,"pause supersedes pending progress immediately")
	await settle()
	check(states.all(func(state):return state.automation.flow.phase=="paused" and not state.automation.hunt.running),"pause is actionable on both devices immediately")
	for link in links:link.close()
	server.stop();backend.queue_free();server.queue_free()
	await process_frame
	print("HUNT STATUS THROTTLE: %d failures" % failures);quit(1 if failures else 0)
