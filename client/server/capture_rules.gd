extends RefCounted
## Pinned gmsv/battle/battle_event.c BATTLE_CaptureCheck (3091–3160).
const Progression = preload("res://server/progression.gd")
const TEMPLATE_IDS := {"wooli":1,"wooli_wooli":2,"woolistan":3,"blue_dragon":92,"golden_tiger":194,"red_rex":303}

static func species_parameter(enemy: Dictionary) -> Variant:
	if enemy.has("capture_parameter"):return enemy.capture_parameter
	var species := str(enemy.get("species",""))
	var definition := Progression.species_definition("original_%d"%TEMPLATE_IDS[species] if TEMPLATE_IDS.has(species) else species)
	return definition.get("capture_resistance",null)

static func evaluate(player: Dictionary, enemy: Dictionary) -> Dictionary:
	if not bool(enemy.get("can_capture",true)) or int(enemy.get("hp",0))<=0:
		return {"eligible":false,"reason":"目标不可捕获"}
	if int(player.get("level",1))+5<int(enemy.get("level",1)):
		return {"eligible":false,"reason":"目标等级超过人物等级5级"}
	var parameter = species_parameter(enemy)
	if parameter == null:
		return {"eligible":false,"reason":"缺少原始物种捕获参数"}
	var hp := f32(float(enemy.hp))
	var max_hp := f32(maxf(1.0,float(enemy.get("max_hp",1))))
	var hp_term := f32(10.0-f32(f32(hp*hp)/max_hp))
	var level_term := f32(f32(f32(float(player.get("level",1)))/2.0)-f32(f32(float(enemy.get("level",1)))/2.0))
	var dex_term := f32(f32(f32(float(player.get("speed",0)))/15.0)-f32(f32(float(enemy.get("speed",0)))/15.0))
	var species_luck := f32(f32(float(parameter))+f32(float(player.get("luck",0))))
	var score := f32(f32(f32(f32(hp_term+level_term)+dex_term)+species_luck)*f32(float(player.get("charm",60))))
	score = f32(score/50.0)
	score = f32(score+float(player.get("capture_bonus",0)))
	if int(enemy.get("sleep_turns",0))>0:score = f32(score+15.0)
	score = minf(99.0,score)
	# Source uses strict '<', not '<=': score99 wins on integers1..98.
	return {"eligible":true,"score":score,"winning_rolls":clampi(int(ceil(score))-1,0,98)}

static func succeeds(evaluation: Dictionary, roll: int) -> bool:
	return bool(evaluation.get("eligible",false)) and roll>=1 and roll<=100 and float(roll)<float(evaluation.score)

static func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]
