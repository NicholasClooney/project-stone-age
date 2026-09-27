extends SceneTree
const Battle = preload("res://server/battle_session.gd")
const Rules = preload("res://server/classic_combat_rules.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		push_error("FAIL: " + label)
		failures += 1
	else: print("PASS: " + label)
func enemy(hp: int = 100) -> Dictionary:
	return {"name":"乌力","species":"wooli","sprite":100250,"hp":hp,"max_hp":100,"attack":1,"defence":0,"speed":1,"reward_xp":3,"reward_gold":2}
func pet() -> Dictionary:
	return {"name":"伙伴","sprite":100250,"hp":100,"max_hp":100,"attack":8,"defence":4,"speed":10,"learned_skills":[3,10,50]}
func _initialize() -> void:
	check(is_equal_approx(Rules.odds({"kind":"player","speed":10},{"speed":10},"miss"),sqrt(4.0/0.02)*0.6),"source dodge agility scaling")
	check(is_equal_approx(Rules.odds({"kind":"player","speed":10},{"speed":10},"critical"),sqrt(4.0/0.09)),"source critical agility scaling")
	var classic_rng := RandomNumberGenerator.new()
	var reference_rng := RandomNumberGenerator.new()
	classic_rng.seed = 91
	reference_rng.seed = 91
	var classic_damage: Dictionary = Rules.resolve({"attack":20,"speed":10},{"defence":10,"speed":0},classic_rng,false,"classic")
	var reference_damage: Dictionary = Rules.resolve({"attack":20,"speed":10},{"defence":10,"speed":0},reference_rng,false,"reference")
	check(classic_damage.damage > reference_damage.damage,"explicit reference profile uses enabled .70 defence branch")
	var battle = Battle.new()
	battle.start_battle({"enemies":[enemy(20),enemy(20),enemy(20)],"player_speed":100,"player_attack":10,"pets":[pet(),pet()],"active_pet":0,"capture_slots":1})
	battle.set_pet_command("defend")
	var state: Dictionary = battle.submit_action("capture",1)
	check(state.active and state.enemies[1].captured and state.capture_success,"capture one enemy leaves battle active")
	check(state.captured_species_list == ["wooli"],"capture list records one companion")
	check(battle.submit_action("capture",0) == state,"capture capacity rejects extra companion without turn")
	state = battle.submit_action("switch",0,1)
	check(state.active_pet == 1 and not "pet" in state.turn_order,"switch consumes player turn and incoming pet waits")
	state = battle.submit_action("switch",0,-1)
	check(state.active_pet == -1 and state.pet.is_empty(),"withdraw leaves no combat pet")
	state = battle.submit_action("switch",0,0)
	check(state.active_pet == 0,"withdrawn pet can return")
	battle.set_pet_command("standby")
	state = battle.submit_action("defend",0)
	check(state.active_pet == 0 and state.turn_frames.any(func(frame): return frame.actor == "pet" and frame.outcome == "standby" and frame.damage == 0),"native standby consumes an action without withdrawing or attacking")
	check(not battle.set_pet_skill(999),"unknown skill rejected")
	check(battle.set_pet_skill(10),"learned continuous attack selectable")
	battle.set_pet_target(2)
	state = battle.submit_action("defend",0)
	var hits := 0
	for frame in state.turn_frames:
		if frame.actor == "pet" and frame.get("skill_id",0) == 10:
			hits += 1
			check(frame.target_index == 2,"pet uses independent target")
	check(hits == 2,"continuous attack emits two independently animated impacts")
	check(state.turn_frames.size() == state.turn_order.size(),"every impact has one ordered frame")
	var outcomes := {"miss":false,"critical":false,"counter":false}
	for seed_value in range(200):
		var sample = Battle.new()
		sample.rng_seed = seed_value
		sample.start_battle({"player_hp":1000,"player_max_hp":1000,"enemy_max_hp":1000,"player_speed":10,"enemy_speed":20})
		var turn: Dictionary = sample.submit_action("attack")
		for frame in turn.turn_frames:
			for key in outcomes:
				if key in str(frame.outcome): outcomes[key] = true
	check(outcomes.miss and outcomes.critical and outcomes.counter,"seed sweep exercises real misses criticals and counters")
	var guarded = Battle.new()
	guarded.start_battle({"player_hp":1000,"player_max_hp":1000,"enemy_max_hp":1000})
	for turn in range(15):
		var result: Dictionary = guarded.submit_action("defend")
		for frame in result.turn_frames:
			check(frame.outcome != "miss" and not str(frame.outcome).begins_with("counter"),"guard disables dodge and retaliatory counter")
	var guard_break_damage := 0
	var normal_guard_damage := 0
	var power_damage := 0
	var normal_damage := 0
	var power_received := 0
	var normal_received := 0
	for seed_value in range(40):
		for skill_id in [0,3,10,50]:
			var skill_battle = Battle.new()
			skill_battle.rng_seed = seed_value
			var target := enemy(1000)
			target.max_hp = 1000
			target.command = "defend"
			var companion := pet()
			companion.attack = 20
			skill_battle.start_battle({"player_speed":100,"enemies":[target],"pets":[companion],"active_pet":0})
			if skill_id > 0: check(skill_battle.set_pet_skill(skill_id),"supported learned skill accepted")
			var result: Dictionary = skill_battle.submit_action("defend")
			var damage := 1000-int(result.enemies[0].hp)
			if skill_id == 0:
				normal_guard_damage += damage
				normal_damage += damage
			elif skill_id == 3: guard_break_damage += damage
			elif skill_id == 50: power_damage += damage
			elif skill_id == 10:
				var expected_rng := RandomNumberGenerator.new()
				expected_rng.seed = seed_value
				companion.kind = "pet"
				var first: Dictionary = Rules.resolve(companion,target,expected_rng,true)
				var second: Dictionary = Rules.resolve(companion,target,expected_rng,true)
				check(damage == int(int(first.damage)/2) + int(int(second.damage)/2),"continuous attack divides each source-calculated hit by two")
		for skill_id in [0,50]:
			var vulnerable = Battle.new()
			vulnerable.rng_seed = seed_value
			var companion := pet()
			companion.hp = 1000
			companion.max_hp = 1000
			companion.defence = 40
			var target := enemy(1000)
			target.max_hp = 1000
			target.attack = 30
			target.speed = 50
			vulnerable.start_battle({"player_hp":1000,"player_max_hp":1000,"enemies":[target],"pets":[companion],"active_pet":0})
			if skill_id > 0: vulnerable.set_pet_skill(skill_id)
			var result: Dictionary = vulnerable.submit_action("defend")
			if skill_id == 0: normal_received += 1000-int(result.pet_hp)
			else: power_received += 1000-int(result.pet_hp)
	check(guard_break_damage > normal_guard_damage*2,"guard break bypasses guard reduction")
	check(power_damage > normal_damage,"power balance increases physical attack")
	check(power_received > normal_received,"power balance exposes pet to extra damage before it acts")
	var untrained = Battle.new()
	var no_skills := pet()
	no_skills.learned_skills = []
	no_skills.level = 10
	untrained.start_battle({"pet":no_skills})
	check(not untrained.set_pet_skill(3) and not untrained.set_pet_command("skill"),"levels never bypass learned-skill validation")
	print("Classic combat failures: ",failures)
	quit(1 if failures else 0)
