extends SceneTree
const Game = preload("res://server/game_session.gd")
const Battle = preload("res://server/battle_session.gd")
var failures := 0
var total_turns := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error("FAIL: " + message)
		failures += 1
	else:
		print("PASS: " + message)
func encounter(game, species: String, capture := false, boss := false) -> Dictionary:
	var battle = Battle.new()
	var config: Dictionary = game.start_battle_config(species,boss)
	check(not config.is_empty(),"encounter authorized")
	battle.start_battle(config)
	while battle.snapshot().active:
		var state: Dictionary = battle.snapshot()
		if capture:
			# Guard companion while weakening so it does not accidentally finish target.
			battle.set_pet_command("defend")
			battle.submit_action("capture" if state.enemy_hp * 100 <= state.enemy_max_hp * 60 else "attack")
		else:
			if state.skill_unlocked and not state.skill_used:
				battle.set_pet_command("skill")
			battle.submit_action("item" if state.player_hp < 18 and state.potions > 0 else "attack")
	var result: Dictionary = battle.snapshot()
	total_turns += result.turn
	check(game.apply_battle_result(result),"terminal result accepted")
	print("LOOP: ",species," capture=",capture," boss=",boss," outcome=",result.outcome," turns=",result.turn," remaining_hp=",result.player_hp)
	return result
func _initialize() -> void:
	var game = Game.new()
	check(game.accept_quest(),"accept quest")
	check(encounter(game,"wooli",true).outcome == "captured","capture first companion")
	# A fresh catch has the original loyalty (44 here) and may ignore 防御
	# (loyalty_test.gd covers that); this balance check wants an obedient pet.
	game._profile.pets[0].variable_ai = 10000
	for species in ["wooli","wooli_wooli","woolistan"]:
		check(game.heal(),"village recovery")
		check(encounter(game,species).outcome == "win","win species encounter")
	check(game.snapshot().pets[0].level == 2,"three fights grow companion")
	for stat in ["vitality","strength","toughness"]:
		check(game.allocate_stat(stat),"spend earned point on " + stat)
	check(game.buy_item("club") and game.equip_item("club"),"combat earnings buy weapon")
	game.heal()
	check(game.snapshot().player.level == 2,"boss balance baseline is level two")
	var boss_path := "user://mvp-boss-baseline-test.json"
	check(game.save_game(boss_path),"save legitimate level-two boss baseline")
	var fair_wins := 0
	for seed_value in range(30):
		var attempt = Game.new()
		attempt.load_game(boss_path)
		var boss_battle = Battle.new()
		boss_battle.rng_seed = seed_value
		boss_battle.start_battle(attempt.start_battle_config("woolistan",true))
		while boss_battle.snapshot().active:
			if not boss_battle.snapshot().skill_used:boss_battle.set_pet_command("skill")
			boss_battle.submit_action("attack")
		if boss_battle.snapshot().outcome == "win":fair_wins += 1
	check(fair_wins == 30,"level-two player pet and club beat modest boss across thirty seeds without potions")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(boss_path+suffix))
	for species in ["wooli_wooli","woolistan"]:
		game.heal()
		check(encounter(game,species,true).outcome == "captured","capture species with equipped weapon and guarding pet")
	check(game.snapshot().pets.size() == 3,"all three species collectable")
	check(game.can_fight_boss(),"boss unlocked without extra grind")
	game.heal()
	check(encounter(game,"woolistan",false,true).outcome == "win","strongest species boss defeated")
	check(game.claim_quest(),"quest completes")
	check(not game.can_fight_boss(),"boss stays completed")
	var save_path := "user://mvp-balance-test.json"
	check(game.set_location(1002,10,15) and not game.set_location(1002,30,0),"interior bounds verified")
	check(game.save_game(save_path),"save finished adventure")
	var restored = Game.new()
	check(restored.load_game(save_path) and restored.snapshot() == game.snapshot(),"reload preserves entire profile and location")
	check(restored.save_game(save_path),"resave restored adventure")
	var again = Game.new()
	check(again.load_game(save_path) and again.snapshot() == restored.snapshot(),"second load remains identical")
	for suffix in ["",".bak",".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("Adventure total turns: ",total_turns," failures: ",failures)
	quit(1 if failures else 0)
