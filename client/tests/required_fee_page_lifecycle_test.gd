extends "res://tests/required_fee_test.gd"
# Internal transport epochs, NOT real socket/authentication acceptance.
func run()->void:
 for mode in ["disconnect","reauth","other_peer","late_cancel","successor_close","stale_cancel"]:
  var b=Backend.new()
  if not setup(b,"permit","page-"+mode,1000):b.free();quit(1);return
  var epoch=b._fee_bindings[71]
  var opened:Dictionary=open_fee(b,"permit")
  check(opened.get("ok",false) and opened.has("dialogue"),"Real permit page before lifecycle change")
  if failures:b.free();quit(1);return
  var before:Dictionary=record(b)
  if failures:b.free();quit(1);return
  if mode in ["disconnect","reauth"]:
   b.fee_detach(71)
   if mode=="reauth":b.fee_attach(71)
   check(b.original_quests.pending.is_empty(),"Exact old epoch page retired on detach/reauth")
   if failures:b.free();quit(1);return
   var reply:Dictionary=b.handle({"type":"permit_shop_choose","token":opened.dialogue.token,"choice":"buy_one","_quest_connection":71,"_fee_binding":epoch})
   check(not reply.get("ok",true),"Old binding cannot buy after retirement")
   before.page={}
   if failures:b.free();quit(1);return
   check(record(b)==before,"Transport retirement changes no profile/cache/disk/activity")
  elif mode=="other_peer":
   b.fee_attach(72)
   check(not permit_command(b,{"type":"permit_shop_choose","token":opened.dialogue.token,"choice":"buy_one"},72).get("ok",true),"Other device cannot spend another page token")
   if failures:b.free();quit(1);return
   check(not permit_command(b,{"type":"quest_close","token":opened.dialogue.token},72).get("ok",true),"Other device cannot retire another page")
   if failures:b.free();quit(1);return
   check(record(b)==before,"Wrong-device request preserves exact current page and disk")
  elif mode=="late_cancel":
   check(permit_command(b,{"type":"permit_shop_cancel","open_id":opened.dialogue.open_id}).get("ok",false),"Cancel by same original binding/open id without using late ACK token")
   if failures:b.free();quit(1);return
   before.page={};check(record(b)==before,"Late open cleanup is page-only, no save")
  elif mode=="successor_close":
   # Explicit adversarial internal state, not claimed as public start (it refuses pending).
   b.quest_auto.identity.begin();b.quest_auto.running=true;b.quest_auto.phase="manual-fixture"
   b.quest_auto.navigation.key="successor"
   var successor:Dictionary=record(b)
   if failures:b.free();quit(1);return
   successor.page={}
   check(permit_command(b,{"type":"quest_close","token":opened.dialogue.token}).get("ok",false),"Exact owned permit close bypasses generic auto reward close")
   if failures:b.free();quit(1);return
   check(b.quest_auto.running and record(b)==successor,"Old page cleanup never stops successor or changes nav/disk")
  else:
   check(permit_command(b,{"type":"permit_shop_cancel","open_id":opened.dialogue.open_id}).get("ok",false),"Original page cancelled")
   if failures:b.free();quit(1);return
   var newer:Dictionary=permit_command(b,{"type":"permit_shop_open","source_id":SHOP,"open_id":"distinct-successor-page"})
   check(newer.get("ok",false) and newer.has("dialogue"),"Actual successor service page")
   if failures:b.free();quit(1);return
   var successor:Dictionary=record(b)
   if failures:b.free();quit(1);return
   check(not permit_command(b,{"type":"permit_shop_cancel","open_id":opened.dialogue.open_id}).get("ok",true),"Late cancel does not match new page")
   if failures:b.free();quit(1);return
   check(record(b)==successor,"No generic pending clear on old cancellation")
  if failures:b.free();quit(1);return
  print("FEE PAGE COMPLETE ",mode)
  b.free()
 print("FEE PAGE: 0 failures; six internal epoch fixtures; no WS claim")
 quit(0)
