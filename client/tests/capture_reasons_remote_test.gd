extends SceneTree
## Portrait-size headless viewport + real input + port-zero WebSocket backend.
## This validates click routing and layout geometry, not rendered pixels.
const Backend=preload("res://server/backend.gd")
const WsServer=preload("res://server/ws_server.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok: bool,note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func click(control: Control,offset: Vector2=Vector2(-1,-1)):
 check(await Wait.until(self,func():return control.is_visible_in_tree() and control.size.x>0),"real click control ready")
 var local: Vector2=control.size/2 if offset.x<0 else offset
 var point: Vector2=control.get_global_transform_with_canvas()*local
 var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;control.get_viewport().push_input(move,true)
 await process_frame
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
  control.get_viewport().push_input(event,true)
  await process_frame
func run():
 root.size=Vector2i(720,1280)
 var backend=Backend.new();backend.set_process(false);root.add_child(backend)
 var server=WsServer.new(backend,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"isolated port-zero server starts")
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 var game=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 game.profile_persistence=false;game.viewer_prefs_path="user://capture-reasons-remote.cfg";root.add_child(game)
 check(await Wait.until(self,func():return game.link.online and not game.data.is_empty()) and await Wait.settle(self,game),"real remote client connected")
 game.random_encounters=false
 check(await Wait.until(self,func():return not game.paused_input and not game.area_transition_busy),"remote UI ready")
 for i in range(25):backend.handle({"type":"gm_grant_pet","template":92,"full_grade":false})
 check(await Wait.settle(self,game),"server grants settled before remote records open")
 var menu=game.adventure_menu
 menu.open_pet_records("caught");menu.records_run="";menu.fetch_records()
 check(await Wait.until(self,func():return not menu.records_loading and menu.records_data.get("entries",[]).size()==20),"remote log RPC returns real frozen decisions")
 var row:Button=menu.panel.find_child("CaptureReason_0",true,false)
 check(row!=null and row.text.contains("GM发放") and not row.tooltip_text.contains("\n") and row.tooltip_text.length()<60,"remote reason tooltip is one short readable hint")
 var tooltip_box:StyleBoxFlat=row.get_theme_stylebox("panel","TooltipPanel")
 check(tooltip_box.bg_color.a==1.0,"global tooltip background is opaque")
 await click(row)
 check(await Wait.until(self,func():return menu.panel.find_child("CaptureReasonDetails",true,false)!=null),"actual click opens reason details")
 var dialog:Panel=menu.panel.find_child("CaptureReasonDetails",true,false)
 check(dialog.find_child("CaptureReasonText",true,false).text.contains("捕获加入背包前冻结"),"detail dialog shows frozen-time explanation")
 check(dialog.find_child("CaptureReasonText",true,false).text.contains("原最高"),"full server ranking stays in click-open details")
 await click(dialog.find_child("CaptureReasonClose",true,false))
 check(await Wait.until(self,func():return menu.panel.get_node_or_null("CaptureReasonDetails")==null),"actual dialog OK click closes details")
 var list:ScrollContainer=menu.panel.find_child("RecordsScroll",true,false)
 check(await Wait.until(self,func():return list.get_v_scroll_bar().max_value>list.size.y),"real captured rows can scroll")
 list.scroll_vertical=137
 await process_frame
 var at:int=list.scroll_vertical
 var panel=menu.panel
 var old_row:Button=menu.panel.find_child("CaptureReason_0",true,false)
 backend.handle({"type":"gm_grant_pet","template":92,"full_grade":true})
 var expected:String=backend.capture_log.entries().back().pet_id
 check(await Wait.until(self,func():return not menu.records_loading and menu.records_data.entries[0].pet_id==expected),"new server capture refreshes open remote records")
 await process_frame
 check(menu.panel==panel and menu.panel.find_child("RecordsScroll",true,false)==list and list.scroll_vertical==at and menu.panel.find_child("CaptureReason_0",true,false)==old_row,"refresh preserves controls and exact scroll")
 list.scroll_vertical=0
 await process_frame
 await click(old_row)
 check(await Wait.until(self,func():return menu.panel.find_child("CaptureReasonDetails",true,false)!=null),"refreshed reason opens detail window")
 var updated:Panel=menu.panel.find_child("CaptureReasonDetails",true,false)
 check(updated!=null and updated.find_child("CaptureReasonText",true,false).text==menu.capture_reason_details(menu.records_data.entries[0]),"refreshed button opens latest server snapshot")
 menu.pet_records_open=false;game.process_mode=Node.PROCESS_MODE_DISABLED;game.link.close();game.music.stop();game.effect.stop();game.queue_free()
 server.queue_free();backend.queue_free();await process_frame
 print("CAPTURE REASONS REMOTE: %d failures"%failures);quit(1 if failures else 0)
