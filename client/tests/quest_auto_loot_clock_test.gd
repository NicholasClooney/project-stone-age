extends "res://tests/quest_auto_loot_state_test.gd"
const LootTimer=preload("res://server/quest_auto_loot.gd")
func run()->void:
 var ledger:Dictionary=State.acquire(State.empty(),KEY,ID,RUN,1,0).ledger
 ledger=State.open(ledger,KEY,State.identity(ledger.entries[KEY])).ledger
 var time:Array=[1000]
 var timer=LootTimer.new();timer.clock=func():return time[0]
 var identity:Dictionary={"run_id":RUN,"step_id":KEY,"revision":1}
 check(timer.start_after_commit(KEY,ledger.entries[KEY],identity),"Timer starts only on committed open span")
 time[0]=11000
 var first:=timer.checkpoint(ledger)
 check(first.ok and first.ledger.entries[KEY].used_ms==10000 and ledger.entries[KEY].used_ms==0,"Failed save keeps original ledger/anchor")
 time[0]=21000
 var retry:=timer.checkpoint(ledger)
 check(retry.ledger.entries[KEY].used_ms==20000,"Retry uses monotonic total, not accumulated failed deltas")
 ledger=retry.ledger;check(timer.accept_commit(ledger),"Checkpoint acknowledged")
 time[0]=61000
 check(not timer.may_attempt(ledger,identity),"Limit forbids new attempt but does not truncate battle")
 time[0]=71000
 check(timer.used_ms()==70000,"Disconnected unfinished step battle still counts when timer not frozen")
 check(timer.pause_idle(),"No-battle pause freezes before close save")
 time[0]=9000000
 check(timer.used_ms()==70000,"Offline idle freeze ignores wall time")
 var closed:=timer.checkpoint(ledger,true)
 check(closed.ok and not closed.ledger.entries[KEY].open_span,"Close candidate persists exact active total")
 check(timer.accept_commit(closed.ledger) and not timer.may_attempt(closed.ledger,identity),"Commit retires timer without runner restart")
 var other=LootTimer.new();other.clock=func():return time[0]
 check(other.start_after_commit(KEY,ledger.entries[KEY],identity),"Independent timer fixture")
 time[0]-=1
 check(other.used_ms()==-1 and other.blocked,"Backward clock conservatively stops; no negative credit")
 var storage=LootTimer.new();time[0]=1000;storage.clock=func():return time[0]
 check(storage.start_after_commit(KEY,ledger.entries[KEY],identity),"Storage fixture starts committed original span")
 time[0]=4000
 check(storage.pause_storage() and storage.used_ms()==int(ledger.entries[KEY].used_ms)+3000,"Final candidate sample includes active settlement computation")
 time[0]=500000
 check(storage.pause_storage() and storage.used_ms()==int(ledger.entries[KEY].used_ms)+3000,"Disk call and failed-save repair wait excluded; retry does not resample")
 check(not storage.may_attempt(ledger,identity),"Storage pause forbids another attempt")
 var storage_close:=storage.checkpoint(ledger,true)
 check(storage_close.ok and storage_close.ledger.entries[KEY].used_ms==int(ledger.entries[KEY].used_ms)+3000,"Retried close reuses sampled total")
 var old_lifetime:RefCounted=storage.lifetime
 check(storage.accept_commit(storage_close.ledger),"Explicit timer-only fixture closes old lifetime")
 var reopened:=State.open(storage_close.ledger,KEY,State.identity(storage_close.ledger.entries[KEY]))
 check(reopened.ok and storage.start_after_commit(KEY,reopened.ledger.entries[KEY],identity),"Same timer object restarts with new lifetime; no disk claim")
 var new_lifetime:RefCounted=storage.lifetime
 var new_anchor:int=storage.anchor_ms
 check(not is_same(old_lifetime,new_lifetime),"Actual start creates distinct lifetime on same object")
 check(not storage.pause_storage_for(old_lifetime) and not storage.frozen and not storage.storage_paused and storage.anchor_ms==new_anchor,"Old failed frame cannot pause reused timer")
 check(storage.pause_storage_for(new_lifetime) and storage.storage_paused,"Matching current lifetime may enter storage pause")
 print("QUEST AUTO LOOT CLOCK: %d failures; no encounter or battle wiring"%failures)
 quit(1 if failures else 0)
