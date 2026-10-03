extends "res://tests/brothers_golden_quests_test.gd"
## Independent source route, not a larger timeout on the five-guard suite.
func run()->void:
 var b=fresh()
 var started:int=Time.get_ticks_msec()
 golden_wrong_door(b)
 timing("golden original wrong door",started)
 b.free();b=fresh();adult(b)
 started=Time.get_ticks_msec()
 golden(b,true)
 timing("golden replacement mirror route",started)
 check(trade(b,"giiru/event/ev28_0").ok and Rules.flag(b.session.snapshot(),"now",28),"golden-first progression does not block original brothers request")
 b.free()
 timing("suite total",suite_started)
 print("GOLDEN REPLACEMENT ROUTE: %d failures"%failures)
 quit(1 if failures else 0)
