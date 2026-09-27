extends SceneTree
const Session = preload("res://server/game_session.gd")
const Battle = preload("res://server/squad_battle_session.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures+=1

func _initialize() -> void:
	var session = Session.new()
	check(not session.clone_squad_enabled,"clone helper defaults off")
	session.clone_squad_enabled=true
	var config: Dictionary = session.start_battle_config()
	check(config.allies.size()==4,"four mirrors plus player make five people")
	for ally in config.allies:
		check(ally.hp==config.player_hp and ally.attack==config.player_attack and ally.weapon==config.player_weapon,"mirror snapshots current HP, stats and weapon")
	config.allies[0].hp=1
	check(config.allies[1].hp==config.player_hp and session.snapshot().player.hp==config.player_hp,"mirrors and profile do not alias")
	var battle = Battle.new()
	var state: Dictionary = battle.start_battle(config)
	check(state.get("allies",[]).size()==4,"authority exposes independent allies")
	if not state.has("allies"):
		print("Clone squad failures: ",failures)
		quit(1)
		return
	# Large durable target keeps all five turns observable without early victory.
	var durable := config.duplicate(true)
	durable.enemies=[{"name":"练习","species":"wooli","sprite":100250,"hp":100000,"max_hp":100000,"attack":1,"defence":0,"speed":1,"reward_xp":20,"reward_gold":0}]
	durable.player_hp=10000
	durable.player_max_hp=10000
	for ally in durable.allies:ally.hp=10000;ally.max_hp=10000
	var observed_targets := {}
	var total_ally_actions := 0
	var ally_counters := 0
	var enemy_ally_counters := 0
	for seed_value in range(60):
		battle=Battle.new()
		battle.rng_seed=seed_value
		battle.start_battle(durable)
		state=battle.submit_action("attack")
		for frame in state.turn_frames:
			check(frame.get("allies",[]).size()==4,"every animation frame contains ally health")
			if frame.actor=="ally":
				total_ally_actions+=1
				if str(frame.outcome).begins_with("counter"):ally_counters+=1
				check(int(frame.ally_index) in range(4),"ally action identifies correct mirror")
			if frame.actor=="enemy" and frame.enemy_target=="ally":
				observed_targets[int(frame.ally_index)]=true
				if str(frame.outcome).begins_with("counter"):enemy_ally_counters+=1
	check(total_ally_actions>=240,"all four living mirrors attack independently")
	check(observed_targets.size()==4,"enemies can attack every mirror")
	var counters:=durable.duplicate(true)
	counters.enemies[0].speed=100
	for ally in counters.allies:ally.speed=1000
	for seed_value in range(20):
		battle=Battle.new()
		battle.rng_seed=seed_value
		battle.start_battle(counters)
		state=battle.submit_action("attack")
		for frame in state.turn_frames:
			if not str(frame.outcome).begins_with("counter"):continue
			if frame.actor=="ally":ally_counters+=1
			if frame.actor=="enemy" and frame.enemy_target=="ally":enemy_ally_counters+=1
	check(ally_counters>0 and enemy_ally_counters>0,"seeded rounds exercise counterattacks in both directions")
	var priority := durable.duplicate(true)
	priority.player_speed=1
	priority.enemies[0].speed=100
	priority.enemies.append(priority.enemies[0].duplicate(true))
	battle=Battle.new()
	battle.start_battle(priority)
	state=battle.submit_action("attack",1)
	check(state.turn_order[0]=="player","helper mode gives the main player first action despite faster enemies")
	var targeted := 0
	for frame in state.turn_frames:
		if frame.actor=="ally" and not str(frame.outcome).begins_with("counter"):
			targeted+=1
			check(int(frame.target_index)==1,"mirrors follow main selected target despite intervening enemy/counter actions")
	check(targeted==4,"all four mirror main target")
	var original = preload("res://server/battle_session.gd").new()
	original.start_battle(priority)
	check(original.submit_action("attack",1).turn_order[0]=="enemy","original solo authority retains normal speed order")
	battle=Battle.new()
	battle.start_battle(durable)
	state=battle.submit_action("capture")
	check(state.turn_frames.filter(func(frame):return frame.actor=="ally" and frame.damage>0).is_empty(),"mirrors do not kill a capture target")
	var defeated := durable.duplicate(true)
	defeated.player_hp=1
	defeated.allies=[]
	defeated.enemies[0].attack=100000
	defeated.enemies[0].speed=100000
	battle=Battle.new()
	battle.start_battle(defeated)
	state=battle.submit_action("attack")
	check(state.outcome=="defeat","ordinary leader defeat remains terminal")
	var fragile:=durable.duplicate(true)
	fragile.enemies[0].attack=100
	fragile.enemies[0].speed=100
	for ally in fragile.allies:ally.hp=1;ally.speed=1
	var saw_dead:=false
	for seed_value in range(20):
		battle=Battle.new()
		battle.rng_seed=seed_value
		battle.start_battle(fragile)
		state=battle.submit_action("attack")
		var dead: Array[int]=[]
		for frame in state.turn_frames:
			if frame.actor=="ally":check(not dead.has(int(frame.ally_index)),"fallen clone never acts again")
			for i in range(4):
				if int(frame.allies[i].hp)<=0 and not dead.has(i):dead.append(i);saw_dead=true
	check(saw_dead,"enemy damage exercises fallen clones")
	var rewards=Session.new()
	rewards.clone_squad_enabled=true
	rewards.grant_starter_pets()
	rewards.set_character("100010")
	rewards.select_pet(0)
	check(rewards.mount_pet(1),"reward fixture has a real deployed pet and riding pet")
	var reward_config: Dictionary=rewards.start_battle_config()
	for ally in reward_config.allies:ally.attack=100000;ally.speed=100
	battle=Battle.new()
	battle.start_battle(reward_config)
	battle.set_pet_command("standby")
	state=battle.submit_action("defend")
	check(state.outcome=="win" and state.turn_frames.any(func(frame):return frame.actor=="ally" and int(frame.damage)>0),"clone independently defeats the enemy")
	check(int(state.enemies[0].defeated_by_pet_index)==0 and int(state.enemies[0].defeated_with_ride_index)==1,"clone kill credits only real active and riding pets")
	var before_reward: Dictionary=rewards.snapshot()
	check(rewards.apply_battle_result(state),"normal authority accepts clone victory")
	var after_reward: Dictionary=rewards.snapshot()
	var xp:=int(reward_config.enemies[0].reward_xp)
	check(int(state.xp)==xp and int(state.gold)==int(reward_config.enemies[0].reward_gold),"clones neither split nor multiply player XP or gold")
	check(state.pet_reward_xp==[xp,preload("res://scripts/riding.gd").experience(xp,1,1),0],"real pets receive unchanged normal XP allocation")
	check(after_reward.pets.size()==before_reward.pets.size() and after_reward.inventory==before_reward.inventory,"clone victory creates no duplicate pets or inventory")
	check(not after_reward.has("allies"),"temporary clones never enter persisted profile")
	check(not rewards.apply_battle_result(state),"clone result cannot be redeemed twice")
	print("Clone squad failures: ",failures)
	quit(1 if failures else 0)
