extends "res://tests/munde_cave_route_test.gd"
## Original exchanges use the actual catalog and a genuinely earned Munde route.
func run() -> void:
 var b=setup()
 check(b.original_quests.branch_for(b.original_quests.npc_by_id(KOLK),b.session.snapshot()).is_empty(),"high level without adult completion cannot request9")
 Rules.set_flag(b.session._profile,"ended",4,true) # Existing adult completion prerequisite.
 var r:=talk(b,KOLK)
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"request9 failed save changes no profile")
 b.save_path=""
 check(trade(b,KOLK).ok and Rules.flag(b.session.snapshot(),"now",9),"original Kolk request9")
 check(trade(b,KATAN).ok and trade(b,HOTOR).ok,"original two-village requests")
 check(Rules.flag(b.session.snapshot(),"now",10) and Rules.flag(b.session.snapshot(),"now",11),"both source subquests started")
 var guard_talk:=source_talk(b,guards[0])
 b.encounter_rng.seed=seed_for(b,0) # Keep exact exchange inventory assertions independent of rare combat loot.
 var started:=choose(b,guard_talk,"yes")
 check(started.get("ok",false) and b.battle_open,"exchange fixture walks original stairs and starts source guard: "+str(started.get("reason","")))
 if not b.battle_open:b.free();quit(1);return
 fight(b);check(b.handle({"type":"battle_close"}).ok,"real guard victory establishes reward access")
 r=choose(b,talk(b,CHIEF),"yes");before=b.session.snapshot();b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"two-stone grant rolls back together")
 b.save_path=""
 check(trade(b,CHIEF).ok and b.session.snapshot().original_items==[2419,2420],"chief source gives both stones, not a fake battle drop")
 before=b.session.snapshot();talk(b,CHIEF)
 check(b.session.snapshot().original_items==before.original_items,"already held stones cannot be claimed twice at the actual chief")
 before=b.session.snapshot()
 talk(b,HOTOR)
 check(b.session.snapshot().original_items==before.original_items and not Rules.flag(b.session.snapshot(),"ended",10),"first completion cannot deliver Hotor stone before Katan")
 var charm:=int(b.session.snapshot().player.charm)
 r=choose(b,talk(b,KATAN),"yes");before=b.session.snapshot();b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"first stone and charm rollback on failed save")
 b.save_path=""
 check(trade(b,KATAN).ok and Rules.flag(b.session.snapshot(),"ended",11) and not Rules.flag(b.session.snapshot(),"ended",12),"Katan first grants1052 and END11 only")
 check(1052 in b.session.snapshot().original_items and int(b.session.snapshot().player.charm)==charm+1,"original Katan armour and one charm")
 r=choose(b,talk(b,HOTOR),"yes");before=b.session.snapshot();b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"second stone and completion12 rollback together")
 b.save_path=""
 check(trade(b,HOTOR).ok and Rules.flag(b.session.snapshot(),"ended",10) and Rules.flag(b.session.snapshot(),"ended",12),"Hotor second writes10 and12")
 check(2421 in b.session.snapshot().original_items and not Rules.flag(b.session.snapshot(),"ended",9),"magatama is not final Kolk completion")
 r=choose(b,talk(b,KOLK),"yes");before=b.session.snapshot();b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"final reward1357 rolls back with END9")
 b.save_path=""
 r=choose(b,talk(b,KOLK),"yes")
 check(choose(b,r,"ok").ok and Rules.flag(b.session.snapshot(),"ended",9) and b.session.snapshot().original_items.count(1357)==1,"only final Kolk return completes9 with1357")
 check(not choose(b,r,"ok").ok,"final reward token is single use")
 before=b.session.snapshot();talk(b,KOLK);talk(b,KATAN);talk(b,HOTOR)
 check(b.session.snapshot().original_items==before.original_items and b.session.snapshot().original_events==before.original_events,"completed source exchanges neither reissue stones nor repeat rewards")
 # Preserve the completed-chain chief revisit case with a second real route,
 # rather than granting a receipt after returning from the three villages.
 guard_talk=source_talk(b,guards[0]);b.encounter_rng.seed=seed_for(b,0)
 check(choose(b,guard_talk,"yes").ok and b.battle_open,"completed chain re-enters original guard route")
 if not b.battle_open:b.free();quit(1);return
 fight(b);check(b.handle({"type":"battle_close"}).ok,"completed chain earns a new legitimate chief approach")
 before=b.session.snapshot();talk(b,CHIEF)
 check(b.session.snapshot().original_items==before.original_items and b.session.snapshot().original_events==before.original_events,"completed chief conversation cannot reissue stones or restart rewards")
 b.free()
 print("MUNDE CAVE EXCHANGES: %d failures"%failures)
 quit(1 if failures else 0)
