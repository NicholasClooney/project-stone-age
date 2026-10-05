extends "res://tests/required_fee_test.gd"
func run()->void:
 for shape in ["legacy","entity","both","none"]:
  var b=Backend.new()
  if not setup(b,"permit","compat-"+shape,1000):b.free();quit(1);return
  b.session._profile.travel_pass=shape in ["legacy","both"]
  if shape in ["entity","both"]:Session.OriginalEquipment.add(b.session._profile,2422)
  check(b.save(),"Save disclosed compatibility profile")
  if failures:b.free();quit(1);return
  var before:Dictionary=record(b)
  if failures:b.free();quit(1);return
  check(b.session.has_travel_pass()==(shape!="none") and record(b)==before,"Read-only OR preserves all native/cache/bytes")
  if failures:b.free();quit(1);return
  var rejected:Dictionary=b.handle({"type":"buy_travel_pass"})
  check(not rejected.get("ok",true) and record(b)==before,"Old public no-NPC purchase never charges or mints permanent bool")
  if failures:b.free();quit(1);return
  if shape in ["entity","both"]:
   var uid:int=int(b.session._profile.original_instances.back().uid)
   check(b.handle({"type":"quest_discard","item_id":2422,"instance_uid":uid}).get("ok",false),"Actual original discard command")
   if failures:b.free();quit(1);return
   check(b.session.has_travel_pass()==(shape=="both"),"Last entity gone loses only nonlegacy right")
   if failures:b.free();quit(1);return
  b.free()
 print("FEE COMPATIBILITY: 0 failures; no migration/no grants")
 quit(0)
