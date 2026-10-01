extends SceneTree
const Comparison=preload("res://scripts/pet_comparison.gd")
const Backend=preload("res://server/backend.gd")
const WsServer=preload("res://server/ws_server.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func ids(menu)->Array:
 return menu.panel.find_children("StorageRow_*","",true,false).map(func(node):return str(node.name).trim_prefix("StorageRow_"))
func click(control:Control):
 var point:Vector2=control.get_global_transform_with_canvas()*(control.size/2)
 var move:=InputEventMouseMotion.new();move.position=point;root.push_input(move,true);await process_frame
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=point;root.push_input(event,true);await process_frame
func run():
 for path in ["user://storage-sort-a.cfg","user://storage-sort-b.cfg","user://storage-sort-remote.cfg"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 root.size=Vector2i(390,844)
 var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;game.viewer_prefs_path="user://storage-sort-a.cfg";root.add_child(game);await process_frame
 game.backend.automation.auto_tick=false;game.session.grant_starter_pets();game.session.select_pet(-1)
 var stored:=[]
 for i in range(26):
  var pet:Dictionary=game.session.snapshot().pets[i%2].duplicate(true)
  pet.pet_id="pet-%d"%(100+i);pet.name="同名";pet.favorite=i==2;pet.level=i+1;pet.attack=100-i;pet.defence=i*2;pet.speed=i*3;pet.max_hp=1000-i
  stored.append(pet)
 game.session._profile.pet_storage=stored;game.session._profile.next_pet_id=200;game.sync_state()
 game.set_viewer_pref("storage_order","");game.set_viewer_pref("storage_species","");game.set_viewer_pref("storage_favorites_first",false)
 var menu=game.adventure_menu;menu.open_menu("pets");menu.pet_storage_open=true;menu.rebuild();await process_frame
 for key in ["level","stat_total","attack","defence","speed","max_hp"]:
  var expected:Array=Comparison.storage_rows(game.session.snapshot(),key,false).slice(0,20).map(func(e):return str(e.pet.pet_id))
  (menu.panel.find_child("StorageSort_"+key,true,false) as Button).pressed.emit();await process_frame
  check(ids(menu)==expected,"column "+key+" uses current values descending")
  (menu.panel.find_child("StorageSort_"+key,true,false) as Button).pressed.emit();await process_frame
  expected=Comparison.storage_rows(game.session.snapshot(),key,false,true).slice(0,20).map(func(e):return str(e.pet.pet_id))
  check(ids(menu)==expected and menu.storage_ascending,"same column reverses "+key)
 menu.pet_storage_page=1;menu.rebuild();await process_frame
 check(ids(menu).size()==6,"second page contains remaining rows")
 var page_scroll:ScrollContainer=menu.panel.find_child("StorageScroll",true,false)
 menu.rebuild();await process_frame
 check(menu.pet_storage_page==1 and is_instance_valid(page_scroll),"data refresh retains current page and scroll node")
 menu.pet_storage_page=999;menu.rebuild();await process_frame
 check(menu.pet_storage_page==1,"stale page clamps to last available page")
 var tied:Dictionary=game.session.snapshot().duplicate(true)
 for pet in tied.pet_storage:pet.attack=50
 check(Comparison.storage_rows(tied,"attack",false,true).map(func(e):return e.index)==range(26),"equal values keep stable original indices")
 var picker:OptionButton=menu.panel.find_child("StorageSpecies",true,false)
 check(picker.item_count==3,"same name different species remain separate choices")
 picker.select(1);picker.item_selected.emit(1);await process_frame
 var species:String=menu.storage_species
 check(menu.pet_storage_page==0 and ids(menu).size()==13 and Comparison.storage_rows(game.session.snapshot(),"",false,false,species).all(func(e):return Comparison.species_key(e.pet)==species),"species filter uses species identity")
 (menu.panel.find_child("StorageFavoritesFirst",true,false) as CheckBox).button_pressed=true;await process_frame
 if species==Comparison.species_key(stored[2]):check(ids(menu)[0]=="pet-102","favorites lead within filtered species")
 var scroll:ScrollContainer=menu.panel.find_child("StorageScroll",true,false);var panel=menu.panel
 await Wait.until(self,func():return scroll.get_v_scroll_bar().max_value>scroll.size.y)
 scroll.scroll_vertical=70;var at:int=scroll.scroll_vertical
 menu.rebuild();await process_frame
 check(menu.panel==panel and is_instance_valid(scroll) and scroll.scroll_vertical==at,"state refresh preserves panel and scroll")
 check(not picker.get_global_rect().intersects(menu.panel.find_child("StorageSort",true,false).get_global_rect()),"species and sort controls do not overlap")
 check(scroll.size.y>0 and scroll.position.y+scroll.size.y<=menu.panel.get_child(0).size.y,"bounded rows scroll fits modal")
 var config:=ConfigFile.new();config.set_value("view","storage_order","bogus");config.set_value("view","storage_ascending","bad");config.set_value("view","storage_species",42);config.set_value("view","storage_favorites_first","bad");config.save(game.viewer_prefs_path);menu._compare_prefs_loaded=false;menu.load_compare_prefs()
 check(menu.storage_order=="" and not menu.storage_ascending and menu.storage_species=="" and menu.storage_favorites_first,"malformed preferences fall back safely")
 config.clear();config.save(game.viewer_prefs_path);game.set_viewer_pref("storage_order","caught_new");menu._compare_prefs_loaded=false;menu.load_compare_prefs();check(menu.storage_order=="caught_new","legacy capture-order preference remains valid")
 game.set_viewer_pref("storage_species",species);game.set_viewer_pref("storage_order","speed");game.set_viewer_pref("storage_ascending",true)
 var second=load("res://scenes/main.tscn").instantiate();second.profile_persistence=false;second.viewer_prefs_path="user://storage-sort-b.cfg";root.add_child(second);await process_frame
 second.set_viewer_pref("storage_order","");second.set_viewer_pref("storage_species","");second.adventure_menu.load_compare_prefs();menu._compare_prefs_loaded=false;menu.load_compare_prefs()
 check(second.adventure_menu.storage_order=="" and second.adventure_menu.storage_species=="" and menu.storage_order=="speed" and menu.storage_species==species and menu.storage_ascending,"two devices keep independent preferences")
 second.queue_free();game.queue_free();await process_frame
 var backend=Backend.new();backend.set_process(false);root.add_child(backend);backend.session.grant_starter_pets();backend.session.select_pet(-1)
 backend.session.store_pet(0);backend.session.store_pet(0)
 var server=WsServer.new(backend,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"remote port-zero server starts")
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 var remote=load("res://scenes/main.tscn").instantiate();script.server_url_override="";remote.profile_persistence=false;remote.viewer_prefs_path="user://storage-sort-remote.cfg";root.add_child(remote)
 check(await Wait.until(self,func():return remote.link.online and not remote.data.is_empty()) and await Wait.settle(self,remote),"remote snapshot ready")
 remote.set_viewer_pref("storage_species",Comparison.species_key(backend.session.snapshot().pet_storage[1]));remote.set_viewer_pref("storage_order","attack")
 var wanted:String=backend.session.snapshot().pet_storage[1].pet_id
 var rm=remote.adventure_menu;rm.open_menu("pets");rm.pet_storage_open=true;rm.rebuild();await process_frame
 check(remote.backend==null and ids(rm)==[wanted],"remote filtered row reads snapshot without backend")
 await click(rm.panel.find_child("RetrievePet_1",true,false))
 check(await Wait.until(self,func():return backend.session.snapshot().pets.any(func(p):return p.pet_id==wanted)),"real filtered withdraw click retrieves the correct UID")
 remote.link.close();remote.queue_free();server.queue_free();backend.queue_free();await process_frame
 print("STORAGE SORT FILTER: %d failures"%failures);quit(1 if failures else 0)
