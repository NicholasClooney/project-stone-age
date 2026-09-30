extends SceneTree
## 气力 and the healing 精灵 (server/spirits.gd,
## docs/reverse-engineering/magic-and-mp.md) on the real GameSession and
## BattleSession with seeded rngs: MP max and save round trip (and the
## version 3 migration), each spirit's amount, cost and target against a
## literal port of the pinned gmsv formulas, too little 气力, revive, field
## use, equipping rules and settlement.
const Session = preload("res://server/game_session.gd")
const Battle = preload("res://server/battle_session.gd")
const Squad = preload("res://server/squad_battle_session.gd")
const Spirits = preload("res://server/spirits.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

# ---- literal ports of the pinned gmsv, written out here on purpose ----------

## util.h: #define RAND(x,y) ((x-1)+1+(int)((double)(y-(x-1))*rand()/(RAND_MAX+1.0)))
func c_RAND(x: float, y: float, rand_value: int) -> float:
	return (x-1)+1+int(float(y-(x-1))*rand_value/(2147483647+1.0))

## battle_magic.c BATTLE_MultiRecovery, BD_KIND_HP, _MAGIC_REHPAI defined:
## UpPoint = RAND((power*0.9),(power*1.1)); with a ride pet
## UpPoint = (allUpPoint * Magic_RideGetHP(toindex, ridepet, 1))/100.
func c_recovery(power: int, rng: RandomNumberGenerator, ride: Array = []) -> Array:
	var up := int(c_RAND(power*0.9,power*1.1,rng.randi() & 0x7fffffff))
	if ride.is_empty():return [up,0]
	var char_d: int = ride[1]-ride[0]
	var pet_d: int = ride[3]-ride[2]
	var all_d := char_d+pet_d
	if all_d<=0:all_d = 1
	var share := int((char_d*100)/all_d)
	var own := int((up*share)/100)
	return [own,up-own]

## BATTLE_MultiRessurect: UpPoint = RAND((power*0.9),(power*1.1)); max(1, UpPoint).
func c_ressurect(power: int, rng: RandomNumberGenerator) -> int:
	return maxi(1,int(c_RAND(power*0.9,power*1.1,rng.randi() & 0x7fffffff)))

func run() -> void:
	mp_and_saves()
	formulas()
	equipment()
	battle_casts()
	party_side()
	field_use()
	print("SPIRITS RULES: %d failures" % failures)
	quit(1 if failures else 0)

func strong_session() -> Session:
	var s := Session.new()
	s._profile.player.level = 12
	s._profile.player.gold = 100000
	s.grant_starter_pets()
	s.select_pet(0)
	return s

func mp_and_saves() -> void:
	var s := Session.new()
	check(int(s.snapshot().player.mp)==100 and Spirits.MAX_MP==100,"a new character starts with 气力 100/100 (char.c:275 CHAR_MAXMP)")
	s._profile.player.mp = 37
	var path := "user://spirits-rules-test.json"
	check(s.save_game(path),"气力 saves")
	var loaded := Session.new()
	check(loaded.load_game(path) and int(loaded.snapshot().player.mp)==37 and int(loaded.snapshot().version)==Session.SAVE_VERSION,"气力 survives the save round trip")
	# A version 3 save (before 气力): loads with full 气力 and no spirit equipment.
	var old: Dictionary = s.snapshot()
	old.version = 3
	old.player.erase("mp")
	old.erase("equipment")
	for item in Spirits.SPIRIT_ITEMS:old.inventory.erase(item)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
	var migrated := Session.new()
	check(migrated.load_game(path) and int(migrated.snapshot().player.mp)==100 and int(migrated.snapshot().version)==4 and migrated.snapshot().equipment=={"body":"","amulet":""} and int(migrated.snapshot().inventory.teo_robe)==0,"a version 3 save migrates to version 4 with 气力 full")
	var broken: Dictionary = s.snapshot()
	broken.player.mp = 101
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(broken))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
	check(not Session.new().load_game(path),"气力 above 100 is an invalid save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# NPC_HealerAllHeal restores 气力; a defeat does not (it only sets HP).
	s._profile.player.mp = 3
	check(s.heal() and int(s.snapshot().player.mp)==100,"休息 at the villager restores 气力 (npc_healer.c)")
	s._profile.player.mp = 3
	s._recover()
	check(int(s.snapshot().player.mp)==3,"a defeat's recovery leaves 气力 as it was")

func formulas() -> void:
	# Every spell's amount against the literal port, same rng stream.
	for id in [0,1,2,3,4,5,10,11,12,13,14,15,20,21,22,23,24,25]:
		var power := int(Spirits.MAGIC[id].power)
		var ours := RandomNumberGenerator.new()
		ours.seed = 900+id
		var theirs := RandomNumberGenerator.new()
		theirs.seed = 900+id
		var same := true
		var low := 1000000
		var high := -1
		for i in range(400):
			var a := Spirits.battle_heal(power,ours)
			var b: int = c_recovery(power,theirs)[0]
			same = same and a==b
			low = mini(low,a)
			high = maxi(high,a)
		check(same and low>=int(power*0.9) and high<=int(power*1.1+0.0001) and high>low,"%s: %d..%d, the literal RAND(0.9, 1.1) port" % [str(Spirits.MAGIC[id].name),low,high])
	check(Spirits.MAGIC[0].power==80 and Spirits.MAGIC[10].power==65 and Spirits.MAGIC[20].power==50 and Spirits.MAGIC[50].power==100,"magic.txt: 治愈 80, 滋润 65, 恩惠 50, 复活 100 at Lv1")
	check(Spirits.ITEMS.haru_armor.mp==5 and Spirits.ITEMS.freya_robe.mp==8 and Spirits.ITEMS.teo_robe.mp==20 and Spirits.ITEMS.koyala_charm.mp==20 and Spirits.ITEMS.mirror_charm.mp==5,"itemset.txt magicusemp: 5, 8, 20, 20 and the mirror 5")
	for id in [50,51,52,53]:
		var ours := RandomNumberGenerator.new()
		ours.seed = id
		var theirs := RandomNumberGenerator.new()
		theirs.seed = id
		var same := true
		for i in range(200):same = same and Spirits.revive_hp(int(Spirits.MAGIC[id].power),100000,ours)==c_ressurect(int(Spirits.MAGIC[id].power),theirs)
		check(same,"%s revives with the literal BATTLE_MultiRessurect amount" % str(Spirits.MAGIC[id].name))
	check(Spirits.revive_hp(100,40,RandomNumberGenerator.new())==40,"a revive never goes above max HP")
	# Magic_RideGetHP: the heal is shared by what rider and mount are missing.
	var rng := RandomNumberGenerator.new()
	for case in [[10,100,50,100],[100,100,10,100],[0,50,0,60],[99,100,99,100],[100,100,100,100]]:
		var split := Spirits.split_heal(80,case[0],case[1],case[2],case[3])
		rng.seed = 5
		var port := c_recovery(80,rng,case)
		rng.seed = 5
		var amount := Spirits.battle_heal(80,rng)
		split = Spirits.split_heal(amount,case[0],case[1],case[2],case[3])
		check(split==port,"rider/mount split %s matches Magic_RideGetHP: %s" % [str(case),str(split)])
	check(Spirits.target_effect("recovery",80)==100601 and Spirits.target_effect("recovery",160)==100602 and Spirits.target_effect("recovery",480)==100603 and Spirits.target_effect("ressurect",100)==100607,"SPR_heal / SPR_fukkatu by power (MAGIC_Recovery_Battle)")

func equipment() -> void:
	var s := Session.new()
	s._profile.player.gold = 100000
	check(s.buy_item("haru_armor") and int(s.snapshot().player.gold)==99600,"哈鲁Lv1铠2 costs 400 (itemset.txt)")
	check(not s.equip_item("haru_armor") and s.last_error=="能力不足无法装备。","a Lv1 player cannot wear the Lv10 armour (char_item.c LACKOFCLASS)")
	s._profile.player.level = 10
	var before: Dictionary = s.effective_player_stats()
	check(s.equip_item("haru_armor") and s.snapshot().equipment.body=="haru_armor","at Lv10 it is worn")
	var after: Dictionary = s.effective_player_stats()
	check(int(after.defence)==int(before.defence)+6 and int(after.speed)==maxi(1,int(before.speed)-2),"防 +6 敏 -2 on the status stats")
	var config := s.start_battle_config()
	check(int(config.player_defence)==int(after.defence) and config.spirits.has("body") and int(config.spirits.body.magic)==0 and int(config.player_mp)==100,"the battle gets the armour, its 治愈的精灵 and 气力")
	s._pending.clear()
	check(not s.sell_item("haru_armor"),"the worn copy cannot be sold")
	s.buy_item("teo_robe")
	check(s.equip_item("teo_robe") and s.snapshot().equipment.body=="teo_robe","another body armour replaces the worn one")
	s.buy_item("koyala_charm");s.buy_item("mirror_charm")
	check(s.equip_item("koyala_charm") and s.snapshot().equipment.amulet=="koyala_charm","柯雅拉Lv1护身符 (level 0) is worn at once")
	check(not s.equip_item("mirror_charm") and s.last_error=="无法同时装备两项同种类的物品。","two amulets are never worn together (char_item.c CANNOTEQUIP2)")
	check(s.equip_item("koyala_charm") and s.equip_item("mirror_charm") and not s.equip_item("koyala_charm"),"after taking one off the other goes on, and not back")
	var path := "user://spirits-equipment-test.json"
	check(s.save_game(path) and Session.new().load_game(path),"worn spirit equipment saves and loads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))

## A battle with the player, its pet (and optionally a mount) and weak foes.
func battle_with(items: Array, mp: int = 100, allies: bool = false) -> Array:
	var s := strong_session()
	for item in items:
		s.buy_item(item)
		s.equip_item(item)
	s._profile.player.mp = mp
	var config := s.start_battle_config() if not allies else s.start_battle_config()
	config.enemy_attack = 1
	config.enemy_max_hp = 100000
	for enemy in config.enemies:
		enemy.attack = 1
		enemy.max_hp = 100000
		enemy.hp = 100000
		enemy.speed = 1
	config.player_speed = 999
	# The pending record the settlement checks sees the same troop.
	s._pending.enemies = config.enemies.duplicate(true)
	var battle = Squad.new() if allies else Battle.new()
	if allies:
		config.allies = [{"name":"分身 1","kind":"player","hp":50,"max_hp":300,"attack":1,"defence":0,"speed":1,"level":1,"elements":[0,0,0,0]}]
		config.ally_pets = [{}]
	battle.rng_seed = 77
	battle.start_battle(config)
	return [s,battle]

func battle_casts() -> void:
	# 治愈: the caster itself, 5 气力.
	var pair := battle_with(["haru_armor"])
	var s: Session = pair[0]
	var battle = pair[1]
	battle._state.player_hp = 100
	battle._state.player_max_hp = 1000
	var mirror := RandomNumberGenerator.new()
	mirror.state = battle._rng.state
	battle._cast_spirit({"kind":"player","index":-1},"body",battle._target_ref(0))
	var expected: int = c_recovery(80,mirror)[0]
	check(int(battle._state.player_hp)==100+expected and int(battle._state.player_mp)==95,"治愈的精灵 heals the literal amount (%d) and costs 5 气力" % expected)
	check(battle._last_spirit.effect==100601 and battle._last_spirit.user_effect==100600,"the cast shows MAGIC_EFFECT_USER and SPR_heal")
	check(not battle.spirit_refusal({"kind":"player","index":-1},"body",1).is_empty() and battle.spirit_refusal({"kind":"player","index":-1},"body",0).is_empty(),"治愈 (MAGIC_TARGET_MYSELF) only targets the caster")
	# Through a whole turn.
	var state: Dictionary = battle.submit_action("spirit:body",0)
	check(int(state.turn)==1 and int(state.player_mp)==90 and "治愈的精灵" in str(state.events),"the 精灵 command takes the player's action")
	var frame: Dictionary = state.turn_frames.filter(func(f):return f.actor=="player")[0]
	check(frame.outcome=="spirit" and frame.spirit.heals.size()==1 and frame.spirit.heals[0].kind=="player","its frame names the heal for the battle view")
	# Too little 气力: refused before the turn, with the reason.
	battle._state.player_mp = 4
	check(battle.submit_action("spirit:body",0).turn==1 and battle.spirit_refusal({"kind":"player","index":-1},"body",0)=="气力不足。","without 5 气力 the command is refused (气力不足。)")
	# Execution with too little (spent meanwhile): MAGIC_Recovery returns FALSE, nothing happens.
	var hp := int(battle._state.player_hp)
	battle._cast_spirit({"kind":"player","index":-1},"body",battle._target_ref(0))
	check(int(battle._state.player_hp)==hp and int(battle._state.player_mp)==4 and battle._last_outcome=="spirit_fail","a cast without the 气力 does nothing")
	# Settlement: the spent 气力 reaches the profile; more than at the start is refused.
	battle._state.player_mp = 60
	battle._state.player_hp = 1
	battle._state.player_max_hp = int(s._profile.player.max_hp)
	var result: Dictionary = battle.developer_escape()
	var cheat := result.duplicate(true)
	cheat.player_mp = 101
	check(not s.apply_battle_result(cheat),"a result with more 气力 than the battle started with is refused")
	check(s.apply_battle_result(result) and int(s.snapshot().player.mp)==60,"the battle's 气力 is settled on the profile")
	# 滋润: one member; the pet here.
	pair = battle_with(["freya_robe"])
	battle = pair[1]
	battle._state.pet_hp = 1
	battle._state.pet.hp = 1
	state = battle.submit_action("spirit:body",1)
	check(int(state.player_mp)==92 and int(state.pet_hp)>1 and int(state.pets[state.active_pet].hp)==int(state.pet_hp),"滋润的精灵 heals the chosen pet for 8 气力")
	check(battle.spirit_refusal({"kind":"player","index":-1},"body",20)!="","滋润 cannot target the whole side")
	# 滋润 on a target that fell meanwhile: a random standing member instead (BATTLE_MultiList).
	battle._state.pet_hp = 0
	battle._state.pet.hp = 0
	battle._state.player_hp = 10
	battle._cast_spirit({"kind":"player","index":-1},"body",battle._target_ref(1))
	check(int(battle._state.pet_hp)==0 and int(battle._state.player_hp)>10,"a heal on a fallen target goes to a standing member")
	# 恩惠: the whole side, each rolled separately, mount share included.
	pair = battle_with(["teo_robe"],100,true)
	battle = pair[1]
	battle._state.player_hp = 10
	battle._state.pet_hp = 5
	battle._state.pet.hp = 5
	mirror = RandomNumberGenerator.new()
	mirror.state = battle._rng.state
	battle._cast_spirit({"kind":"player","index":-1},"body",battle._target_ref(20))
	var healed: Array = battle._last_spirit.heals
	var port_player: int = c_recovery(50,mirror)[0]
	var port_pet: int = c_recovery(50,mirror)[0]
	var port_ally: int = c_recovery(50,mirror)[0]
	check(healed.size()==3 and int(battle._state.player_hp)==mini(10+port_player,int(battle._state.player_max_hp)) and int(battle._state.pet_hp)==mini(5+port_pet,int(battle._state.pet_max_hp)) and int(battle._state.allies[0].hp)==mini(50+port_ally,300) and int(battle._state.player_mp)==80,"恩惠的精灵 heals player, pet and the ally, each its own RAND, for 20 气力")
	# A mounted player: the heal is shared with the mount by what each lacks.
	pair = battle_with(["haru_armor"])
	s = pair[0]
	battle = pair[1]
	battle._state.ride_pet = 1
	battle._state.pets[1].hp = 10
	battle._state.player_hp = int(battle._state.player_max_hp)-5
	var rider_before := int(battle._state.player_hp)
	var mount_max := int(battle._state.pets[1].max_hp)
	mirror = RandomNumberGenerator.new()
	mirror.state = battle._rng.state
	battle._cast_spirit({"kind":"player","index":-1},"body",battle._target_ref(0))
	var shared := c_recovery(80,mirror,[rider_before,int(battle._state.player_max_hp),10,mount_max])
	check(int(battle._state.player_hp)==mini(int(battle._state.player_max_hp),rider_before+int(shared[0])) and int(battle._state.pets[1].hp)==mini(mount_max,10+int(shared[1])) and int(shared[1])>int(shared[0]),"a rider's heal is split with its mount by what each lacks (Magic_RideGetHP): %s" % str(shared))
	# 复活精灵: a fallen member only; the 气力 goes either way.
	pair = battle_with(["koyala_charm"])
	battle = pair[1]
	check(battle.spirit_refusal({"kind":"player","index":-1},"amulet",1).is_empty(),"复活精灵 may target the pet")
	mirror = RandomNumberGenerator.new()
	battle._state.pet_hp = 0
	battle._state.pet.hp = 0
	mirror.state = battle._rng.state
	state = battle.submit_action("spirit:amulet",1)
	var cast: Dictionary = state.turn_frames.filter(func(f):return f.actor=="player")[0].get("spirit",{})
	check(int(state.pet_hp)>0 and int(cast.heals[0].amount)==mini(int(state.pet_max_hp),c_ressurect(100,mirror)) and int(state.player_mp)==80 and int(cast.effect)==100607 and cast.heals[0].revived,"复活精灵 Lv1 gets the fallen pet up with the literal amount for 20 气力")
	var up := int(battle._state.pet_hp)
	battle._cast_spirit({"kind":"player","index":-1},"amulet",battle._target_ref(1))
	check(int(battle._state.pet_hp)==up and int(battle._state.player_mp)==60,"on a standing pet it does nothing, yet costs its 气力 (BATTLE_MultiListDead)")
	state = battle.submit_action("attack",0)
	check(state.turn_order.has("pet"),"the revived pet acts again the next turn")

func party_side() -> void:
	# A clone ally in 五人镜像队 is on the player's side: 滋润 reaches it, 复活 gets it up.
	var pair := battle_with(["freya_robe"],100,true)
	var battle = pair[1]
	battle._state.allies[0].hp = 20
	var state: Dictionary = battle.submit_action("spirit:body",2)
	check(int(state.allies[0].hp)>20 and int(state.player_mp)==92,"滋润 on the squad's ally (target code 2)")
	pair = battle_with(["koyala_charm"],100,true)
	battle = pair[1]
	battle._state.allies[0].hp = 0
	check(battle.spirit_refusal({"kind":"player","index":-1},"amulet",2).is_empty(),"a fallen ally is a revive target")
	state = battle.submit_action("spirit:amulet",2)
	check(int(state.allies[0].hp)>0,"复活精灵 gets the fallen ally up")

func field_use() -> void:
	var s := strong_session()
	s.buy_item("haru_armor");s.equip_item("haru_armor")
	s._profile.player.hp = 1
	var theirs := RandomNumberGenerator.new()
	s.field_rng.seed = 11
	theirs.seed = 11
	# magic_field.c: power = RAND((power*0.9),(power*1.1)) in float, (int) when added.
	var expected := int(c_RAND(80*0.9,80*1.1,theirs.randi() & 0x7fffffff))
	check(s.use_spirit("body",0) and int(s._profile.player.hp)==mini(int(s._profile.player.max_hp),1+expected) and int(s._profile.player.mp)==95,"治愈 outside battle heals the literal field amount for 5 气力")
	check(s.last_note==("耐久力回复%d" % (int(s._profile.player.hp)-1)),"it says 耐久力回复N (MAGIC_Recovery_Field)")
	s._profile.player.mp = 4
	check(not s.use_spirit("body",0) and s.last_error=="气力不足。" and int(s._profile.player.mp)==4,"without the 气力 it is refused")
	s.buy_item("freya_robe");s.equip_item("freya_robe")
	s._profile.player.mp = 100
	s._profile.pets[0].hp = 1
	check(s.use_spirit("body",1) and int(s._profile.pets[0].hp)>1 and s.last_note.begins_with(str(s._profile.pets[0].name)+"的耐久力回复"),"滋润 heals a carried pet outside battle (X的耐久力回复N)")
	s.buy_item("teo_robe");s.equip_item("teo_robe")
	check(not s.use_spirit("body",0) and "只能在战斗中使用" in s.last_error,"恩惠 is MAGIC_FIELD_BATTLE: refused outside battle")
	s.equip_item("freya_robe")
	s._profile.player.max_hp = 1000
	s._profile.player.hp = 5
	s._profile.player.mp = 16

	check(s.spirit_heal_to_line(50) and int(s._profile.player.mp)==0,"用精灵补血 between battles casts while the 气力 lasts")
	s.start_battle_config()
	check(not s.use_spirit("body",0),"field use waits for the battle to end")
