extends SceneTree
## 实际 GameScene、真实 backend/session 与端口 0 WebSocket；无窗口仅检查几何和输入。
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
var visual := false
const SHOTS := "/private/tmp/tmux-agents/encyclopedia-owned-list/"
func _initialize():run.call_deferred()
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures += 1
func row(menu, uid: String):return menu.body.find_child("OwnedPet_"+uid,true,false)
func caption(menu, uid: String) -> String:
 var found = row(menu,uid)
 if found == null:return ""
 var line = found.get_node("Line")
 return "%s · %s · 攻 %s 防 %s 敏 %s · 三围合 %s · 血 %s" % [line.get_node("name").text,line.get_node("place").text,line.get_node("attack").text,line.get_node("defence").text,line.get_node("speed").text,line.get_node("stat_total").text,line.get_node("hp").text]
func click(control: Control):
 if not check_ready(control):return
 var point: Vector2 = control.get_global_transform_with_canvas()*(control.size/2)
 var move := InputEventMouseMotion.new();move.position=point;move.global_position=point;root.push_input(move,true)
 check(await Wait.until(self,func():return root.gui_get_hovered_control()==control),"real pointer hover reaches target")
 for pressed in [true,false]:
  var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
  root.push_input(event,true)
  await process_frame
func check_ready(control) -> bool:
 var valid: bool = is_instance_valid(control) and control.is_visible_in_tree() and control.size.x>0
 check(valid,"actual click target is visible")
 return valid
func show_button(menu, uid: String):
 await Wait.until(self,func():return not menu._owned_dirty)
 await physics_frame
 var button = menu.body.find_child("WithdrawOwned_"+uid,true,false)
 if button == null:return null
 var horizontal: ScrollContainer=menu.body.find_child("OwnedHorizontalScroll",true,false)
 check(await Wait.until(self,func():
  horizontal.ensure_control_visible(button)
  menu.scroll.ensure_control_visible(button)
  return menu.scroll.get_global_rect().encloses(button.get_global_rect()) and horizontal.get_global_rect().encloses(button.get_global_rect())),"action layout and both scroll positions settled")
 await process_frame
 return button
func client(port: int, tag: String):
 var script = load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%port
 var game = load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 game.profile_persistence=false;game.viewer_prefs_path="user://owned-%s.cfg"%tag;root.add_child(game)
 check(await Wait.until(self,func():return game.link.online and not game.data.is_empty()) and await Wait.settle(self,game),"remote client connects and settles")
 game.random_encounters=false
 return game
func close_game(game):
 game.process_mode=Node.PROCESS_MODE_DISABLED
 if game.link.has_method("close"):game.link.close()
 game.music.stop();game.effect.stop();game.queue_free()
 await process_frame
func seed_roster(backend):
 # Isolated authority fixture; publish once after constructing the roster.
 backend.session.grant_starter_pets()
 backend.session.gm_raise_level(0,120)
 for i in range(11):
  backend.session.gm_grant_pet(92)
  backend.session.gm_raise_level(backend.session.snapshot().pets.size()-1,120)
  backend.session.store_pet(backend.session.snapshot().pets.size()-1)
 backend.session.gm_grant_pet(113)
 backend.session.store_pet(backend.session.snapshot().pets.size()-1)
 backend.publish()
func local_scene():
 root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
 var game = load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;game.viewer_prefs_path="user://owned-local.cfg";root.add_child(game)
 check(await Wait.until(self,func():return game.link!=null and not game.data.is_empty()),"local scene ready")
 game.random_encounters=false
 seed_roster(game.backend)
 var menu=game.pet_encyclopedia;menu.open_menu(92)
 check(await Wait.until(self,func():return menu.body.find_children("OwnedPet_*","PanelContainer",true,false).size()==12),"every carried and stored blue dragon is listed")
 var profile: Dictionary=game.session.snapshot()
 var carried_uid := str(profile.pets[0].pet_id)
 var target_uid := str(profile.pet_storage[5].pet_id)
 check(caption(menu,carried_uid).contains("随身") and caption(menu,target_uid).contains("仓库") and caption(menu,target_uid).contains("三围合") and caption(menu,target_uid).contains("血"),"individual current stats and locations")
 menu.show_species(113)
 check(menu.body.find_children("OwnedPet_*","PanelContainer",true,false).size()==1,"switching species replaces individuals")
 menu.show_species(92)
 await process_frame
 await compact_checks(menu,game,"1280")
 var saved_row=row(menu,target_uid);var saved_button=menu.body.find_child("WithdrawOwned_"+target_uid,true,false)
 menu.scroll.scroll_vertical=200
 await process_frame
 var offset:int=menu.scroll.scroll_vertical
 var before_attack:int=game.session.snapshot().pets[0].attack
 game.backend.handle({"type":"gm_set_base_stat","index":0,"stat":"strength","value":12,"additive":true})
 check(await Wait.until(self,func():return game.session.snapshot().pets[0].attack!=before_attack and caption(menu,carried_uid).contains("攻 %d"%game.session.snapshot().pets[0].attack)),"open individual stats refresh from server mutation")
 check(row(menu,target_uid)==saved_row and menu.body.find_child("WithdrawOwned_"+target_uid,true,false)==saved_button and menu.scroll.scroll_vertical==offset,"stats refresh preserves row, hover target and scroll")
 # Remove an earlier warehouse row while the target's displayed index is stale.
 game.backend.handle({"type":"retrieve_pet_by_id","pet_id":str(profile.pet_storage[0].pet_id)})
 var target_before: Dictionary=game.session.snapshot().pet_storage.filter(func(p):return str(p.pet_id)==target_uid)[0].duplicate(true)
 await click(await show_button(menu,target_uid))
 check(await Wait.until(self,func():return caption(menu,target_uid).contains("随身")),"actual local click withdraws displayed UID after indices shift")
 var retrieved: Array=game.session.snapshot().pets.filter(func(p):return str(p.pet_id)==target_uid)
 check(retrieved.size()==1 and retrieved[0]==target_before,"withdraw preserves full individual without UID or stats changes")
 game.backend.handle({"type":"store_pet","index":game.session.snapshot().pets.size()-1})
 # Existing storage command publishes the changed snapshot even if save fails.
 # This UI must reflect that authority; it cannot claim an atomic rollback.
 var fail_uid := str(game.session.snapshot().pet_storage[0].pet_id)
 game.backend.save_path="user://absent-owned-list-parent/save.json"
 await click(await show_button(menu,fail_uid))
 check(await Wait.until(self,func():return menu._withdraw_pending.is_empty() and caption(menu,fail_uid).contains("随身")),"save failure follows existing non-atomic storage authority and clears pending")
 check(game.backend.session.last_error=="Cannot create save." and not FileAccess.file_exists(game.backend.save_path),"real storage save failure is exercised (backend still acknowledges move)")
 game.backend.save_path=""
 # All carried slots occupied: let server explain the refusal rather than disable button.
 while game.backend.session.snapshot().pets.size()<game.backend.session.PET_CAPACITY:
  game.backend.handle({"type":"gm_grant_pet","template":113})
 var refused_uid := str(game.session.snapshot().pet_storage[0].pet_id)
 var before: Dictionary=game.session.snapshot()
 await click(await show_button(menu,refused_uid))
 check(await Wait.until(self,func():return menu.feedback.contains("已满")) and game.session.snapshot()==before,"full carried server refusal is displayed with no mutation")
 # Battle reserves the remaining party slots for possible captures.
 game.backend.handle({"type":"store_pet","index":game.session.snapshot().pets.size()-1})
 var issued: Dictionary=game.backend.handle({"type":"start_battle_config","species":"wooli","enemy_count":2})
 game.backend.handle({"type":"open_battle","config":issued.config})
 game.backend.set_process(false) # Keep the capture reservation fixed while driving UI input.
 var battle_before: Dictionary=game.session.snapshot()
 await click(await show_button(menu,refused_uid))
 check(await Wait.until(self,func():return menu.feedback.contains("捕捉")) and game.session.snapshot()==battle_before,"real battle capture-room refusal is displayed: "+menu.feedback)
 if game.session.snapshot()!=battle_before:
  for key in battle_before:
   if game.session.snapshot().get(key)!=battle_before[key]:print("BATTLE FIXTURE DIFF: ",key)
 game.backend.handle({"type":"battle_escape_dev"})
 game.backend.handle({"type":"battle_close"})
 game.backend.set_process(true)
 # Same pet may be active and ridden: both positions must appear.
 game.backend.session._profile.player.level=120
 game.backend.session._profile.pets[2].loyalty=100
 game.backend.session._profile.active_pet=2
 game.backend.session._profile.ride_pet=2
 game.backend.handle({"type":"rename_pet","index":2,"name":"巴朵兰恩"})
 menu.show_species(303)
 var ride_uid := str(game.session.snapshot().pets[2].pet_id)
 check(await Wait.until(self,func():return caption(menu,ride_uid).contains("出战") and caption(menu,ride_uid).contains("骑乘")),"one individual displays both active and riding positions")
 # Renaming a different real species to the selected one's name cannot change ownership.
 game.backend.handle({"type":"rename_pet","index":1,"name":"扬奇洛斯"})
 menu.show_species(92)
 check(not caption(menu,str(game.session.snapshot().pets[1].pet_id)).contains("扬奇洛斯"),"species matching uses templates, never renamed pet names")
 # More than one list page, using real server grants of distinct species.
 for id in menu.book.order:
  if menu.book.owned_counts(game.session.snapshot()).size()>35:break
  game.backend.handle({"type":"gm_grant_pet","template":int(id)})
 menu.view="list";menu.set_ownership("owned")
 await Wait.until(self,func():return not menu._owned_dirty)
 await physics_frame
 menu.scroll.scroll_vertical=200
 var list_area=menu.scroll
 var list_offset:int=menu.scroll.scroll_vertical
 game.backend.handle({"type":"gm_set_base_stat","index":0,"stat":"strength","value":1,"additive":true})
 await Wait.until(self,func():return not menu._owned_dirty)
 check(list_offset>0 and menu.scroll==list_area and menu.scroll.scroll_vertical==list_offset,"list stat refresh preserves actual scroll and hovered row")
 menu.list_page=1;menu.rebuild()
 await physics_frame
 var next_area=menu.scroll
 game.backend.handle({"type":"gm_set_base_stat","index":0,"stat":"strength","value":1,"additive":true})
 await Wait.until(self,func():return not menu._owned_dirty)
 check(menu.scroll==next_area and menu.list_page==1,"snapshot update preserves second page")
 menu.close_menu()
 await close_game(game)
func remote_scene():
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 var backend=Backend.new();backend.set_process(false);root.add_child(backend)
 seed_roster(backend)
 var server=WsServer.new(backend,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"real LAN server uses port zero")
 var other=await client(server.port,"b")
 var game=await client(server.port,"a")
 check(game.backend==null and other.backend==null,"both remote scenes have no UI backend")
 var menu=game.pet_encyclopedia;var peer=other.pet_encyclopedia
 peer.open_menu(92);other.ui_layer.hide()
 menu.open_menu(92)
 await compact_checks(menu,game,"390")
 var uid := str(backend.session.snapshot().pet_storage[1].pet_id)
 var button=await show_button(menu,uid)
 check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(menu.panel.get_global_rect()),"390×844 panel stays bounded: %s min %s"%[menu.panel.get_global_rect(),menu.panel.get_combined_minimum_size()])
 check(menu.scroll.size.y>0 and menu.scroll.size.y<844 and menu.panel.get_global_rect().encloses(menu.scroll.get_global_rect()),"detail has bounded scroll")
 check(button!=null and menu.scroll.get_global_rect().encloses(button.get_global_rect()),"mobile withdraw button is reachable in scroll")
 check(not menu.scroll.get_global_rect().intersects(menu.panel.find_child("EncyclopediaClose",true,false).get_global_rect()),"mobile scroll clears close footer/header control")
 var variants=menu.body.find_child("SpeciesVariants",true,false)
 var overlap:=false
 for i in range(variants.get_child_count()):
  for j in range(i):overlap=overlap or variants.get_child(i).get_rect().intersects(variants.get_child(j).get_rect())
 check(not overlap,"mobile thumbnail buttons do not overlap")
 var before: Dictionary=backend.session.snapshot().pet_storage[1].duplicate(true)
 var hover := InputEventMouseMotion.new();hover.position=button.get_global_rect().get_center();hover.global_position=hover.position;root.push_input(hover,true)
 check(await Wait.until(self,func():return root.gui_get_hovered_control()==button),"remote action actual hover before screenshot")
 await shot("390-hover-action")
 await click(button)
 check(await Wait.settle(self,game) and await Wait.settle(self,other) and await Wait.until(self,func():return caption(menu,uid).contains("随身") and caption(peer,uid).contains("随身")),"actual remote click synchronizes individual location on both devices")
 var moved_place: Control=row(menu,uid).get_node("Line/place")
 check(await Wait.until(self,func():
  menu.scroll.ensure_control_visible(moved_place)
  return menu.scroll.get_global_rect().encloses(moved_place.get_global_rect())),"moved location remains readable after feedback expands")
 await shot("390-after-move")
 var pets: Array=backend.session.snapshot().pets.filter(func(p):return str(p.pet_id)==uid)
 check(pets.size()==1 and pets[0]==before,"remote withdrawal preserves exact UID and stats")
 var own_row=row(menu,uid);var peer_row=row(peer,uid)
 var peer_offset:int=peer.scroll.scroll_vertical
 backend.handle({"type":"gm_set_base_stat","index":0,"stat":"strength","value":1,"additive":true})
 var changed_uid:=str(backend.session.snapshot().pets[0].pet_id)
 var attack:int=backend.session.snapshot().pets[0].attack
 check(await Wait.settle(self,game) and await Wait.settle(self,other) and await Wait.until(self,func():return caption(menu,changed_uid).contains("攻 %d"%attack) and caption(peer,changed_uid).contains("攻 %d"%attack)),"real remote stat mutation refreshes both devices")
 check(row(menu,uid)==own_row and row(peer,uid)==peer_row and peer.scroll.scroll_vertical==peer_offset,"remote stats preserve individual controls and peer scroll")
 menu.show_species(113)
 check(menu.body.find_children("OwnedPet_*","PanelContainer",true,false).size()==1,"remote species change does not leak prior rows")
 menu.close_menu();peer.close_menu()
 await close_game(game);await close_game(other)
 server.queue_free();backend.queue_free();await process_frame
func shot(tag: String):
 if not visual:return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(SHOTS+tag+".png")
func compact_checks(menu,game,tag: String):
 var list = menu.body.find_child("OwnedList",true,false)
 check(await Wait.until(self,func():return list.rows.get_child_count()==12 and list.rows.get_child(0).size.y>0),"12 real same-species individuals ready")
 var before: Dictionary=game.session.snapshot()
 var summary: String=menu.body.find_child("OwnedSummary",true,false).text
 var best: Dictionary=menu.book.owned_best(before,menu.book.entry_for(92))
 check(summary.contains("共 12 只") and summary.contains("最佳120级三围合 %d"%best.best_sum) and summary.contains("最佳120级攻击 %d"%best.best_attack),"summary retains exact projected meanings")
 var tie_list = preload("res://scripts/pet_owned_list.gd").new()
 var tie_pet: Dictionary=before.pets[0].duplicate(true)
 var tie_second: Dictionary=tie_pet.duplicate(true);tie_second.pet_id="tie-stored"
 tie_list.update_snapshot([{"pet":tie_pet,"location":"pets","index":0},{"pet":tie_second,"location":"pet_storage","index":0}],before,false)
 tie_list.sort_by("attack")
 check(tie_list.best_sum_uid==str(tie_pet.pet_id) and tie_list.best_attack_uid==str(tie_pet.pet_id),"equal projections choose carried first independently of display sorting")
 tie_list.update_snapshot([{"pet":tie_second,"location":"pet_storage","index":0},{"pet":tie_pet,"location":"pet_storage","index":1}],before,false)
 check(tie_list.best_sum_uid=="tie-stored" and tie_list.best_attack_uid=="tie-stored","equal stored projections choose original first UID")
 tie_list.free()
 var winners := [list.best_sum_uid,list.best_attack_uid]
 check(list.rows.get_children().filter(func(item):return item.get_meta("best_sum")).size()==1 and list.rows.get_children().filter(func(item):return item.get_meta("best_attack")).size()==1,"exactly one stable winner per projection")
 for key in ["stat_total","attack"]:
  var button: Button=list.header.get_node("OwnedSort_"+key)
  check(await Wait.until(self,func():
   menu.body.find_child("OwnedHorizontalScroll",true,false).ensure_control_visible(button)
   menu.scroll.ensure_control_visible(button)
   return menu.scroll.get_global_rect().encloses(button.get_global_rect())),"sort header reachable")
  await click(button)
  check(list.order==key and not list.ascending,"real header click sorts current "+key)
  var numbers: Array=list.rows.get_children().map(func(item):return int(item.get_node("Line/"+key).text))
  var expected := numbers.duplicate();expected.sort();expected.reverse()
  check(numbers==expected,"descending current values "+key)
  await click(button)
  numbers=list.rows.get_children().map(func(item):return int(item.get_node("Line/"+key).text))
  expected.sort()
  check(list.ascending and numbers==expected,"second click reverses "+key)
 check(game.session.snapshot()==before and [list.best_sum_uid,list.best_attack_uid]==winners,"display sorting preserves assets and projection tie winners")
 check(list.rows.get_children().all(func(item):return item.size.y<=46),"each pet occupies a compact single row")
 list.sort_by("attack") # Show strongest first in review images, after checking both directions.
 var scroll: ScrollContainer=menu.body.find_child("OwnedHorizontalScroll",true,false)
 scroll.scroll_horizontal=0
 var card: Control=menu.body.find_child("SpeciesOwned",true,false)
 menu.scroll.scroll_vertical += roundi(card.global_position.y-menu.scroll.global_position.y)
 check(await Wait.until(self,func():return scroll.scroll_horizontal==0),"leftmost identity columns reachable")
 await shot(tag+"-owned-left")
 var target_uid := str(before.pet_storage[2].pet_id)
 var button=await show_button(menu,target_uid)
 var point: Vector2=button.get_global_rect().get_center()
 var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 check(await Wait.until(self,func():return root.gui_get_hovered_control()==button),"inline action hover reachable")
 check(button.size.x<100 and button.size.y>=38,"inline action stays compact and tappable")
 await shot(tag+"-owned-hover")
func run():
 root.unfocusable=true;root.position=Vector2i(-10000,-10000)
 visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
 await local_scene()
 await remote_scene()
 print("ENCYCLOPEDIA OWNED PETS: %d failures"%failures)
 quit(1 if failures else 0)
