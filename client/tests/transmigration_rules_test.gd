extends SceneTree
const Rules = preload("res://server/transmigration_rules.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error("FAIL: "+message)
func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-rules.json"))
	for i in range(data.inheritance.size()):
		var vector: Dictionary=data.inheritance[i]
		var base := {}
		for j in range(4):base[Rules.STATS[j]]=int(vector.base[j])
		var before: Dictionary=base.duplicate(true)
		var result: Dictionary=Rules.inherit(base,int(vector.equation),int(vector.level),int(vector.new_count),int(vector.quests))
		check(result.get("ok",false),"C vector %d accepted"%i)
		if not result.get("ok",false):continue
		for j in range(4):check(result.base_stats[Rules.STATS[j]]==int(vector.expected.base[j]),"C vector %d stat %d"%[i,j])
		for key in ["equation","stat_points","ans"]:check(result[key]==int(vector.expected[key]),"C vector %d %s"%[i,key])
		check(base==before,"inherit does not mutate input")
	var base := {"vitality":900,"strength":700,"toughness":0,"dexterity":400}
	check(not Rules.inherit(base,0,80,2,0).ok,"positive turn with unknown history rejected")
	check(not Rules.inherit(base,1,80,1,0).ok,"zero turn cannot contain historical levels")
	check(not Rules.inherit(base,0,79,1,20).ok,"underlevel rejected")
	check(not Rules.inherit(base,0,80,6,20).ok,"sixth turn closed")
	check(not Rules.inherit(base,0,80,1,21).ok,"quest count bounded")
	check(not Rules.inherit({"vitality":0,"strength":0,"toughness":0,"dexterity":0},0,80,1,0).ok,"zero total rejected before C division")
	check(not Rules.inherit(base,0.5,80,1,0).ok,"fractional history not truncated")
	check(not Rules.inherit(base,0,80,true,0).ok,"bool count is not an integer")
	print("transmigration_rules_test: %d C vectors, %d failures"%[data.inheritance.size(),failures])
	quit(1 if failures else 0)
