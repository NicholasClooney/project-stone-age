extends "res://tests/required_fee_test.gd"
func run()->void:
 for mode in ["second_vendor","gold_changed","capacity_changed","source_changed","left_returned"]:
  var b=Backend.new()
  if not setup(b,"permit","conditions-"+mode,1000):b.free();quit(1);return
  var source:String=SHOP
  if mode=="second_vendor":
   source="genout/ss_4000_99_85"
   check(b.session.set_location(4000,98,85),"Second ordinary source-near fixture, not travel")
   if failures:b.free();quit(1);return
   b.automation.position_changed(4000,Vector2i(98,85),true)
   check(b.save(),"Second vendor fixture persisted before request")
   if failures:b.free();quit(1);return
  var opened:Dictionary=permit_command(b,{"type":"permit_shop_open","source_id":source,"open_id":"conditions-"+mode})
  check(opened.get("ok",false) and opened.has("dialogue"),"Original source page before change")
  if failures:b.free();quit(1);return
  if mode=="gold_changed":
   b.session._profile.player.gold=199
   check(b.save(),"Actual concurrent complete wallet save after page")
  elif mode=="capacity_changed":
   while Session.bag_slots(b.session._profile)<15:Session.OriginalEquipment.add(b.session._profile,2752)
   check(b.session._valid_profile(b.session.snapshot()) and b.save(),"Legal full bag after page, exact unchanged capacity rule")
  elif mode=="source_changed":
   # Explicit catalog mutation double, never edit actual imported source file.
   var found:bool=false
   for npc in b.quest_helper.places.residents:
    if npc.get("dialogue_source","")=="gmsv/data/npc/"+source:
     npc.name=str(npc.name)+"-changed";found=true;break
   check(found,"Exact source resident changed in fixture")
  elif mode=="left_returned":
   var away:Dictionary=b.handle({"type":"report_position","map_id":1100,"cell":[84,107]})
   check(away.get("ok",false),"Actual report away retires old page")
   if failures:b.free();quit(1);return
   var returned:Dictionary=b.handle({"type":"report_position","map_id":1100,"cell":[85,107]})
   check(returned.get("ok",false),"Actual report back does not recreate old page")
  if failures:b.free();quit(1);return
  var baseline:Dictionary=record(b)
  if failures:b.free();quit(1);return
  baseline.page={}
  var expected:Dictionary=baseline.profile.duplicate(true)
  if mode=="second_vendor":expected.player.gold-=200;Session.OriginalEquipment.add(expected,2422)
  var reply:Dictionary=choose_fee(b,"permit",opened)
  if failures:b.free();quit(1);return
  if mode=="second_vendor":
   check(reply.get("committed",false) and b.session.snapshot()==expected,"Second original vendor exact gold/entity/UID candidate")
   if failures:b.free();quit(1);return
   var bytes:PackedByteArray=disk(b.save_path)
   if failures:b.free();quit(1);return
   var parsed:Dictionary=Compare.validated_copy(b.session,bytes.get_string_from_utf8())
   check(parsed.get("ok",false) and parsed.profile==expected and b.last_saved_payload==JSON.stringify(expected),"Second vendor full primary/cache equality")
  else:check(not reply.get("ok",true) and record(b)==baseline,"Changed page conditions reject without fee/profile/disk mutation")
  if failures:b.free();quit(1);return
  print("FEE CONDITIONS COMPLETE ",mode)
  b.free()
 print("FEE CONDITIONS: 0 failures; five fixed page-condition fixtures")
 quit(0)
