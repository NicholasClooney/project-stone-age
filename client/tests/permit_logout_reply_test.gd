extends SceneTree
# TMP UNPARSED/UNRUN. Uses actual LogoutReply with synthetic owners/transport.
const Remote=preload("res://scripts/game/game_remote.gd")
class Counter extends RefCounted:
 var remembered:=0
 var reloaded:=0
 func reload_current_scene()->int:
  reloaded+=1
  return OK
class Text extends RefCounted:
 var text:="unchanged"
class Link extends RefCounted:
 var _lifecycle:=9
 var _peer:RefCounted
class Scene extends RefCounted:
 var link
 var message=Text.new()
 var counter:Counter
 func is_inside_tree()->bool:return true
 func get_tree():return counter
class Owner extends RefCounted:
 var game
 var logout_generation:=3
 var counter:Counter
 func _remember_login()->void:counter.remembered+=1
var failures:=0
func _initialize()->void:call_deferred("run")
func fixture()->Dictionary:
 var counter=Counter.new()
 var peer=RefCounted.new()
 var link=Link.new();link._peer=peer
 var scene=Scene.new();scene.link=link;scene.counter=counter
 var owner=Owner.new();owner.game=scene;owner.counter=counter
 var guard=Remote.LogoutReply.new()
 guard.owner_ref=weakref(owner);guard.game_ref=weakref(scene)
 guard.link_ref=weakref(link);guard.peer_ref=weakref(peer)
 guard.lifecycle=9;guard.generation=3
 return {"counter":counter,"peer":peer,"link":link,"scene":scene,"owner":owner,"guard":guard}
func check(ok:bool,label:String)->bool:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
 return ok
func exercise(mode:String)->bool:
 var f:Dictionary=fixture()
 var reply:Dictionary={"ok":true}
 match mode:
  "stale":reply={"ok":false,"stale":true,"reason":"superseded"}
  "stale_ok":reply={"ok":true,"stale":true}
  "false":reply={"ok":false,"reason":"original rejection"}
  "owner_freed":f.owner=null
  "scene_freed":f.owner.game=null;f.scene=null
  "link_freed":f.scene.link=null;f.link=null
  "peer_freed":f.link._peer=null;f.peer=null
  "link_replaced":f.scene.link=Link.new()
  "peer_replaced":f.link._peer=RefCounted.new()
  "lifecycle_changed":f.link._lifecycle+=1
  "generation_changed":f.owner.logout_generation+=1
  "owner_scene_replaced":f.owner.game=Scene.new()
 Remote.LogoutReply.deliver(reply,f.guard)
 # A duplicate callback never gains new permission, even after initial rejection.
 Remote.LogoutReply.deliver({"ok":true},f.guard)
 var success:bool=mode=="success"
 if not check(f.counter.remembered==(1 if success else 0),mode+": remember count is exact"):return false
 if not check(f.counter.reloaded==(1 if success else 0),mode+": reload count is exact"):return false
 if f.scene!=null:
  var expected:String="original rejection" if mode=="false" else "unchanged"
  if not check(f.scene.message.text==expected,mode+": only original non-stale refusal writes message"):return false
 return check(f.guard.delivered,mode+": once latch consumed")
func run()->void:
 for mode in ["success","stale","stale_ok","false","owner_freed","scene_freed","link_freed","peer_freed","link_replaced","peer_replaced","lifecycle_changed","generation_changed","owner_scene_replaced"]:
  if not exercise(mode):
   finish()
   return
 finish()
func finish()->void:
 print("PERMIT LOGOUT REPLY: %d failures (synthetic owners; no WS/auth/filesystem proof)"%failures)
 quit(1 if failures else 0)
