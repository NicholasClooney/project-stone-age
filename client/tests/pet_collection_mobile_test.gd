extends "res://tests/original_herb_use_ui_test.gd"
## Run with --visual-review through a muted offscreen renderer for pixel evidence.
var visual:=false
var menu
func shot(name:String)->void:
 if not visual:return
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/private/tmp/pet-collection-mobile/"+name+".png")
func find(name:String)->Control:return menu.panel.find_child(name,true,false)
func ready_layout()->void:
 await process_frame
 await process_frame
func reach(control:Control)->void:
 var scroll:ScrollContainer=find("PetCollectionScroll")
 scroll.ensure_control_visible(control)
 await ready_layout()
func mobile_checks()->void:
 var frame:Control=find("PetCollectionMobile")
 check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(frame.get_global_rect()),"collection frame stays inside phone")
 var scroll:ScrollContainer=find("PetCollectionScroll")
 check(scroll.get_h_scroll_bar().max_value<=scroll.size.x+1,"collection has no horizontal overflow")
 for control in frame.find_children("*","BaseButton",true,false):
  if control.is_visible_in_tree():check(control.size.y>=44 and control.size.x>=44,"touch target dimensions: "+str(control.name))
func run()->void:
 root.unfocusable=true;root.position=Vector2i(-10000,-10000);root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
 var world=load("res://scenes/main.tscn").instantiate()
 world.profile_persistence=false;world.viewer_prefs_path="user://pet-mobile.cfg";root.add_child(world)
 await ready_layout()
 world.session.grant_starter_pets()
 for i in range(6):
  var pet:Dictionary=world.session.snapshot().pets[0].duplicate(true)
  pet.pet_id="pet-mobile-%d"%i;pet.name="分页伙伴%d"%i
  world.session._profile.pets.append(pet)
 menu=world.adventure_menu;menu.open_menu("pets");await ready_layout()
 mobile_checks()
 await shot("390-list-top")
 await click(find("PetRow1"));await ready_layout()
 check(menu.selected_pet==1 and menu.pet_view=="detail","real row click selects original roster index")
 await shot("390-detail")
 await reach(find("PetRenameTouch"));await click(find("PetRenameTouch"));await ready_layout()
 menu.name_edit.text="手机改名伙伴"
 await reach(find("PetRenameConfirmTouch"));await click(find("PetRenameConfirmTouch"));await ready_layout()
 check(world.session.snapshot().pets[1].name=="手机改名伙伴" and not menu.pet_rename,"actual rename confirmation uses existing Session action")
 await reach(find("PetSkillsTouch"));await click(find("PetSkillsTouch"));await ready_layout()
 check(menu.pet_view=="skills","touch skills action opens original learned skills")
 await shot("390-skills")
 await reach(find("PetBackTouch"));await click(find("PetBackTouch"));await ready_layout()
 check(menu.pet_view=="detail" and menu.selected_pet==1,"skills return retains selection")
 await reach(find("PetGrowthToggle"));await click(find("PetGrowthToggle"));await ready_layout()
 check(menu.pet_growth_open,"actual growth toggle expands selected pet")
 var scroll:ScrollContainer=find("PetCollectionScroll")
 var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=scroll.get_global_rect().get_center()
 root.push_input(wheel,true);wheel=wheel.duplicate();wheel.pressed=false;root.push_input(wheel,true)
 check(await Wait.until(self,func():return scroll.scroll_vertical>0),"actual wheel scrolls collection")
 await reach(find("PetInnateQuality"))
 scroll.scroll_vertical=100000;await ready_layout()
 check(scroll.scroll_vertical>0 and scroll.scroll_vertical+scroll.size.y>=scroll.get_v_scroll_bar().max_value-2,"last forecast explanation reachable")
 await shot("390-growth-bottom")
 var old_scroll:int=scroll.scroll_vertical
 menu.rebuild();await ready_layout()
 scroll=find("PetCollectionScroll")
 check(abs(scroll.scroll_vertical-old_scroll)<=1 and menu.selected_pet==1 and menu.pet_growth_open,"refresh retains scroll selection and growth state")
 mobile_checks()
 await reach(find("PetPageNext"));await click(find("PetPageNext"));await ready_layout()
 check(menu.pet_page==1 and menu.pet_view=="list" and find("PetRow5")!=null,"actual page click retains original roster paging")
 await shot("390-page-two")
 root.size=Vector2i(1280,720)
 check(await Wait.until(self,func():return find("PetCollectionMobile")==null),"resize automatically restores desktop layout")
 await ready_layout()
 check(find("PetCollectionMobile")==null and menu.panel.get_node("PetRow5").position==Vector2(67,28),"desktop keeps original native layout")
 await click(find("PetRow5"));await ready_layout()
 await click(find("PetGrowthToggle"));await ready_layout()
 await shot("1280-growth")
 check(menu.panel.get_node("PetGrowthHeading").position.x>=560,"desktop growth retains separate right column")
 world.music.stop();world.effect.stop();world.queue_free();await ready_layout()
 # An actual remote device with no backend executes a collection action.
 root.size=Vector2i(390,844)
 var b=Backend.new();root.add_child(b);b.session.grant_starter_pets()
 var server=WsServer.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"isolated remote server starts")
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://pet-mobile-remote.cfg";root.add_child(world)
 check(await Wait.until(self,func():return world.link.online and not world.data.is_empty()) and await Wait.settle(self,world) and world.backend==null,"remote collection has no backend")
 menu=world.adventure_menu;menu.open_menu("pets");await ready_layout()
 await click(find("PetRow0"));await ready_layout()
 var store=find("PetStatusStoreTouch")
 await reach(store);await click(store)
 check(await Wait.until(self,func():return world.session.snapshot().pet_storage.size()==1) and await Wait.settle(self,world),"actual mobile store click goes through remote Session")
 await ready_layout();await shot("390-remote-stored")
 await click(find("PetCollectionClose"))
 check(not menu.visible,"fixed 44px close works without scrolling")
 world.music.stop();world.effect.stop();world.link.close();world.queue_free();server.stop();server.queue_free();b.queue_free()
 await ready_layout()
 for path in ["user://pet-mobile.cfg","user://pet-mobile-remote.cfg"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 print("PET COLLECTION MOBILE: %d failures"%failures)
 quit(1 if failures else 0)
