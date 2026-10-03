extends "res://tests/brothers_golden_quests_test.gd"
## Production backend and Hub commands; connection ids stand in for sockets.
## No GameScene/rendering or WebSocket transport claim is made by this suite.
const RouteDriver=preload("res://tests/support/original_route_driver.gd")
const JUDGE="jaruga/event/event04_1"

func run() -> void:
 var b=Backend.new()
 b.automation.position_changed(10202,Vector2i(31,13))
 check(not b.handle({"type":"check_passage","from_map":10202,"to_map":10204}).ok,"original adult level gate rejects level one")
 check(not b.handle({"type":"report_position","map_id":10204,"cell":[2,6]}).ok,"low-level source portal report cannot bypass gate")
 b.automation.position_changed(10204,Vector2i(13,6))
 check(not b.handle({"type":"quest_talk","npc_id":JUDGE}).ok,"project placement behind gate cannot start ritual")
 b.free()

 var folder: String="user://adult-arrival-%d"%OS.get_process_id()
 DirAccess.make_dir_recursive_absolute(folder)
 var hub=Hub.new(folder.path_join("accounts.json"));hub.tick=false;hub.backups=false
 check(hub.start(),"isolated real profile hub starts")
 check(hub.handle(11,{"type":"create_profile","name":"AdultRoute","pin":"1234"}).ok,"first device creates profile")
 check(hub.handle(22,{"type":"login","name":"AdultRoute","pin":"1234"}).ok,"second device logs into same profile")
 b=hub.backend_of(11)
 check(b==hub.backend_of(22),"both devices use one server-owned arrival instance")
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 b.session.gm_raise_level(-1,30)
 b.automation.position_changed(10202,Vector2i(31,13))
 check(hub.handle(11,{"type":"report_position","map_id":10204,"cell":[2,6]}).ok,"level thirty enters actual source portal")
 check(RouteDriver.walk(b,10204,Vector2i(13,6),[10204]).ok,"original channel begins with real consecutive steps")
 var opened: Dictionary=hub.handle(11,{"type":"quest_talk","npc_id":JUDGE})
 check(opened.ok and opened.has("dialogue"),"first device opens ritual on legitimate route")
 # Same-map nonadjacent reports are position requests, never route evidence.
 # Even a client's invented server origin cannot authorize the jump.
 check(hub.handle(22,{"type":"report_position","map_id":10204,"cell":[187,13],"arrival_kind":"script","evidence":{"scope":"adult"}}).ok,"second device location request reaches real backend")
 check(hub.handle(22,{"type":"report_position","map_id":10204,"cell":[13,6]}).ok,"second device reports back beside judge")
 check(not hub.handle(11,{"type":"quest_choose","token":opened.get("dialogue",{}).get("token",""),"choice":"yes"}).ok and not Rules.flag(b.session.snapshot(),"now",4),"other-device jump invalidates first-device transaction without setting NOW4")
 for connection in [11,22]:
  check(not hub.handle(connection,{"type":"quest_talk","npc_id":JUDGE}).ok,"both devices reject the same invalid arrival")
 check(RouteDriver.complete_adult(b).get("ok",false),"real gate, full channel round trip and three exchanges complete END4")
 check(b.session.snapshot().original_items==[2418] and Rules.flag(hub.backend_of(22).session.snapshot(),"ended",4),"both devices observe consumed fifteen jade and one original reward")
 var path: String=b.save_path
 check(b.save() and b.load_profile(path),"real saved profile reload succeeds")
 for connection in [11,22]:
  check(not hub.backend_of(connection).quest_arrival.has_arrival(b,10204,b.automation.position_cell),"profile reload clears both devices' shared arrival")
  check(not hub.handle(connection,{"type":"quest_talk","npc_id":JUDGE}).ok,"saved location and END4 cannot replace fresh arrival")
 var restarted=Backend.new()
 check(restarted.load_profile(path) and Rules.flag(restarted.session.snapshot(),"ended",4),"new backend preserves actual completed quest")
 check(not restarted.quest_arrival.has_arrival(restarted,10204,Vector2i(13,6)),"new backend does not deserialize arrival eligibility")
 restarted.free();hub.shut_down();hub.free()
 print("QUEST ARRIVAL ADULT: %d failures"%failures)
 quit(1 if failures else 0)
