extends SceneTree

const Battle = preload("res://server/battle_session.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		push_error("FAIL: " + message)
		failures += 1

func _initialize() -> void:
	var battle = Battle.new()
	var before: Dictionary = battle.snapshot()
	check(battle.submit_action("attack") == before, "actions before start do not mutate state")
	before = battle.start_battle()
	check(before.active and before.turn == 0 and before.player_hp == 48, "start initializes active battle")
	check(battle.submit_action("invalid") == before, "unknown actions do not spend a turn or change state")
	var copy: Dictionary = battle.snapshot()
	copy.events.append("forged")
	copy.player_hp = 0
	check(battle.snapshot() == before, "snapshot mutation cannot alter authority")
	battle.submit_action("attack")
	before = battle.snapshot()
	check(battle.start_battle() == before, "repeated start cannot reset an active battle")
	while battle.snapshot().active:
		battle.submit_action("attack")
	before = battle.snapshot()
	check(before.outcome == "win" and before.enemy_hp == 0 and before.player_hp > 0, "attack reaches victory with bounded health")
	for action in ["attack", "defend", "escape", "bad"]:
		check(battle.submit_action(action) == before, "finished battle rejects " + action)
	check(battle.start_battle().turn == 0, "new battle can begin after completion")
	var guarded: Dictionary = battle.submit_action("defend")
	check(48 - guarded.player_hp >= 2 and 48 - guarded.player_hp <= 4, "guard reduces incoming 5–9 damage to 2–4")
	var attacked: Dictionary = battle.submit_action("attack")
	check(guarded.player_hp - attacked.player_hp >= 5, "guard expires before the next attack turn")
	while battle.snapshot().active:
		battle.submit_action("defend")
	check(battle.snapshot().outcome == "defeat" and battle.snapshot().player_hp == 0, "defending without attacking eventually reaches defeat")
	before = battle.snapshot()
	check(battle.submit_action("attack") == before, "defeat is terminal")
	var saw_failed_escape := false
	for seed_value in range(30):
		var first = Battle.new()
		var second = Battle.new()
		first.rng_seed = seed_value
		second.rng_seed = seed_value
		first.start_battle()
		second.start_battle()
		for action in ["escape", "escape", "escape"]:
			var state: Dictionary = first.submit_action(action)
			if state.active:
				saw_failed_escape = true
				check(state.player_hp < 48, "failed escape allows enemy retaliation")
			check(state == second.submit_action(action), "seeded command replay stays deterministic")
		check(first.snapshot().outcome == "escaped", "escape guaranteed by third attempt")
		before = first.snapshot()
		check(first.submit_action("attack") == before, "escape is terminal")
	check(saw_failed_escape, "tests exercise failed and successful escape paths")
	var fast_enemy = Battle.new()
	fast_enemy.start_battle({"player_hp":1,"enemy_speed":20,"player_speed":10})
	var fast_state: Dictionary = fast_enemy.submit_action("attack")
	check(fast_state.outcome == "defeat" and fast_state.enemy_hp == 32 and fast_state.turn_order == ["enemy"],"faster enemy defeats player before player can attack")
	var slow_pet = Battle.new()
	slow_pet.start_battle({"pet":{"hp":30,"max_hp":30,"speed":2,"attack":4,"name":"伙伴"},"enemy_speed":7,"player_speed":10})
	var order: Dictionary = slow_pet.submit_action("attack")
	check(order.turn_order == ["player","enemy","pet"],"slower companion acts after enemy")
	var ties = Battle.new()
	ties.start_battle({"pet":{"hp":30,"max_hp":30,"speed":10,"attack":4,"name":"伙伴"},"enemy_speed":10,"player_speed":10})
	check(ties.submit_action("defend").turn_order == ["player","pet","enemy"],"equal speed ties resolve player pet enemy")
	var early_guard = Battle.new()
	early_guard.start_battle({"pet":{"hp":30,"max_hp":30,"speed":2,"attack":4,"name":"伙伴"},"enemy_speed":20,"player_speed":10})
	early_guard.set_pet_command("defend")
	var guarded_state: Dictionary = early_guard.submit_action("defend")
	check(guarded_state.player_hp == 48 and guarded_state.pet_hp >= 28 and guarded_state.pet_hp < 30,"slow actors defend from start of round")
	print("Battle rules failures: ", failures)
	quit(1 if failures else 0)
