extends SceneTree
const Compare=preload("res://scripts/pet_comparison.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,message:String):
 if not ok:failures+=1;push_error(message)
 else:print("PASS: ",message)
func run():
 var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
 game.session.grant_starter_pets()
 var profile:Dictionary=game.session.snapshot();var source:Dictionary=profile.pets.filter(func(p):return p.species=="blue_dragon")[0]
 var twin:Dictionary=source.duplicate(true);twin.species="original_92";twin.pet_id="pet-999";twin.name=source.name;twin.growth_weights=[29,38,18,22];twin.attack=source.attack+1
 profile.pet_storage=[twin]
 var before:=profile.duplicate(true)
 var rows:=Compare.rows(profile,source)
 check(rows.size()==2,"blue starter and original92 same-species aliases include warehouse")
 check(rows[0].location=="pets" and rows[1].location=="pet_storage","carried group precedes higher-stat stored pet")
 check(profile==before,"sorting never mutates authoritative order or pets")
 check(Compare.expected(source)==preload("res://scripts/pet_growth.gd").forecast(source).expected,"lightweight projection matches full forecast exactly")
 var large:=profile.duplicate(true);large.pet_storage=[]
 for i in range(300):
  var clone:=twin.duplicate(true);clone.pet_id="pet-%d"%(1000+i);large.pet_storage.append(clone)
 var started:=Time.get_ticks_usec();var large_rows:=Compare.rows(large,source,"speed",true)
 check(large_rows.size()==301,"large warehouse comparison retains every same-species pet")
 print("300-pet comparison data ms: ",(Time.get_ticks_usec()-started)/1000.0)
 check(Compare.quality(twin).full and Compare.quality(twin).total==8,"full innate grade uses actual weights")
 game.session._profile.pet_storage=[twin];game.session._profile.next_pet_id=1000
 var menu=game.adventure_menu
 check(menu.open_pet_comparison("pet-999"),"stable ID opens warehouse comparison")
 await process_frame
 check(menu.panel.has_node("PetComparisonPanel"),"comparison panel opens without requiring carried selection")
 var overlay=menu.panel.get_node("PetComparisonPanel")
 check(overlay.get_node("ComparePinned_选中").text.contains("pet-999"),"selected stable ID remains pinned independent of page")
 check(overlay.has_node("ComparePinned_当前分组首位"),"sorted leader has pinned comparison summary")
 check(not menu.continue_comparison_hunt(twin),"continue hunt rejects unavailable same species without wildcard fallback")
 overlay=menu.panel.get_node("PetComparisonPanel")
 check(overlay.find_children("CompareTransfer_*","Button",true,false).size()==2,"each row exposes location action")
 var transfer=overlay.find_child("CompareTransfer_pet-999",true,false);transfer.pressed.emit();await process_frame
 check(game.session.snapshot().pet_storage.is_empty(),"comparison retrieves warehouse pet")
 check(game.session.snapshot().pets.back().pet_id=="pet-999","retrieval preserves stable ID")
 menu.panel.find_child("CompareDeploy_pet-999",true,false).pressed.emit();await process_frame
 check(game.session.snapshot().pets[game.session.snapshot().active_pet].pet_id=="pet-999","comparison deploys chosen stable identity")
 check(not menu.panel.find_child("CompareTransfer_pet-999",true,false).disabled,"active pet can be stored with automatic withdrawal")
 menu.panel.find_child("CompareTransfer_pet-999",true,false).pressed.emit();await process_frame
 check(game.session.snapshot().active_pet==-1 and game.session.snapshot().pet_storage.back().pet_id=="pet-999","comparison stores active pet and automatically withdraws it")
 menu.panel.find_child("CompareTransfer_pet-999",true,false).pressed.emit();await process_frame
 menu.panel.find_child("CompareDeploy_pet-999",true,false).pressed.emit();await process_frame
 check(menu.panel.find_child("CompareDeploy_pet-999",true,false).text=="撤回","active row offers withdrawal inside hub")
 menu.panel.find_child("CompareDeploy_pet-999",true,false).pressed.emit();await process_frame
 check(game.session.snapshot().active_pet==-1,"hub withdrawal clears battle selection")
 game.session._profile.ride_pet=game.session.snapshot().pets.size()-1;menu.rebuild()
 menu.panel.find_child("CompareDismount_pet-999",true,false).pressed.emit();await process_frame
 check(game.session.snapshot().ride_pet==-1,"hub dismount clears riding selection before storage")
 menu.panel.find_child("CompareTransfer_pet-999",true,false).pressed.emit();await process_frame
 check(game.session.snapshot().pet_storage.size()==1,"comparison stores withdrawn pet")
 menu.panel.find_child("CompareTransfer_pet-999",true,false).pressed.emit();await process_frame
 menu.pet_compare_open=false;menu.selected_pet=game.session.snapshot().pets.size()-1;menu.pet_growth_open=true;menu.open_menu("pets")
 check(menu.panel.has_node("PetInnateQuality"),"growth screen displays separate innate quality")
 game.session._profile.pets[menu.selected_pet].level=120;menu.rebuild()
 check(menu.panel.get_node("PetGrowthHeading").text.contains("当前能力"),"max-level title shows current results")
 check(not menu.panel.get_children().any(func(n):return n is Label and n.text=="约90%范围"),"max-level view omits zero-width uncertainty column")
 game.close_adventure_menu();game.music.stop();game.effect.stop();await create_timer(0.3).timeout;game.queue_free();await process_frame;await process_frame;quit(1 if failures else 0)
