extends SceneTree
## 宠物记录: every capture path logs an entry (find-pet cycle with its run,
## the hunt's automatic capture, a manual battle capture, GM 发放) with where
## and the exact Lv120 stats; 本轮 pages the current run; caught and released
## entries link to each other; and 抓捕顺序 sorts 同种比较 and 宠物仓库.
const Backend = preload("res://server/backend.gd")
const Battle = preload("res://server/battle_session.gd")
const Progression = preload("res://server/progression.gd")
const ConditionsOff = preload("res://tests/support/conditions_off.gd")
const PetComparison = preload("res://scripts/pet_comparison.gd")
const PREFS := "user://pet-records-test-viewer.cfg"
var failures := 0

class FixedTroop extends RefCounted:
	var troop: Dictionary
	func roll(_map, _cell, _rng, _held_items: Array = []) -> Dictionary:return troop.duplicate(true)

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## A real local Lv1 newborn at capture-ready health, fixed as the next troop.
func newborn(game, seed_value: int) -> FixedTroop:
	var fixture := FixedTroop.new()
	var rng := RandomNumberGenerator.new();rng.seed = seed_value
	for i in range(200):
		var rolled: Dictionary = game.encounter_catalog.roll(100,game.cell,rng)
		for actor in rolled.get("enemies",[]):
			if int(actor.level)==1 and actor.can_capture and game.battle_view.can_render_troop([actor]):
				actor.hp = 1
				fixture.troop = {"enemies":[actor]};return fixture
	return fixture

func captures(game) -> Array:
	return game.backend.capture_log.entries()

## One find-pet cycle capture through the real settlement.
func cycle_capture(game, seed_value: int) -> bool:
	var flow = game.pet_workflow
	var hunt = game.pet_hunt_menu
	var helper = game.training_helper
	var fixture := newborn(game,seed_value)
	# 展示模式 off: this suite covers the full-speed find-pet cycle (stop to
	# compare). The newborn's species has no 属性条件, so no 摸底 comes first.
	game.link.request({"type":"set_automation_settings","settings":ConditionsOff.for_troop(fixture.troop).merged({"hunt":{"showcase":false,"stop_after":1}})})
	if not flow.start_cycle():return false
	hunt.hunt_catalog = fixture;hunt.scan_once();game.pet_workflow.advance()
	for i in range(100):
		game.battle_view._process(0.2);helper.advance();flow.advance()
		if flow.phase!="capture":break
	return flow.phase=="compare"

func real_paths() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	game.viewer_prefs_path = PREFS
	root.add_child(game)
	await process_frame
	game.session.grant_starter_pets()
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,120);game.session.gm_set_base_stat(-1,"toughness",500);game.session.gm_heal()
	for node in [game.pet_workflow,game.pet_hunt_menu,game.training_helper]:node.set_process(false)
	game.pet_hunt_menu.close_menu();game.pet_hunt_menu.apply_preset(0)
	check(await cycle_capture(game,1234),"a find-pet cycle captures a pet")
	var first: Array = captures(game)
	check(first.size()==1 and first[0].source=="找宠流程" and not str(first[0].run).is_empty(),"the capture is logged as 找宠流程 with its run")
	var caught_id := str(first[0].pet_id)
	check(int(first[0].level)==1 and first[0].has("lv120") and int(first[0].map_id)==100 and first[0].cell==[637,493] and not str(first[0].map_name).is_empty(),"it keeps the level at capture, the Lv120 stats and where (map name and cell)")
	var levelled: Dictionary = {}
	for pet in game.session.snapshot().pets:
		if str(pet.pet_id)==caught_id:levelled = pet
	check(not levelled.is_empty() and int(first[0].lv120.attack)==int(levelled.attack) and int(first[0].lv120.max_hp)==int(levelled.max_hp),"the logged Lv120 stats equal the pet after the cycle levelled it")
	game.adventure_menu.hide();game.paused_input = false
	check(await cycle_capture(game,4321),"a second cycle captures another pet")
	var both: Array = captures(game)
	check(both.size()==2 and both[1].source=="找宠流程" and str(both[1].run)!=str(both[0].run),"a new cycle is a new run")
	var latest: Dictionary = game.backend.handle({"type":"pet_log","kind":"caught","run":"latest"}).log
	check(latest.total==1 and latest.entries[0].pet_id==both[1].pet_id and latest.latest_run==both[1].run,"本轮 pages the current run only")
	var all: Dictionary = game.backend.handle({"type":"pet_log","kind":"caught"}).log
	check(all.total==2 and all.entries[0].pet_id==both[1].pet_id and all.runs.size()==2,"全部 pages every capture newest first and lists the runs")
	game.adventure_menu.hide();game.paused_input = false
	game.pet_workflow.stop_cycle();game.pet_workflow.advance()
	# The hunt's automatic capture battle, without the find-pet cycle.
	var hunt = game.pet_hunt_menu
	if not hunt.visible:hunt.open_menu()
	check(hunt.visible,"raw capture settings can be opened after queued workflow")
	hunt.auto_capture.button_pressed = true;hunt.train_after_capture.button_pressed = false
	hunt.start_hunt()
	hunt.hunt_catalog = newborn(game,999);hunt.scan_once()
	var before: int = captures(game).size()
	for i in range(100):
		game.battle_view._process(0.2);game.training_helper.advance()
		if captures(game).size()>before:break
	check(captures(game).size()==before+1 and captures(game)[-1].source=="自动抓宠" and str(captures(game)[-1].run).is_empty(),"the hunt's automatic capture is logged as 自动抓宠 without a run")
	hunt.close_menu()
	# GM 发放
	check(game.session.gm_grant_pet(92) and captures(game)[-1].source=="GM发放","a GM grant is logged as GM发放")
	# Cross links: release the first capture.
	game.session.release_pets([caught_id])
	var linked: Dictionary = game.backend.handle({"type":"pet_log","kind":"caught"}).log
	var entry: Dictionary = linked.entries.filter(func(item):return item.pet_id==caught_id)[0]
	check(entry.has("released") and entry.released.reason=="手动放生","a caught pet later released shows 已放生 with the reason")
	var gone: Dictionary = game.backend.handle({"type":"pet_log","kind":"released"}).log
	check(gone.entries[0].pet_id==caught_id and gone.entries[0].caught.source=="找宠流程" and int(gone.entries[0].caught.time)>0 and not str(gone.entries[0].caught.map_name).is_empty(),"the release entry shows when and where it was caught")
	# The window: 抓到 and 放生 tabs.
	var menu = game.adventure_menu
	menu.open_pet_records("caught",-1)
	await process_frame
	check(menu.panel.has_node("PetRecordsPanel") and menu.panel.find_child("CaughtRow_0",true,false)!=null and menu.panel.find_child("RecordsRun",true,false)!=null,"宠物记录 opens on 抓到 with a 本轮 filter")
	check(menu.records_run=="latest" and menu.records_data.total==1,"it starts on 本轮")
	var run_pick: OptionButton = menu.panel.find_child("RecordsRun",true,false)
	run_pick.select(1);run_pick.item_selected.emit(1)
	await process_frame
	check(menu.records_data.total==4 and menu.panel.find_child("CaughtRow_3",true,false)!=null,"全部 shows every capture")
	var released_row = null
	for i in range(4):
		var row = menu.panel.find_child("CaughtRow_%d"%i,true,false)
		if row!=null and row.tooltip_text.contains(caught_id):released_row = row
	check(released_row!=null and released_row.find_children("*","Label",true,false).any(func(label):return label.text=="已放生"),"a released capture shows 已放生")
	(menu.panel.find_child("RecordsTabReleased",true,false) as Button).pressed.emit()
	await process_frame
	var release_row = menu.panel.find_child("ReleaseLogRow_0",true,false)
	check(menu.records_tab=="released" and release_row!=null and release_row.find_children("*","Label",true,false).any(func(label):return label.text.begins_with("抓到：")),"the 放生 tab shows where each release was caught")
	# Live: while the window is open, new releases and captures show up
	# without reopening it (pet_log_changed, at most twice a second).
	var released_before: int = int(menu.records_data.total)
	check(game.session.gm_grant_pet(92),"a pet is granted while 放生 is open")
	var granted_id := str(captures(game)[-1].pet_id)
	game.session.release_pets([granted_id])
	check(int(menu.records_data.total)==released_before,"the page is not fetched inside the event itself")
	await create_timer(0.7).timeout
	await process_frame
	check(int(menu.records_data.total)==released_before+1 and str(menu.records_data.entries[0].pet_id)==granted_id and menu.panel.find_child("ReleaseLogRow_%d" % released_before,true,false)!=null,"the 放生 page shows the new release without reopening")
	(menu.panel.find_child("RecordsTabCaught",true,false) as Button).pressed.emit()
	await process_frame
	run_pick = menu.panel.find_child("RecordsRun",true,false)
	run_pick.select(1);run_pick.item_selected.emit(1)
	await process_frame
	var caught_before: int = int(menu.records_data.total)
	game.session.gm_grant_pet(92)
	game.session.gm_grant_pet(92)
	await create_timer(0.7).timeout
	await process_frame
	check(int(menu.records_data.total)==caught_before+2 and menu.panel.find_child("CaughtRow_%d" % (caught_before+1),true,false)!=null,"the 抓到 page shows new captures without reopening (%d → %d)" % [caught_before,int(menu.records_data.total)])
	menu.pet_records_open = false
	game.close_adventure_menu()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

func manual_capture() -> void:
	var backend = Backend.new()
	root.add_child(backend)
	var session = backend.session
	var config: Dictionary = session.start_battle_config("wooli",false,1)
	config.player_attack = 100;config.player_speed = 100;config.player_defence = 100
	for enemy in config.enemies:enemy.hp = 1
	var battle = Battle.new();battle.start_battle(config)
	battle.submit_action("capture",0)
	for i in range(10):
		if not battle.snapshot().active:break
		battle.submit_action("capture",0)
	var result: Dictionary = battle.snapshot()
	check(result.outcome=="captured" and session.apply_battle_result(result),"a battle capture settles")
	backend.handle({"type":"ping"})
	var logged: Array = backend.capture_log.entries()
	check(logged.size()==1 and logged[0].source=="手动捕获" and str(logged[0].run).is_empty(),"a capture outside automation is logged as 手动捕获")
	backend.queue_free()
	await process_frame

func sorting() -> void:
	var make := func(id: int, favorite: bool) -> Dictionary:
		return {"pet_id":"pet-%d"%id,"species":"original_92","template_id":92,"name":"扬奇洛斯","level":120,"attack":290,"defence":180,"speed":150,"max_hp":1300,"favorite":favorite}
	var profile := {"pets":[],"pet_storage":[make.call(12,false),make.call(3,true),make.call(40,false),make.call(7,false)]}
	var ids := func(rows: Array) -> Array:return rows.map(func(row):return row.pet.pet_id)
	var selected: Dictionary = profile.pet_storage[0]
	check(ids.call(PetComparison.rows(profile,selected,["caught_new"],false,false))==["pet-40","pet-12","pet-7","pet-3"],"同种比较 最新抓到 orders by id, newest first")
	check(ids.call(PetComparison.rows(profile,selected,["caught_old","attack"],false,false))==["pet-3","pet-7","pet-12","pet-40"],"最早抓到 orders oldest first and decides every pair by itself")
	check(ids.call(PetComparison.rows(profile,selected,["caught_new"],false,true))[0]=="pet-3","收藏优先 still leads")
	check(PetComparison.full_order(["caught_new"])==["caught_new","stat_total","attack","speed","max_hp","defence"],"stat keys stay the tie-break after a capture-order key")
	check(ids.call(PetComparison.storage_rows(profile))==["pet-3","pet-12","pet-40","pet-7"],"宠物仓库 keeps its own order with favourites first by default")
	check(ids.call(PetComparison.storage_rows(profile,"caught_new"))==["pet-3","pet-40","pet-12","pet-7"],"最新抓到 sorts within the favourites-first grouping")
	check(ids.call(PetComparison.storage_rows(profile,"caught_old",false))==["pet-3","pet-7","pet-12","pet-40"],"with 收藏优先 off the favourite takes its place in the order")
	# The controls, remembered per device.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	game.viewer_prefs_path = PREFS
	root.add_child(game)
	await process_frame
	game.session.grant_starter_pets()
	var base: Dictionary = game.session._profile.pets[0].duplicate(true)
	var stored := []
	for id in [12,3,40,7]:
		var copy: Dictionary = base.duplicate(true);copy.pet_id = "pet-%d"%(900+id);copy.favorite = id==3
		stored.append(copy)
	game.session._profile.pet_storage = stored
	game.sync_state()
	var menu = game.adventure_menu
	game.show_adventure_menu("pets")
	menu.pet_storage_open = true;menu.rebuild()
	await process_frame
	var sort: OptionButton = menu.panel.find_child("StorageSort",true,false)
	check(sort!=null and sort.get_item_text(sort.selected)=="现有顺序","宠物仓库 has a sort picker on 现有顺序")
	sort.select(1);sort.item_selected.emit(1)
	await process_frame
	var order: Array = menu.panel.find_children("StorageRow_*","",true,false).map(func(node):return str(node.name).trim_prefix("StorageRow_"))
	check(order==["pet-903","pet-940","pet-912","pet-907"] and game.viewer_pref("storage_order","")=="caught_new","最新抓到 reorders the rows and is remembered on this device")
	(menu.panel.find_child("StorageFavoritesFirst",true,false) as CheckBox).button_pressed = false
	await process_frame
	order = menu.panel.find_children("StorageRow_*","",true,false).map(func(node):return str(node.name).trim_prefix("StorageRow_"))
	check(order==["pet-940","pet-912","pet-907","pet-903"] and game.viewer_pref("storage_favorites_first",true)==false,"收藏优先 off lets the favourite fall into place")
	menu.pet_storage_open = false
	menu.open_pet_comparison("pet-912")
	await process_frame
	var first_pick: OptionButton = menu.panel.find_child("PetCompareSort1",true,false)
	var labels := []
	for i in range(first_pick.item_count):labels.append(first_pick.get_item_text(i))
	check(labels.has("最新抓到") and labels.has("最早抓到"),"同种比较's pickers offer 最新抓到 and 最早抓到")
	game.close_adventure_menu()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	await real_paths()
	await manual_capture()
	await sorting()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	await create_timer(0.3).timeout
	print("PET RECORDS: %d failures" % failures)
	quit(1 if failures else 0)
