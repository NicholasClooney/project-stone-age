extends SceneTree
## 后台搜宠 (hunt.showcase, AutomationSettings.SHOWCASE_NAME) in the find-pet
## cycle (server/automation.gd): hits found while the player watches wait in a
## queue (hunt.queue long, best first; the worst over the limit is written to
## 放生记录 as 未捕获·排队已满); a queued hit is replayed from its own roll seed
## and captured in a normal, animated capture battle; then 自动练级 trains it to
## Lv120 with the player's own 经验倍率, every battle played in full; battle
## music takes the music player from the radio and loops until the run ends;
## the top-left info block tells what was found, caught and kept or released.
const Progression = preload("res://server/progression.gd")
const Automation = preload("res://server/automation.gd")
const AutomationSettings = preload("res://scripts/automation_settings.gd")
const PREFS := "user://showcase-test.cfg"
var failures := 0
var clock := 1000

class FixedTroop extends RefCounted:
	var troop: Dictionary
	func roll(_map, _cell, _rng, _held_items: Array = []) -> Dictionary:return troop.duplicate(true)

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func _initialize() -> void:call_deferred("run")

func stats(pet: Dictionary) -> Dictionary:
	return {"attack":int(pet.attack),"defence":int(pet.defence),"speed":int(pet.speed),"max_hp":int(pet.max_hp)}

## Drives in-process frames: presentation, battle runner and workflow.
func drive(game, until: Callable, steps: int = 4000) -> bool:
	for i in range(steps):
		if until.call():return true
		step(game)
	return bool(until.call())

func step(game) -> void:
	game.battle_view._process(0.25)
	game.acknowledge_presentation()
	game.training_helper.advance()
	game.pet_workflow.advance()
	game.pet_workflow.on_status(game.state.automation)
	clock += 250

func log_kinds(game) -> Array:
	return game.state.automation.flow.get("log",[]).map(func(line):return str(line.kind))

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game = load("res://scenes/main.tscn").instantiate();game.profile_persistence = false;game.viewer_prefs_path = PREFS;root.add_child(game)
	await process_frame
	# This suite deliberately presents several local training battles near120.
	# Default borrowed showcase training has its own real-capture core coverage.
	game.link.request({"type":"set_automation_settings","settings":{"training":{"borrow_troops":false}}})
	game.session.grant_starter_pets()
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,120);game.session.gm_set_base_stat(-1,"toughness",500);game.session.gm_heal()
	var automation = game.backend.automation
	var flow = game.pet_workflow;flow.set_process(false)
	var hunt = game.pet_hunt_menu;hunt.set_process(false)
	var helper = game.training_helper;helper.set_process(false)
	flow.timer_clock = func():return clock
	check(bool(game.automation_settings().hunt.showcase) and int(game.automation_settings().hunt.queue)==10,"%s is on by default with a queue of 10" % AutomationSettings.SHOWCASE_NAME)
	check(hunt.showcase.text==AutomationSettings.SHOWCASE_NAME and hunt.capture_page.is_ancestor_of(hunt.showcase) and hunt.capture_page.is_ancestor_of(hunt.showcase_xp) and hunt.capture_page.is_ancestor_of(hunt.showcase_speed) and hunt.capture_page.is_ancestor_of(hunt.queue_size),"the switch, 排队上限, 经验倍率 and 战斗速度 are on 抓宠设置")

	# 经验倍率 and 战斗速度 are 自动练级's own settings, not copies.
	hunt.open_menu()
	hunt.showcase_xp.select(3);hunt.showcase_xp.item_selected.emit(3)
	game.flush_automation_settings()
	check(int(game.automation_settings().training.xp)==100,"经验倍率 here is 自动练级's training.xp (100×)")
	hunt.showcase_speed.select(3);hunt.showcase_speed.item_selected.emit(3)
	check(is_equal_approx(game.playback_speed(),8.0) and is_equal_approx(float(game.viewer_pref("battle_speed",0.0)),8.0),"战斗速度 here is this device's battle speed (8×)")
	helper.open_menu()
	check(helper.multiplier.selected==3 and helper.speed.selected==3,"自动练级 shows the same 经验倍率 and 战斗速度")
	helper.close_menu()
	# 排队上限: validated like the other hunt settings.
	check(not bool(game.link.request({"type":"set_automation_settings","settings":{"hunt":{"queue":0}}}).get("ok",false)) and not bool(game.link.request({"type":"set_automation_settings","settings":{"hunt":{"queue":51}}}).get("ok",false)),"排队上限 outside 1 to 50 is refused")

	# A real local newborn, ready to capture, as the fixed troop every roll returns.
	var fixture := FixedTroop.new()
	var rng := RandomNumberGenerator.new();rng.seed = 1234
	for i in range(200):
		var rolled: Dictionary = game.encounter_catalog.roll(100,game.cell,rng)
		for actor in rolled.get("enemies",[]):
			if int(actor.level)==1 and actor.can_capture and game.battle_view.can_render_troop([actor]):
				actor.hp = 1
				fixture.troop = {"enemies":[actor]};break
		if not fixture.troop.is_empty():break
	check(not fixture.troop.is_empty(),"a real local newborn is the fixture")
	var target := int(fixture.troop.enemies[0].template_id)
	# Qualifiers of this species are stored and the cycle goes on (stop_after 0);
	# auto tidy with a rule that keeps nothing releases each one after Lv120.
	game.link.request({"type":"set_automation_settings","settings":{"hunt":{"stop_after":0},"stat_filters":{str(target):{"threshold_mode":"absolute","conditions":{"sum":{"enabled":true,"value":1}},"keep_rule":{"tiers":0,"champions":0,"auto":true}}}}})
	hunt.apply_preset(0)
	# The radio plays before the run; the watched battles set it aside.
	var radio = game.radio
	var radio_ok: bool = radio.available()
	if radio_ok:
		radio.turn_on()
		await process_frame
	var radio_track: String = radio.current
	var clone_before: bool = game.backend.session.clone_squad_enabled
	check(flow.start_cycle(),"a find-pet cycle starts with %s" % AutomationSettings.SHOWCASE_NAME)
	# 绝对 ≥ 1 (set above): a threshold every hit meets (最高 − x and 摸底 are covered by survey_test).
	check(bool(game.state.automation.flow.showcase),"the status says so")

	# Queue: over the limit the worst hit (by the keep rule's order) is dropped
	# and written to 放生记录 as 未捕获·排队已满.
	hunt.hunt_catalog = fixture
	var variants: Array = []
	game.backend.session.release_events.clear()
	for i in range(11):
		var actor: Dictionary = fixture.troop.enemies[0].duplicate(true)
		actor.growth_seed = 7000+i*37
		variants.append(actor)
		automation._showcase_enqueue(100+i,0,{"enemies":[actor]},{"offsets":[0,0,0,0],"total_offset":0})
	# The default 保留规则 order: 攻击, 敏捷, 血, then 三围合 and 防御.
	var rank := func(p: Dictionary) -> Array:return [int(p.attack),int(p.speed),int(p.max_hp),int(p.attack)+int(p.defence)+int(p.speed),int(p.defence)]
	var ranks: Array = variants.map(func(actor):return rank.call(Progression.project_pet(actor,120)))
	var kept_ranks: Array = automation.showcase_queue.map(func(e):return rank.call(e.prediction))
	var sorted_ranks := ranks.duplicate();sorted_ranks.sort();sorted_ranks.reverse()
	check(automation.showcase_queue.size()==10,"the queue keeps at most 10")
	check(kept_ranks==sorted_ranks.slice(0,10),"best first by the 保留规则 order (攻击 first); the last is dropped (%s)" % str(kept_ranks))
	var dropped: Array = game.backend.session.release_events.filter(func(e):return str(e.get("source",""))=="排队已满")
	check(dropped.size()==1 and bool(dropped[0].get("uncaught",false)) and str(dropped[0].where)=="未捕获","the dropped hit goes to 放生记录 as 未捕获·排队已满")
	check(dropped.size()==1 and str(dropped[0].reason).ends_with("的排队已满（每个品种上限10），排在第11") and not dropped[0].beaten_by.is_empty() and int(dropped[0].lv120.attack)>0,"with its reason, the hits that beat it and its predicted Lv120 stats")
	check(dropped.size()==1 and str(dropped[0].run_seed)==str(automation.hunt_run_seed) and dropped[0].has("slot"),"with its run seed and slot, to replay it later")
	check(log_kinds(game).has("dropped"),"and a line in the info block")
	# A smaller limit applies to the next run and drops the worst at once.
	hunt.showcase_xp.select(3)
	game.link.request({"type":"set_automation_settings","settings":{"hunt":{"queue":3}}})
	check(int(game.automation_settings().hunt.queue)==3 and int(hunt.queue_size.value)==3,"排队上限 is saved with the character and shown")
	automation.flow_hunt_request.queue = 3
	automation._showcase_enqueue(200,0,{"enemies":[variants[0].duplicate(true)]},{"offsets":[0,0,0,0],"total_offset":0})
	check(automation.showcase_queue.size()==3,"a limit of 3 keeps the best 3")
	automation.showcase_queue.clear()
	game.backend.session.release_events.clear()
	game.link.request({"type":"set_automation_settings","settings":{"hunt":{"queue":10}}})
	automation.flow_hunt_request.queue = 10

	# Real scans: hits queue and the search keeps running.
	for i in range(3):hunt.scan_once()
	check(automation.showcase_queue.size()==3 and automation.hunt_running and flow.phase=="hunt","three hits queue while the search keeps running")

	# Capture: the best queued hit, replayed from its roll seed, in a normal
	# capture battle with the capture animation.
	flow.advance()
	var predicted: Dictionary = Progression.project_pet(fixture.troop.enemies[0],120)
	check(flow.phase=="capture" and game.battle_view.visible and not game.state.automation.compact,"the capture battle opens right away and is presented")
	check(not game.training_helper.visible,"no 自动练级 progress window over the capture battle")
	check(not hunt.visible and hunt.minimized,"the hunt window folds to its progress bar")
	var lines: Array = game.state.automation.flow.log
	check(str(lines.back().kind)=="found" and str(lines.back().text).contains("三围合%d" % (int(predicted.attack)+int(predicted.defence)+int(predicted.speed))) and str(lines.back().text).contains("排队2"),"the info block says what was found, its Lv120 prediction and the queue (%s)" % str(lines.back().text))
	flow.on_status(game.state.automation)
	check(game.showcase_ticker.visible and game.showcase_ticker.find_child("Line_found",true,false)!=null,"this device shows the info block")
	check(is_equal_approx(game.battle_view.playback_speed,8.0),"the battle plays at this device's 战斗速度")
	var bgm: String = str(preload("res://scripts/battle_art.gd").index().audio.bgm)
	if radio_ok:check(radio.suspended and radio.current==radio_track and game.music.stream.resource_path.get_file().get_basename()==bgm.get_file().get_basename(),"battle music takes over from the radio, which keeps its track")
	for i in range(2):hunt.scan_once()
	check(automation.hunt_running and automation.showcase_queue.size()==4,"the search goes on during the capture battle (queue 4)")
	var captures_before: int = game.battle_view.captures_presented
	check(drive(game,func():return flow.phase!="capture"),"the capture battle finishes")
	check(game.battle_view.captures_presented>captures_before,"the automated capture plays the character's capture animation (the resolved command drives it)")
	var pets: Array = game.session.snapshot().pets
	var caught: Dictionary = pets[game.session.snapshot().active_pet]
	check(flow.phase=="train" and caught.pet_id==flow.pet_id,"the captured pet is active for its training")
	check(log_kinds(game).has("captured"),"the info block says it was caught")

	# Training: 自动练级 with the player's 经验倍率, the 五人镜像队 of the best
	# other pets, every battle shown in full.
	check(automation.running and not bool(automation.settings.compact) and int(game.backend.session.experience_multiplier)==100 and int(automation.settings.hp)==-1,"自动练级 runs shown, at the player's 100× 经验倍率, without an HP stop line for the Lv1 pet")
	check(game.backend.session.clone_squad_enabled and game.backend.session.clone_best_others,"with the 五人镜像队 of best other pets")
	check(drive(game,func():return game.battle_view.visible or not automation.running) and game.battle_view.visible and not automation.compact_active,"the first training battle opens shown, not compact (at 100× it may be the only one)")
	check(not game.training_helper.visible,"no 自动练级 progress window over the training battle")
	var allies: Array = game.battle_session.snapshot().get("ally_pets",[])
	var best_ids: Array = game.backend.session.best_other_pets(4).map(func(pet):return str(pet.pet_id))
	var ally_ids: Array = allies.map(func(pet):return str(pet.get("pet_id","")))
	check(ally_ids.slice(0,best_ids.size())==best_ids and not ally_ids.has(str(flow.pet_id)) and not ally_ids.has("clone-of-"+str(flow.pet_id)),"the clones bring the best other pets, not the trained one (%s)" % str(ally_ids))
	# Growth is fixed per level by the pet's seed, so levelling most of the way
	# at once keeps this suite short; the last levels are still shown battles.
	# (Between two battles: a battle in progress keeps the pet as it is.)
	var levelled := false
	var shown := 0
	var cut_short := 0
	var last_battle := ""
	var last_state: Dictionary = {}
	var music_ok := true
	for i in range(40000):
		var battle_id := str(game.state.battle.get("battle_id",""))
		if game.battle_view.visible and battle_id!=last_battle:
			# A battle may only start once the one before it was over.
			if not last_state.is_empty() and bool(last_state.get("active",false)):cut_short += 1
			last_battle = battle_id
			shown += 1
		if game.state.battle_open:last_state = game.state.battle.duplicate()
		if radio_ok and flow.phase=="train" and not game.battle_view.visible and game.music.stream.resource_path.get_file().get_basename()!=bgm.get_file().get_basename():music_ok = false
		if flow.phase!="train":break
		if not levelled and shown>=2:levelled = game.backend.session.level_pet_to(str(flow.pet_id),117)
		step(game)
	check(levelled,"the trainee was levelled close to 120 for this test")
	check(shown>=3,"several training battles are shown (%d)" % shown)
	check(cut_short==0,"no battle ends early: each is over before the next one starts (%d cut short)" % cut_short)
	if radio_ok:check(music_ok,"between training battles the battle music keeps playing")
	var found_pet: Dictionary = game.backend.release_log.entries().filter(func(e):return str(e.get("source",""))!="排队已满").back() if not game.backend.release_log.entries().is_empty() else {}
	lines = game.state.automation.flow.log
	var level_lines: Array = lines.filter(func(line):return str(line.kind)=="level")
	check(not level_lines.is_empty() and str(level_lines.back().text).contains("三围合%d" % (int(predicted.attack)+int(predicted.defence)+int(predicted.speed))) and str(level_lines.back().text).contains("与预测一致"),"the info block gives the Lv120 stats, matching the prediction")
	var released_lines: Array = lines.filter(func(line):return str(line.kind)=="released")
	check(not released_lines.is_empty() and not found_pet.is_empty() and str(released_lines.back().text).ends_with("放生：%s" % str(found_pet.reason)),"a pet the keep rule releases is still captured and trained on screen; the block says why (%s)" % (str(released_lines.back().text) if not released_lines.is_empty() else ""))
	check(game.backend.session.clone_squad_enabled==clone_before and not game.backend.session.clone_best_others,"五人镜像队 and its composition are restored")

	# The next queued pet starts at once.
	check(drive(game,func():return flow.phase=="capture",40),"the next queued pet's capture starts right away")
	check(automation.showcase_queue.size()==3,"and the queue shrinks (3 left)")
	var capture_log: Array = game.backend.capture_log.entries()
	check(capture_log.any(func(e):return str(e.get("source",""))=="找宠流程" and not str(e.get("run","")).is_empty()),"the capture is logged as 找宠流程 with its run")
	# The block gives way to a menu over the top left.
	game.adventure_menu.show()
	game.showcase_ticker._process(0.0)
	check(not game.showcase_ticker.visible,"the info block gives way to the pet window")
	game.adventure_menu.hide()
	game.showcase_ticker._process(0.0)
	check(game.showcase_ticker.visible,"and comes back when it closes")

	# Moving drops the queue with a note; the radio plays on where it was.
	check(drive(game,func():return flow.phase!="capture"),"that capture finishes")
	var resume_at: float = radio._resume_at
	game.cell += Vector2i.ONE
	flow.advance()
	flow.on_status(game.state.automation)
	check(flow.phase=="paused" and automation.showcase_queue.is_empty() and str(game.state.automation.flow.reason).contains("排队的"),"moving pauses the cycle and drops the queue with a note")
	if radio_ok:check(not radio.suspended and radio.on and radio.current==radio_track and game.music.stream==radio._stream and game.music.get_playback_position()>=resume_at-0.1,"the radio plays on with the same track where it was")
	game.cell -= Vector2i.ONE
	if game.state.battle_open:game.link.request({"type":"battle_close"})

	# The runner waits for a shown turn to finish playing; it does not give up
	# after the 5 s it allows an unwatched turn.
	automation.client_attached = true
	automation._presented_key = ""
	automation._shown_key = "b:1"
	automation._shown_msec = Time.get_ticks_msec()-6000
	automation.showcase_show_battle = true
	check(not automation._presentation_done({"battle_id":"b","turn":1}),"a watched turn is waited for past 5 s")
	automation.showcase_show_battle = false
	check(automation._presentation_done({"battle_id":"b","turn":1}),"an unwatched turn is not")

	# 停止 in the hunt window during a shown capture battle stops the whole
	# cycle (the scan runs beside it, so stopping only the scan left the capture,
	# training and queue going) and leaves the battle to the player.
	game.session.gm_heal()
	check(flow.start_cycle(),"a new cycle starts for 停止")
	hunt.hunt_catalog = fixture
	for i in range(2):hunt.scan_once()
	flow.advance()
	check(flow.phase=="capture" and game.battle_view.visible and game.battle_session.snapshot().active and automation.hunt_running,"its capture battle is shown while the search goes on")
	hunt.restore()
	# First 停止: this pet is still caught (and would be trained); the search
	# and the queue stop now, and the button offers 立即停止.
	hunt.stop_button.pressed.emit()
	check(flow.phase=="capture" and automation.running and not automation.hunt_running and automation.showcase_queue.is_empty() and not flow.stop_pending().is_empty(),"停止 lets this pet finish; the search and queue stop now")
	check(hunt.stop_button.text=="立即停止","the button then offers 立即停止")
	# Where the next pet would start, the waiting stop ends the cycle.
	var saved_phase: String = automation.flow_phase
	automation.flow_phase = "restart"
	automation.flow_step()
	check(automation.flow_phase=="paused" and str(automation.flow_reason).begins_with("本只练完，已停止"),"once the pet is done the cycle stops (%s)" % automation.flow_reason)
	# Back to the running capture for 立即停止.
	automation.flow_phase = saved_phase
	automation.flow_stop_pending = "已停止，可调整条件后重新开始。"
	automation._emit_status()
	hunt.stop_button.pressed.emit()
	check(flow.phase=="paused" and not automation.running and not automation.hunt_running and automation.showcase_queue.is_empty(),"立即停止 stops the whole cycle: capture, search and queue")
	check(game.battle_session.snapshot().active and game.battle_view.visible,"the battle stays open for the player")
	hunt.close_menu()
	var stop_turn := int(game.battle_session.snapshot().turn)
	game.battle_action("attack")
	check(int(game.battle_session.snapshot().turn)>stop_turn or not game.battle_session.snapshot().active,"and the player can fight it by hand")
	# Close that battle before the next part.
	if game.battle_session.snapshot().active:game.battle_action("developer_escape")
	for i in range(60):await process_frame
	game.battle_view._process(game.battle_view.feedback_until+30.0)
	game.return_from_battle()
	await process_frame

	# Off: a hit goes straight into the compact capture, as before.
	hunt.showcase.button_pressed = false
	game.flush_automation_settings()
	hunt.close_menu()
	game.session.gm_heal()
	check(flow.start_cycle(),"a full-speed cycle starts")
	check(not bool(game.state.automation.flow.showcase),"with %s off" % AutomationSettings.SHOWCASE_NAME)
	hunt.hunt_catalog = fixture;hunt.scan_once()
	check(flow.phase=="capture" and bool(game.state.automation.compact) and not automation.hunt_running,"a hit goes straight to the compact capture and the search stops")
	flow.stop_cycle();flow.advance()

	# Battle music only while a pet is caught or trained on screen, or the next
	# one waits; a search alone gives the music back to the radio or the map.
	var saved_automation: Dictionary = game.state.automation
	var music_for := func(phase: String, queued: int) -> bool:
		game.state.automation = {"flow":{"showcase":true,"phase":phase,"queue_size":queued}}
		return game.showcase_music_active()
	check(music_for.call("capture",0) and music_for.call("train",0) and music_for.call("hunt",2),"battle music while capturing, training or with a pet queued")
	check(not music_for.call("hunt",0) and not music_for.call("restart",0),"searching alone plays the radio or map music again")
	game.state.automation = saved_automation

	if radio_ok:radio.turn_off()
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("SHOWCASE: %d failures" % failures);quit(1 if failures else 0)
