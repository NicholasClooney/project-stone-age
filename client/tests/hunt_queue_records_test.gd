extends SceneTree
## 宠物记录's 排队 tab and stat sorting: the 后台搜宠 queue (automation.gd
## queue_view, backend hunt_queue) with the hit being caught on top, each
## queued hit's rank, roll, Lv, 成长档 and predicted Lv.120 stats, live while
## the window is open, on a remote client too; the stat headers sort 排队 and
## 放生 (highest first, again lowest first); 放生's 只看未捕获 shows the hits
## the queue let go with their reason and who beat them; tab, sorts and the
## filter are remembered per device.
const Backend = preload("res://server/backend.gd")
const Progression = preload("res://server/progression.gd")
const Wait = preload("res://tests/support/wait.gd")
const PREFS := "user://hunt-queue-records-test.cfg"
const REMOTE_PREFS := "user://hunt-queue-records-remote.cfg"
var failures := 0

class FixedTroop extends RefCounted:
	var troop: Dictionary
	func roll(_map, _cell, _rng, _held_items: Array = []) -> Dictionary:return troop.duplicate(true)

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## A real local Lv1 newborn at capture-ready health.
func newborn(game) -> Dictionary:
	var rng := RandomNumberGenerator.new();rng.seed = 1234
	for i in range(200):
		var rolled: Dictionary = game.encounter_catalog.roll(100,game.cell,rng)
		for actor in rolled.get("enemies",[]):
			if int(actor.level)==1 and actor.can_capture and game.battle_view.can_render_troop([actor]):
				actor.hp = 1
				return actor
	return {}

## The rolls of the rows on screen, top to bottom.
func shown_rolls(menu) -> Array:
	var result: Array = []
	for i in range(60):
		var row = menu.panel.find_child("QueueRow_%d" % i,true,false)
		if row==null:break
		result.append(int(str(row.tooltip_text).get_slice("第",1).get_slice("组",0)))
	return result

func press(menu, node_name: String) -> void:
	(menu.panel.find_child(node_name,true,false) as BaseButton).pressed.emit()
	await process_frame

func local() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game = load("res://scenes/main.tscn").instantiate();game.profile_persistence = false;game.viewer_prefs_path = PREFS;root.add_child(game)
	await process_frame
	game.session.grant_starter_pets()
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,120);game.session.gm_set_base_stat(-1,"toughness",500);game.session.gm_heal()
	var automation = game.backend.automation
	var flow = game.pet_workflow;flow.set_process(false)
	var hunt = game.pet_hunt_menu;hunt.set_process(false)
	game.training_helper.set_process(false)
	var menu = game.adventure_menu

	# No hunt: an empty state.
	menu.open_pet_records("queue",-1)
	await process_frame
	check(menu.records_tab=="queue" and menu.panel.find_child("QueueEmpty",true,false)!=null and menu.panel.find_child("QueueRow_0",true,false)==null,"排队 without a hunt shows an empty state")
	check(not bool(menu.records_data.get("active",true)),"the backend says no 后台搜宠 is running")
	menu.pet_records_open = false;game.close_adventure_menu()

	var actor := newborn(game)
	check(not actor.is_empty(),"a real local newborn is the fixture")
	var target := int(actor.template_id)
	game.link.request({"type":"set_automation_settings","settings":{"hunt":{"stop_after":0},"stat_filters":{str(target):{"threshold_mode":"absolute","conditions":{"sum":{"enabled":true,"value":1}},"keep_rule":{"tiers":0,"champions":0,"auto":true}}}}})
	hunt.apply_preset(0)
	check(flow.start_cycle(),"a find-pet cycle starts with 后台搜宠")
	var fixture := FixedTroop.new();fixture.troop = {"enemies":[actor]}
	hunt.hunt_catalog = fixture
	game.backend.session.release_events.clear()
	for i in range(11):
		var variant: Dictionary = actor.duplicate(true)
		variant.growth_seed = 7000+i*37
		automation._showcase_enqueue(100+i,0,{"enemies":[variant]},{"valid":true,"offsets":[1,0,-1,2],"total_offset":2})
	check(automation.showcase_queue.size()==10,"11 hits: the queue keeps its limit of 10")

	# The backend's view follows the queue's own order.
	var view: Dictionary = game.link.request({"type":"hunt_queue"}).queue
	var queued_rolls: Array = automation.showcase_queue.map(func(e):return int(e.index)+1)
	check(bool(view.active) and int(view.size)==10 and int(view.limit)==10 and view.entries.map(func(e):return int(e.roll))==queued_rolls,"hunt_queue lists the queue in its rank order")
	var first: Dictionary = view.entries[0]
	var predicted: Dictionary = automation.showcase_queue[0].prediction
	check(int(first.rank)==1 and int(first.level)==1 and first.offsets==[1,0,-1,2] and int(first.total_offset)==2 and not bool(first.survey) and not bool(first.current),"each row has its rank, Lv, 成长档 and 摸底 flag")
	check(int(first.attack)==int(predicted.attack) and int(first.max_hp)==int(predicted.max_hp) and int(first.sum)==int(predicted.attack)+int(predicted.defence)+int(predicted.speed),"and the predicted Lv.120 stats")

	# The window.
	menu.open_pet_records("queue",-1)
	await process_frame
	check(menu.panel.find_child("RecordsTabQueue",true,false)!=null and shown_rolls(menu)==queued_rolls,"排队 shows every queued hit in rank order")
	var group_row = menu.panel.find_child("QueueGroup_%d" % target,true,false)
	check(group_row!=null and group_row.find_children("*","Label",true,false).any(func(label):return label.text=="排队 10 / 10"),"the species has a header with its count and the per-species limit")
	var row_text: String = menu.panel.find_child("QueueRow_0",true,false).tooltip_text
	check(row_text.contains("排队第1名") and row_text.contains("攻%d" % int(predicted.attack)),"a row tells its rank and predicted stats (%s)" % row_text.replace("\n"," / "))
	await press(menu,"RecordsSort_attack")
	var attacks: Array = view.entries.map(func(e):return int(e.attack))
	var by_attack: Array = shown_rolls(menu).map(func(roll):return int(view.entries.filter(func(e):return int(e.roll)==roll)[0].attack))
	var desc := attacks.duplicate();desc.sort();desc.reverse()
	check(by_attack==desc,"攻 sorts highest first (%s)" % str(by_attack))
	check((menu.panel.find_child("RecordsSort_attack",true,false) as Button).text=="攻▼","the sorted header is marked ▼")
	await press(menu,"RecordsSort_attack")
	var asc := desc.duplicate();asc.reverse()
	by_attack = shown_rolls(menu).map(func(roll):return int(view.entries.filter(func(e):return int(e.roll)==roll)[0].attack))
	check(by_attack==asc and (menu.panel.find_child("RecordsSort_attack",true,false) as Button).text=="攻▲","again: lowest first, marked ▲")
	check(game.viewer_pref("records_sort_queue",[])==["attack",true] and game.viewer_pref("records_tab","")=="","the sort is remembered on this device")
	await press(menu,"RecordsSort_own")
	check(shown_rolls(menu)==queued_rolls,"名次 goes back to the queue's order")

	# Live: a new hit shows up without reopening.
	var better: Dictionary = actor.duplicate(true);better.growth_seed = 99991
	automation._showcase_enqueue(300,0,{"enemies":[better]},{"valid":true,"offsets":[2,2,2,2],"total_offset":8})
	var now_rolls: Array = automation.showcase_queue.map(func(e):return int(e.index)+1)
	check(await Wait.until(self,func():return shown_rolls(menu)==now_rolls,5.0),"the open tab follows the queue live (%s)" % str(shown_rolls(menu)))

	# 放生: the dropped hits, sortable and filtered to 未捕获.
	game.backend.handle({"type":"ping"})
	check(game.session.gm_grant_pet(92),"a caught pet to release by hand")
	game.session.release_pets([str(game.backend.capture_log.entries()[-1].pet_id)])
	var all: Dictionary = game.link.request({"type":"pet_log","kind":"released"}).log
	var uncaught: Dictionary = game.link.request({"type":"pet_log","kind":"released","uncaught":true}).log
	check(int(all.total)==int(uncaught.total)+1 and int(uncaught.total)>=2 and uncaught.entries.all(func(e):return bool(e.get("uncaught",false))),"uncaught keeps only hits the queue let go (%d of %d)" % [int(uncaught.total),int(all.total)])
	var sorted_attack: Array = game.link.request({"type":"pet_log","kind":"released","uncaught":true,"sort":"attack"}).log.entries.map(func(e):return int(e.lv120.attack))
	var expect := sorted_attack.duplicate();expect.sort();expect.reverse()
	check(sorted_attack==expect,"sort attack orders by the Lv120 attack, highest first (%s)" % str(sorted_attack))
	var rising: Array = game.link.request({"type":"pet_log","kind":"released","uncaught":true,"sort":"attack","ascending":true}).log.entries.map(func(e):return int(e.lv120.attack))
	expect.reverse()
	check(rising==expect,"ascending reverses it")
	await press(menu,"RecordsTabReleased")
	check(menu.records_tab=="released" and game.viewer_pref("records_tab","")=="released","choosing 放生 is remembered on this device")
	var filter: CheckBox = menu.panel.find_child("RecordsUncaught",true,false)
	check(filter!=null and not filter.button_pressed,"放生 has 只看未捕获, off")
	filter.button_pressed = true
	check(await Wait.until(self,func():return int(menu.records_data.get("total",0))==int(uncaught.total) and menu.panel.find_child("ReleaseLogRow_0",true,false)!=null,5.0),"只看未捕获 shows only those")
	var row = menu.panel.find_child("ReleaseLogRow_0",true,false)
	var labels: Array = row.find_children("*","Label",true,false).map(func(label):return str(label.text))
	check(labels.any(func(text):return text.contains("的排队已满（每个品种上限10）")) and labels.any(func(text):return text.begins_with("被比下去：")),"each shows its reason and who beat it")
	await press(menu,"RecordsSort_sum")
	check(await Wait.until(self,func():return menu.records_sorts.released==["sum",false] and menu.records_data.get("entries",[]).size()>0,5.0),"三围合 sorts 放生")
	var sums: Array = menu.records_data.entries.map(func(e):return int(e.lv120.attack)+int(e.lv120.defence)+int(e.lv120.speed))
	var sums_desc := sums.duplicate();sums_desc.sort();sums_desc.reverse()
	check(sums==sums_desc and game.viewer_pref("records_sort_released",[])==["sum",false] and game.viewer_pref("records_uncaught",false)==true,"highest first, filter and sort remembered (%s)" % str(sums))

	# The current hit: a real capture of a queued hit.
	automation.showcase_queue.clear()
	for i in range(2):hunt.scan_once()
	check(automation.showcase_queue.size()==2,"two real hits queue")
	flow.advance()
	check(flow.phase=="capture" and not automation.showcase_current.is_empty(),"the best one's capture opens")
	view = game.link.request({"type":"hunt_queue"}).queue
	check(view.entries.size()==2 and bool(view.entries[0].current) and str(view.entries[0].phase)=="capture" and int(view.entries[0].rank)==0 and int(view.entries[1].rank)==1,"the hit being caught is on top, outside the ranking")
	game.close_adventure_menu();game.adventure_menu.hide()
	menu.open_pet_records("",-1)
	check(menu.records_tab=="released","「宠物记录」 opens on the tab last chosen")
	await press(menu,"RecordsTabQueue")
	check(await Wait.until(self,func():return menu.panel.find_child("QueueRow_1",true,false)!=null,5.0),"排队 shows the current and the queued hit")
	check(str(menu.panel.find_child("QueueRow_0",true,false).tooltip_text).contains("当前 · 捕获中"),"the current one is marked 捕获中")

	# After the cycle stops the tab empties live.
	flow.stop_cycle();flow.advance()
	check(await Wait.until(self,func():return menu.panel.find_child("QueueEmpty",true,false)!=null,5.0),"after stopping, 排队 is empty again")
	menu.pet_records_open = false
	game.close_adventure_menu()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

## A LAN client has no backend: the tab asks the server and follows its status.
func remote() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REMOTE_PREFS))
	var backend = Backend.new()
	root.add_child(backend)
	var server = preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"a real server listens on port 0")
	var script = load("res://scripts/game.gd")
	script.server_url_override = "ws://127.0.0.1:%d" % server.port
	var world = load("res://scenes/main.tscn").instantiate()
	script.server_url_override = ""
	world.profile_persistence = false;world.viewer_prefs_path = REMOTE_PREFS
	root.add_child(world)
	check(await Wait.until(self,func():return not world.data.is_empty() and world.link.online) and await Wait.settle(self,world),"the remote client settles")
	check(world.backend==null,"the remote client owns no backend")
	# The server's queue, as a running 后台搜宠 cycle holds it.
	var automation = backend.automation
	# Held still (auto_tick off): only the transport is under test here.
	automation.auto_tick = false
	automation.flow_showcase = true;automation.flow_phase = "hunt"
	var base: Dictionary = Progression.species_actor("wooli",1,573)
	base.merge({"species":"wooli","name":"乌力","template_id":1,"level":1,"xp":0})
	for i in range(3):
		var pet: Dictionary = base.duplicate(true);pet.growth_seed = 500+i
		var p: Dictionary = Progression.project_pet(pet,120)
		automation.showcase_queue.append({"index":i,"slot":0,"actor":pet,"quality":{"valid":true,"offsets":[0,0,0,0],"total_offset":0},"prediction":{"attack":int(p.attack),"defence":int(p.defence),"speed":int(p.speed),"max_hp":int(p.max_hp)}})
	automation._emit_status()
	var menu = world.adventure_menu
	world.show_adventure_menu("pets")
	menu.open_pet_records("queue",-1)
	var shown: bool = await Wait.until(self,func():return menu.panel.find_child("QueueRow_2",true,false)!=null,10.0)
	check(shown,"排队 on the remote client shows the server's queue")
	var pet: Dictionary = base.duplicate(true);pet.growth_seed = 900
	var p: Dictionary = Progression.project_pet(pet,120)
	automation.showcase_queue.append({"index":3,"slot":0,"actor":pet,"quality":{},"prediction":{"attack":int(p.attack),"defence":int(p.defence),"speed":int(p.speed),"max_hp":int(p.max_hp)},"survey":true})
	automation._emit_status()
	check(await Wait.until(self,func():return menu.panel.find_child("QueueRow_3",true,false)!=null),"and follows it live")
	var survey_row = menu.panel.find_child("QueueRow_3",true,false)
	check(str(survey_row.tooltip_text).contains("摸底选中") and survey_row.find_children("*","Label",true,false).any(func(label):return label.text=="摸底"),"a 摸底 pick is marked")
	automation.showcase_queue.clear();automation.flow_phase = "idle";automation.flow_showcase = false
	menu.pet_records_open = false
	world.close_adventure_menu()
	world.music.stop();world.effect.stop();world.queue_free()
	server.queue_free();backend.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REMOTE_PREFS))

func run() -> void:
	await local()
	await remote()
	await create_timer(0.3).timeout
	print("HUNT QUEUE RECORDS: %d failures" % failures)
	quit(1 if failures else 0)
