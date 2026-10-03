extends "res://tests/item_storage_test.gd"
const WsLink=preload("res://network/ws_link.gd")
const Codec=preload("res://network/codec.gd")
var peers: Array=[]
var states: Array=[]
func _process(delta: float) -> bool:
 for link in peers:link.poll(delta)
 return false
func ask(link,cmd:Dictionary) -> Dictionary:
 var result:=[{}];link.request(cmd,func(reply):result[0]=reply)
 check(await Wait.until(self,func():return not result[0].is_empty(),180),"Large-warehouse RPC response")
 return result[0]
func run() -> void:
 var b=fresh()
 var count:=3000*64
 for i in range(count):b.session._profile.item_storage.append(Equipment.instance(2468,i+1))
 b.session._profile.next_original_uid=count+1
 # Include the real rest of the profile and typical carried state in the payload.
 var begin:=Time.get_ticks_msec()
 var snapshot:Dictionary=b.full_snapshot()
 var encoded:=Codec.encode(snapshot)
 var byte_count:=encoded.to_utf8_buffer().size()
 print("MAX STORAGE count=%d bytes=%d buffer=%d snapshot_ms=%d"%[count,byte_count,32<<20,Time.get_ticks_msec()-begin])
 check(byte_count>(8<<20) and byte_count<(16<<20),"Maximum UID warehouse fits32MB with at least16MB remaining for other profile fields")
 begin=Time.get_ticks_msec()
 check(b.session._valid_profile(b.session.snapshot()) and Storage.used(b.session._profile)==3000,"Maximum192000 UIDs is a valid3000-stack save")
 print("MAX STORAGE validation_ms=%d"%(Time.get_ticks_msec()-begin))
 var path:="user://item-storage-max-%d.json"%OS.get_process_id();b.save_path=path
 begin=Time.get_ticks_msec();check(b.save(),"Persist maximum UID warehouse")
 var loaded=Session.new();check(loaded.load_game(path) and loaded.snapshot().item_storage.size()==count,"Read back every maximum-capacity UID")
 print("MAX STORAGE save_and_load_ms=%d"%(Time.get_ticks_msec()-begin))
 # Disable test persistence for the following wire checks: disk atomicity has
 # its dedicated suite and was checked above at maximum size as well.
 b.save_path=""
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"Maximum warehouse ephemeral server")
 begin=Time.get_ticks_msec()
 for i in range(2):
  var state=preload("res://network/client_state.gd").new();states.append(state)
  var link=WsLink.new("ws://127.0.0.1:%d"%server.port);peers.append(link);link.message.connect(state.apply);link.connect_now()
  check(await Wait.until(self,func():return link.online and state.profile.get("item_storage",[]).size()==count,180),"Real LAN receives full192000 UID snapshot on device%d"%i)
  await ask(link,{"type":"ping"})
 print("MAX STORAGE two_device_sync_ms=%d"%(Time.get_ticks_msec()-begin))
 begin=Time.get_ticks_msec()
 var result:Dictionary=await ask(peers[0],{"type":"item_storage_transfer","direction":"withdraw","revision":0,"items":[{"uids":[1,2,3]}]})
 check(result.get("ok",false),"Maximum warehouse real LAN partial withdrawal")
 await ask(peers[1],{"type":"ping"})
 check(await Wait.until(self,func():return states[1].profile.get("item_storage_revision",0)==1,180),"Second device receives full changed maximum warehouse")
 check(states[0].profile.item_storage.size()==count-3 and states[1].profile.item_storage.size()==count-3,"Neither device truncates large state")
 check(states[1].profile.original_instances.map(func(e):return int(e.uid))==[1,2,3],"Both devices agree on exact returned UIDs")
 print("MAX STORAGE partial_transfer_sync_ms=%d"%(Time.get_ticks_msec()-begin))
 result=await ask(peers[1],{"type":"item_storage_transfer","direction":"withdraw","revision":0,"items":[{"uids":[1]}]})
 check(not result.get("ok",true),"Maximum warehouse rejects stale second device replay")
 for link in peers:link.close()
 server.stop();server.queue_free();b.queue_free();await process_frame
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
 print("ITEM STORAGE CAPACITY LAN: %d failures"%failures)
 quit(1 if failures else 0)
