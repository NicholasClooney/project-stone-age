extends SceneTree
const Game = preload("res://server/game_session.gd")
const Catalog = preload("res://server/encounter_catalog.gd")
const Battle = preload("res://server/battle_session.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures += 1
func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=932
	var actor: Dictionary = Catalog.new().actor(120,rng)
	actor.can_capture=true
	for outcome in ["win","captured","escaped","defeat"]:
		var game = Game.new()
		game._profile.player.level=30
		game.clone_squad_enabled=true
		game.experience_multiplier=100
		var config: Dictionary = game.start_wild_battle_config({"enemies":[actor.duplicate(true),actor.duplicate(true)]})
		check(config.battle_gold==300,"pre-level-up player level snapshots one 300-stone payout")
		var result: Dictionary = Battle.new().start_battle(config)
		result.active=false;result.outcome=outcome
		if outcome in ["win","captured"]:
			for enemy in result.enemies:
				enemy.hp=0
				if outcome=="captured":
					enemy.captured=true
					result.captured_species_list.append(enemy.species)
		if outcome=="defeat":result.player_hp=0
		result.gold=999999 # Client reward claims are never trusted.
		check(game.apply_battle_result(result),outcome+" authoritative settlement accepted")
		var expected := 300 if outcome in ["win","captured"] else 0
		check(result.gold==expected and game.snapshot().player.gold==20+expected,outcome+": payout once, unaffected by troop/clones/100x XP/client claim")
		check(not game.apply_battle_result(result),"duplicate "+outcome+" cannot mint currency")
		if outcome=="win":
			var path := "user://wild-currency-test.json"
			var loaded=Game.new()
			check(game.save_game(path) and loaded.load_game(path) and loaded.snapshot().player.gold==320,"currency survives save and reload")
			for suffix in ["",".bak",".tmp"]:
				if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var capped=Game.new()
	capped._profile.player.gold=999999995
	var config: Dictionary = capped.start_wild_battle_config({"enemies":[actor]})
	var result: Dictionary = Battle.new().start_battle(config)
	result.active=false;result.outcome="win";result.enemies[0].hp=0
	check(capped.apply_battle_result(result) and result.gold==5 and capped.snapshot().player.gold==1000000000,"currency cap reports only amount actually credited")
	print("WILD CURRENCY: %d failures"%failures)
	quit(1 if failures else 0)
