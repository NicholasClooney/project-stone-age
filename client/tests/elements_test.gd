extends SceneTree
## 属性相克 against vectors produced by compiling gmsv BATTLE_AttrCalc verbatim
## (battle_event.c:795-840, with the work/GetAttr steps around it).
const Elements = preload("res://server/elements.gd")
const Rules = preload("res://server/classic_combat_rules.gd")
const Riding = preload("res://scripts/riding.gd")
const Session = preload("res://server/game_session.gd")
const Battle = preload("res://server/battle_session.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if value: print("PASS: "+label)
	else:
		push_error("FAIL: "+label)
		failures += 1

# [attacker, defender, damage for 0,1,7,13,37,100,123,999] from the C build.
const DAMAGES := [0,1,7,13,37,100,123,999]
const VECTORS := [
	[[100,0,0,0],[0,100,0,0],[0,1,10,19,55,150,184,1498]],
	[[0,100,0,0],[100,0,0,0],[0,0,4,7,22,60,73,599]],
	[[0,0,0,0],[100,0,0,0],[0,0,4,7,22,60,73,599]],
	[[100,0,0,0],[0,0,0,0],[0,1,10,19,55,150,184,1498]],
	[[0,0,0,0],[0,0,0,0],[0,1,7,13,37,100,123,999]],
	[[100,0,0,0],[100,0,0,0],[0,1,7,13,37,100,123,999]],
	[[0,30,70,0],[80,20,0,0],[0,0,5,11,31,84,104,847]],
	[[80,20,0,0],[0,30,70,0],[0,1,8,15,44,119,146,1188]],
	[[0,0,100,0],[0,0,0,100],[0,1,10,19,55,150,184,1498]],
	[[0,0,0,100],[100,0,0,0],[0,1,10,19,55,150,184,1498]],
	[[30,0,0,70],[0,40,60,0],[0,0,6,11,33,89,109,891]],
	[[100,0,0,0],[50,0,0,50],[0,0,5,10,29,80,98,799]],
	[[0,0,60,40],[0,20,80,0],[0,0,5,10,30,82,101,823]],
	[[60,40,0,0],[20,0,0,80],[0,0,5,10,28,77,95,775]],
	[[50,0,0,50],[0,0,0,0],[0,1,10,19,55,150,184,1498]],
	[[0,0,0,0],[0,30,70,0],[0,0,4,7,22,60,73,599]],
]

func power_of(elements: Array) -> Array:
	return Elements.power(Elements.work(elements))

func _initialize() -> void:
	for vector in VECTORS:
		var got := []
		for damage in DAMAGES:got.append(Elements.adjust(power_of(vector[0]),power_of(vector[1]),damage))
		check(got == vector[2],"%s -> %s matches the compiled source %s" % [Elements.text(vector[0]),Elements.text(vector[1]),str(got)])
	# The cycle and 无属性 in percent (damage 100).
	check(Elements.percent(power_of([100,0,0,0]),power_of([0,100,0,0])) == 150 and Elements.percent(power_of([0,100,0,0]),power_of([0,0,100,0])) == 150 and Elements.percent(power_of([0,0,100,0]),power_of([0,0,0,100])) == 150 and Elements.percent(power_of([0,0,0,100]),power_of([100,0,0,0])) == 150,"地克水, 水克火, 火克风, 风克地 at 150%")
	check(Elements.percent(power_of([0,100,0,0]),power_of([100,0,0,0])) == 60,"the countered side deals 60%")
	check(Elements.percent(power_of([100,0,0,0]),power_of([0,0,100,0])) == 100,"opposite elements (地/火) are neutral to each other")
	check(Elements.work([80,20,0,0]) == [80,20,-80,-20] and Elements.power([80,20,-80,-20]) == [80,20,0,0,0],"work values write the opposite negative, battle power clamps it")
	check(Elements.power(Elements.work([0,0,0,0])) == [0,0,0,0,100],"no element is 100 无属性")
	check(Elements.power([100,100,0,0]) == [100,100,0,0,0],"an over-100 template leaves no 无属性 (renum clamps at 0)")
	# Riding: classic averages the work values, reference (_BATTLE_NEWPOWER) does not.
	check(Elements.mounted_power([100,0,0,0],[0,30,70,0]) == [15,15,0,0,70],"classic rider 地100 on 水30火70 averages to 地15 水15 无70")
	check(Elements.mounted_power([100,0,0,0],[0,30,70,0],"reference") == [100,0,0,0,0],"reference profile ignores the mount's 属性")
	var mounted := Riding.adjusted_stats({"attack":10,"defence":5,"speed":10,"elements":[100,0,0,0]},{"attack":20,"defence":8,"speed":20,"elements":[0,30,70,0]})
	check(mounted.attr_pow == [15,15,0,0,70] and Elements.battle_power(mounted) == [15,15,0,0,70],"mounted stats carry the averaged 属性")
	# Creation rules.
	check(Elements.valid_player([100,0,0,0]) and Elements.valid_player([60,40,0,0]) and Elements.valid_player([0,0,30,70]) and Elements.valid_player([30,0,0,70]),"legal creation choices")
	check(not Elements.valid_player([50,0,50,0]) and not Elements.valid_player([0,50,0,50]) and not Elements.valid_player([0,0,0,0]) and not Elements.valid_player([50,40,0,0]) and not Elements.valid_player([55,45,0,0]) and not Elements.valid_player([40,30,30,0]),"opposite, empty, short, off-step and three-element choices are refused")
	# The creation screen's buttons (login.cpp:3480-3535), in creation points.
	check(Elements.creation_step([0,0,0,0],0,true) == [1,0,0,0] and Elements.creation_step([10,0,0,0],2,true) == [10,0,0,0],"+ adds a point and is refused while the opposite element has points")
	check(Elements.creation_step([10,0,0,0],1,true) == [9,1,0,0] and Elements.creation_step([4,6,0,0],3,true) == [4,6,0,0],"with no points left + takes one from another element, never past an opposite")
	check(Elements.creation_step([3,0,0,0],0,false) == [2,0,0,0] and Elements.creation_step([0,0,0,0],1,false) == [0,0,0,0],"- returns a point, never below zero")
	# Fallbacks for actors saved before the field existed.
	check(Elements.of({"species":"wooli"}) == [80,20,0,0] and Elements.of({"species":"blue_dragon"}) == [0,30,70,0],"tutorial species use their source template 属性")
	check(Elements.of({"species":"original_92"}) == [0,30,70,0] and Elements.of({"elements":[0,0,100,0],"species":"wooli"}) == [0,0,100,0],"stored 属性 wins over the template")
	check(Elements.text([0,30,70,0]) == "水30 火70" and Elements.text([0,0,0,0]) == "无","属性 text")
	# Resolve applies it before the critical bonus and the guard roll.
	var neutral := {"attack":200,"speed":40,"dex":40}
	var earth := {"attack":200,"speed":40,"dex":40,"elements":[100,0,0,0]}
	var target := {"defence":10,"speed":40,"dex":40,"elements":[0,100,0,0]}
	var same := 0
	for seed_value in range(40):
		var a := RandomNumberGenerator.new(); a.seed = seed_value
		var b := RandomNumberGenerator.new(); b.seed = seed_value
		var plain: Dictionary = Rules.resolve(neutral,target,a,false)
		var strong: Dictionary = Rules.resolve(earth,target,b,false)
		if plain.outcome == "hit" and strong.outcome == "hit":
			same += 1
			var base_rng := RandomNumberGenerator.new(); base_rng.seed = seed_value
			var none_target := {"defence":10,"speed":40,"dex":40}
			var base: Dictionary = Rules.resolve(neutral,none_target,base_rng,false)
			check(int(plain.damage) == Elements.adjust([0,0,0,0,100],[0,100,0,0,0],int(base.damage)) and int(strong.damage) == Elements.adjust([100,0,0,0,0],[0,100,0,0,0],int(base.damage)),"seed %d: resolve scales the base hit by 属性 (%d / %d / %d)" % [seed_value,int(base.damage),int(plain.damage),int(strong.damage)])
	check(same > 10,"enough plain hits compared")
	# Session: default, choice, save/load, battle config.
	var session := Session.new()
	check(session.snapshot().player.elements == Elements.PLAYER_DEFAULT,"a new player starts with the default 属性")
	check(not session.set_player_elements([50,0,50,0]) and session.set_player_elements([0,0,30,70]) and session.snapshot().player.elements == [0,0,30,70],"the 属性 choice follows the creation rules")
	var path := OS.get_user_data_dir()+"/elements-test-save.json"
	check(session.save_game(path),"save with 属性")
	var loaded := Session.new()
	check(loaded.load_game(path) and loaded.player_elements() == [0,0,30,70],"属性 survives save and load")
	var config: Dictionary = loaded.start_battle_config()
	check(config.player_elements == [0,0,30,70],"battle config carries the player's 属性")
	var battle := Battle.new()
	battle.start_battle(config)
	check(battle._player_stats().elements == [0,0,30,70],"the battle's player stats carry 属性")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path+".bak")
	print("Elements failures: %d" % failures)
	quit(failures)
