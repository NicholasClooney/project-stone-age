extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,message:String):
 if not ok:failures+=1;push_error(message)
 else:print("PASS: ",message)
func run():
 var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
 game.session.grant_starter_pets()
 var menu=game.adventure_menu;menu.open_menu("pets");await process_frame
 var frame:=Rect2(288,0,256,432)
 for name in ["PetCompare","PetStorage","PetGrowthToggle","PetMount","StarterPets"]:
  check(frame.encloses(menu.panel.get_node(name).get_rect()),"collection frame contains "+name)
 menu.pet_category="人龙";menu.pet_page=999;menu.pet_view="list";menu.rebuild();await process_frame
 check(menu.pet_page==0,"stale category page clamps before rows")
 var expected=menu.filtered_pet_indices(game.session.snapshot()).size()
 check(menu.panel.find_children("PetRow*","Button",false,false).size()==mini(5,expected),"native filtered pet list retains visible rows")
 menu.pet_growth_open=true;menu.rebuild();await process_frame
 check(menu.panel.get_node("PetGrowthHeading").get_global_rect().end.y<menu.size.y-40,"growth detail stays above bottom HUD")
 check(menu.panel.get_node("PetGrowthHeading").position.x>=560,"growth uses separate framed right column")
 menu.pet_storage_open=true;menu.pet_storage_target_id=str(game.session.snapshot().pets.back().pet_id);menu.rebuild();await process_frame
 check(menu.panel.get_child_count()==1 and menu.panel.has_node("PetStoragePanel"),"storage has no underlying collection labels or clickable buttons")
 var storage=menu.panel.get_node("PetStoragePanel")
 check(storage.mouse_filter==Control.MOUSE_FILTER_STOP and storage.z_index>1,"storage modal blocks input and draws above native labels")
 check(storage.size.y<300,"empty warehouse uses compact height")
 check(Rect2(Vector2.ZERO,menu.size).encloses(storage.get_global_rect()),"warehouse fits viewport")
 storage.get_node("StoreSelectedPet").pressed.emit();await process_frame
 var remaining:int=game.session.snapshot().pets.size()
 check(menu.panel.get_node("PetStoragePanel/StoreSelectedPet").disabled,"stored stable target cannot silently become adjacent pet")
 check(game.session.snapshot().pet_storage.back().pet_id==menu.pet_storage_target_id,"warehouse stores the explicitly selected stable identity")
 menu.pet_storage_open=false;menu.pet_compare_open=false;menu.open_menu("pets")
 var pet=game.session.snapshot().pets[0];menu.open_pet_comparison(pet.pet_id);await process_frame
 check(menu.panel.get_child_count()==1 and menu.panel.has_node("PetComparisonPanel"),"comparison has no underlay text or controls to bleed through")
 var overlay=menu.panel.get_node("PetComparisonPanel")
 check(overlay.mouse_filter==Control.MOUSE_FILTER_STOP and overlay.z_index>1,"comparison independently blocks pointer input")
 check(Rect2(Vector2.ZERO,menu.size).encloses(overlay.get_global_rect()),"comparison fits viewport")
 game.session._profile.pets[0].level=120;menu.rebuild();await process_frame
 var row=menu.panel.find_child("CompareRow_pets_0",true,false)
 check(row!=null and not row.text.contains("\n120级 血"),"max-level row does not duplicate current stats as forecast")
 menu.pet_compare_open=false;menu.pet_view="list";menu.rebuild();await process_frame
 check(menu.panel.find_children("PetRow*","Button",false,false).size()>0,"native pet rows return after helper closes")
 game.close_adventure_menu();game.music.stop();game.effect.stop();await create_timer(.3).timeout;game.queue_free();await process_frame;await process_frame;quit(1 if failures else 0)
