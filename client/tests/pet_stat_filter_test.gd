extends SceneTree
const Filter = preload("res://scripts/pet_stat_filter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok:failures += 1
func _initialize() -> void:
	var stats := {"max_hp":1308,"attack":291,"defence":178,"speed":151}
	check(Filter.evaluate(stats, {}), "no configured conditions preserves existing hunt behavior")
	var conditions := {"sum":{"enabled":true,"value":620},"attack":{"enabled":true,"value":291,"strict":true}}
	check(not Filter.evaluate(stats, {"conditions":conditions,"mode":"all"}), "all requires strict attack improvement even when sum equals minimum")
	check(Filter.evaluate(stats, {"conditions":conditions,"mode":"any"}), "any accepts sum equal to 620")
	conditions.attack.enabled = false
	check(Filter.evaluate(stats, {"conditions":conditions}), "disabled individual threshold cannot block total match")
	conditions.sum.value = 621
	check(not Filter.evaluate(stats, {"conditions":conditions}), "HP does not inflate attack plus defence plus speed")
	check(not Filter.evaluate({"attack":291,"speed":151}, {"conditions":conditions}), "missing defence cannot silently qualify a sum")
	conditions.sum.enabled = false
	check(Filter.evaluate({}, {"conditions":conditions,"mode":"any"}), "zero enabled conditions pass in any mode")
	conditions.attack.enabled = true
	conditions.attack.value = 290
	check(Filter.evaluate(stats, {"conditions":conditions}), "individual strict greater-than accepts 291 over 290")
	check(stats.attack == 291 and stats.max_hp == 1308, "evaluation does not modify pet stats")
	var blue:=Filter.defaults(92)
	check(blue.mode=="any" and blue.conditions.sum.enabled and int(blue.conditions.sum.minus)==1 and blue.conditions.attack.enabled and int(blue.conditions.attack.minus)==1 and not Filter.absolute(blue) and str(blue.threshold_mode)=="relative","blue defaults to 三围合 ≥ 最高−1 OR 攻击 ≥ 最高−1 (relative)")
	check(int(blue.conditions.sum.value)==624 and int(blue.conditions.attack.value)==293 and int(blue.conditions.defence.value)==179 and int(blue.conditions.speed.value)==151,"each condition also keeps its fixed default: 624 / 293 / 179 / 151")
	check(blue.stop_after==0 and blue.conditions.sum.keep==15 and blue.conditions.attack.keep==10,"blue defaults never stop and keep 15 by sum plus 10 by attack")
	check(not Filter.enabled(Filter.defaults(194)),"other species default to no enabled thresholds")
	# 最高 − x: the best of the player's own pets, each metric on its own.
	var owned := [{"attack":301,"defence":170,"speed":150,"max_hp":900},{"attack":290,"defence":185,"speed":152,"max_hp":950}]
	var best := Filter.maxima(owned)
	check(best=={"sum":627,"attack":301,"defence":185,"speed":152},"maxima: sum is the best pet's sum (627), each stat its own best")
	check(Filter.maxima([])=={} and Filter.maxima([{"attack":305,"defence":170,"speed":150}],best).attack==305 and Filter.maxima([],best)==best,"no pets: no maxima; a base is raised, never lowered")
	check(not Filter.evaluate({"attack":999,"defence":999,"speed":999},blue),"an unresolved relative condition never passes")
	check(Filter.needs_survey(blue,{}) and not Filter.needs_survey(blue,best) and not Filter.needs_survey(Filter.defaults(194),{}),"no pet of the species: survey first (only with enabled conditions)")
	var resolved := Filter.resolve(blue,best)
	check(int(resolved.conditions.sum.value)==626 and int(resolved.conditions.attack.value)==300 and not resolved.conditions.sum.strict and not resolved.conditions.sum.has("minus") and int(blue.conditions.sum.value)==624 and int(blue.conditions.sum.minus)==1,"resolve: 627−1=626 and 301−1=300 (the saved filter is not changed)")
	check(not Filter.resolve(blue,{}).conditions.sum.has("value"),"relative without a maximum stays unresolved, ignoring the saved fixed value")
	check(Filter.evaluate({"attack":288,"defence":186,"speed":152},resolved),"sum exactly 626 passes regardless of attack")
	check(Filter.evaluate({"attack":300,"defence":150,"speed":140},resolved),"attack 300 passes below the sum threshold")
	check(not Filter.evaluate({"attack":299,"defence":180,"speed":146},resolved),"sum 625 with attack 299 fails")
	resolved.mode="all"
	check(not Filter.evaluate({"attack":299,"defence":187,"speed":150},resolved),"explicit AND remains respected")
	var zero := blue.duplicate(true);zero.conditions.sum.minus=0
	check(int(Filter.resolve(zero,best).conditions.sum.value)==627,"x = 0 asks to match the best")
	check(Filter.describe_condition("sum",blue.conditions.sum,best)=="三围合 ≥ 最高 627 − 1 = 626" and Filter.describe_condition("attack",blue.conditions.attack,{})=="攻击 ≥ 最高 − 1（还没有同种，先摸底）","the UI sentence shows the resolved number")
	check(Filter.describe_thresholds(blue,best)=="三围合 ≥ 最高 627 − 1 = 626，或 攻击 ≥ 最高 301 − 1 = 300","all enabled conditions joined by the mode")
	absolute(blue,best)
	print("PET STAT FILTER: %d failures" % failures)
	quit(1 if failures else 0)

## 绝对：≥ 数值: the saved values, whatever the maxima; no 摸底.
func absolute(blue: Dictionary, best: Dictionary) -> void:
	var fixed := blue.duplicate(true)
	fixed.threshold_mode = "absolute"
	check(Filter.absolute(fixed) and not Filter.absolute(blue) and not Filter.absolute({}),"threshold_mode absolute; missing means relative")
	var resolved := Filter.resolve(fixed,best)
	check(int(resolved.conditions.sum.value)==624 and int(resolved.conditions.attack.value)==293 and not resolved.conditions.sum.has("minus") and not resolved.conditions.sum.strict,"absolute resolves to the fixed values, not 最高 − x")
	check(Filter.resolve(fixed,{}).conditions==resolved.conditions and Filter.resolve(fixed,{"sum":900,"attack":400}).conditions==resolved.conditions,"better pets (or none) do not move them")
	check(not Filter.needs_survey(fixed,{}) and Filter.needs_survey(blue,{}),"no 摸底 in absolute mode")
	check(Filter.evaluate({"attack":293,"defence":1,"speed":1},resolved) and Filter.evaluate({"attack":200,"defence":250,"speed":174},resolved) and not Filter.evaluate({"attack":292,"defence":180,"speed":151},resolved),"≥ 624 or ≥ 293: equal passes, 623 with 292 fails")
	check(Filter.describe_condition("sum",fixed.conditions.sum,best,true)=="三围合 ≥ 624（现有最高 627）" and Filter.describe_condition("sum",fixed.conditions.sum,{},true)=="三围合 ≥ 624","absolute sentence shows the value and the best for reference")
	check(Filter.describe_thresholds(fixed,best)=="三围合 ≥ 624（现有最高 627），或 攻击 ≥ 293（现有最高 301）","describe_thresholds follows the filter's mode: %s" % Filter.describe_thresholds(fixed,best))
	# Switching to absolute starts from the threshold hunted now.
	check(Filter.absolute_values(blue,best)=={"sum":626,"attack":300,"defence":184,"speed":151},"switch prefill: 最高 − x per metric when the species is owned")
	check(Filter.absolute_values(blue,{})=={"sum":624,"attack":293,"defence":179,"speed":151},"else the defaults")
	var own := blue.duplicate(true);own.conditions.sum.value = 610
	check(int(Filter.absolute_values(own,best,["sum"]).sum)==610 and int(Filter.absolute_values(own,best,["sum"]).attack)==300,"a value the player saved is kept")
	var back := Filter.resolve(fixed.merged({"threshold_mode":"relative"},true),best)
	check(int(back.conditions.sum.value)==626,"back to relative: x still there, 627 − 1")
