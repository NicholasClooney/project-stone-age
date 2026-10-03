extends SceneTree
const Session=preload("res://server/game_session.gd")
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():
 var session=Session.new();session.grant_starter_pets()
 var before:Dictionary=session.snapshot()
 check(before.pet_storage.is_empty() and before.pets[0].pet_id!=before.pets[1].pet_id,"new pets receive distinct stable identities")
 session.select_pet(1);session._profile.ride_pet=2
 check(not session.store_pet(2),"mounted pet remains protected")
 var original:Dictionary=session.snapshot().pets[0].duplicate(true)
 check(session.store_pet(0),"idle pet can be stored")
 var stored:Dictionary=session.snapshot()
 check(stored.pet_storage[0]==original and stored.pets.size()==2,"storage preserves entire individual and frees carried slot")
 check(stored.active_pet==0 and stored.ride_pet==1 and stored.pets[0].pet_id==before.pets[1].pet_id,"carried removal preserves active and riding identities")
 check(session.retrieve_pet(0) and session.snapshot().pets.back()==original,"retrieval preserves identity and every property")
 var count:int=session.snapshot().pets.size();session.grant_starter_pets()
 check(session.snapshot().pets.size()==count,"starter grant remains idempotent")
 session.select_pet(-1);session._profile.ride_pet=-1
 session.store_pet(0)
 count=session.snapshot().pets.size();session.grant_starter_pets()
 check(session.snapshot().pets.size()==count,"stored starters do not get duplicated by grant")
 var recalled=Session.new();recalled.grant_starter_pets();recalled.select_pet(1)
 recalled._profile.ride_pet=2
 var fighter:Dictionary=recalled.snapshot().pets[1].duplicate(true)
 check(recalled.store_pet(1),"out-of-battle active pet can be stored directly")
 var after_recall:Dictionary=recalled.snapshot()
 check(after_recall.active_pet==-1 and after_recall.pet_storage[0]==fighter,"storing active pet recalls it and preserves full individual")
 check(after_recall.ride_pet==1 and after_recall.pets[1].species=="red_rex","auto-recall preserves mounted pet identity after index shift")
 var recall_path:="user://stone-age-storage-recall-test.json"
 var recall_loaded=Session.new()
 check(recalled.save_game(recall_path) and recall_loaded.load_game(recall_path) and recall_loaded.snapshot()==after_recall,"auto-recalled active pet and warehouse survive save reload")
 for name in [recall_path,recall_path+".bak"]:
  if FileAccess.file_exists(name):DirAccess.remove_absolute(name)
 var path:="user://stone-age-storage-test.json"
 check(session.save_game(path),"storage saves successfully")
 var restored=Session.new()
 check(restored.load_game(path) and restored.snapshot()==session.snapshot(),"storage and stable IDs survive save/reload unchanged")
 var malformed:Dictionary=session.snapshot().duplicate(true)
 malformed.pet_storage[0].pet_id=malformed.pets[0].pet_id
 check(not session._valid_profile(malformed),"duplicate identities across carried/storage rejected")
 malformed=session.snapshot().duplicate(true);malformed.next_pet_id=1
 check(not session._valid_profile(malformed),"counter cannot reuse existing identity")
 malformed=session.snapshot().duplicate(true);malformed.pet_storage[0].hp=-1
 check(not session._valid_profile(malformed),"stored actors receive full save validation")
 var old:Dictionary=before.duplicate(true);old.version=2;old.erase("pet_storage");old.erase("next_pet_id")
 old.erase("rebirth");old.player.erase("transmigration") # Historical format predates v7.
 check(not session._valid_profile(old),"v2 pet profile with v6 warehouse fields is an invalid hybrid")
 for key in Session.ItemStorage.FIELDS:old.erase(key)
 for pet in old.pets:pet.erase("pet_id")
 var legacy:="user://stone-age-storage-legacy.json"
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(legacy+suffix)
 var file=FileAccess.open(legacy,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
 var migrated=Session.new();var again=Session.new()
 var loaded_legacy:bool=migrated.load_game(legacy) and again.load_game(legacy)
 check(loaded_legacy and migrated.snapshot()==again.snapshot(),"legacy IDs migrate deterministically without changing pet stats")
 if not loaded_legacy:quit(1);return
 var migrated_profile:Dictionary=migrated.snapshot()
 for i in range(before.pets.size()):
  check(migrated_profile.pets[i]==before.pets[i],"legacy migration preserves every pet field and deterministic UID %d"%i)
 check(migrated.save_game(legacy) and again.load_game(legacy) and again.snapshot()==migrated_profile,"legacy pet migration writes and reads back the complete profile")
 check(migrated.snapshot().pets[0].base_stats==before.pets[0].base_stats and migrated.snapshot().pets[0].growth_seed==before.pets[0].growth_seed,"legacy migration preserves actual individual growth")
 while session._profile.pets.size()<Session.PET_CAPACITY:
  var copy:Dictionary=original.duplicate(true);session._assign_pet_id(copy);session._profile.pets.append(copy)
 check(not session.retrieve_pet(0) and session.snapshot().pet_storage.size()==1,"full carried roster prevents retrieval without losing stored pet")
 session.select_pet(0);session.start_battle_config()
 check(not session.store_pet(0) and not session.retrieve_pet(0),"a battle locks storing its fighting pet, and a full party still cannot withdraw")
 check(session.store_pet(1) and session.snapshot().pets.size()==Session.PET_CAPACITY-1,"a pet outside the battle can still be stored")
 for name in [path,path+".bak",legacy,legacy+".bak",legacy+".tmp"]:
  if FileAccess.file_exists(name):DirAccess.remove_absolute(name)
 print("PET STORAGE: %d failures"%failures)
 quit(1 if failures else 0)
