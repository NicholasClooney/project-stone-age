extends SceneTree
## Backend automation without any game scene: the detached runner settles and
## saves battles on its own tick, and an attached client can pace it only up
## to the presentation ceiling.
const Backend = preload("res://server/backend.gd")
const TroopArt = preload("res://server/troop_art.gd")
const SAVE := "user://backend-automation-test.json"
const MAP := 100
const CELL := [637,493]
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func choose_seed(backend, count: int) -> int:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(10000):
		rng.seed = seed_value
		var valid := true
		for i in range(count):
			var troop: Dictionary = backend.encounter_catalog.roll(MAP,Vector2i(CELL[0],CELL[1]),rng)
			if troop.is_empty() or not TroopArt.can_render(troop.enemies):valid = false;break
		if valid:return seed_value
	return -1

func strong_backend():
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	for command in [{"type":"gm_raise_level","index":-1,"target":10},{"type":"gm_set_base_stat","index":-1,"stat":"strength","value":100},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":100},{"type":"gm_heal"}]:
		backend.handle(command)
	return backend

func run() -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))
	# ---- detached: nothing presents, so nothing paces ----
	var backend = strong_backend()
	backend.save_path = SAVE
	var kinds := {}
	backend.event.connect(func(message: Dictionary):kinds[str(message.type)] = int(kinds.get(str(message.type),0))+1)
	var seed_value := choose_seed(backend,2)
	check(seed_value>=0,"deterministic renderable troops exist at the test location")
	backend.encounter_rng.seed = seed_value
	backend.automation.client_attached = false
	var before: Dictionary = backend.session.snapshot()
	var reply: Dictionary = backend.handle({"type":"auto_start","kind":"battle","map_id":MAP,"cell":CELL,"settings":{"compact":false,"limit":2,"hp":1,"xp":100,"speed":8.0,"preset":"attack","level":120}})
	check(reply.ok and backend.automation.running,"backend accepts an automation start with no client")
	for i in range(5000):
		if not backend.automation.running:break
		backend._process(0.05)
	var after: Dictionary = backend.session.snapshot()
	check(backend.automation.battles==2 and backend.automation.stop_reason=="已达到战斗场次上限","detached runner settles two full battles on its own tick")
	check(backend.session._pending.is_empty() and not backend.battle_open,"no battle is left pending or open")
	check(int(after.player.level)>int(before.player.level),"settlement awards experience without a client")
	check(int(kinds.get("battle_started",0))==2 and int(kinds.get("battle_closed",0))==2 and int(kinds.get("battle_turn",0))>=2,"each battle still emits presentable events")
	var saved := FileAccess.get_file_as_string(SAVE)
	var parsed = JSON.parse_string(saved)
	check(parsed is Dictionary and int(parsed.player.level)==int(after.player.level),"progress is saved by the backend itself")
	backend.queue_free()

	# ---- attached: presentation paces turns, but only up to the ceiling ----
	backend = strong_backend()
	backend.encounter_rng.seed = seed_value
	backend.handle({"type":"auto_start","kind":"battle","map_id":MAP,"cell":CELL,"settings":{"compact":false,"limit":1,"hp":1,"speed":8.0,"preset":"attack","level":120}})
	backend.handle({"type":"auto_step"})
	check(backend.battle_open and int(backend.battle.snapshot().turn)==0,"attached runner opens a battle")
	backend.handle({"type":"auto_step"})
	check(int(backend.battle.snapshot().turn)==0,"runner waits for the client to finish presenting")
	backend.handle({"type":"presented","battle_id":str(backend.battle.snapshot().battle_id),"turn":0})
	backend.handle({"type":"auto_step"})
	check(int(backend.battle.snapshot().turn)==1,"acknowledged presentation releases the next turn")
	backend.handle({"type":"auto_step"})
	var waited := int(backend.battle.snapshot().turn)
	OS.delay_msec(backend.automation.PRESENT_TIMEOUT_MSEC+100)
	backend.handle({"type":"auto_step"})
	check(waited==1 and (int(backend.battle.snapshot().turn)==2 or not backend.battle.snapshot().active),"an unresponsive client cannot stall automation past the ceiling")
	backend.handle({"type":"auto_stop"})
	check(not backend.automation.running,"stop command ends the runner")
	backend.queue_free()
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))
	await process_frame
	print("BACKEND AUTOMATION: %d failures" % failures)
	quit(1 if failures else 0)
