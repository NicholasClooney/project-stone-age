extends "res://tests/support/required_fee_runner_harness.gd"
## UNRUN. No product-private cleanup; references below are test-owned only.
func one(mode:String)->void:
 var c:Dictionary=setup("lifetime-"+mode)
 if failures:finish(c);return
 var b=c.b;var session=c.s
 var wb:WeakRef=weakref(b);var ws:WeakRef=weakref(session)
 var cap:RefCounted=arm(c)
 if mode=="wrong_take":check(not b.turn(RefCounted.new()).get("ok",false) and not b._required_fee_runner._cap.is_empty(),"wrong take does not consume legitimate unconsumed handoff")
 if mode=="revoke":b._required_fee_runner.revoke()
 if mode=="detach":b.fee_detach(71)
 if mode in ["success","failed","hold"]:
  if mode=="failed":b.mode="false_before"
  if mode=="hold":session.mode="post_unknown"
  var reply:Dictionary=b.turn(cap)
  check(reply.get("ok",false)==(mode=="success"),"actual success/failure endpoint")
  check(b._required_fee_runner._cap.is_empty() and b._required_fee_runner._op.is_empty(),"one take and temporary frame released")
  if mode=="hold":check(not session._required_fee_hold.is_empty(),"legitimate protection retained until owner disposed")
 check(not b._persist_required_fee_runner(RefCounted.new(),session._profile.duplicate(true)),"arbitrary stale writer handle rejected")
 # External handle is retained on purpose. It contains no strong Backend/Session.
 finish(c)
 c={};b=null;session=null
 check(wb.get_ref()==null and ws.get_ref()==null,"Backend and Session truly released without clearing private product fields: "+mode)
 check(cap!=null,"external stale handle retained during WeakRef check")
func run()->void:
 for mode in ["unconsumed","wrong_take","revoke","detach","success","failed","hold"]:
  one(mode)
  if failures:summary("D0 LIFETIME");return
 summary("D0 LIFETIME")
