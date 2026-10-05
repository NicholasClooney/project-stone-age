extends "res://tests/required_fee_test.gd"
const Server=preload("res://server/ws_server.gd")
func run()->void:
 var b=Backend.new()
 if not setup(b,"permit","server-stop-order",1000):b.free();quit(1);return
 var server=Server.new(b,0)
 var peer=WebSocketPeer.new()
 # Explicit private promotion fixture, not an OPEN socket or authenticated device.
 server._promote(peer)
 var connection:int=peer.get_instance_id()
 var opened:Dictionary=permit_command(b,{"type":"permit_shop_open","source_id":SHOP,"open_id":"server-stop-page"},connection)
 check(opened.get("ok",false) and opened.has("dialogue"),"Actual permit service page using registered transport epoch")
 if failures:server.free();b.free();quit(1);return
 var old_epoch=b._fee_bindings[connection]
 var fired:Array=[false]
 var weak_server:WeakRef=weakref(server)
 var weak_backend:WeakRef=weakref(b)
 b.event.connect(func(_message):
  if failures or fired[0]:return
  fired[0]=true
  var host=weak_server.get_ref();var backend=weak_backend.get_ref()
  check(is_instance_valid(host) and is_instance_valid(backend),"Captured stop owners are live")
  if failures:return
  check(host._stopping and not backend._fee_bindings.has(connection) and backend.original_quests.pending.is_empty(),"ALL original fee capability retired before real suspend publication")
  if failures:return
  var new_peer=WebSocketPeer.new()
  host._promote(new_peer)
  check(not new_peer in host.clients() and not backend._fee_bindings.has(new_peer.get_instance_id()),"Reentrant promotion cannot create a new client/fee epoch during stop")
  if failures:return
  check(host.start()==ERR_BUSY,"Reentrant restart rejected before listener mutation")
  if failures:return
  host.stop() # nested stop is no-op; must not retire arbitrary later state
  var before:Dictionary=record(backend)
  if failures:return
  host._receive(peer,JSON.stringify({"type":"permit_shop_open","source_id":SHOP,"open_id":"during-stop"}))
  host._process(0.0)
  check(record(backend)==before,"Nested receive/process dispatch no new request during stop")
 )
 b.quest_auto.running=true;b.quest_auto.quest_id=1;b.quest_auto.connection=connection;b.quest_auto.identity.begin()
 server.stop()
 if failures:server.free();b.free();quit(1);return
 check(fired[0] and server._stopped and not server._stopping and not b._fee_bindings.has(connection),"Original stop returns once after actual suspend observer")
 if failures:server.free();b.free();quit(1);return
 var rejected:Dictionary=b.handle({"type":"permit_shop_choose","token":opened.dialogue.token,"choice":"buy_one","_quest_connection":connection,"_fee_binding":old_epoch})
 check(not rejected.get("ok",true),"Retired original epoch cannot purchase after stop")
 if failures:server.free();b.free();quit(1);return
 print("FEE SERVER STOP ORDER: 0 failures; internal peer fixture, no OPEN/shutdown-full claim")
 server.free();b.free();quit(0)
