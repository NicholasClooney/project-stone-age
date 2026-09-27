extends SceneTree
const Routes=preload("res://scripts/leveling_routes.gd")
var failures:=0
func check(ok: bool,note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize() -> void:
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://data/training-spots.json"))
	var spots: Array=data.spots
	var catalog=preload("res://server/encounter_catalog.gd").new()
	check(spots.size()>100,"source encounter destinations generated")
	var all_levels:=true
	for level in range(1,121):
		var rows:=Routes.recommend(spots,level)
		if rows.is_empty() or Routes.classic_guide(level).is_empty():all_levels=false
		for row in rows:
			var area: Dictionary=catalog.area_at(int(row.map_id),Vector2i(row.cell[0],row.cell[1]))
			if area.is_empty() or int(area.id)!=int(row.area_id):all_levels=false
	check(all_levels,"all120levels have verified recommendations and classic context")
	var early:=Routes.recommend(spots,1)
	var late:=Routes.recommend(spots,120)
	check(float(early[0].mean_level)<5 and float(late[0].mean_level)>=80,"recommendations progress from beginners to high level zones")
	check(float(Routes.recommend(spots,30,true)[0].mean_level)>=float(Routes.recommend(spots,30,false)[0].mean_level),"squad recommendations allow modestly higher foes")
	check(Routes.classic_guide(100).contains("圣石"),"classic gated water-thunder route not claimed available")
	print("LEVELING ROUTES: %d failures"%failures);quit(1 if failures else 0)
