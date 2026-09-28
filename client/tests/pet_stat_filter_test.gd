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
	check(blue.mode=="any" and blue.conditions.sum.value==624 and blue.conditions.attack.enabled and blue.conditions.attack.value==292,"blue defaults to sum>=624 OR attack>292")
	check(blue.stop_after==0 and blue.conditions.sum.keep==15 and blue.conditions.attack.keep==10,"blue defaults never stop and keep 15 by sum plus 10 by attack")
	check(Filter.evaluate({"attack":288,"defence":184,"speed":152},blue),"sum exactly 624 passes regardless of attack")
	check(Filter.evaluate({"attack":293,"defence":170,"speed":150},blue),"attack 293 passes below sum 624")
	check(not Filter.evaluate({"attack":292,"defence":180,"speed":151},blue),"sum 623 with attack 292 fails")
	check(not Filter.enabled(Filter.defaults(194)),"other species default to no enabled thresholds")
	blue.mode="all"
	check(not Filter.evaluate({"attack":291,"defence":170,"speed":150},blue),"explicit AND remains respected")
	print("PET STAT FILTER: %d failures" % failures)
	quit(1 if failures else 0)
