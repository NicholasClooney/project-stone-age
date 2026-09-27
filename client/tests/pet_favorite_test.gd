extends SceneTree
const Session=preload("res://server/game_session.gd")
const Compare=preload("res://scripts/pet_comparison.gd")
var failures:=0
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	var session=Session.new();session.grant_starter_pets()
	var pet_id:String=session.snapshot().pets[0].pet_id
	check(not session.snapshot().pets[0].favorite,"new pets default to unstarred")
	check(session.set_pet_favorite(pet_id,true) and session.store_pet(0),"favorite toggles by identity and transfers into warehouse")
	check(session.snapshot().pet_storage[0].favorite and session.retrieve_pet_by_id(pet_id),"retrieval retains favorite and stable identity")
	var path:="/tmp/stone-age-favorite-test.json"
	var restored=Session.new()
	check(session.save_game(path) and restored.load_game(path) and restored.snapshot().pets.back().favorite,"favorite survives save reload")
	var old:Dictionary=session.snapshot().duplicate(true)
	for pet in old.pets:pet.erase("favorite")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
	check(restored.load_game(path) and not restored.snapshot().pets.back().favorite,"existing saves without favorite migrate to false")
	old.pets[0].favorite="yes"
	check(not session._valid_profile(old),"malformed favorite type rejected")
	check(not session.set_pet_favorite("pet-missing",true),"unknown stable identity cannot favorite another pet")
	for name in [path,path+".bak"]:
		if FileAccess.file_exists(name):DirAccess.remove_absolute(name)
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets()
	var source:Dictionary=game.session.snapshot().pets[0]
	game.session._profile.pet_storage=[]
	for i in range(22):
		var pet:Dictionary=source.duplicate(true);pet.pet_id="pet-%d"%(100+i);pet.favorite=false
		game.session._profile.pet_storage.append(pet)
	game.session._profile.next_pet_id=122
	game.session.set_pet_favorite("pet-121",true)
	var profile:Dictionary=game.session.snapshot()
	var sorted:=Compare.storage_rows(profile)
	check(sorted[0].pet.pet_id=="pet-121" and sorted[1].pet.pet_id=="pet-100" and sorted[2].pet.pet_id=="pet-101","warehouse stars sort first and equal-priority rows retain original order")
	check(profile.pet_storage[0].pet_id=="pet-100","display sorting leaves authoritative indices untouched")
	var rows:=Compare.rows(profile,source)
	check(rows[0].location=="pets" and rows[1].pet.pet_id=="pet-121","comparison retains carried first and favors starred warehouse pets")
	var menu=game.adventure_menu;menu.open_menu("pets");menu.pet_storage_open=true;menu.rebuild();await process_frame
	var overlay=menu.panel.get_node("PetStoragePanel")
	var first=overlay.find_child("StorageRow_pet-121",true,false)
	check(first!=null and first.get_index()==0,"star from second page moves to first visible row")
	check(first.get_combined_minimum_size().x<=650,"warehouse row and all actions fit scroll width")
	var toggle=overlay.find_child("StorageFavorite_pet-121",true,false);toggle.pressed.emit();await process_frame
	check(not game.session.snapshot().pet_storage[21].favorite,"warehouse unstar acts on correct sorted identity")
	menu.pet_storage_page=1;menu.rebuild();await process_frame
	overlay=menu.panel.get_node("PetStoragePanel")
	check(overlay.find_child("StorageRow_pet-121",true,false)!=null,"unstarred pet returns to original page order")
	overlay.find_child("StorageFavorite_pet-121",true,false).pressed.emit();await process_frame
	menu.pet_storage_page=0;menu.rebuild();await process_frame
	overlay=menu.panel.get_node("PetStoragePanel")
	var retrieve=overlay.find_child("RetrievePet_21",true,false)
	retrieve.pressed.emit();await process_frame
	check(game.session.snapshot().pets.back().pet_id=="pet-121" and game.session.snapshot().pets.back().favorite,"retrieve from sorted row chooses exact stable ID and retains star")
	check(game.session.snapshot().pet_storage[0].pet_id=="pet-100" and game.session.snapshot().pet_storage.size()==21,"retrieve does not remove visual-position neighbor")
	check(not game.session.retrieve_pet_by_id("pet-121"),"stale repeated retrieval cannot retrieve a different pet")
	game.close_adventure_menu();game.music.stop();game.effect.stop();await create_timer(0.3).timeout
	game.process_mode=Node.PROCESS_MODE_DISABLED;game.queue_free();await process_frame;await process_frame
	print("PET FAVORITES: %d failures"%failures);quit(1 if failures else 0)
