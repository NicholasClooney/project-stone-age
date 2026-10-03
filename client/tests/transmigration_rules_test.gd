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
	# Project capacity compatibility, distinct from the original C five-slot oracle.
	var carried := []
	for index in range(30):carried.append({"pet_id":"carried-%d"%index,"species":"original_1","level":1})
	carried[5].species="original_693"
	carried[29].species="original_693"
	var carried_before: Array=carried.duplicate(true)
	check(Rules.select_sacrifices(carried.slice(0,6),1).indices==[5],"sixth carried slot eligible")
	check(Rules.select_sacrifices(carried,1).indices==[5],"30-slot default retains first match")
	check(Rules.select_sacrifices(carried,1,["carried-29"]).indices==[29],"30-slot explicit UID selects final slot")
	check(carried==carried_before,"30-slot selection leaves input unchanged")
	carried[5].species="original_1"
	check(Rules.select_sacrifices(carried,1).indices==[29],"default finds sole sacrifice in slot 30")
	carried[5].species="original_694"
	carried[12].species="original_695"
	carried[20].species="original_696"
	check(Rules.select_sacrifices(carried,5).indices==[29,5,12,20],"five-turn default scans all 30 slots in template order")
	check(Rules.select_sacrifices(carried,5,["carried-20","carried-12","carried-5","carried-29"]).indices==[29,5,12,20],"five-turn explicit UID order is canonical")
	check(not Rules.select_sacrifices(carried,5,["carried-29","carried-5","carried-12","carried-12"]).ok,"30-slot duplicate selection rejected")
	check(not Rules.select_sacrifices(carried,1,["warehouse-only"]).ok,"stored-only UID cannot satisfy carried sacrifice")
	check(not Rules.select_sacrifices(carried,1,[29]).ok,"numeric selected UID rejected")
	check(not Rules.select_sacrifices(carried,1,["carried-0"]).ok,"30-slot wrong template rejected")
	var invalid_carried: Array=carried.duplicate(true)
	invalid_carried[29].pet_id=invalid_carried[0].pet_id
	check(not Rules.select_sacrifices(invalid_carried,5).ok,"duplicate stored identity at slot 30 rejected")
	invalid_carried=carried.duplicate(true)
	invalid_carried[29].pet_id=""
	check(not Rules.select_sacrifices(invalid_carried,1).ok,"empty final-slot UID rejected")
	invalid_carried[29].pet_id=29
	check(not Rules.select_sacrifices(invalid_carried,1).ok,"numeric final-slot UID rejected")
	invalid_carried[29]=null
	check(not Rules.select_sacrifices(invalid_carried,1).ok,"invalid final-slot pet rejected")
	check(not Rules.select_sacrifices({"pets":carried},1).ok,"requires carried array, not profile or storage container")
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
