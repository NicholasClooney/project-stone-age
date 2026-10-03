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
	for vector in data.auxiliary.events:
		var events := {"ended":vector.words.slice(0,6),"now":vector.words.slice(6,12)}
		var before: Dictionary=events.duplicate(true)
		check(Rules.quest_count(events)==int(vector.quests),"C END quest table")
		var result: Dictionary=Rules.flags_after(events,vector.new_count)
		check(result.ok and result.events.ended==vector.after.slice(0,6).map(func(v):return int(v)) and result.events.now==vector.after.slice(6,12).map(func(v):return int(v)),"C six-word clear/preserve")
		check(events==before,"flags input unchanged")
	for vector in data.auxiliary.sacrifices:
		var pets := []
		for index in range(5):pets.append({"pet_id":"p%d"%index,"species":"original_%d"%int(vector.templates[index]),"level":1})
		var before: Array=pets.duplicate(true)
		var result: Dictionary=Rules.select_sacrifices(pets,vector.new_count)
		check(result.ok==vector.ok,"C sacrifice availability")
		if result.ok:check(result.indices==vector.indices.map(func(v):return int(v)),"C first carried slot selection")
		check(pets==before,"pet input unchanged")
	for vector in data.auxiliary.rewards:
		var result: Dictionary=Rules.reward_for(vector.bits,vector.new_count)
		check(result.ok==(int(vector.village)>=0),"C birth availability")
		if result.ok:
			check(result.village_index==int(vector.village),"C first birth bit")
			check(result.enemy_id==int(vector.enemy_id) and result.template_id==int(vector.template_id),"source Present/enemy template")
			check([result.location.map_id,result.location.x,result.location.y]==vector.location.map(func(v):return int(v)),"source Warp")
	var choices := [{"pet_id":"first","species":"original_693","level":1},{"pet_id":"second","species":"original_693","level":140}]
	check(Rules.select_sacrifices(choices,1,["second"]).pet_ids==["second"],"explicit UID project supplement")
	check(not Rules.select_sacrifices(choices,1,["missing"]).ok,"missing UID rejected")
	check(not Rules.select_sacrifices(choices,1,["first","first"]).ok,"duplicate UID rejected")
	check(not Rules.select_sacrifices([choices[0],choices[0]],1).ok,"ambiguous stored UID rejected")
	check(not Rules.select_sacrifices(choices,2,["first"]).ok,"wrong template rejected")
	check(not Rules.flags_after({"now":[0],"ended":[0]},1).ok,"short event words rejected")
	check(Rules.quest_count({"now":[0,0,0,0,0,0],"ended":[-1,0,0,0,0,0]})==-1,"signed event word rejected")
	check(not Rules.flags_after({"now":[0,0,0,0,0,0],"ended":[0,0,0,0,0,0]},6).ok,"flags sixth turn rejected")
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
