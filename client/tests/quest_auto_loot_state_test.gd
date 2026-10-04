extends SceneTree
const State=preload("res://server/quest_auto_loot_state.gd")
const KEY=State.STEP
const ID="0123456789abcdef0123456789abcdef"
const RUN="fedcba9876543210fedcba9876543210"
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var initial:=State.empty()
 var created:=State.acquire(initial,KEY,ID,RUN,30,2)
 check(created.ok and initial==State.empty(),"Pure candidate never mutates caller")
 var ledger:Dictionary=created.ledger
 check(State.valid(ledger) and ledger.entries[KEY].limit_ms==1800000,"Default persistent30 minutes")
 check(State.acquire(ledger,KEY,RUN,ID,180,99).ledger==ledger,"New run cannot reset old ledger or inventory baseline")
 for value in [true,0,-1,181,1.5,NAN,INF]:
  check(not State.acquire(initial,KEY,ID,RUN,value,0).ok,"Strict minute validation "+str(value))
 for field in State.ENTRY_KEYS:
  var bad:=ledger.duplicate(true);bad.entries[KEY].erase(field)
  check(not State.valid(bad),"Required entry field "+field)
 for value in [true,-1,0.5,NAN,INF]:
  var bad:=ledger.duplicate(true);bad.entries[KEY].used_ms=value
  check(not State.valid(bad),"Reject noninteger used time")
 var old_identity:=State.identity(ledger.entries[KEY])
 ledger=State.open(ledger,KEY,old_identity).ledger
 check(not State.open(ledger,KEY,old_identity).ok,"One serial span and stale identity rejected")
 var opened:=ledger.duplicate(true)
 var receipt:Dictionary={"budget_id":ID,"generation":0,"issued_seq":1,"battle_id":"real-battle-fixture"}
 var settled:=State.settle(ledger,KEY,receipt,"real-battle-fixture",1800100,1)
 check(settled.ok and ledger==opened,"Late current battle can settle beyond limit; candidate remains isolated")
 ledger=settled.ledger
 check(ledger.entries[KEY].saved_battles==1 and ledger.entries[KEY].new_items==1 and ledger.entries[KEY].existing_items==2,"Saved candidate separates baseline/new/battles")
 check(not State.settle(ledger,KEY,receipt,"real-battle-fixture",1800200,1).ok,"Duplicate receipt cannot count twice")
 check(not State.open(ledger,KEY,State.identity(ledger.entries[KEY])).ok,"Exhaustion prevents a new span")
 var adjusted:=State.adjust(ledger,KEY,State.identity(ledger.entries[KEY]),60)
 check(adjusted.ok and adjusted.ledger.entries[KEY].used_ms==1800100,"Explicit increase preserves used time")
 check(not State.adjust(adjusted.ledger,KEY,State.identity(ledger.entries[KEY]),90).ok,"Same-generation stale revision cannot overwrite adjustment")
 ledger=adjusted.ledger
 for seq in range(2,133):
  ledger=State.open(ledger,KEY,State.identity(ledger.entries[KEY])).ledger
  receipt.issued_seq=seq;receipt.battle_id="battle-%d"%seq
  ledger=State.settle(ledger,KEY,receipt,receipt.battle_id,1800100+seq,0).ledger
 check(ledger.entries[KEY].saved_battles==132 and ledger.entries[KEY].new_items==1,"High water survives128-battle history capacity; zero received unchanged")
 check(not State.settle(ledger,KEY,receipt,receipt.battle_id,1809999,1).ok,"Latest duplicate still refused")
 ledger=State.open(ledger,KEY,State.identity(ledger.entries[KEY])).ledger
 var recovered:=State.recovered({"version":8,"quest_loot":ledger},false)
 check(recovered.entries[KEY].recovery_blocked and recovered.entries[KEY].used_ms==ledger.entries[KEY].used_ms,"Crash preserves known lower bound and locks")
 check(not State.acquire(recovered,KEY,RUN,ID,30,0).ok,"Start cannot clear recovery")
 check(not State.reset(recovered,KEY,State.identity(recovered.entries[KEY]),30).ok,"Recovery reset requires explicit confirmation")
 var reset:=State.reset(recovered,KEY,State.identity(recovered.entries[KEY]),30,true)
 check(reset.ok and reset.ledger.entries[KEY].generation==1 and reset.ledger.entries[KEY].saved_battles==132 and reset.ledger.entries[KEY].issued_seq==133,"Reset preserves historical stats/high water")
 var backup:=State.recovered({"version":7},true)
 check(backup.recovery_blocked and not State.acquire(backup,KEY,ID,RUN,30,0).ok,"Older backup cannot become fresh budget")
 check(State.reset_missing(backup,backup.duplicate(true),KEY,ID,RUN,30,0,true).ok,"Explicit missing-history reset separately acknowledged")
 print("QUEST AUTO LOOT STATE: %d failures; pure candidates only"%failures)
 quit(1 if failures else 0)
