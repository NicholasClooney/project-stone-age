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
	check(battle.submit_action("capture") == before, "unknown actions do not spend a turn or change state")
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
	print("Battle rules failures: ", failures)
	quit(1 if failures else 0)
