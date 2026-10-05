extends "res://tests/required_fee_test.gd"
const Hub=preload("res://server/profile_hub.gd")
const Presence=preload("res://server/presence.gd")
# Account authentication/storage is not under test. Only actual connection lifecycle bodies.
class TraceAccounts extends RefCounted:
 var revoked:Array=[]
 func revoke_token(id:String,token:String)->void:revoked.append([id,token])
 func profiles()->Array:return []
 func allow_create()->bool:return false
class PreparedHub extends Hub:
 var after_attach:Callable
 func open_profile(id:String)->String:return "" if backends.has(id) else "fixture missing backend"
 func _attach(id:String)->void:
  super._attach(id)
  if after_attach.is_valid():after_attach.call()
class ObservedPresence extends Presence:
 var after_forget:Callable
 func forget(connection)->void:
  super.forget(connection)
  if after_forget.is_valid():after_forget.call()
var observed:Dictionary={}
func run()->void:
 for mode in ["admin_publish","attach_return","presence_return","logout_stop","disconnect_detach"]:
  var hub=PreparedHub.new()
  hub.accounts=TraceAccounts.new();hub.tick=false;hub.share_dir=""
  var first=Backend.new();var second=Backend.new()
  if not setup(first,"permit","connection-"+mode+"-a",1000):first.free();second.free();hub.free();quit(1);return
  if not setup(second,"permit","connection-"+mode+"-b",1000):first.free();second.free();hub.free();quit(1);return
  first.admin=false;second.admin=false
  hub.backends={"a":first,"b":second}
  hub._connections[71]={"id":"a","token":"old-test-token"}
  var opened:Dictionary=open_fee(first,"permit")
  check(opened.get("ok",false) and opened.has("dialogue"),"Old page installed before connection operation")
  if failures:first.free();second.free();hub.free();quit(1);return
  var fired:Array=[false]
  var weak_hub:WeakRef=weakref(hub)
  var weak_first:WeakRef=weakref(first)
  var weak_second:WeakRef=weakref(second)
  var perform:Callable=func():
   if failures or fired[0]:return
   fired[0]=true
   var host=weak_hub.get_ref();var old=weak_first.get_ref();var target=weak_second.get_ref()
   check(is_instance_valid(host) and is_instance_valid(old) and is_instance_valid(target),"Captured owners remain live")
   if failures:return
   check(not old._fee_bindings.has(71) or mode in ["attach_return","presence_return"],"Old fee epoch retired before real publishing stop/enter")
   if failures:return
   var nested:Dictionary=host._enter(71,{"id":"b","name":"second","admin":false},"new-test-token")
   check(nested.get("ok",false),"Nested actual _enter installs intended successor")
   if failures:return
   var old_record:Dictionary=record(old)
   if failures:return
   var new_record:Dictionary=record(target)
   if failures:return
   observed={"record":host._connections[71],"value":host._connections[71].duplicate(true),"epoch":target._fee_bindings[71],"first":old_record,"second":new_record,"revoked":host.accounts.revoked.duplicate(true)}
  if mode=="attach_return":hub.after_attach=perform
  elif mode=="presence_return":
   var presence=ObservedPresence.new();presence.after_forget=perform;hub.presence=presence
  else:
   first.event.connect(func(_message):
    if failures:return
    perform.call()
   )
  var reply:Dictionary={}
  if mode=="logout_stop":
   first.quest_auto.running=true;first.quest_auto.connection=71;first.quest_auto.quest_id=1
   first.quest_auto.identity.begin()
   reply=hub._logout(71)
  elif mode=="disconnect_detach":
   first.quest_auto.running=true;first.quest_auto.connection=71;first.quest_auto.quest_id=1
   first.quest_auto.identity.begin()
   hub.disconnect_connection(71)
  else:reply=hub._enter(71,{"id":"a","name":"first","admin":mode=="admin_publish"},"outer-test-token")
  if failures:first.free();second.free();hub.free();quit(1);return
  check(fired[0],"Required real publish or explicit return-double injection reached")
  if failures:first.free();second.free();hub.free();quit(1);return
  if mode!="disconnect_detach":
   check(not reply.get("ok",true) and reply.get("stale",false),"Outer operation reports superseded instead of old success")
   if failures:first.free();second.free();hub.free();quit(1);return
  check(is_same(hub._connections[71],observed.record) and hub._connections[71]==observed.value and second._fee_bindings[71]==observed.epoch,"Old tail cannot erase/replace successor record or epoch")
  if failures:first.free();second.free();hub.free();quit(1);return
  check(record(first)==observed.first and record(second)==observed.second and hub.accounts.revoked==observed.revoked and hub._connection_calls.is_empty(),"No old caller tail save/activity/revoke; only own short call retired")
  if failures:first.free();second.free();hub.free();quit(1);return
  print("FEE CONNECTION ORDER COMPLETE ",mode)
  first.free();second.free();hub.free()
 print("FEE CONNECTION ORDER: 0 failures; internal lifecycle bodies, not authenticated WS")
 quit(0)
