extends SceneTree
const Rules=preload("res://server/capture_rules.gd")
const Battle=preload("res://server/battle_session.gd")
const Session=preload("res://server/game_session.gd")
const Catalog=preload("res://server/encounter_catalog.gd")
var failures:=0
func check(value:bool,label:String)->void:
	if value:print("PASS: "+label)
	else:push_error("FAIL: "+label);failures+=1
func _initialize()->void:
	# Expected float32 values compiled from the pinned C expression, not this GDScript.
	var vectors=JSON.parse_string(FileAccess.get_file_as_string("res://tests/capture_reference_vectors.json"))
	var parity:=true
	for v in vectors:
		var p={"level":v[0],"speed":v[2],"charm":v[4],"luck":v[5],"capture_bonus":v[9]}
		var e={"level":v[1],"speed":v[3],"capture_parameter":v[6],"hp":v[7],"max_hp":v[8],"sleep_turns":v[10]}
		var actual=Rules.evaluate(p,e)
		parity=parity and actual.eligible==bool(v[11])
		if actual.eligible:parity=parity and actual.score==v[12]
	check(parity,"32 independent C float32 source vectors match exact scores and level eligibility")
	var player={"level":20,"speed":30,"luck":2,"charm":60}
	var enemy={"hp":10,"max_hp":40,"level":10,"speed":15,"capture_parameter":3,"can_capture":true}
	var result=Rules.evaluate(player,enemy)
	check(is_equal_approx(result.score,22.2) and result.winning_rolls==22,"source float formula yields22.2 and22 winning rolls")
	check(Rules.succeeds(result,22) and not Rules.succeeds(result,23),"strict random comparison at fractional score")
	player.level=120
	result=Rules.evaluate(player,enemy)
	player.capture_bonus=100
	result=Rules.evaluate(player,enemy)
	check(result.score==99 and result.winning_rolls==98 and Rules.succeeds(result,98) and not Rules.succeeds(result,99),"99 score cap has98 percent success")
	player={"level":1,"speed":1,"charm":60,"luck":0}
	enemy.level=7
	check(not Rules.evaluate(player,enemy).eligible,"source player plus5 level gate")
	enemy.level=6
	check(Rules.evaluate(player,enemy).eligible,"exactly5 levels higher remains eligible")
	enemy.level=1;enemy.hp=100;enemy.max_hp=100
	result=Rules.evaluate(player,enemy)
	check(result.score<0 and result.winning_rolls==0 and not Rules.succeeds(result,1),"negative scores retained and never win")
	enemy.hp=1;enemy.max_hp=0
	check(Rules.evaluate(player,enemy).eligible,"invalid maxHP protected by source denominator1")
	enemy.max_hp=40
	var awake=Rules.evaluate(player,enemy)
	enemy.sleep_turns=1
	check(is_equal_approx(Rules.evaluate(player,enemy).score,awake.score+15),"sleep adds15 after charm multiplier")
	enemy.erase("capture_parameter")
	check(not Rules.evaluate(player,enemy).eligible,"missing species parameter cannot silently become30")
	enemy.species="blue_dragon"
	check(Rules.species_parameter(enemy)==3,"blue dragon aliases exact source template92")
	enemy.species="golden_tiger"
	check(Rules.species_parameter(enemy)==-1,"negative golden tiger capture parameter preserved")
	var catalog=Catalog.new();var rng=RandomNumberGenerator.new();rng.seed=9
	var actor=catalog.actor(int(catalog.data.enemies.keys()[0]),rng)
	check(actor.capture_parameter==catalog.data.templates[str(actor.template_id)].capture_resistance,"generated wild actor carries source species parameter")
	var battle=Battle.new()
	battle.start_battle({"player_level":120,"player_speed":1000,"player_hp":10000,"player_max_hp":10000,"capture_bonus":200,"enemies":[{"hp":100,"max_hp":100,"level":1,"speed":1,"attack":1,"capture_parameter":3,"species":"blue_dragon"}]})
	var state=battle.submit_action("capture",0)
	check(state.capture_evaluation.score==99 and int(state.capture_evaluation.roll)>=1 and int(state.capture_evaluation.roll)<=100,"fullHP capture is a rolled attempt without60percent hard gate")
	check(battle._config.capture_bonus==0,"capture bonus consumed on attempted capture")
	var denied=Battle.new()
	denied.start_battle({"player_level":1,"player_speed":1000,"capture_bonus":200,"enemies":[{"hp":1,"max_hp":100,"level":7,"speed":1,"attack":1,"capture_parameter":3,"species":"blue_dragon"}]})
	state=denied.submit_action("capture",0)
	check(not state.capture_success and not state.capture_evaluation.eligible and denied._config.capture_bonus==0,"ineligible attempt fails and still clears capture bonus")
	quit(1 if failures else 0)
