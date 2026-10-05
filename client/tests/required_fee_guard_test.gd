extends "res://tests/required_fee_test.gd"
var observed:Dictionary={}
func run()->void:
 for mode in ["guard_save","guard_identity","queued_save","queued_stop","queued_identity"]:
  var b=Backend.new()
  if not setup(b,"seimu",mode,1000):b.free();quit(1);return
  var opened:Dictionary=open_fee(b,"seimu")
  check(opened.get("ok",false) and opened.has("dialogue"),"Real300 source page before attack")
  if failures:b.free();quit(1);return
  var fired:Array=[false]
  var weak:WeakRef=weakref(b)
  if mode.begins_with("guard"):
   b.quest_visit_guard=func():
    if failures:return "test failure"
    var host=weak.get_ref()
    check(host!=null,"Guard owner remains live")
    if failures:return "test failure"
    if fired[0]:return ""
    fired[0]=true
    if mode=="guard_save":
     check(host.save(),"Actual samepayload save changes serial inside original party guard")
     if failures:return "test failure"
    else:host.quest_auto.identity.begin()
    observed=record(host)
    return ""
  else:
   b.event.connect(func(message):
    if failures or fired[0] or message.get("type","")!="position":return
    var host=weak.get_ref()
    check(host!=null and host._depth==0,"Real queued observer after original handle returns")
    if failures:return
    fired[0]=true
    if mode=="queued_save":
     host.session._profile.player.gold+=11
     check(host.save(),"Real successor complete save")
     if failures:return
    elif mode=="queued_stop":host.quest_auto.stop(host,"收费观察者停止")
    else:host.quest_auto.identity.begin();host.quest_auto.navigation.key="fee-new-identity"
    if failures:return
    observed=record(host)
   )
  var reply:Dictionary=choose_fee(b,"seimu",opened)
  if failures:b.free();quit(1);return
  check(fired[0] and reply.get("ok",false)==mode.begins_with("queued"),"Actual guard rejects stale; queued committed fact remains success")
  if failures:b.free();quit(1);return
  check(record(b)==observed,"No old tail overwrites complete observed successor")
  if failures:b.free();quit(1);return
  print("FEE GUARD COMPLETE ",mode)
  b.free()
 print("FEE GUARD: 0 failures; original Callable and queue fixtures")
 quit(0)
