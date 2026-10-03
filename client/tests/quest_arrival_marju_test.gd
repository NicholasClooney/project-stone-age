extends "res://tests/brothers_golden_quests_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
func run()->void:
 var b=fresh()
 var sender:Dictionary=Travel.npc(b,"extra/event/marju")
 var receiver:Dictionary=Travel.npc(b,"extra/event/marju01")
 var gate:Dictionary=Travel.npc(b,"genout/wpm_120_19_15")
 b.automation.position_changed(1300,Vector2i(70,52))
 check(Travel.commit(b,sender) and 2687 in b.session.snapshot().original_items,"real public original mail request needs no cave qualification")
 b.automation.position_changed(119,Vector2i(97,89))
 check(not Travel.commit(b,receiver),"project mail delivery placement cannot set END37/NOW38")
 b.automation.position_changed(120,Vector2i(19,16))
 check(Travel.commit(b,gate) and b.quest_arrival.has_arrival(b,122,Vector2i(6,5)),"saved actual level50 source gate starts maze route")
 check(Travel.walk_near(b,receiver,[122,118,119]),"actual huge original maze and both floor portals reach recipient")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-marju-arrival/save.json"
 check(not Travel.commit(b,receiver) and b.session.snapshot()==before,"delivery save failure preserves mail and flags")
 b.save_path=""
 check(Travel.commit(b,receiver) and Rules.flag(b.session.snapshot(),"ended",37) and 2697 in b.session.snapshot().original_items,"actual delivery exchange sets END37 only after saved route")
 check(Route.walk(b,119,Vector2i(103,93),[119]).get("ok",false),"real original one-way exit approach")
 check(b.handle({"type":"report_position","map_id":121,"cell":[17,15]}).ok,"original one-way exit leaves protected maze")
 check(not b.quest_helper.places.links(121).values().any(func(link):return int(link.to_map)==119),"no invented reverse entrance from exit house")
 # Public return travel is allowed; original item/event predicates decide it.
 b.automation.position_changed(1300,Vector2i(70,52))
 check(Travel.commit(b,sender) and Rules.flag(b.session.snapshot(),"ended",38),"legitimate public return reward after leaving maze remains available")
 b.automation.position_changed(119,Vector2i(97,89))
 check(b.handle({"type":"quest_discard","item_id":2697}).ok,"discard own stone for source replacement branch")
 check(not b.handle({"type":"quest_talk","npc_id":receiver.id}).ok,"project return cannot use MESSAGE replacement branch")
 b.free();print("QUEST ARRIVAL MARJU: %d failures"%failures);quit(1 if failures else 0)
