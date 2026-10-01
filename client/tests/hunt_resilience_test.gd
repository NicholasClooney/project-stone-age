extends SceneTree
## 自动抓极品 keeps going when it can and says why when it cannot
## (server/automation.gd): every stop, pause, skip and retry is written to
## 停止记录 (<save>.stop-log.jsonl, pet_log kind stops) and printed; a capture
## the cycle cannot finish skips that hit (the open battle ends without
## rewards or a GM mark) while anything needing the player stops, and the same
## failure three times in a row stops; a shown training battle that ends early
## is retried once, then levelled instantly. 宠物记录 opens from the window.
const Automation = preload("res://server/automation.gd")
const LOG := "user://hunt-resilience-test.stop-log.jsonl"
var failures := 0

class FixedTroop extends RefCounted:
	var troop: Dictionary
	func roll(_map, _cell, _rng, _held_items: Array = []) -> Dictionary:return troop.duplicate(true)

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func _initialize() -> void:call_deferred("run")

## The newest 停止记录 entry (the backend drains the automation's events into
## the log after every command and frame; drain now, then read the file).
func last_stop(game) -> Dictionary:
	game.backend._record_releases()
	var all: Array = game.backend.stop_log.entries()
	return all.back() if not all.is_empty() else {}

func stop_count(game) -> int:
	game.backend._record_releases()
	return game.backend.stop_log.entries().size()

## A capture battle against a real local newborn, open and active.
func open_capture_battle(game, troop: Dictionary) -> void:
	var config: Dictionary = game.backend.session.start_wild_battle_config(troop.duplicate(true))
	game.backend.open_battle(config)

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))
	var game = load("res://scenes/main.tscn").instantiate();game.profile_persistence = false;root.add_child(game)
	await process_frame
	game.backend.stop_log_path = LOG
	game.link.request({"type":"set_automation_settings","settings":{"hunt":{"stop_after":1}}}) # cycles here stop to compare
	game.session.grant_starter_pets()
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,120);game.session.gm_heal()
	var automation = game.backend.automation
	var flow = game.pet_workflow;flow.set_process(false)
	var hunt = game.pet_hunt_menu;hunt.set_process(false)
	game.training_helper.set_process(false)
	automation.auto_tick = false
	check(automation.position_map==100,"the character stands on the hunting ground")

	var fixture := FixedTroop.new()
	var rng := RandomNumberGenerator.new();rng.seed = 99
	for i in range(200):
		var rolled: Dictionary = game.encounter_catalog.roll(100,game.cell,rng)
		for actor in rolled.get("enemies",[]):
			if int(actor.level)==1 and actor.can_capture and game.battle_view.can_render_troop([actor]):
				fixture.troop = {"enemies":[actor]};break
		if not fixture.troop.is_empty():break
	check(not fixture.troop.is_empty(),"a real local newborn is the fixture")

	# ---- stop logging -----------------------------------------------------
	check(automation.start_hunt(automation.hunt_request()),"a scan on its own starts")
	automation.stop_hunt("已停止，可调整条件后重新开始。")
	var entry := last_stop(game)
	check(entry.get("scope")=="hunt" and entry.get("outcome")=="停止" and str(entry.get("reason","")).begins_with("已停止") and int(entry.get("map_id",-1))==100 and not str(entry.get("map_name","")).is_empty(),"a scan stopped by hand is logged with its reason and place")
	check(automation.start_hunt(automation.hunt_request()),"another scan starts")
	automation.stop_hunt("找到达标个体：乌力 Lv.1，总成长档 +8。")
	check(last_stop(game).get("outcome")=="找到","a scan on its own that finds its pet is logged as 找到")
	check(automation.start_hunt(automation.hunt_request()),"a scan starts before a map change")
	automation.position_changed(1000,Vector2i(80,90),true)
	check(last_stop(game).get("reason")=="地图发生变化，筛选已停止。","a map change stopping a scan is logged")
	game.load_area_id(100,Vector2i(637,493))
	check(automation.position_map==100,"back on the hunting ground")

	var count_before: int = stop_count(game)
	hunt.open_menu();hunt.apply_preset(0);hunt.showcase.button_pressed = false
	check(flow.start_cycle(),"a find-pet cycle starts (展示模式 off)")
	check(stop_count(game)==count_before,"a cycle's own scan pausing for a hit or starting logs nothing")
	automation.stop_request("已手动停止")
	entry = last_stop(game)
	check(entry.get("scope")=="flow" and entry.get("outcome")=="停止" and entry.get("reason")=="已手动停止" and entry.get("phase")=="hunt" and not str(entry.get("run","")).is_empty(),"a cycle stopped by hand is logged once, with its phase and run")
	check(stop_count(game)==count_before+1,"stopping the cycle's scan with it adds no second entry")
	hunt.close_menu()

	hunt.open_menu();hunt.apply_preset(0)
	check(flow.start_cycle(),"a cycle starts before a map change")
	automation.position_changed(1000,Vector2i(80,90),true)
	check(last_stop(game).get("outcome")=="暂停" and last_stop(game).get("reason")=="地图发生变化，流程已暂停。","a map change pausing the cycle is logged as 暂停")
	game.load_area_id(100,Vector2i(637,493))
	hunt.close_menu()

	# Finishing: a trained pet with no stat condition stops for comparison.
	var carried_id := str(game.session.snapshot().pets[0].pet_id)
	game.session.level_pet_to(carried_id,120)
	var carried: Dictionary = game.session.snapshot().pets[0]
	automation.flow_phase = "train"
	automation.flow_pet_id = str(carried.pet_id)
	automation.flow_target_filter = {}
	automation.complete_trained_pet(carried)
	entry = last_stop(game)
	check(entry.get("outcome")=="完成" and entry.get("pet_id")==str(carried.pet_id) and str(entry.get("name","")).length()>0,"a cycle that stops to compare its pet is logged as 完成 with the pet")
	automation.flow_phase = "idle";automation.flow_pet_id = ""

	# The server quitting mid-hunt.
	check(automation.start_hunt(automation.hunt_request()),"a scan runs when the server quits")
	game.backend.record_shutdown()
	check(str(last_stop(game).get("reason","")).begins_with("服务器关闭"),"quitting the server records the interrupted scan")
	automation.stop_hunt("x")

	# The log file and the pet_log command.
	game.backend._record_releases()
	var lines := FileAccess.get_file_as_string(LOG).split("\n",false)
	check(lines.size()>=7,"停止记录 is its own file next to the save (%d entries)" % lines.size())
	var reply: Dictionary = game.link.request({"type":"pet_log","kind":"stops","page":0,"page_size":3})
	var page: Dictionary = reply.get("log",{})
	check(reply.get("ok",false) and page.get("kind")=="stops" and page.entries.size()==3 and int(page.total)==lines.size(),"pet_log kind stops pages the log")
	check(str(page.entries[0].reason)=="x" and str(page.entries[1].reason).begins_with("服务器关闭"),"newest first")

	# ---- skip or stop -------------------------------------------------------
	automation.flow_showcase = false
	automation.flow_map = automation.position_map;automation.flow_cell = automation.position_cell
	automation.flow_run_id = "test-run"
	automation.flow_skip_kind = "";automation.flow_skip_streak = 0;automation.flow_skipped_count = 0
	var gm_before: bool = bool(game.session.snapshot().get("gm_modified",false))
	# The target went down: the runner stopped with the battle still open.
	open_capture_battle(game,fixture.troop)
	automation.flow_phase = "capture"
	automation.flow_matched_actor = fixture.troop.enemies[0].duplicate(true)
	automation.flow_matched_index = 0
	automation.flow_capture_battle_id = str(game.backend.battle.snapshot().battle_id)
	automation.running = false
	automation.stop_reason = "捕捉目标已倒下，已停止；不会改抓其他敌人"
	var pets_before: int = game.session.snapshot().pets.size()
	automation.flow_step()
	check(automation.flow_phase=="restart" and automation.flow_skipped_count==1,"a capture target that went down skips that hit instead of stopping")
	check(not game.backend.battle_open and game.session.snapshot().pets.size()==pets_before,"the open capture battle ends without a capture")
	check(bool(game.session.snapshot().get("gm_modified",false))==gm_before,"giving the battle up leaves no GM mark")
	entry = last_stop(game)
	check(entry.get("outcome")=="已跳过" and entry.get("reason")=="捕捉目标已倒下，已停止；不会改抓其他敌人" and str(entry.get("name",""))==str(fixture.troop.enemies[0].name),"the skip is logged with the wild pet")
	check(flow.skipped_count==1 and flow.skip_note.contains("捕捉失败"),"the window and chip see the skip count and note")
	hunt.open_menu()
	check(hunt.workflow_summary().contains("已跳过 1 只"),"the hunt window says how many were skipped")
	hunt.close_menu()

	# A closed battle without the pet skips too.
	automation.flow_phase = "capture"
	automation.stop_reason = "本场自动战斗已完成"
	automation.flow_capture_battle_id = str(game.backend.battle.snapshot().battle_id)
	automation.flow_step()
	check(automation.flow_phase=="restart" and automation.flow_skipped_count==2 and last_stop(game).get("reason")=="目标未捕获；未改抓其他敌人。","a finished battle without the pet skips it")
	# The third failure in a row stops the cycle.
	automation.flow_phase = "capture"
	automation.stop_reason = "战斗未获胜"
	automation.flow_step()
	check(automation.flow_phase=="paused" and str(automation.flow_reason).begins_with("连续3次捕捉失败"),"the same failure three times in a row stops the cycle")
	check(last_stop(game).get("outcome")=="停止","and that stop is logged")

	# Cases that need the player stop at once.
	for reason in ["已手动停止","宠物栏已满，请先腾出位置","没有可用低等级宠物：请选存活、非骑乘且符合等级上限的宠物"]:
		automation.flow_skip_kind = "";automation.flow_skip_streak = 0
		automation.flow_phase = "capture"
		automation.stop_reason = reason
		automation.flow_step()
		check(automation.flow_phase=="paused" and automation.flow_reason==reason,"「%s」 stops the cycle" % reason)
	automation.flow_skip_kind = "";automation.flow_skip_streak = 0
	open_capture_battle(game,fixture.troop)
	automation.flow_phase = "capture"
	automation.stop_reason = "本场自动战斗已完成"
	automation.flow_capture_battle_id = "another-battle"
	automation.flow_step()
	check(automation.flow_phase=="paused" and automation.flow_reason=="捕捉战斗状态已改变。" and game.backend.battle_open,"a different battle still open is left to the player")
	game.backend.abandon_battle()

	# 后台搜宠: a queued roll that no longer verifies is skipped.
	automation.flow_showcase = true
	automation.flow_phase = "hunt"
	automation.flow_skip_kind = "";automation.flow_skip_streak = 0
	automation.hunt_catalog = fixture
	var other: Dictionary = fixture.troop.duplicate(true)
	other.enemies[0].growth_seed = int(other.enemies[0].growth_seed)+1
	automation.showcase_queue = [{"index":41,"slot":0,"run_seed":5,"actor":other.enemies[0],"troop":other,"quality":{},"prediction":{"attack":1,"defence":1,"speed":1,"max_hp":1}}]
	automation._showcase_capture()
	check(automation.flow_phase=="restart" and last_stop(game).get("outcome")=="已跳过" and str(last_stop(game).reason).contains("第 42 组复核不一致") and not game.backend.battle_open,"a queued hit that no longer verifies is skipped without a battle")
	check(automation.showcase_log.any(func(line):return str(line.kind)=="skipped" and str(line.text).contains("复核不一致")),"后台搜宠's info block shows the skip note")

	# 后台搜宠: a training battle that ends early is fought again; the same
	# failure SKIP_LIMIT times in a row stops the cycle.
	var trainee: Dictionary = game.session.snapshot().pets[0]
	automation.flow_pet_id = str(trainee.pet_id)
	automation.showcase_current = {"prediction":{},"quality":{},"actor":trainee}
	automation.flow_phase = "train"
	automation.flow_skip_kind = "";automation.flow_skip_streak = 0
	automation.running = false
	automation.stop_reason = "战斗未获胜"
	automation._showcase_step()
	check(last_stop(game).get("outcome")=="已重试" and automation.flow_phase=="train" and automation.running,"a training battle that ends early is fought again")
	check(automation.showcase_log.back().kind=="retry","and the info block says so")
	for i in range(Automation.SKIP_LIMIT-1):
		automation.running = false
		automation.stop_reason = "战斗未获胜"
		automation._showcase_step()
	check(automation.flow_phase=="paused" and str(automation.flow_reason).contains("连续%d次" % Automation.SKIP_LIMIT),"the same failure %d times in a row stops the cycle (%s)" % [Automation.SKIP_LIMIT,automation.flow_reason])
	automation.stop_cycle("测试结束")
	game.backend.abandon_battle()

	# ---- 宠物记录 from the window ----------------------------------------------
	hunt.open_menu()
	await process_frame
	check(flow.start_cycle(),"a cycle runs")
	# 宠物记录 from the window: running, the window folds and the cycle goes on.
	var records: Button = hunt.panel.find_child("PetHuntRecords",true,false)
	check(records!=null,"the window has a 宠物记录 button")
	records.pressed.emit()
	await process_frame
	check(hunt.minimized and automation.flow_active() and game.adventure_menu.pet_records_open and game.adventure_menu.records_tab=="caught" and game.adventure_menu.records_run=="latest","while running it folds the window and opens 抓到 on 本轮找宠")
	game.adventure_menu.open_pet_records("stops")
	await process_frame
	var stop_row: Control = game.adventure_menu.panel.find_child("StopRow_0",true,false)
	check(stop_row!=null and not stop_row.tooltip_text.is_empty(),"宠物记录 has a 停止 tab listing the entries")
	check(game.adventure_menu.panel.find_child("RecordsTabStops",true,false)!=null,"with its own tab button")
	game.close_adventure_menu()
	hunt.restore()
	automation.stop_request("已手动停止")
	hunt.close_menu()
	hunt.open_menu()
	records = hunt.panel.find_child("PetHuntRecords",true,false)
	records.pressed.emit()
	await process_frame
	check(not hunt.visible and not hunt.minimized and game.adventure_menu.pet_records_open,"idle, it closes the window and opens 宠物记录")
	game.close_adventure_menu()

	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))
	print("HUNT RESILIENCE: %d failures" % failures)
	quit(1 if failures else 0)
