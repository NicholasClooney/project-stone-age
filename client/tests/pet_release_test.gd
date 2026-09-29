extends SceneTree
var failures:=0
const TEMP_SAVE:="user://pet-release-test.json"
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")
func ids(list:Array)->Array:return list.map(func(pet):return str(pet.pet_id))
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets()
	var session=game.session
	var source:Dictionary=session.snapshot().pets.filter(func(p):return p.species=="blue_dragon")[0]
	# Six carried blue dragons and 25 stored, sums rising with the number.
	session._profile.pets=[];session._profile.pet_storage=[]
	for i in range(31):
		var pet:Dictionary=source.duplicate(true);pet.pet_id="pet-%d"%(500+i);pet.species="original_92";pet.favorite=false
		pet.attack=200+i;pet.defence=150;pet.speed=100
		if i<6:session._profile.pets.append(pet)
		else:session._profile.pet_storage.append(pet)
	session._profile.next_pet_id=600
	session._profile.pets[1].favorite=true
	session._profile.active_pet=2;session._profile.ride_pet=4
	# Server rules.
	var result:Dictionary=session.release_pets(["pet-500","pet-501","pet-502","pet-504","pet-503","pet-510","pet-missing"])
	check(int(result.released)==3,"releases the unprotected carried and stored pets")
	var reasons:={}
	for item in result.skipped:reasons[item.id]=item.reason
	check(reasons.get("pet-501")=="收藏" and reasons.get("pet-502")=="出战中" and reasons.get("pet-504")=="骑乘中" and reasons.get("pet-missing")=="找不到","favorite, active, mount and unknown IDs are skipped with reasons")
	var carried:Array=ids(session._profile.pets)
	check(carried==["pet-501","pet-502","pet-504","pet-505"] and not "pet-510" in ids(session._profile.pet_storage),"released pets leave party and warehouse")
	check(session._profile.pets[session._profile.active_pet].pet_id=="pet-502" and session._profile.pets[session._profile.ride_pet].pet_id=="pet-504","active and mount indices follow their pets after removal")
	session._pending={"battle":"x"}
	var refused:Dictionary=session.release_pets(["pet-505"])
	check(int(refused.released)==0 and not session.last_error.is_empty() and "pet-505" in ids(session._profile.pets),"release is refused entirely during a battle")
	session._pending={}
	# Backup through the game layer with a temporary save path.
	game.save_path=TEMP_SAVE;game.profile_persistence=true;game.checkpoint()
	var released:Dictionary=game.release_pets(["pet-505"])
	check(int(released.released)==1 and str(released.backup).begins_with("user://pet-release-test.before-release-") and FileAccess.file_exists(str(released.backup)),"release writes a timestamped backup of the save first")
	var backup_text:=FileAccess.get_file_as_string(str(released.backup))
	check(backup_text.contains("pet-505") and not FileAccess.get_file_as_string(TEMP_SAVE).contains("\"pet-505\""),"backup keeps the released pet while the saved profile drops it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(released.backup)));DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	for suffix in [".bak",".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE+suffix))
	game.profile_persistence=false
	# UI: selection, pages, threshold and two-step confirm.
	var menu=game.adventure_menu
	check(menu.open_pet_comparison("pet-520"),"comparison opens on a warehouse blue dragon");await process_frame
	var overlay=menu.panel.get_node("PetComparisonPanel")
	check(overlay.find_child("CompareSelect_pet-520",true,false)!=null,"each row has a selection checkbox")
	overlay.find_child("CompareSelectPage",true,false).pressed.emit();await process_frame
	var first_page:int=menu.pet_release_selected.size()
	check(first_page==20,"select page takes the 20 rows on this page")
	menu.pet_compare_page=1;menu.rebuild();await process_frame
	overlay=menu.panel.get_node("PetComparisonPanel")
	check(menu.pet_release_selected.size()==20 and overlay.find_child("CompareSelectedCount",true,false).text.contains("20"),"selection persists across pages and is counted")
	menu.pet_compare_order=["speed"];menu.rebuild();await process_frame
	check(menu.pet_release_selected.size()==20,"selection survives re-sorting")
	overlay=menu.panel.get_node("PetComparisonPanel")
	overlay.find_child("CompareClearSelection",true,false).pressed.emit();await process_frame
	check(menu.pet_release_selected.is_empty(),"clear empties the selection")
	overlay=menu.panel.get_node("PetComparisonPanel")
	check(overlay.find_child("CompareRelease",true,false).disabled,"release is disabled with nothing selected")
	var metric=overlay.find_child("CompareThresholdMetric",true,false);metric.select(1);metric.item_selected.emit(1)
	overlay.find_child("CompareThresholdValue",true,false).value=212
	overlay.find_child("CompareThresholdSelect",true,false).pressed.emit();await process_frame
	var picked:Array=menu.pet_release_selected.keys();picked.sort()
	check(picked==["pet-506","pet-507","pet-508","pet-509","pet-511"],"attack < 212 selects matching pets but not favorite, active or mount")
	overlay=menu.panel.get_node("PetComparisonPanel")
	overlay.find_child("CompareRelease",true,false).pressed.emit();await process_frame
	overlay=menu.panel.get_node("PetComparisonPanel")
	check(overlay.find_child("CompareReleaseConfirm",true,false)!=null and session._profile.pet_storage.size()==24,"first click only asks for confirmation")
	overlay.find_child("CompareReleaseCancel",true,false).pressed.emit();await process_frame
	overlay=menu.panel.get_node("PetComparisonPanel")
	check(overlay.find_child("CompareRelease",true,false)!=null and menu.pet_release_selected.size()==5,"cancel keeps the selection without releasing")
	overlay.find_child("CompareRelease",true,false).pressed.emit();await process_frame
	menu.panel.get_node("PetComparisonPanel").find_child("CompareReleaseConfirm",true,false).pressed.emit();await process_frame
	var remaining:Array=ids(session._profile.pet_storage)
	check(not "pet-506" in remaining and not "pet-511" in remaining and remaining.size()==19 and menu.pet_release_selected.is_empty(),"confirm releases the selection and clears it")
	check(menu.feedback.contains("已放生 5 只"),"feedback reports the released count")
	overlay=menu.panel.get_node("PetComparisonPanel")
	var bar=overlay.find_child("CompareThresholdBar",true,false)
	check(Rect2(Vector2.ZERO,overlay.size).encloses(Rect2(bar.position,bar.get_combined_minimum_size())),"release controls fit inside the comparison overlay")
	var scroll:ScrollContainer=overlay.find_children("*","ScrollContainer",false,false)[0]
	check(scroll.position.y+scroll.size.y<=overlay.find_child("CompareReleaseBar",true,false).position.y,"pet list ends above the release controls")
	menu.pet_release_selected["pet-520"]=true
	for child in overlay.get_children():
		if child is Button and child.text=="关闭":child.pressed.emit()
	await process_frame
	check(menu.pet_release_selected.is_empty(),"closing the comparison clears the selection")
	game.close_adventure_menu();game.music.stop();game.effect.stop();await create_timer(0.3).timeout;game.queue_free();await process_frame;await process_frame
	print("PET RELEASE: %d failures"%failures);quit(1 if failures else 0)
