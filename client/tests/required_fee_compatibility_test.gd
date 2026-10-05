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
  var legacy_access:bool=shape in ["legacy","both"]
  var boolean_right:bool=legacy_access
  var entity_uids:Array=[]
  for instance in b.session._profile.original_instances:
   if int(instance.item_id)==2422:entity_uids.append(int(instance.uid))
  check(b.session.has_travel_pass()==legacy_access and record(b)==before,"Default-disabled entity entitlement preserves legacy boolean qualification and all bytes")
  if failures:b.free();quit(1);return
  var rejected:Dictionary=b.handle({"type":"buy_travel_pass"})
  check(not rejected.get("ok",true) and record(b)==before,"Old public no-NPC purchase never charges or mints permanent bool")
  if failures:b.free();quit(1);return
  if shape in ["entity","none"]:
   # Entity-only profiles do not gain the new candidate entitlement while
   # disabled; both shapes may still buy the shipped permanent boolean here.
   var opened:Dictionary=permit_command(b,{"type":"permit_shop_open","source_id":SHOP,"open_id":"legacy-vendor-result"})
   check(opened.get("ok",false) and opened.get("dialogue",{}).get("kind","")=="original_permit_shop" and opened.get("already_owned",false)==false,"No boolean right: purchase begins at the pinned original vendor page")
   if failures:b.free();quit(1);return
   var page:Dictionary=record(b)
   if failures:b.free();quit(1);return
   var bought:Dictionary=permit_command(b,{"type":"permit_shop_choose","token":opened.dialogue.token,"choice":"buy_one"})
   var expected:Dictionary=page.profile.duplicate(true)
   expected.player.gold-=200;expected.travel_pass=true
   var purchased_uids:Array=[]
   for instance in b.session._profile.original_instances:
    if int(instance.item_id)==2422:purchased_uids.append(int(instance.uid))
   check(bought.get("ok",false) and bought.get("committed",false) and b.session.snapshot()==expected and purchased_uids==entity_uids,"Original vendor commits 200-stone permanent boolean entitlement without changing physical permit UIDs")
   if failures:b.free();quit(1);return
   boolean_right=true
   var persisted:Dictionary=record(b)
   check(persisted.profile==expected and b.session.has_travel_pass(),"Saved legacy right is immediately usable on original gates")
   if failures:b.free();quit(1);return
   var duplicate:Dictionary=permit_command(b,{"type":"permit_shop_open","source_id":SHOP,"open_id":"duplicate-legacy-purchase"})
   check(duplicate.get("already_owned",false) and not duplicate.has("dialogue") and record(b)==persisted,"Owned legacy right cannot be charged twice")
   if failures:b.free();quit(1);return
  if shape in ["entity","both"]:
   var uid:int=int(entity_uids.back()) if shape=="entity" else int(b.session._profile.original_instances.back().uid)
   check(b.handle({"type":"quest_discard","item_id":2422,"instance_uid":uid}).get("ok",false),"Actual original discard command")
   if failures:b.free();quit(1);return
   check(b.session.has_travel_pass()==boolean_right and not b.session._profile.original_instances.any(func(instance):return int(instance.item_id)==2422),"Discarding the permit entity preserves only the purchased or legacy boolean right")
   if failures:b.free();quit(1);return
  b.free()
 print("FEE COMPATIBILITY: 0 failures; legacy boolean purchase; no entity grants/migration")
 quit(0)
