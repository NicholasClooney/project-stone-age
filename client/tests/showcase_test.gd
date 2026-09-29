extends SceneTree
## 展示模式 of the find-pet cycle (server/automation.gd): hits found while busy
## wait in a queue of at most 10, best first; a queued hit is replayed from its
## own roll seed before its capture; the reveal card, the capture battle and
## the shown training battles (10x experience, 五人镜像队 with the best other
## pets) are presented on this device at 1x; milestone and final cards; the
## player's settings come back afterwards; the next queued pet starts at once;
## moving drops the queue.
const Progression = preload("res://server/progression.gd")
const Automation = preload("res://server/automation.gd")
var failures := 0
var clock := 1000

class FixedTroop extends RefCounted:
	var troop: Dictionary
	func roll(_map, _cell, _rng) -> Dictionary:return troop.duplicate(true)

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func _initialize() -> void:call_deferred("run")

func stats(pet: Dictionary) -> Dictionary:
	return {"attack":int(pet.attack),"defence":int(pet.defence),"speed":int(pet.speed),"max_hp":int(pet.max_hp)}

## Drives in-process frames: presentation, battle runner and workflow.
func drive(game, until: Callable, steps: int = 4000) -> bool:
	var helper = game.training_helper
	var flow = game.pet_workflow
	for i in range(steps):
		if until.call():return true
		game.battle_view._process(0.25)
		game.acknowledge_presentation()
		helper.advance()
		flow.advance()
		clock += 250
	return bool(until.call())

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate();game.profile_persistence = false;root.add_child(game)
	await process_frame
	game.session.grant_starter_pets()
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,120);game.session.gm_set_base_stat(-1,"toughness",500);game.session.gm_heal()
	var automation = game.backend.automation
	var flow = game.pet_workflow;flow.set_process(false)
	var hunt = game.pet_hunt_menu;hunt.set_process(false)
	var helper = game.training_helper;helper.set_process(false)
	flow.timer_clock = func():return clock
	check(bool(game.automation_settings().hunt.showcase) and hunt.showcase.button_pressed,"展示模式 is on by default")

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
	# auto tidy with a rule that keeps nothing releases each one after its showcase.
	game.link.request({"type":"set_automation_settings","settings":{"stat_filters":{str(target):{"stop_after":0,"conditions":{"sum":{"enabled":true,"value":1,"strict":false}},"keep_rule":{"tiers":0,"champions":0,"auto":true}}}}})
	hunt.open_menu();hunt.apply_preset(0)
	var xp_before: int = game.backend.session.experience_multiplier
	var clone_before: bool = game.backend.session.clone_squad_enabled
	check(flow.start_cycle(),"a find-pet cycle starts in 展示模式")
	check(bool(game.state.automation.flow.showcase),"the status says 展示模式")

	# Queue: at most 10, the best kept, found while the flow is idle or busy.
	hunt.hunt_catalog = fixture
	var variants: Array = []
	for i in range(11):
		var actor: Dictionary = fixture.troop.enemies[0].duplicate(true)
		actor.growth_seed = 7000+i*37
		variants.append(actor)
		automation._showcase_enqueue(100+i,0,{"enemies":[actor]},{"offsets":[0,0,0,0],"total_offset":0})
	var sums: Array = variants.map(func(actor): var p := Progression.project_pet(actor,120);return int(p.attack)+int(p.defence)+int(p.speed))
	var kept_sums: Array = automation.showcase_queue.map(func(e):return int(e.prediction.attack)+int(e.prediction.defence)+int(e.prediction.speed))
	var sorted_sums := sums.duplicate();sorted_sums.sort();sorted_sums.reverse()
	check(automation.showcase_queue.size()==10,"the queue keeps at most 10")
	check(kept_sums==sorted_sums.slice(0,10),"best first by predicted 三围合; the lowest is dropped (%s)" % str(kept_sums))
	automation.showcase_queue.clear()

	# Real scans while idle: hits queue and the search keeps running.
	for i in range(3):hunt.scan_once()
	check(automation.showcase_queue.size()==3 and automation.hunt_running and flow.phase=="hunt","three hits queue while the search keeps running")
	check(hunt.queue_text()=="后台已找到 3 只在排队","the hunt window shows the queue")

	# Reveal: the best queued hit and its exact Lv120 prediction.
	flow.advance()
	var card: Dictionary = game.state.automation.flow.card
	var predicted: Dictionary = Progression.project_pet(fixture.troop.enemies[0],120)
	check(flow.phase=="reveal" and str(card.kind)=="reveal","the next step reveals the best queued hit")
	check(card.prediction==stats(predicted) and int(card.sum)==int(predicted.attack)+int(predicted.defence)+int(predicted.speed),"the reveal card carries the exact Lv120 prediction")
	check(card.rarity is Array and not card.rarity.is_empty() and int(card.queue)==2,"with rarity lines and the queue behind it")
	check(game.showcase_cards.visible and game.showcase_cards.find_child("ShowcaseTitle",true,false).text.begins_with(str(card.name)),"this device shows the reveal card")
	check(not hunt.visible and hunt.minimized,"the hunt window folds to its progress bar")
	flow.advance()
	check(flow.phase=="reveal","the card stays for its time")

	# Capture: replayed from its roll seed, then shown at 1x.
	clock += Automation.REVEAL_MSEC
	flow.advance()
	check(flow.phase=="capture" and game.battle_view.visible and not game.state.automation.compact,"the capture battle opens uncompacted and is presented")
	check(bool(game.state.automation.flow.show_battle) and is_equal_approx(game.battle_view.playback_speed,1.0),"shown battles play at 1x on this device")
	check(not game.showcase_cards.visible,"the card gives way to the battle")
	for i in range(2):hunt.scan_once()
	check(automation.hunt_running and automation.showcase_queue.size()==4,"the search goes on during the capture battle (queue 4)")
	check(drive(game,func():return flow.phase!="capture"),"the capture battle finishes")
	var pets: Array = game.session.snapshot().pets
	var caught: Dictionary = pets[game.session.snapshot().active_pet]
	check(flow.phase=="train" and caught.pet_id==flow.pet_id,"the captured pet is active for its training")

	# Training: 10x, 五人镜像队 with the best other pets, shown battles.
	check(automation.running and not bool(automation.settings.compact) and int(game.backend.session.experience_multiplier)==10 and int(automation.settings.hp)==-1,"training battles run shown, at 10x experience, without an HP stop line for the Lv1 pet")
	check(game.backend.session.clone_squad_enabled and game.backend.session.clone_best_others,"with the 五人镜像队 of best other pets")
	check(drive(game,func():return game.battle_view.visible or not automation.running),"a training battle opens")
	var allies: Array = game.battle_session.snapshot().get("ally_pets",[])
	var best_ids: Array = game.backend.session.best_other_pets(4).map(func(pet):return str(pet.pet_id))
	var ally_ids: Array = allies.map(func(pet):return str(pet.get("pet_id","")))
	check(ally_ids.slice(0,best_ids.size())==best_ids and not ally_ids.has(str(flow.pet_id)) and not ally_ids.has("clone-of-"+str(flow.pet_id)),"the clones bring the best other pets, not the trained one (%s)" % str(ally_ids))
	var shown := 0
	var milestones: Array = []
	var last_battle := ""
	var final_card: Dictionary = {}
	for i in range(20000):
		var f: Dictionary = game.state.automation.flow
		var battle_id := str(game.state.battle.get("battle_id",""))
		if game.battle_view.visible and battle_id!=last_battle:
			last_battle = battle_id
			shown += 1
			check(is_equal_approx(game.battle_view.playback_speed,1.0),"shown training battle %d plays at 1x" % shown)
		var c: Dictionary = f.get("card",{})
		if str(c.get("kind",""))=="milestone" and not milestones.has(int(c.level)):
			milestones.append(int(c.level))
			check(game.showcase_cards.visible and game.showcase_cards.find_child("ShowcaseMilestone",true,false)!=null,"the Lv%d milestone toast shows" % int(c.level))
		if str(c.get("kind",""))=="final" and final_card.is_empty():
			final_card = c.duplicate(true)
			check(game.showcase_cards.visible and game.showcase_cards.find_child("ShowcaseRank",true,false)!=null,"the final card shows")
			check(int(game.backend.session.experience_multiplier)==xp_before and game.backend.session.clone_squad_enabled==clone_before and not game.backend.session.clone_best_others,"experience multiplier and 五人镜像队 are restored")
		if flow.phase!="train":break
		game.battle_view._process(0.25);game.acknowledge_presentation();helper.advance();flow.advance()
		clock += 250
	check(shown==7,"3 training battles and one at Lv30, 60, 90 and 120 are shown (%d)" % shown)
	check(milestones==[30,60,90],"milestone toasts at Lv30, 60 and 90 (%s)" % str(milestones))
	check(int(final_card.get("actual",{}).get("attack",0))>0 and final_card.get("actual",{})==stats(Progression.project_pet(fixture.troop.enemies[0],120)),"the final card shows the Lv120 pet's actual stats")
	check(bool(final_card.get("matches",false)) and final_card.prediction==stats(predicted),"which match the prediction")
	check(int(final_card.get("rank",0))>=1 and int(final_card.get("of",0))>=1,"and its rank in the species (%d of %d)" % [int(final_card.get("rank",0)),int(final_card.get("of",0))])
	var released: Array = game.backend.release_log.entries().filter(func(e):return str(e.get("pet_id",""))==str(final_card.get("pet_id","")))
	check(bool(final_card.get("released",false)) and str(final_card.get("outcome","")).begins_with("按保留规则放生：") and not released.is_empty() and str(final_card.outcome).ends_with(str(released[0].reason)),"a pet the keep rule releases still gets its full showcase, and the final card says why (%s)" % str(final_card.get("outcome","")))

	# The next queued pet starts at once.
	check(drive(game,func():return flow.phase=="reveal",40),"the next queued pet is revealed right away")
	check(automation.showcase_queue.size()==3,"and the queue shrinks (3 left)")
	var capture_log: Array = game.backend.capture_log.entries()
	check(capture_log.any(func(e):return str(e.get("pet_id",""))==str(final_card.get("pet_id","")) and str(e.get("source",""))=="找宠流程" and not str(e.get("run","")).is_empty()),"the showcase capture is logged as 找宠流程 with its run")

	# Moving drops the queue with a note.
	game.cell += Vector2i.ONE
	flow.advance()
	check(flow.phase=="paused" and automation.showcase_queue.is_empty() and str(game.state.automation.flow.reason).contains("排队的 3 只已放弃"),"moving pauses the cycle and drops the queue with a note")
	check(not game.showcase_cards.visible,"no card is left on screen")
	game.cell -= Vector2i.ONE

	# 展示模式 off: a hit goes straight into the compact capture, as before.
	hunt.showcase.button_pressed = false
	game.flush_automation_settings()
	hunt.close_menu()
	game.session.gm_heal()
	check(flow.start_cycle(),"a full-speed cycle starts")
	check(not bool(game.state.automation.flow.showcase),"with 展示模式 off")
	hunt.hunt_catalog = fixture;hunt.scan_once()
	check(flow.phase=="capture" and bool(game.state.automation.compact) and not automation.hunt_running,"a hit goes straight to the compact capture and the search stops")
	flow.stop_cycle();flow.advance()

	game.process_mode = Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	print("SHOWCASE: %d failures" % failures);quit(1 if failures else 0)
