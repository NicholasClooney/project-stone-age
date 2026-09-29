extends SceneTree
## 属性 bars on the status and pet windows, and the status window's 属性 editor.
var failures:=0
func check(ok: bool, message: String):
 print(("PASS: " if ok else "FAIL: ")+message)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func settle():
 await process_frame;await process_frame
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 await settle()
 var menu=game.adventure_menu
 menu.open_menu("status")
 await settle()
 var earth=menu.panel.get_node_or_null("ElementBar0")
 check(earth!=null and earth.size.x==81 and earth.position==Vector2(178,179),"status window draws the default 地100 bar at the original spot, 0.8 px per point")
 check(menu.panel.get_node_or_null("ElementBar1")==null,"elements without points draw no bar")
 menu.panel.get_node("PlayerElements").pressed.emit()
 await settle()
 check(menu.panel.has_node("ElementConfirm") and menu.panel.get_node("ElementConfirm").disabled,"the editor opens and cannot confirm an unchanged choice")
 menu.panel.get_node("ElementPlus2").pressed.emit()
 await settle()
 check(menu.element_draft==[10,0,0,0],"+ on 火 is refused while 地 has points")
 for i in range(3):
  menu.panel.get_node("ElementPlus1").pressed.emit()
  await settle()
 check(menu.element_draft==[7,3,0,0] and not menu.panel.get_node("ElementConfirm").disabled,"+ on 水 with no points left moves them from 地")
 menu.panel.get_node("ElementConfirm").pressed.emit()
 await settle()
 check(game.session.snapshot().player.elements==[70,30,0,0] and not menu.element_editor_open,"confirm saves 地70 水30 through the session")
 check(menu.panel.get_node("ElementBar1").size.x==25,"the new 水30 bar shows")
 # Pet window: bars beside the four stat rows.
 game.session.gm_grant_pet(92)
 await settle()
 menu.open_menu("pets")
 menu.selected_pet=0
 menu.pet_switch_view("detail")
 await settle()
 var water=menu.panel.get_node_or_null("ElementBar1")
 var fire=menu.panel.get_node_or_null("ElementBar2")
 check(water!=null and fire!=null and water.position==Vector2(179,207) and fire.position==Vector2(179,231) and fire.size.x==57,"扬奇洛斯 shows 水30 火70 on the defence and speed rows")
 check(menu.panel.get_node("PetElements").tooltip_text=="属性：水30 火70","pet 属性 tooltip")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null
 game.queue_free();await process_frame;await create_timer(0.5).timeout
 print("ELEMENTS UI: %d failures"%failures)
 quit(1 if failures else 0)
