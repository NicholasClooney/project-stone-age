extends "res://tests/lan_party_auto_test.gd"
## Real party battle, no replacement settings RPC and no change to party rules.
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Settings=preload("res://scripts/automation_settings.gd")
func disk(path:String)->Dictionary:
 return JSON.parse_string(FileAccess.get_file_as_string(path))
func other_fields(value:Dictionary)->String:
 var copy:Dictionary=value.duplicate(true)
 copy.erase("automation_settings")
 return JSON.stringify(copy)
func patch(server,peer:int,value:Dictionary)->Dictionary:
 return server.handle(peer,{"type":"set_automation_settings","settings":value})
func run()->void:
 seed(4101)
 dir="user://battle-settings-persistence-%d"%OS.get_process_id()
 remove_tree(dir);DirAccess.make_dir_recursive_absolute(dir)
 var made:=party_hub()
 var server=made[0]
 for peer in [2,3]:check(patch(server,peer,{"party":{"auto":true,"compact":true}}).ok,"Persist initial auto member")
 check(server.handle(4,{"type":"login","name":"Cid","pin":"3333"}).ok,"Second authenticated Cid device")
 check(start_run(server).ok,"Start actual party runner")
 check(drive(server,func():return server.backends.cid.battle_open),"Enter actual active party battle before changing settings")
 var b=server.backends.cid
 var entry:=entry_of(server,"cid")
 check(not b.session._pending.is_empty() and bool(entry.session.snapshot().active),"Active party pending is real")
 var baseline:Dictionary=disk(b.save_path)
 var pending:Dictionary=b.session._pending.duplicate(true)
 var live_before:Dictionary=b.session.snapshot()
 # Deliberately divergent unsaved fields test the write boundary. Battle state
 # and pending are real; these sentinels are restored before real settlement.
 b.session._profile.player.hp-=7
 b.session._profile.player.gold+=17
 b.session._profile.inventory.potion-=1
 b.session._profile.location.x+=1
 var live:Dictionary=b.session.snapshot()
 var changed:Dictionary=patch(server,3,{"party":{"auto":false,"compact":false},"quest":{"mode":"C","loot_minutes":47}})
 check(changed.ok and server.party_auto("cid").is_empty(),"Active-battle manual toggle succeeds immediately")
 var saved:Dictionary=disk(b.save_path)
 check(other_fields(saved)==other_fields(baseline),"Disk preserves every non-settings field of trusted saved baseline")
 check(other_fields(JSON.parse_string(JSON.stringify(b.session.snapshot())))==other_fields(JSON.parse_string(JSON.stringify(live))),"Write does not swap or normalize live battle profile")
 check(b.session._pending==pending,"Settings write preserves full pending battle")
 check(b.last_saved_payload==FileAccess.get_file_as_string(b.save_path),"last_saved_payload is exactly actual candidate bytes")
 check(b.last_saved_payload!=JSON.stringify(b.session.snapshot()),"Live unsaved battle profile is never marked saved")
 var loaded=Session.new()
 check(loaded.load_game(b.save_path) and not Settings.effective(loaded.automation_settings()).party.auto and Settings.effective(loaded.automation_settings()).quest.mode=="C","Fresh Session reload sees durable mixed preferences")
 check(not b.session.save_game(b.save_path),"Ordinary whole-profile battle save remains forbidden")
 var snapshot:Dictionary=b.session.snapshot()
 var payload:String=b.last_saved_payload
 DirAccess.make_dir_recursive_absolute(b.save_path+".tmp")
 var rejected:Dictionary=patch(server,4,{"party":{"auto":true},"quest":{"mode":"B"}})
 check(not rejected.ok and rejected.get("reason")=="save_failed","Real .tmp creation failure rejects whole mixed patch")
 check(b.session.snapshot()==snapshot and b.session._pending==pending and b.last_saved_payload==payload and FileAccess.get_file_as_string(b.save_path)==payload,"True disk failure leaves live/profile/pending/disk/receipt unchanged")
 DirAccess.remove_absolute(b.save_path+".tmp")
 for invalid in [{"party":{"auto":true},"quest":{"mode":"Z"}},{"party":{"auto":true},"quest":{"loot_minutes":0}},{"party":{"auto":"false"},"quest":{"mode":"A"}}]:
  check(not patch(server,4,invalid).ok and b.session.snapshot()==snapshot and b.last_saved_payload==payload,"Invalid mixed patch cannot partially apply")
 for invalid_baseline in ["","{}","not json"]:
  b.last_saved_payload=invalid_baseline
  check(not patch(server,4,{"party":{"auto":true}}).ok and b.session.snapshot()==snapshot and FileAccess.get_file_as_string(b.save_path)==payload,"Missing/corrupt trusted baseline refuses write")
 b.last_saved_payload=payload
 check(patch(server,4,{"party":{"auto":false,"compact":true},"quest":{"mode":"B","loot_minutes":61}}).ok,"Second device can atomically change full legal settings during same battle")
 check(not Settings.effective(b.session.automation_settings()).party.auto and Settings.effective(b.session.automation_settings()).party.compact and Settings.effective(b.session.automation_settings()).quest.mode=="B","Later mixed update retains manual control")
 check(other_fields(disk(b.save_path))==other_fields(baseline),"Second device still writes only baseline settings")
 # Remove only the explicit unsaved sentinels, retaining committed settings.
 b.session._profile.player=live_before.player.duplicate(true)
 b.session._profile.inventory=live_before.inventory.duplicate(true)
 b.session._profile.location=live_before.location.duplicate(true)
 server.party_battles.tick()
 check(entry.session.waiting_slots().has(2),"Real party now waits for manual Cid")
 check(send(server,3,"attack").ok and entry.session.has_command(2),"Cid submits a real current-turn command")
 check(patch(server,4,{"party":{"auto":true}}).ok and patch(server,3,{"party":{"auto":false}}).ok and entry.session.has_command(2),"Turning auto on/off never retracts an already submitted command")
 var battle_id:String=str(b.session._pending.battle_id)
 check(drive(server,func():return not bool(entry.session.snapshot().active),[3]),"Original party battle finishes and settles normally")
 check(b.session._pending.is_empty(),"Original settlement clears pending, not the settings writer")
 saved=disk(b.save_path)
 check(saved.completed_battles.has(battle_id) and int(saved.player.xp)>int(baseline.player.xp),"Subsequent full save persists actual battle reward and completion")
 check(b.last_saved_payload==FileAccess.get_file_as_string(b.save_path) and Settings.effective(saved.automation_settings).quest.mode=="B","Full settlement replaces baseline while preserving latest preferences")
 server.handle(1,{"type":"auto_stop"})
 await close(server)
 var memory=Backend.new()
 memory.session._pending={"fixture":"pending save guard without disk"}
 check(memory.handle({"type":"set_automation_settings","settings":{"party":{"auto":true}}}).ok and memory.session.automation_settings().party.auto,"No-disk backend retains original in-memory success semantics")
 memory.free()
 remove_tree(dir)
 print("BATTLE SETTINGS PERSISTENCE: %d failures"%failures)
 quit(1 if failures else 0)
