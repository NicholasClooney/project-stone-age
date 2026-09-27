extends SceneTree
const Game = preload("res://server/game_session.gd")
const Battle = preload("res://server/battle_session.gd")
const Growth = preload("res://server/progression.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures += 1
func pet(index: int) -> Dictionary:
	var value := Growth.species_actor("wooli",1,100+index)
	value.merge({"species":"wooli","name":"伙伴%d" % index,"sprite":100250,"level":1,"xp":0,"skill_unlocked":false})
	return value
func _initialize() -> void:
	var game = Game.new()
	game._profile.pets = [pet(0),pet(1)]
	game._profile.active_pet = 0
	var config: Dictionary = game.start_battle_config("wooli",false,3)
	# Controlled actor strength makes each target die in one attack; actual
	# battle actions, counters, switching and settlement still execute.
	config.player_attack = 100;config.player_speed = 100;config.player_defence = 100
	var battle = Battle.new()
	battle.start_battle(config)
	battle.set_pet_command("defend")
	battle.submit_action("attack",0)
	battle.submit_action("switch",1,1)
	battle.set_pet_command("defend")
	battle.submit_action("attack",1)
	battle.submit_action("switch",2,-1)
	battle.submit_action("attack",2)
	var result: Dictionary = battle.snapshot()
	check(result.outcome == "win" and game.apply_battle_result(result),"three-enemy battle settles after switching and withdrawal")
	check(game.snapshot().active_pet == -1 and game.snapshot().pets[0].xp == 20 and game.snapshot().pets[1].xp == 20,"withdrawn companions retain only XP earned while present")
	check(result.pet_reward_xp == [20,20] and result.xp == 60,"settlement exposes actual per-pet reward ledger")
	check(not game.apply_battle_result(result),"group rewards cannot be replayed")
	for outcome in ["escaped","defeat"]:
		game = Game.new()
		config = game.start_battle_config("wooli",false,3)
		config.player_attack = 100;config.player_speed = 100
		config.player_defence = 100 if outcome == "escaped" else 0
		if outcome == "defeat":
			for enemy in config.enemies:enemy.attack = 1000
		battle = Battle.new();battle.start_battle(config)
		battle.submit_action("attack",0)
		for turn in range(10):
			if not battle.snapshot().active:break
			battle.submit_action("escape" if outcome == "escaped" else "defend")
		result = battle.snapshot()
		check(result.outcome == outcome and game.apply_battle_result(result),"partial kill then "+outcome+" settles")
		check(game.snapshot().player.xp == 0 and game.snapshot().player.gold == 20,"no XP or gold paid after "+outcome)
	game = Game.new()
	for i in range(Game.PET_CAPACITY-1):game._profile.pets.append(pet(i))
	config = game.start_battle_config("wooli",false,3)
	config.player_attack = 100;config.player_speed = 100;config.player_defence = 100
	# Wounded encounter fixture isolates capture-capacity accounting.
	for enemy in config.enemies:enemy.hp = int(enemy.max_hp/2)
	battle = Battle.new();battle.start_battle(config)
	battle.submit_action("capture",2)
	var before: Dictionary = battle.snapshot()
	check(not before.can_capture and battle.submit_action("capture",1) == before,"last roster slot immediately blocks another capture in same group")
	battle.submit_action("attack",0);battle.submit_action("attack",1)
	result = battle.snapshot()
	var forged := result.duplicate(true)
	forged.captured_species_list.append("wooli")
	check(not game.apply_battle_result(forged),"over-capacity captured roster rejected atomically")
	check(game.apply_battle_result(result) and game.snapshot().pets.size() == Game.PET_CAPACITY,"capture plus remaining kills settles exactly one new pet")
	check(result.xp == 40 and game.snapshot().player.gold == 40,"captured foe awards no kill XP or gold")
	print("SETTLEMENT: %d failures" % failures)
	quit(1 if failures else 0)
