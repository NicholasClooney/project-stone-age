extends "res://tests/required_fee_reentry_test.gd"
# Inherits actual private-writer-return injection, never fakes writer result.
func run()->void:
 for mode in ["new_page","stationary"]:
  var b=ReturningBackend.new()
  if not setup(b,"permit","failed-return-"+mode,1000):b.free();quit(1);return
  var opened:Dictionary=open_fee(b,"permit")
  check(opened.get("ok",false) and opened.has("dialogue"),"Real permit confirmation before actual save failure")
  if failures:b.free();quit(1);return
  check(not b.session._profile.get("no_random_encounters",false),"Stationary successor needs existing random-enabled fixture; do not change it")
  if failures:b.free();quit(1);return
  var baseline:Dictionary=record(b)
  if failures:b.free();quit(1);return
  check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Fresh genuine writer blocker")
  if failures:b.free();quit(1);return
  var fired:Array=[false]
  b.after_write=func(host):
   if failures:return
   fired[0]=true
   var primary:PackedByteArray=disk(host.save_path)
   if failures:return
   var backup:Dictionary=backup_record(host.save_path+".bak")
   if failures:return
   check(host.session.snapshot()==baseline.profile and host.last_saved_payload==baseline.cache and primary==baseline.disk and backup==baseline.bak,"Base failure rollback completed BEFORE virtual return observer")
   if failures:return
   if mode=="new_page":
    var next_page:Dictionary=permit_command(host,{"type":"permit_shop_open","source_id":SHOP,"open_id":"failure-successor"})
    check(next_page.get("ok",false) and next_page.has("dialogue"),"Actual successor permit open after failed transaction")
    if failures:return
   else:
    var moved:Dictionary=host.handle({"type":"report_position","map_id":100,"cell":[637,493]})
    check(moved.get("ok",false),"Original ordinary report moves successor, fixture convenience")
    if failures:return
    var start:Dictionary=host.handle({"type":"stationary_encounters","enabled":true,"_quest_connection":71})
    check(start.get("ok",false) and host.stationary.running,"Real stationary start after failed fee; no battle driven")
    if failures:return
   successor=record(host)
  b.armed=true
  var reply:Dictionary=choose_fee(b,"permit",opened)
  if failures:b.free();quit(1);return
  check(not reply.get("ok",true) and fired[0],"Actual failed writer returned once; no fabricated commit")
  if failures:b.free();quit(1);return
  check(record(b)==successor and DirAccess.dir_exists_absolute(b.save_path+".tmp"),"Old failure tail neither clears new page nor stops new stationary; blocker retained")
  if failures:b.free();quit(1);return
  var primary:PackedByteArray=disk(b.save_path)
  if failures:b.free();quit(1);return
  var backup:Dictionary=backup_record(b.save_path+".bak")
  if failures:b.free();quit(1);return
  check(primary==baseline.disk and backup==baseline.bak,"Failed transaction plus successor actions do not fake a saved fee")
  if failures:b.free();quit(1);return
  print("FEE FAILED RETURN COMPLETE ",mode)
  b.free()
 print("FEE FAILED RETURN: 0 failures; two actual writer-failure observers")
 quit(0)
