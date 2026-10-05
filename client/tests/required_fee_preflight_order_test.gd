extends "res://tests/required_fee_test.gd"
func run()->void:
 for mode in ["forged_open","other_open","other_choose","retired_choose","malformed_choose"]:
  var b=Backend.new()
  if not setup(b,"permit","preflight-"+mode,1000):b.free();quit(1);return
  var opened:Dictionary=open_fee(b,"permit")
  check(opened.get("ok",false) and opened.has("dialogue"),"Real page before adversarial command")
  if failures:b.free();quit(1);return
  var old_epoch=b._fee_bindings[71]
  b.fee_attach(72)
  if mode=="retired_choose":b.fee_detach(71)
  # Explicit internal activity marker: no public stationary/auto start claim.
  # Current stationary whitelist has no permit type: do not claim it already stops it.
  # Also retain a synthetic queued marker to expose accidental generic handle flushing.
  b.stationary.running=true;b.stationary.reason="successor activity sentinel";b.stationary.elapsed=0.25
  b.quest_auto.running=true;b.quest_auto.identity.begin();b.quest_auto.navigation.key="keep-successor"
  b._queue.append({"type":"fee-test-observer-marker"}) # explicit dispatch fixture, not proof
  var queue_before:Array=b._queue.duplicate(true)
  var observed:Array=[false]
  b.event.connect(func(_message):observed[0]=true)
  var before:Dictionary=record(b)
  if failures:b.free();quit(1);return
  var command:Dictionary={"type":"permit_shop_choose","token":opened.dialogue.token,"choice":"buy_one","_quest_connection":72,"_fee_binding":b._fee_bindings[72]}
  if mode=="forged_open":command={"type":"permit_shop_open","source_id":SHOP,"open_id":"forged","_quest_connection":71,"_fee_binding":RefCounted.new()}
  elif mode=="other_open":command={"type":"permit_shop_open","source_id":SHOP,"open_id":"other","_quest_connection":72,"_fee_binding":b._fee_bindings[72]}
  elif mode=="retired_choose":command._quest_connection=71;command._fee_binding=old_epoch
  elif mode=="malformed_choose":command._quest_connection=71;command._fee_binding=old_epoch;command.token=5
  var reply:Dictionary=b.handle(command)
  if failures:b.free();quit(1);return
  check(not reply.get("ok",true) and record(b)==before and b.stationary.running and b.quest_auto.running and b._queue==queue_before and not observed[0],"Untrusted or foreign permit command rejected before ALL generic activity side effects")
  if failures:b.free();quit(1);return
  print("FEE PREFLIGHT ORDER COMPLETE ",mode)
  b.free()
 print("FEE PREFLIGHT ORDER: 0 failures; five internal state-preservation negatives")
 quit(0)
