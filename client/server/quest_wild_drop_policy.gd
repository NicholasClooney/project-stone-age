extends RefCounted
## Exact reviewed source tuples only; never an item-ID blacklist.
static var _index: Dictionary={}
static func _key(map_id:int, area:int, group:int, enemy:int, item:int, slot:int)->String:
	return "%d/%d/%d/%d/%d/%d"%[map_id,area,group,enemy,item,slot]
static func match_rule(map_id:int, area:int, group:int, enemy:int, item:int, slot:int)->Dictionary:
	if _index.is_empty():
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/quest-wild-drop-policy.json"))
		for row in data.rules:
			_index[_key(int(row.map),int(row.area),int(row.group),int(row.enemy),int(row.item),int(row.slot))]=row
	return _index.get(_key(map_id,area,group,enemy,item,slot),{}).duplicate(true)
