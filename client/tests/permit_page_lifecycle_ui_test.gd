extends SceneTree
# TMP UNPARSED/UNRUN: real consumer methods, delayed test-local transport only.
# Does NOT prove WsServer/ProfileHub auth or actual WS delivery order.
const Travel=preload("res://scripts/world_travel.gd")
class Peer extends RefCounted:
 func get_ready_state()->int:return WebSocketPeer.STATE_OPEN
class Link extends RefCounted:
 var sent:Array=[]
 var callbacks:Array=[]
 var _lifecycle:=1
 var _peer=Peer.new()
 var online:=true
 var _closed:=false
 func is_local()->bool:return false
 func request(command:Dictionary,done:Callable=Callable())->Dictionary:
  sent.append(command.duplicate(true));callbacks.append(done)
  return {"pending":true,"ok":false}
 func deliver(index:int,reply:Dictionary)->void:
  var done:Callable=callbacks[index];callbacks[index]=Callable()
  if done.is_valid():done.call(reply)
class World extends Node:
 var link=Link.new()
 var paused_input:=true
 var data={"map_id":1100}
 var cell:=Vector2i(85,107)
 func clear_input()->void:pass
 func play_ui_sound(_id:int)->void:pass
var failures:=0
func check(ok:bool,label:String)->bool:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
 return ok
func _initialize()->void:call_deferred("run")
func run()->void:
 var w=World.new();root.add_child(w)
 var ui=Travel.new();w.add_child(ui);ui.world=w
 ui.overlay=Control.new();w.add_child(ui.overlay)
 ui.body=Label.new();ui.overlay.add_child(ui.body)
 ui.choice=Button.new();ui.overlay.add_child(ui.choice)
 var vendor={"dialogue_source":"gmsv/data/npc/genout/ss_1100_86_107"}
 ui._permit_open(vendor)
 var first:String=ui.permit_open_id
 var generation:int=ui.permit_generation
 if not check(first.length()==64 and w.link.sent[0].open_id==first and ui.permit_busy,"open uses unique nonce; pending is not success"):return finish(w)
 ui._close()
 if not check(not ui.permit_active and w.link.sent[1]=={"type":"permit_shop_cancel","open_id":first},"in-flight close cancels exact old open before ACK"):return finish(w)
 ui._permit_open(vendor)
 var second:String=ui.permit_open_id
 if not check(second!=first and ui.permit_generation!=generation,"new page never reuses original open id"):return finish(w)
 w.link.deliver(0,{"ok":true,"dialogue":{"kind":"original_permit_shop","token":"old","open_id":first}})
 if not check(ui.permit_open_id==second and ui.permit_token.is_empty() and ui.permit_busy,"late original ACK cannot revive or overwrite new page"):return finish(w)
 w.link.deliver(2,{"ok":true,"dialogue":{"kind":"original_permit_shop","token":"new","open_id":second,"name":"商人","text":"原价","choices":[{"id":"buy_one","text":"购买"}]}})
 if not check(ui.permit_token=="new" and not ui.choice.disabled,"only matching open reply enables choose"):return finish(w)
 ui._choose()
 if not check(w.link.sent[3]=={"type":"permit_shop_choose","token":"new","choice":"buy_one"} and ui.choice.disabled,"choose uses frozen token; no checkpoint or optimistic fee"):return finish(w)
 var old_lifecycle:int=w.link._lifecycle
 ui.permit_logout_begin()
 if not check(ui.permit_auth_retired and not ui.permit_active and w.link._lifecycle==old_lifecycle and w.link.sent[4].open_id==second,"logout locally retires before transport lifecycle changes"):return finish(w)
 var count:int=w.link.sent.size()
 w.link.deliver(3,{"ok":true,"committed":true,"closed":true})
 ui._choose()
 if not check(w.link.sent.size()==count and not ui.permit_active,"late committed ACK does not restore old purchase controls"):return finish(w)
 # Fresh consumer, same connection; realistic scene tree retirement with pending ACK.
 var other=Travel.new();w.add_child(other);other.world=w
 other.overlay=Control.new();w.add_child(other.overlay)
 other.body=Label.new();other.overlay.add_child(other.body)
 other.choice=Button.new();other.overlay.add_child(other.choice)
 other._permit_open(vendor)
 var third:String=other.permit_open_id
 w.remove_child(other)
 if not check(w.link.sent.back()=={"type":"permit_shop_cancel","open_id":third},"tree exit cancels original open on original context"):other.free();return finish(w)
 other.free()
 # Old consumer on a different transport owner must not cancel the new owner.
 var last=Travel.new();w.add_child(last);last.world=w
 last.overlay=Control.new();w.add_child(last.overlay)
 last.body=Label.new();last.overlay.add_child(last.body)
 last.choice=Button.new();last.overlay.add_child(last.choice)
 last._permit_open(vendor)
 count=w.link.sent.size();w.link._lifecycle+=1;w.link._peer=Peer.new()
 w.remove_child(last)
 if not check(w.link.sent.size()==count,"new transport generation never receives old cancel"):last.free();return finish(w)
 last.free()
 finish(w)
func finish(w:Node)->void:
 w.free()
 print("PERMIT PAGE UI LIFECYCLE: %d failures (synthetic transport only)"%failures)
 quit(1 if failures else 0)
