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
  elif mode=="capacity_changed":
   Session.OriginalEquipment.add(b.session._profile,2422)
   check(not b.session.has_travel_pass() and b.save(),"Entity-only shop buyer remains unqualified while the entity feature is closed")
   if failures:b.free();quit(1);return
  var opened:Dictionary=permit_command(b,{"type":"permit_shop_open","source_id":source,"open_id":"conditions-"+mode})
  check(opened.get("ok",false) and opened.has("dialogue"),"Original source page before change")
  if failures:b.free();quit(1);return
  if mode=="gold_changed":
   b.session._profile.player.gold=199
   check(b.save(),"Actual concurrent complete wallet save after page")
  elif mode=="capacity_changed":
   while Session.bag_slots(b.session._profile)<15:Session.OriginalEquipment.add(b.session._profile,2752)
   check(Session.bag_slots(b.session._profile)==15 and b.session._valid_profile(b.session.snapshot()) and b.save(),"Legal full bag after entity-only page; permanent boolean permit uses no item slot")
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
  if mode in ["second_vendor","capacity_changed"]:expected.player.gold-=200;expected.travel_pass=true
  var reply:Dictionary=choose_fee(b,"permit",opened)
  if failures:b.free();quit(1);return
  if mode in ["second_vendor","capacity_changed"]:
   check(reply.get("committed",false) and b.session.snapshot()==expected and Session.bag_slots(expected)==Session.bag_slots(baseline.profile),"Original vendor preserves full legacy profile and charges exactly 200 without a slot")
   if failures:b.free();quit(1);return
   if mode=="capacity_changed":
    check(b.session.has_travel_pass() and expected.original_items==baseline.profile.original_items and b.session._profile.original_instances==baseline.profile.original_instances,"Full-bag purchase preserves the physical permit and grants only the permanent boolean right")
    if failures:b.free();quit(1);return
   var bytes:PackedByteArray=disk(b.save_path)
   if failures:b.free();quit(1);return
   var parsed:Dictionary=Compare.validated_copy(b.session,bytes.get_string_from_utf8())
   check(parsed.get("ok",false) and parsed.profile==expected and b.last_saved_payload==JSON.stringify(expected),"Second vendor full primary/cache equality")
   if failures:b.free();quit(1);return
   if mode=="capacity_changed":
    var permit_uid:int=-1
    for instance in b.session._profile.original_instances:
     if int(instance.item_id)==2422:permit_uid=int(instance.uid);break
    check(permit_uid>0 and b.handle({"type":"quest_discard","item_id":2422,"instance_uid":permit_uid}).get("ok",false) and b.session.has_travel_pass() and not b.session._profile.original_items.has(2422),"After full-bag purchase, discarding the old entity leaves the paid permanent right")
  else:check(not reply.get("ok",true) and record(b)==baseline,"Changed page conditions reject without fee/profile/disk mutation")
  if failures:b.free();quit(1);return
  print("FEE CONDITIONS COMPLETE ",mode)
  b.free()
 print("FEE CONDITIONS: 0 failures; five fixed page-condition fixtures")
 quit(0)
