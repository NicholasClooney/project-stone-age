extends SceneTree
## Real socket lifecycle regression; callback-close is an explicit fault fixture.
## Companion original scene diagnostic retains logout/reload/profile coverage.
const Backend=preload("res://server/backend.gd")
const Server=preload("res://server/ws_server.gd")
const Link=preload("res://network/ws_link.gd")
const Wait=preload("res://tests/support/wait.gd")
var backend
var server
var link
var stage:String=""
var fired:bool=false
var connected_count:int=0
var snapshots:int=0
var disconnected_count:int=0
var retired_peer
var replacement_peer
var replacement_callbacks:Dictionary={}
var reentry_checks:bool=true
var replies:Dictionary={}
var log_rows:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->bool:
	print(("PASS " if ok else "FAIL ")+note)
	if not ok:quit(1)
	return ok
func until(condition:Callable,note:String)->bool:
	return check(await Wait.until(self,func():link.poll(0.016);return condition.call()),note)
func count_reply(key:String,reply:Dictionary)->void:
	replies[key]=int(replies.get(key,0))+1
	log_rows.append({"stage":stage,"key":key,"ok":reply.get("ok",false),"reason":reply.get("reason","")})
	print("LIFECYCLE REPLY ",JSON.stringify(log_rows.back()))
func on_snapshot(event:Dictionary)->void:
	if event.get("type","")!="snapshot":return
	snapshots+=1
	if fired:return
	if stage=="snapshot_close":
		fired=true
		link.request({"type":"ping"},func(reply):count_reply("pending",reply))
		retired_peer=link._peer
		link.close()
		reentry_checks=reentry_checks and disconnected_count==1 and replies.get("pending",0)==1 and not link.online
		link.request({"type":"ping"},func(reply):count_reply("after_close",reply))
	elif stage=="snapshot_replace":
		fired=true
		retired_peer=link._peer
		link.connect_now() # Real replacement, no forged receive/snapshot call.
func on_connected()->void:
	connected_count+=1
	if stage=="connected_close" and not fired:
		fired=true
		link.request({"type":"ping"},func(reply):count_reply("pending",reply))
		retired_peer=link._peer
		link.close()
		reentry_checks=reentry_checks and disconnected_count==1 and replies.get("pending",0)==1 and not link.online
func downstream_connected()->void:
	if stage=="connected_close":
		# Signal iteration may already be underway; a later subscriber must
		# receive a synchronous rejection, not send to the now-closed transport.
		link.request({"type":"ping"},func(reply):count_reply("after_close",reply))
func fresh(which:String)->void:
	if link!=null:link.close()
	stage=which;fired=false;connected_count=0;snapshots=0;replies={};log_rows=[]
	disconnected_count=0;reentry_checks=true;retired_peer=null;replacement_peer=null;replacement_callbacks={}
	link=Link.new("ws://127.0.0.1:%d"%server.port)
	link.message.connect(on_snapshot)
	link.connected.connect(on_connected)
	link.connected.connect(downstream_connected)
	link.disconnected.connect(func():disconnected_count+=1)
	link.connect_now()
func barrier()->bool:
	var ack:Dictionary={}
	var count:Array=[0]
	link.request({"type":"ping"},func(reply):count[0]+=1;ack.merge(reply))
	if not await until(func():return ack.get("ok",false),"Real new-connection barrier succeeds"):return false
	return check(count[0]==1,"Valid ping ACK callback occurs once")
func run()->void:
	backend=Backend.new();root.add_child(backend);backend.set_process(false)
	server=Server.new(backend,0,"127.0.0.1");root.add_child(server)
	if not check(server.start()==OK,"Real isolated server port0"):return
	for which in ["snapshot_close","connected_close"]:
		fresh(which)
		if not await until(func():return fired and not link.online,"Close synchronously revokes online"):return
		if not check(reentry_checks and disconnected_count==1 and retired_peer.get_ready_state()!=WebSocketPeer.STATE_OPEN,"Close synchronously signals once, settles pending, and closes captured peer"):return
		if not check(connected_count==(0 if which=="snapshot_close" else 1),"No old connected after snapshot close; already-emitting signal remains one"):return
		if not check(replies=={"pending":1,"after_close":1} and link._callbacks.is_empty(),"Pending and post-close callbacks each complete once, no queued replay"):return
		for row in log_rows:
			if not check(not row.ok and row.reason=="offline","Each close rejection is explicit offline"):return
		stage="recovered"
		link.connect_now()
		if not await until(func():return link.online,"Explicit reconnect authenticates") or not await barrier():return
		if not check(replies=={"pending":1,"after_close":1},"Retired callbacks never run again on the new connection"):return
	fresh("snapshot_replace")
	if not await until(func():return fired and snapshots==2 and link.online,"Synchronous snapshot replacement gets real second hello"):return
	if not check(connected_count==1,"Only replacement authentication emits connected") or not await barrier():return
	if not check(retired_peer.get_ready_state()!=WebSocketPeer.STATE_OPEN,"Snapshot replacement explicitly closes old peer"):return
	stage="callback_reconnect"
	link.request({"type":"ping"},func(reply):
		count_reply("old_first",reply)
		link.connect_now()
		replacement_peer=link._peer
		replacement_callbacks=link._callbacks)
	link.request({"type":"ping"},func(reply):
		count_reply("old_second",reply)
		reentry_checks=reentry_checks and link._peer==replacement_peer and is_same(link._callbacks,replacement_callbacks))
	retired_peer=link._peer
	var disconnected_before:int=disconnected_count
	link.close()
	if not check(reentry_checks and link._peer==replacement_peer and is_same(link._callbacks,replacement_callbacks),"Remaining retired callbacks do not replace new peer or callback map"):return
	if not check(disconnected_count==disconnected_before,"Old retirement suppresses a stale disconnect after callback replaced owner"):return
	if not check(retired_peer.get_ready_state()!=WebSocketPeer.STATE_OPEN and replies.get("old_first",0)==1 and replies.get("old_second",0)==1,"Both original requests rejected exactly once and old socket closed"):return
	for row in log_rows:
		if row.key in ["old_first","old_second"] and not check(not row.ok and row.reason=="offline","Retired callbacks never receive new-peer ACK"):return
	link.connected.connect(func():
		if stage=="callback_reconnect":link.request({"type":"ping"},func(reply):count_reply("new_valid",reply)))
	if not await until(func():return link.online and replies.get("new_valid",0)==1,"New peer receives its own valid request callback"):return
	if not await barrier():return
	for row in log_rows:
		if row.key=="new_valid" and not check(row.ok,"Replacement peer returns a successful real ACK"):return
	if not check(replies.get("new_valid",0)==1 and replies.get("old_first",0)==1 and replies.get("old_second",0)==1,"New valid ACK and old rejections remain once after barrier"):return
	if not check(link._callbacks.is_empty(),"No pending callback survives settled requests"):return
	stage="nonopen_request"
	link.request({"type":"ping"},func(reply):count_reply("pending_nonopen",reply))
	retired_peer=link._peer
	link._peer.close() # Actual socket-closing fault, deliberately bypass public close.
	var reply:Dictionary=link.request({"type":"ping"},func(answer):count_reply("rejected_nonopen",answer))
	if not check(retired_peer.get_ready_state()!=WebSocketPeer.STATE_OPEN and link._hello_seq==-1 and link._login_seq==-1 and link._ping_seq==-1,"NonOPEN retirement closes peer and clears all request markers"):return
	if not check(not reply.ok and not link.online and link._callbacks.is_empty(),"NonOPEN request rejects and clears previous callbacks"):return
	if not check(replies.get("pending_nonopen",0)==1 and replies.get("rejected_nonopen",0)==1,"NonOPEN callbacks complete exactly once"):return
	link.close();server.stop();backend.queue_free();server.queue_free()
	await process_frame
	print("WS LINK AUTH LIFECYCLE: PASS")
	quit(0)
