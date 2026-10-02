extends SceneTree
const Catalog = preload("res://server/encounter_catalog.gd")
const Session = preload("res://server/game_session.gd")
const Art = preload("res://server/troop_art.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var catalog := Catalog.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	for enemy_id in range(1287,1305):
		var enemy := catalog.actor(enemy_id,rng)
		check(Art.can_render([enemy]),"Original disciple battle art %d / %d" % [enemy_id,int(enemy.sprite)])
		var session := Session.new()
		var route: int = (enemy_id-1287)/6
		var area := catalog.area_at(800+route*20,Vector2i(14,26))
		var battle := session.start_wild_battle_config({"area_id":area.id,"group_id":708+route,"enemies":[enemy]})
		check(not battle.is_empty(),"Real Session accepts original disciple actor %d" % enemy_id)
	for map_id in [800,820,840]:
		var troop := catalog.roll(map_id,Vector2i(14,26),rng)
		check(not troop.is_empty() and Art.can_render(troop.get("enemies",[])),"Original random group renders on route %d" % map_id)
	print("golden_bui_art_test: %d failures" % failures)
	quit(1 if failures else 0)
