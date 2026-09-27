extends SceneTree
const Session=preload("res://server/game_session.gd")
const Battle=preload("res://server/squad_battle_session.gd")
var failures:=0
func check(ok: bool, text: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+text)
	if not ok:failures+=1
func _initialize() -> void:
	var session=Session.new()
	session.clone_squad_enabled=true
	var pet={"name":"战宠","hp":500,"max_hp":500,"attack":20,"defence":10,"speed":30,"level":2,"sprite":100250}
	var mount={"name":"坐骑","hp":100,"max_hp":100,"attack":100,"defence":20,"speed":20,"level":2,"sprite":100260}
	session._profile.pets=[pet.duplicate(true),mount.duplicate(true)]
	session._profile.active_pet=0
	session._profile.ride_pet=1
	var config: Dictionary=session.start_battle_config()
	check(config.ally_pets.size()==4 and config.allies[0].mount.hp==100,"snapshots four active pets and four mounts")
	config.ally_pets[0].hp=450
	config.allies[0].mount.hp=90
	check(config.ally_pets[1].hp==500 and session._profile.pets[0].hp==500 and config.allies[1].mount.hp==100,"all pets and mounts independent of each other and profile")
	config.player_hp=10000
	config.player_max_hp=10000
	config.enemies=[{"name":"练习","species":"wooli","sprite":100250,"hp":100000,"max_hp":100000,"attack":1,"defence":0,"speed":1,"reward_xp":20,"reward_gold":0}]
	var battle=Battle.new()
	var state: Dictionary=battle.start_battle(config)
	check(is_equal_approx(float(state.allies[0].attack),0.8*(config.player_attack+100)),"clone rider uses native mount attack formula")
	battle._apply_member_damage(0,"ally",20)
	state=battle.snapshot()
	var expected:=int(20.0*20/(maxi(1,int(config.player_defence))+20))+1
	check(state.allies[0].hp==config.allies[0].hp-expected and state.allies[0].mount.hp==90-(20-expected+1),"native rider and mount damage split")
	battle._state.allies[0].mount.hp=1
	battle._apply_member_damage(0,"ally",1000)
	state=battle.snapshot()
	check(state.allies[0].mount.hp==0 and state.allies[0].mounted_sprite==-1 and state.allies[0].attack==config.player_attack,"dead mount dismounts only its rider and restores base stats")
	state=battle.submit_action("attack")
	var actions:=0
	check(state.turn_order[0]=="player","real player still first")
	for frame in state.turn_frames:
		check(frame.ally_pets.size()==4,"frame includes independent clone pet health")
		if frame.actor=="ally_pet" and not str(frame.outcome).begins_with("counter"):actions+=1
	check(actions==4,"four fighting pets automatically take independent actions")
	check(session._profile.pets[1].hp==100,"temporary mount damage cannot mutate persistent pet")
	var targets:={}
	for seed_value in range(80):
		battle=Battle.new();battle.rng_seed=seed_value;battle.start_battle(config)
		state=battle.submit_action("attack")
		for frame in state.turn_frames:
			if frame.enemy_target=="ally_pet":targets[int(frame.ally_index)]=true
	check(targets.size()==4,"every mirror fighting pet can be attacked")
	battle=Battle.new();battle.start_battle(config)
	battle._state.ally_pets[0].hp=0
	state=battle.submit_action("capture")
	var attacks:=0
	for frame in state.turn_frames:
		if frame.actor=="ally_pet" and frame.outcome!="defend":attacks+=1
	check(attacks==0,"mirror pets defend during capture and dead pets cannot act")
	var rewards=Session.new()
	rewards.clone_squad_enabled=true
	rewards.grant_starter_pets()
	rewards.set_character("100010")
	rewards.select_pet(0)
	rewards.mount_pet(1)
	var reward_config: Dictionary=rewards.start_battle_config()
	for ally in reward_config.allies:ally.hp=0
	for mirror_pet in reward_config.ally_pets:mirror_pet.attack=100000;mirror_pet.speed=1000
	battle=Battle.new();battle.start_battle(reward_config);battle.set_pet_command("standby")
	state=battle.submit_action("defend")
	check(state.outcome=="win" and state.turn_frames.any(func(f):return f.actor=="ally_pet" and int(f.damage)>0),"mirror pet can independently win")
	check(state.enemies[0].defeated_by_pet_index==0 and state.enemies[0].defeated_with_ride_index==1,"mirror pet kill credits real deployed and riding pets")
	check(rewards.apply_battle_result(state),"mirror pet victory settles normally")
	var xp:=int(reward_config.enemies[0].reward_xp)
	check(state.xp==xp and state.pet_reward_xp==[xp,preload("res://scripts/riding.gd").experience(xp,1,1),0],"mirror pet rewards are neither divided nor duplicated")
	check(not rewards.apply_battle_result(state),"mirror pet victory settles only once")
	print("Clone pet rules failures: ",failures)
	quit(1 if failures else 0)
