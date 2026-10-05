extends "res://tests/required_fee_test.gd"
# Real writer return injection. no_mark is explicitly a private-method test double.
class ReturningBackend:
 extends Backend
 var after_write:Callable
 var omit:=false
 var armed:=false
 func _save_required_fee(frame:Dictionary)->bool:
  if armed and omit:
   armed=false;quest_save_serial+=1
   return true # deliberately no actual writer/mark; not a real disk success
  var result:bool=super._save_required_fee(frame)
  if armed:
   armed=false
   if after_write.is_valid():after_write.call(self)
  return result
var successor:Dictionary={}
func run()->void:
 for kind in ["permit","seimu"]:
  for mode in ["save","identity","no_mark"]:
   var b=ReturningBackend.new()
   if not setup(b,kind,"reentry-"+kind+"-"+mode,1000):b.free();quit(1);return
   var opened:Dictionary=open_fee(b,kind)
   check(opened.get("ok",false) and opened.has("dialogue"),"Actual original confirmation before writer injection")
   if failures:b.free();quit(1);return
   var before:Dictionary=record(b)
   if failures:b.free();quit(1);return
   before.page={}
   var fired:Array=[false]
   b.after_write=func(host):
    if failures:return
    fired[0]=true
    if mode=="save":
     host.session._profile.player.gold+=7
     check(host.save(),"Real nested complete save after fee writer returned")
     if failures:return
    else:
     host.quest_auto.identity.begin();host.quest_auto.navigation.key="fee-successor"
    successor=record(host)
   b.omit=mode=="no_mark";b.armed=true
   var reply:Dictionary=choose_fee(b,kind,opened)
   if failures:b.free();quit(1);return
   if mode=="no_mark":
    check(not reply.get("ok",true) and not fired[0],"true/+1 without base mark never authorizes fee result")
    if failures:b.free();quit(1);return
    before.serial+=1
    check(record(b)==before,"No actual base writer means no candidate installation; only explicit double serial changes")
   else:
    check(reply.get("ok",false) and fired[0] and record(b)==successor,"Old fee return cannot overwrite complete successor")
   if failures:b.free();quit(1);return
   print("FEE REENTRY COMPLETE ",kind,"/",mode)
   b.free()
 print("FEE REENTRY: 0 failures; six return fixtures, no public start claim")
 quit(0)
