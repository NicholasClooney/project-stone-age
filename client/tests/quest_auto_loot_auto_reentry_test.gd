extends "res://tests/quest_auto_loot_battle_cancel_test.gd"
func auto_values(b)->Dictionary:
 return {"turns":b.automation.turns,"battles":b.automation.battles,"xp":b.automation.earned_xp,"pet_xp":b.automation.earned_pet_xp,"text":b.automation.turn_text,"reason":b.automation.stop_reason,"running":b.automation.running,"settings":b.automation.settings.duplicate(true)}
func run()->void:
 for mode in ["battle_command","close_publish","auto_status","stop_tail","freeze_publish","start_publish","handoff_publish"]:
  var b=CountedBackend.new();var time:Array=[1000]
  if not real_battle(b,"user://loot-auto-reentry-"+mode+".json",time):b.free();quit(1);return
  var original_token=b.automation.start_lifetime
  var original_scope:Dictionary=b.automation._loot_frame()
  check(not b.automation.start({"kind":"battle","settings":{"select_troops":1}}).get("ok",true) and is_same(original_token,b.automation.start_lifetime) and b.automation._loot_current(original_scope),"Invalid actual start fails without changing valid old lifecycle")
  if failures:b.free();quit(1);return
  if mode=="freeze_publish":
   check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own real failure blocker")
   if failures:b.free();quit(1);return
  var fired:Array=[false];var expected:Array=[];var newer_token:Array=[];var saved:Array=[];var extra_stopped:Array=[0]
  b.event.connect(func(event):
   if fired[0]:
    if event.get("type")=="auto_event" and event.get("detail",{}).get("kind")=="battle_stopped":extra_stopped[0]+=1
    return
   var trigger:bool=false
   match mode:
    "start_publish","handoff_publish":trigger=event.get("type")=="profile"
    "battle_command":trigger=event.get("type")=="battle_turn"
    "close_publish":trigger=event.get("type")=="battle_closed"
    "auto_status":trigger=event.get("type")=="auto_status" and not b.battle_open
    "stop_tail":trigger=event.get("type")=="auto_status" and not b.automation.running
    "freeze_publish":trigger=event.get("type")=="auto_status" and b.quest_loot.storage_paused and not b.battle_state.get("settled",true)
   if not trigger:return
   fired[0]=true
   if mode=="freeze_publish":
    check(b.battle_open and not b.automation.running and not b.automation.compact_active and b.session._pending.has("quest_loot_receipt"),"Freeze publication retains actual repair obligation before successor")
    if failures:return
    check(not b.automation.start({"kind":"battle"}).get("ok",true) and is_same(original_token,b.automation.start_lifetime),"Unsettled real receipt rejects start without replacing old repair token")
    if failures:return
    check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Remove own blocker after observing actual frozen failure")
    if failures:return
    var actual_id:String=str(b.session._pending.battle_id)
    check(b.handle({"type":"battle_close","battle_id":actual_id}).get("ok",false),"Callback repairs actual battle via original command before new run")
    if failures:return
   b.quest_auto.identity.begin();b.quest_auto.identity.select_step(KEY)
   b.quest_auto.running=true;b.quest_auto.phase="successor";b.quest_auto.navigation.key="successor-nav"
   var started:Dictionary=b.automation.start({"kind":"battle","settings":{"preset":"attack","compact":true}})
   var token_changed:bool=not is_same(original_token,b.automation.start_lifetime)
   print("E3B SUCCESSOR mode=",mode," reply=",started," token_changed=",token_changed)
   check(started.get("ok",false),"Actual same-object successor start API accepts legitimate new request")
   if failures:return
   check(token_changed,"Accepted actual successor API creates independent token")
   if failures:return
   newer_token.append(b.automation.start_lifetime);expected.append(auto_values(b))
   if b.session._pending.is_empty():
    b.session._profile.player.gold+=9
    check(b.save(),"Successor actual complete save")
    if failures:return
    saved.append(b.last_saved_payload)
  )
  if mode=="start_publish":
   check(not b.automation.start({"kind":"battle","settings":{"preset":"attack","compact":true}},original_scope).get("ok",true),"Old internal start reports its own lost lifecycle, not successor success")
  elif mode=="handoff_publish":b.quest_auto.handoff(b,"Old handoff tail")
  elif mode=="stop_tail":b.automation.stop("Old original stop tail")
  else:
   for tick in range(100):
    if fired[0] or failures:break
    time[0]+=500;b.automation.tick_battle(0.5)
  if failures:b.free();quit(1);return
  check(fired[0] and newer_token.size()==1 and is_same(b.automation.start_lifetime,newer_token[0]) and auto_values(b)==expected[0],"Old call/tick never mutates successor stats/text/running/settings")
  if failures:b.free();quit(1);return
  check(b.quest_auto.phase=="successor" and b.quest_auto.navigation.key=="successor-nav" and extra_stopped[0]==0,"Old completion/failure/stop tail never handoffs or stops successor")
  if failures:b.free();quit(1);return
  if not saved.is_empty():
   check(b.last_saved_payload==saved[0] and FileAccess.get_file_as_string(b.save_path)==saved[0],"Old return never overwrites newer full saved payload")
   if failures:b.free();quit(1);return
  b.free()
 print("QUEST AUTO LOOT AUTO REENTRY: 0 failures; 7 real API callback fixtures")
 quit(0)
