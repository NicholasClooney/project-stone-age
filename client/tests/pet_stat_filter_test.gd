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
	print("PET STAT FILTER: %d failures" % failures)
	quit(1 if failures else 0)
