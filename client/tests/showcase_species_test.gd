extends SceneTree
## 后台搜宠 keeps one queue per species (server/automation.gd): each species'
## queue holds up to hunt.queue hits ranked by its own 保留规则 order; a full
## species drops only its own last hit (未捕获·排队已满, naming the species),
## never another species' hit; captures take the best hit of each species in
## turn (round-robin); a resume file with the earlier single shared queue is
## split per species on restart. The real backend and find-pet cycle run;
## the hits are real newborn rolls (the other species are the same rolls
## under another real template id, so their stats compare across species).
const Backend = preload("res://server/backend.gd")
const Progression = preload("res://server/progression.gd")
const SAVE := "user://showcase-species-test.json"
const MAP := 100
const CELL := Vector2i(637,493)
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func clean() -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))
	for ext in [".resume.json",".stop-log.jsonl",".release-log.jsonl",".capture-log.jsonl"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE.get_basename()+ext))

func new_backend(from_save: bool):
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	if from_save:check(backend.load_profile(SAVE),"the save loads after the restart")
	backend.save_path = SAVE
	backend.automation.client_attached = false
	return backend

func start(backend) -> void:
	backend.handle({"type":"grant_starter_pets"})
	backend.handle({"type":"set_automation_settings","settings":{"hunt":{"fast":false,"total":-8,"offsets":[-2,-2,-2,-2],"showcase":true,"queue":3,"auto_capture":true,"train_after_capture":true}}})
	backend.handle({"type":"report_position","map_id":MAP,"cell":[CELL.x,CELL.y]})
	var started: Dictionary = backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y]})
	check(bool(started.ok) and backend.automation.flow_showcase and backend.automation.queue_limit()==3,"a find-pet cycle with 后台搜宠 runs, 排队上限 3")

## A real capturable Lv1 newborn rolled at the hunt's spot.
func newborn(backend) -> Dictionary:
	var rng := RandomNumberGenerator.new();rng.seed = 4242
	for i in range(400):
		for actor in backend.encounter_catalog.roll(MAP,CELL,rng).get("enemies",[]):
			if int(actor.level)==1 and actor.can_capture:return actor
	return {}

## A hit of species `template` (its real name) with its own growth.
func hit(backend, base: Dictionary, template: int, growth: int) -> Dictionary:
	var actor: Dictionary = base.duplicate(true)
	actor.template_id = template
	actor.name = str(backend.encounter_catalog.data.templates.get(str(template),{}).get("name","#%d" % template))
	actor.growth_seed = growth
	return actor

func enqueue(automation, index: int, actor: Dictionary) -> void:
	automation._showcase_enqueue(index,0,{"enemies":[actor]},{"valid":true,"offsets":[0,0,0,0],"total_offset":0})

func templates_of(entries: Array) -> Array:
	return entries.map(func(e):return int(e.actor.template_id))

## The queue is grouped by species and each group is best first.
func grouped(automation) -> bool:
	var queue: Array = automation.showcase_queue
	for i in range(1,queue.size()):
		var a: Dictionary = queue[i-1]
		var b: Dictionary = queue[i]
		if int(a.actor.template_id)>int(b.actor.template_id):return false
		if int(a.actor.template_id)==int(b.actor.template_id) and automation._showcase_better(b,a):return false
	var seen := []
	for id in templates_of(queue):
		if seen.has(id) and seen.back()!=id:return false
		if not seen.has(id):seen.append(id)
	return true

func run() -> void:
	clean()
	var backend = new_backend(false)
	start(backend)
	var automation = backend.automation
	var base := newborn(backend)
	check(not base.is_empty(),"a real newborn to queue")
	var ids: Array = backend.encounter_catalog.data.templates.keys().map(func(key):return int(key)).filter(func(id):return id!=int(base.template_id))
	ids.sort()
	var a := int(base.template_id)
	var b := int(ids[0])
	var c := int(ids[1])
	backend.session.release_events.clear()

	# Species A fills its queue and overflows; B and C stay untouched.
	var a_hits: Array = []
	for i in range(5):
		var actor := hit(backend,base,a,8000+i*53)
		a_hits.append(actor)
		enqueue(automation,i,actor)
	for i in range(2):enqueue(automation,10+i,hit(backend,base,b,8000+i*53))
	enqueue(automation,20,hit(backend,base,c,8000))
	check(automation._species_queue(a).size()==3 and automation._species_queue(b).size()==2 and automation._species_queue(c).size()==1,"each species keeps its own queue up to the limit (A 3, B 2, C 1)")
	check(grouped(automation),"the queue is grouped by species, each best first by its keep rule")
	var dropped: Array = backend.session.release_events.filter(func(e):return str(e.get("source",""))=="排队已满")
	check(dropped.size()==2 and dropped.all(func(e):return int(e.template_id)==a),"only species A's overflow is dropped")
	var a_name := str(backend.encounter_catalog.data.templates.get(str(a),{}).get("name",""))
	check(dropped.size()==2 and dropped.all(func(e):return str(e.reason).begins_with(a_name+"的排队已满（每个品种上限3）")),"the reason names the species' queue (%s)" % (str(dropped[0].reason) if not dropped.is_empty() else ""))
	check(dropped.all(func(e):return not e.beaten_by.is_empty() and e.beaten_by.all(func(other):return str(other.name)==a_name)),"only hits of its own species beat it")
	# The kept A hits are the best 3 by A's ranking.
	var ranked: Array = a_hits.map(func(actor):return {"index":0,"actor":actor,"prediction":automation._prediction(Progression.project_pet(actor,120))})
	ranked.sort_custom(automation._showcase_better)
	check(automation._species_queue(a).map(func(e):return e.prediction)==ranked.slice(0,3).map(func(e):return e.prediction),"A keeps its best 3")

	# A hit worse than every A hit still joins B's queue: no cross-species dropping.
	var b_before: Array = automation._species_queue(b).map(func(e):return int(e.index))
	var weakest: Dictionary = {}
	for i in range(200):
		var actor := hit(backend,base,b,9000+i)
		var p: Dictionary = automation._prediction(Progression.project_pet(actor,120))
		if ranked.all(func(e):return int(p.attack)<int(e.prediction.attack)):weakest = actor;break
	check(not weakest.is_empty(),"a B hit weaker than every A hit")
	var released_before: int = backend.session.release_events.size()
	enqueue(automation,30,weakest)
	check(automation._species_queue(b).size()==3 and automation._species_queue(a).size()==3 and backend.session.release_events.size()==released_before,"it joins B's queue and nothing of A is dropped")
	check(automation._species_queue(b).map(func(e):return int(e.index)).filter(func(index):return b_before.has(index)).size()==2,"B's earlier hits stay")

	# The 排队 view groups by species with per-species ranks.
	var view: Dictionary = backend.handle({"type":"hunt_queue"}).queue
	var species := [a,b,c];species.sort()
	check(view.groups.map(func(g):return int(g.template_id))==species,"hunt_queue lists the species groups")
	check(view.groups.map(func(g):return int(g.count))==[automation._species_queue(view.groups[0].template_id).size(),automation._species_queue(view.groups[1].template_id).size(),automation._species_queue(view.groups[2].template_id).size()] and int(view.limit)==3,"each group with its count; the limit is per species")
	check(view.entries.filter(func(e):return int(e.rank)==1).size()==3,"ranks count within each species")

	# Resume: an older file holds one shared queue (any order, no round-robin
	# field); the restart splits it per species, each best first.
	var state: Dictionary = automation.resume_state()
	var mixed: Array = state.flow.showcase_queue.duplicate(true)
	mixed.reverse()
	state.flow.showcase_queue = mixed
	state.flow.erase("showcase_last_template")
	var kept_rolls: Array = automation.showcase_queue.map(func(e):return int(e.index));kept_rolls.sort()
	automation.record_shutdown()
	check(backend.save(),"the save goes through")
	backend.queue_free()
	await process_frame
	var fresh = new_backend(true)
	fresh.automation.load_resume(JSON.parse_string(JSON.stringify(state)))
	fresh.automation.try_resume()
	automation = fresh.automation
	var rolls: Array = automation.showcase_queue.map(func(e):return int(e.index));rolls.sort()
	check(automation.flow_active() and automation.flow_showcase and rolls==kept_rolls,"after the restart the cycle goes on with every queued hit")
	check(grouped(automation),"the old shared queue is split per species, each best first")

	# Round-robin: each capture takes the best hit of the next species.
	var left := {}
	for id in species:left[id] = automation._species_queue(id).size()
	var expected: Array = []
	while expected.size()<automation.showcase_queue.size():
		for id in species:
			if int(left[id])>0:
				expected.append(id);left[id] = int(left[id])-1
	var taken: Array = []
	var best_first := true
	while not automation.showcase_queue.is_empty():
		var entry: Dictionary = automation._take_queued()
		var rest: Array = automation._species_queue(int(entry.actor.template_id))
		if not rest.is_empty() and automation._showcase_better(rest[0],entry):best_first = false
		taken.append(int(entry.actor.template_id))
	check(taken==expected,"captures go round the species with hits: %s" % str(taken))
	check(best_first,"each takes its species' best hit")
	fresh.handle({"type":"auto_stop"})
	fresh.queue_free()
	await process_frame
	clean()
	print("SHOWCASE SPECIES: %d failures" % failures)
	quit(1 if failures else 0)
