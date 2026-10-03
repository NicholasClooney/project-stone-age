extends "res://tests/quest_helper_ui_test.gd"
const Backend=preload("res://server/backend.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Storage=preload("res://server/item_storage.gd")
var second
var second_state=preload("res://network/client_state.gd").new()
var proof_dir:=""
func check(ok: bool, text: String) -> bool:
 print(("PASS " if ok else "FAIL ")+text)
 return super.check(ok,text)
func _process(delta: float) -> bool:
 if second!=null:second.poll(delta)
 return false
func proof(label:String) -> void:
 if proof_dir.is_empty():return
 if not check(DisplayServer.get_name()!="headless","Pixel proof requires real renderer"):return
 await RenderingServer.frame_post_draw
 var pixels:=root.get_texture().get_image()
 check(not pixels.is_empty() and pixels.save_png(proof_dir.path_join(label+".png"))==OK,"Saved rendered "+label)
func request(link,command:Dictionary) -> Dictionary:
 var answer:=[{}];link.request(command,func(reply):answer[0]=reply)
 await ready(func():return not answer[0].is_empty(),"RPC answered")
 return answer[0]
func push(b) -> void:
 b.publish()
 await Wait.settle(self,world)
 await request(second,{"type":"ping"})
func press(menu,ident:String) -> bool:
 print("CLICK "+ident)
 return await click(menu.find_child(ident,true,false))
func run() -> void:
 root.unfocusable=true;root.position=Vector2i(-10000,-10000)
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1120,760)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var b=Backend.new();root.add_child(b)
 b.session._profile.default_companions_claimed=true;b.session._profile.no_random_encounters=true
 Equipment.add(b.session._profile,2605);Equipment.add(b.session._profile,2468);Equipment.add(b.session._profile,2401)
 var path:="user://item-storage-ui-%d.json"%OS.get_process_id();b.save_path=path
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Isolated port0 server"):return
 var url:="ws://127.0.0.1:%d"%server.port
 var script=load("res://scripts/game.gd");script.server_url_override=url
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://item-storage-viewer.cfg";root.add_child(world)
 if not await ready(func():return world.link.online and not world.data.is_empty(),"Remote game initialized"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"UI has no backend"):return
 second=preload("res://network/ws_link.gd").new(url);second.message.connect(second_state.apply);second.connect_now()
 if not await ready(func():return second.online,"Second real device connected"):return
 await request(second,{"type":"ping"})
 world.show_adventure_menu("inventory")
 await proof("desktop-bag-entry")
 if not await press(world.adventure_menu,"OpenItemStorage"):return
 var menu=world.adventure_menu.item_storage_menu
 if not await ready(func():return menu.visible,"Actual bag button opens warehouse"):return
 if not await press(menu,"StorageRow_uid_1"):return
 if not await press(menu,"StorageRow_uid_2"):return
 await proof("desktop-multiple-deposit")
 if not await press(menu,"StorageTransfer"):return
 if not await ready(func():return not menu.busy and world.session.snapshot().item_storage.size()==2,"Clicked batch deposit committed"):return
 await request(second,{"type":"ping"})
 if not check(second_state.profile.item_storage==world.session.snapshot().item_storage,"LAN second device sees same UIDs"):return
 if not await press(menu,"StorageWarehouseTab"):return
 if not await press(menu,"StorageRow_uid_1"):return
 if not await press(menu,"StorageRow_uid_2"):return
 await proof("desktop-multiple-withdraw")
 if not await press(menu,"StorageTransfer"):return
 if not await ready(func():return not menu.busy and world.session.snapshot().item_storage.is_empty(),"Clicked batch withdraw committed"):return
 # Portrait is a real viewport, not a resized screenshot.
 root.size=Vector2i(390,844)
 if not await ready(func():return world.get_viewport_rect().size==Vector2(390,844),"Portrait viewport ready"):return
 if not await press(menu,"StorageBagTab"):return
 if not await press(menu,"StorageRow_uid_1"):return
 if not await press(menu,"StorageRow_uid_2"):return
 await proof("portrait-multiple-deposit")
 if not await press(menu,"StorageTransfer"):return
 if not await ready(func():return not menu.busy and world.session.snapshot().item_storage.size()==2,"Portrait multi deposit works"):return
 if not await press(menu,"StorageWarehouseTab"):return
 if not await press(menu,"StorageRow_uid_1"):return
 # Another device acts first with the same revision; old captured request rejects.
 var old:Dictionary={"type":"item_storage_transfer","direction":"withdraw","revision":menu.revision,"items":[{"uids":[1]}]}
 var reply:Dictionary=await request(second,old)
 if not check(reply.ok,"Second device withdraws selection"):return
 await Wait.settle(self,world)
 reply=await request(world.link,old)
 if not check(not reply.ok and b.session.snapshot().item_storage.size()==1,"Stale duplicate across devices rejected"):return
 if not await ready(func():return menu.selected.is_empty(),"Stale selection cleared on push"):return
 await proof("portrait-lan-stale-selection")
 # Actual save failure feedback and complete rollback from clicked row.
 if not await press(menu,"StorageRow_uid_2"):return
 if not check(b.save(),"Persistence baseline"):return
 DirAccess.make_dir_absolute(path+".tmp")
 var before:Dictionary=b.session.snapshot()
 if not await press(menu,"StorageTransfer"):return
 if not await ready(func():return not menu.busy and menu.status.text.contains("保存失败"),"Clicked save failure displayed"):return
 if not check(b.session.snapshot()==before,"LAN save failure leaves all fields unchanged"):return
 await proof("portrait-save-failure")
 DirAccess.remove_absolute(path+".tmp")
 if not await press(menu,"StorageTransfer"):return
 if not await ready(func():return not menu.busy and world.session.snapshot().item_storage.is_empty(),"Same selection can retry after save recovery"):return
 # Backend-owned full bag fixture; real click proves refusal in UI.
 for i in range(14-b.session._profile.original_items.size()):Equipment.add(b.session._profile,2468)
 var uid:=int(b.session._profile.next_original_uid);b.session._profile.next_original_uid=uid+1
 b.session._profile.item_storage.append(Equipment.instance(2605,uid));await push(b)
 if not await press(menu,"StorageRow_uid_%d"%uid):return
 if not await press(menu,"StorageTransfer"):return
 if not await ready(func():return not menu.busy and menu.status.text.contains("背包已满"),"Full bag refusal visible"):return
 await proof("portrait-full-bag")
 # Backend-owned full warehouse fixture; no live saves or live server involved.
 b.session._profile.original_items=[];b.session._profile.original_instances=[];b.session._profile.item_storage=[]
 Equipment.add(b.session._profile,2605);uid=int(b.session._profile.original_instances[0].uid)
 for i in range(3000):
  var next:=int(b.session._profile.next_original_uid);b.session._profile.next_original_uid=next+1;b.session._profile.item_storage.append(Equipment.instance(2605,next))
 await push(b)
 if not await press(menu,"StorageBagTab"):return
 if not await press(menu,"StorageRow_uid_%d"%uid):return
 if not await press(menu,"StorageTransfer"):return
 if not await ready(func():return not menu.busy and menu.status.text.contains("仓库已满"),"Full warehouse refusal visible"):return
 await proof("portrait-full-warehouse")
 # Real split control on a64-member stack: only chosen UIDs return to bag.
 b.session._profile.original_items=[];b.session._profile.original_instances=[];b.session._profile.item_storage=[]
 var first_uid:=int(b.session._profile.next_original_uid)
 for i in range(65):
  var next:=int(b.session._profile.next_original_uid);b.session._profile.next_original_uid=next+1;b.session._profile.item_storage.append(Equipment.instance(2468,next))
 await push(b)
 if not await press(menu,"StorageWarehouseTab"):return
 var quantity=menu.find_child("StorageCount_uid_%d"%first_uid,true,false)
 if not check(quantity!=null,"64-stack offers quantity control"):return
 if not await click(quantity.get_line_edit()):return
 quantity.get_line_edit().select_all()
 var digit:=InputEventKey.new();digit.pressed=true;digit.keycode=KEY_3;digit.unicode=51;root.push_input(digit,true)
 var enter:=InputEventKey.new();enter.pressed=true;enter.keycode=KEY_ENTER;root.push_input(enter,true)
 if not await ready(func():return int(quantity.value)==3,"Actual quantity keyboard input selects3"):return
 await proof("portrait-stack-split")
 if not await press(menu,"StorageTransfer"):return
 if not await ready(func():return not menu.busy and world.session.snapshot().original_items.size()==3,"Clicked stack split returns three independent items"):return
 if not check(b.session.snapshot().original_instances.map(func(e):return int(e.uid))==[first_uid,first_uid+1,first_uid+2],"UI split returns deterministic original UIDs"):return
 if not check(int(b.session.snapshot().player.gold)==20,"All clicked free transactions preserve gold"):return
 await proof("portrait-stack-split-complete")
 second.close();world.link.close();server.stop();world.music.stop();world.effect.stop()
 world.queue_free();server.queue_free();b.queue_free();await process_frame
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
 print("ITEM STORAGE UI/LAN: %d failures"%failures)
 quit(1 if failures else 0)
