extends "res://tests/quest_helper_ui_test.gd"
const SHOTS="/private/tmp/ui-panel-storage-shots/"
var visual:=false
func shot(id:String)->void:
 if not visual:return
 await process_frame
 await RenderingServer.frame_post_draw
 var picture:Image=root.get_texture().get_image()
 picture.save_png(SHOTS+id+".png")
 if id.ends_with("opaque-warehouse") or id.ends_with("warehouse-after-helper"):
  # This blank warehouse region covers the old bag's item-name/description.
  # A z51 bag label used to leak here despite a fully opaque z50 backdrop.
  var clear:=true
  for y in range(335,380):
   for x in range(root.size.x-260,root.size.x-35):
    var pixel:=picture.get_pixel(x,y)
    if maxf(pixel.r,maxf(pixel.g,pixel.b))>0.1:clear=false
  check(clear,"Rendered warehouse blank region has no bag text/highlight")
 if id.ends_with("helper-over-warehouse"):
  var point:Vector2=world.quest_helper_menu.global_position+Vector2(5,100)
  var pixel:=picture.get_pixel(int(point.x),int(point.y))
  check(pixel.g>0.1 and pixel.b>0.1,"Rendered helper panel is actually above warehouse")
func run()->void:
 root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO
 visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
 if visual:DirAccess.make_dir_recursive_absolute(SHOTS)
 world=load("res://scenes/main.tscn").instantiate();world.profile_persistence=false;world.viewer_prefs_path="user://storage-panel-layers.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty(),"Real game ready"):return
 world.backend.set_process(false)
 for dimensions in [Vector2i(1280,720),Vector2i(390,844)]:
  root.size=dimensions
  var tag:="%dx%d"%[dimensions.x,dimensions.y]
  world.adventure_menu.open_menu("inventory")
  if not await click(world.adventure_menu.find_child("OpenItemStorage",true,false)):return
  var storage=world.adventure_menu.item_storage_menu
  if not await click(storage.warehouse_tab):return
  if not check(not storage.deposit,"Warehouse tab true click works over backpack"):return
  await shot(tag+"-opaque-warehouse")
  world.quest_helper_menu.open_menu()
  if not await ready(func():return not world.showcase_ticker.visible,"Ticker yields to stacked menus"):return
  await shot(tag+"-helper-over-warehouse")
  if not await click(world.quest_helper_menu.find_child("QuestHelperClose",true,false)):return
  if not check(not world.quest_helper_menu.visible,"Helper close click works above warehouse"):return
  if not await click(storage.bag_tab):return
  if not check(storage.deposit,"Warehouse input returns after helper closes"):return
  if not await click(storage.find_child("StorageClose",true,false)):return
  if not check(not storage.visible,"Warehouse return button receives actual click"):return
  world.adventure_menu.hide()
  # Actual reverse navigation: close the front helper before its covered bag
  # entry becomes available. Never click an invisible underlying control.
  world.quest_helper_menu.open_menu()
  if not await click(world.quest_helper_menu.find_child("QuestHelperClose",true,false)):return
  world.show_adventure_menu("inventory")
  if not await click(world.adventure_menu.find_child("OpenItemStorage",true,false)):return
  if not await click(storage.warehouse_tab):return
  if not check(storage.visible and not world.quest_helper_menu.visible and not storage.deposit,"Reverse route opens visible warehouse after closing helper"):return
  await shot(tag+"-warehouse-after-helper")
  if not await click(storage.find_child("StorageClose",true,false)):return
  if not check(world.adventure_menu.visible and not storage.visible,"Returning from warehouse restores underlying bag"):return
  await shot(tag+"-returned-bag")
  world.adventure_menu.hide()
 world.queue_free();await process_frame
 print("ITEM STORAGE PANEL LAYERS: PASS");quit(0)
