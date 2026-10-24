extends "res://tests/brothers_golden_quests_test.gd"
const Clock=preload("res://scripts/clock.gd")
## Every original party slice/UID/save assertion is retained in the shared driver.
func run()->void:
 for failed_slot in [0,1,2]:
  var started:int=Clock.ticks_msec()
  await party_retry(failed_slot)
  timing("party personal slice save failure%d"%failed_slot,started)
 timing("suite total",suite_started)
 print("BROTHERS PARTY RETRY: %d failures"%failures)
 quit(1 if failures else 0)
