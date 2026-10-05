extends "res://tests/quest_auto_loot_attempt_test.gd"
## Internal original-pool fixture; no public/target-drop/route proof.
func real_battle(b,path:String,time:Array)->bool:
 if not prepare_attempt(b,path,time):return false
 b.encounter_rng.seed=4101;b.encounter_catalog.pressure=50
 var reply:Dictionary={}
 for index in range(200):
  reply=b.quest_loot.attempt_once(b)
  if reply.get("battle",false) or not reply.get("ok",false):break
  time[0]+=500
 check(reply.get("battle",false) and reply.get("ok",false) and b.battle_open and b.automation.running and b.automation.single_battle and b.session._pending.has("quest_loot_receipt"),"Real E1/E2 original single battle is running")
 if failures:return false
 check(b.session._pending.group_id==169,"Fixed seed4101 original group169; never select or retry seed")
 if failures:return false
 print("E3B REAL GROUP ",b.session._pending.group_id," path=",path)
 return true
func drive_original(b,time:Array)->bool:
 for tick in range(100):
  if not b.automation.running:break
  time[0]+=500;b.automation.tick_battle(0.5)
  if failures:return false
 check(not b.automation.running,"Original driver stops within unchanged 100 tick bound")
 return failures==0
func complete_disk(b)->bool:
 var copied:Dictionary=ProfileCompare.validated_copy(b.session,FileAccess.get_file_as_string(b.save_path))
 check(copied.get("ok",false),"Whole actual disk validates")
 if failures:return false
 check(copied.profile==b.session.snapshot(),"Complete native profile/UID/ledger equals validated disk copy")
 return failures==0
func refusal_state(b)->Dictionary:
 return {"scope":b.automation.loot_scope.duplicate(true),"running":b.automation.running,"compact":b.automation.compact_active,"settings":b.automation.settings.duplicate(true),"reason":b.automation.stop_reason,"turns":b.automation.turns,"battles":b.automation.battles,"single":b.automation.single_battle,"training_pet":b.automation.training_pet_id,"finish_capture":b.automation.finish_after_capture,"profile":b.session.snapshot().duplicate(true),"pending":b.session._pending.duplicate(true),"cache":b.last_saved_payload,"disk":FileAccess.get_file_as_bytes(b.save_path)}
func refused_starts(b)->bool:
 var token=b.automation.start_lifetime
 var before:Dictionary=refusal_state(b)
 for command in [{"kind":"hunt","speed":1,"settings":{"preset":"capture","compact":false}},{"kind":"pet_train","speed":1,"pet_id":"missing","settings":{"compact":false}}]:
  check(not b.automation.start(command).get("ok",true),"Legal busy start is refused before installing lifetime/settings")
  if failures:return false
  check(is_same(token,b.automation.start_lifetime) and refusal_state(b)==before,"Busy refusal preserves complete scope/settings/receipt/native/cache/disk")
  if failures:return false
 check(not b.automation.start_pet_training("missing",120,{"compact":false}),"Direct pet API refuses actual active battle")
 if failures:return false
 check(is_same(token,b.automation.start_lifetime) and refusal_state(b)==before,"Direct busy pet refusal leaves original battle scope unchanged")
 if failures:return false
 # Real original solo battle has no mirror allies; do not fabricate actors.
 if b.battle.snapshot().get("allies",[]).is_empty():
  check(not b.automation.start({"kind":"battle","settings":{"preset":"train_pet"}}).get("ok",true),"Actual no-mirror train_pet request refuses before settings install")
  if failures:return false
  check(is_same(token,b.automation.start_lifetime) and refusal_state(b)==before,"No-mirror refusal preserves original active scope")
  if failures:return false
  # Explicit candidate-settings fixture for the direct API; actors/proof remain real.
  var original:Dictionary=b.automation.settings.duplicate(true)
  b.automation.settings.preset="train_pet"
  var direct_before:Dictionary=refusal_state(b)
  var accepted:bool=b.automation.start_training()
  var direct_after:Dictionary=refusal_state(b)
  b.automation.settings=original
  check(not accepted and is_same(token,b.automation.start_lifetime) and direct_after==direct_before,"Direct training refusal installs neither token nor scope; only test candidate preset restored")
  if failures:return false
  check(refusal_state(b)==before,"Original settings restored after isolated direct-API preflight fixture")
  if failures:return false
 return true
func refused_inactive_capture(b)->bool:
 var token=b.automation.start_lifetime
 var before:Dictionary=refusal_state(b)
 check(not b.battle.snapshot().active,"Original battle actually completed before capture refusal")
 if failures:return false
 check(not b.automation.start({"kind":"capture_battle","speed":1,"target":0,"settings":{"compact":false}}).get("ok",true) and not b.automation.start_capture_battle(0),"Both capture entry points reject actual inactive battle")
 if failures:return false
 check(is_same(token,b.automation.start_lifetime) and refusal_state(b)==before,"Inactive capture refusal cannot mutate token/settings/scope/disk")
 return failures==0
func run()->void:
 for mode in ["stop","detach","suspend"]:
  var b=CountedBackend.new();var time:Array=[1000]
  if not real_battle(b,"user://loot-battle-cancel-"+mode+".json",time):b.free();quit(1);return
  if not refused_starts(b):b.free();quit(1);return
  var fields:int=b.field_calls;var receipt:Dictionary=b.session._pending.quest_loot_receipt.duplicate(true)
  var token=b.automation.start_lifetime
  if mode=="stop":b.quest_auto.stop(b,"Internal active receipt cancellation")
  elif mode=="detach":b.quest_auto.detach(b,71)
  else:b.quest_auto.suspend(b)
  check(b.automation.running and is_same(token,b.automation.start_lifetime) and b.battle_open and b.session._pending.quest_loot_receipt==receipt and not b.quest_loot.frozen,"Cancel preserves only original battle and active timing")
  if failures:b.free();quit(1);return
  check(not b.quest_loot.attempt_once(b).get("ok",true),"Cancelled receipt cannot start another attempt")
  if failures:b.free();quit(1);return
  b.quest_auto.tick(b,0.5)
  if not drive_original(b,time):b.free();quit(1);return
  var entry:Dictionary=b.session._profile.quest_loot.entries[KEY]
  check(not b.battle_open and b.session._pending.is_empty() and b.battle_state.get("settled",false) and entry.saved_battles==1 and entry.new_items==0 and not entry.open_span,"Original cancelled battle settles once with no fabricated target drop")
  if failures:b.free();quit(1);return
  check(not b.quest_auto.running and b.field_calls==fields and not b.quest_loot.attempt_once(b).get("ok",true),"Success never resurrects old runner or opens second battle")
  if failures:b.free();quit(1);return
  if not complete_disk(b):b.free();quit(1);return
  if not refused_inactive_capture(b):b.free();quit(1);return
  # Retain the real production scope copy, not any strong owner frame. Free only
  # the original host as before; never clear production scope/ticket in teardown.
  var retained_scope:Dictionary=b.automation._loot_frame()
  var weak_owners:Dictionary={"session":weakref(b.session),"battle":weakref(b.battle),"automation":weakref(b.automation),"runner":weakref(b.quest_auto),"timer":weakref(b.quest_loot)}
  for owner_key in weak_owners:
   check(retained_scope.get(owner_key) is WeakRef and preload("res://server/quest_auto_loot.gd").scope_owner_matches(retained_scope,owner_key,weak_owners[owner_key].get_ref()),"Stored scope copy resolves exact live owner before host retirement")
   if failures:b.free();quit(1);return
  b.free()
  var replacement:RefCounted=RefCounted.new()
  for owner_key in weak_owners:
   check(weak_owners[owner_key].get_ref()==null and retained_scope[owner_key].get_ref()==null,"Real host retirement releases every scope owner despite retained scope copy")
   if failures:quit(1);return
   check(not preload("res://server/quest_auto_loot.gd").scope_owner_matches(retained_scope,owner_key,replacement),"Expired original weak owner cannot authorize a replacement object")
   if failures:quit(1);return
 print("QUEST AUTO LOOT BATTLE CANCEL: 0 failures; 3 internal original-pool fixtures")
 quit(0)
