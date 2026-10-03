extends "res://tests/quest_arrival_transactions_test.gd"
## Reuse the actual dream final-transaction/savefail/stale-token checks, with
## END4 obtained by the source level gate and full adult corridor round trip.
## The inherited older fixture remains owned by its original suite owner.
func adult(b) -> void:
 b.automation.position_changed(10204,Vector2i(13,6))
 check(not b.handle({"type":"quest_talk","npc_id":"jaruga/event/event04_1"}).ok,"project arrival cannot start adult ritual behind level gate")
 check(RouteDriver.complete_adult(b).get("ok",false),"actual adult entrance, channel round trip and END4 exchange")
