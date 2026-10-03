extends SceneTree
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func run() -> void:
 var b=Backend.new()
 b.handle({"type":"report_position","map_id":100,"cell":[637,493]})
 var other=Backend.new()
 check(not b.full_snapshot().derived.no_random_encounters,"new characters keep random encounters")
 check(not b.handle({"type":"no_random_encounters","enabled":"true"}).ok,"malformed setting rejected")
 check(b.handle({"type":"no_random_encounters","enabled":true}).ok,"ordinary character can enable helper")
 check(not other.full_snapshot().derived.no_random_encounters,"other character unaffected")
 var before: int=b.encounter_rng.state
 var pressure: int=b.encounter_catalog.pressure
 for i in range(200):
  var r:Dictionary=b.handle({"type":"field_step","map_id":100,"cell":[637,493],"encounter":true})
  check(r.ok and not r.hit and not r.battle,"disabled random walk %d" % i)
 check(before==b.encounter_rng.state and pressure==b.encounter_catalog.pressure,"disabled walking does not roll RNG or accumulate pressure")
 var path:="user://random-encounter-toggle.json"
 check(b.session.save_game(path),"save helper setting")
 var loaded=Session.new()
 check(loaded.load_game(path) and loaded.snapshot().no_random_encounters,"save round trip retains setting")
 loaded._profile.erase("no_random_encounters")
 check(loaded.save_game(path),"write pre-setting save")
 check(loaded.load_game(path) and not loaded.snapshot().no_random_encounters,"old saves migrate to original encounter default")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
 var explicit:Dictionary=b.handle({"type":"wild_encounter","map_id":100,"cell":[637,493]})
 check(explicit.ok and b.battle_open,"explicit encounter still opens real battle")
 check(b.handle({"type":"no_random_encounters","enabled":false}).ok,"setting can change during battle")
 b.free();other.free()
 print("RANDOM ENCOUNTER TOGGLE: %d failures" % failures)
 quit(1 if failures else 0)
