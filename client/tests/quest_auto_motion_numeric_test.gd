extends SceneTree
const Backend=preload("res://server/backend.gd")
const Motion=preload("res://server/quest_auto_motion.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
var link
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func rpc(command:Dictionary)->Dictionary:
 var answer:Array=[]
 link.request(command,func(reply):answer.append(reply))
 check(await Wait.until(self,func():link.poll(0.01);return not answer.is_empty()),"Real WS round trip")
 return {} if answer.is_empty() else answer[0]
func run()->void:
 var b=Backend.new();b.set_process(false);root.add_child(b)
 b.session._profile.no_random_encounters=true
 var portal:Dictionary={}
 for candidate in b.quest_helper.places.links(1300).values():
  if int(candidate.to_map)==100:portal=candidate;break
 check(not portal.is_empty(),"Original 1300 to100 portal exists")
 b.automation.position_changed(1300,Vector2i(portal.cell[0],portal.cell[1]))
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"Server uses isolated port0")
 link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port);link.connect_now()
 check(await Wait.until(self,func():link.poll(0.01);return link.online),"Real WS connects")
 check((await rpc({"type":"quest_auto_start","quest_id":12,"client":"numeric"})).ok,"Real WS starts original job")
 b.quest_auto.tick(b,0.21)
 check(b.quest_auto.phase=="landing" and b.automation.position_map==100,"Original portal reaches actual landing")
 var receipt:Dictionary=b.quest_auto.issued[-1]
 var ack:Dictionary={"type":"report_position","map_id":100,"cell":[int(portal.target[0]),int(portal.target[1])],"client":"numeric","quest_position_seq":receipt.seq}
 for field in Motion.IDENTITY_FIELDS:ack[field]=receipt[field]
 check(receipt.cell[0] is int and receipt.quest_segment.cells[0].cell[0] is int and receipt.quest_segment.from_cell[0] is int,"JSON float source normalized throughout packet")
 for value in [true,NAN,INF,621.25,"621"]:
  var forged:Dictionary=ack.duplicate(true);forged.cell=[value,190]
  check(not Motion.matches(forged,receipt,b.quest_auto.identity),"Malformed scalar cannot be truncated to an integer")
  check(Motion.packet(b.quest_auto.identity,1,{"map_id":100,"cell":[value,190]},{},true).is_empty(),"Malformed source packet rejected")
 var fractional:Dictionary=ack.duplicate(true);fractional.cell=[float(portal.target[0])+0.25,float(portal.target[1])]
 await rpc(fractional)
 check(b.quest_auto.phase=="landing","Fractional WS ack cannot release landing")
 var old_float:Dictionary=receipt.duplicate(true);old_float.cell=[float(portal.target[0]),float(portal.target[1])]
 check(Motion.matches(ack,old_float,b.quest_auto.identity),"Validated mathematical integers compare across old float receipt and codec ints")
 check((await rpc(ack)).ok and b.quest_auto.phase=="travel","Complete real WS integer ACK releases float-source portal")
 link.close();server.stop();server.queue_free();b.queue_free()
 await process_frame
 print("QUEST AUTO MOTION NUMERIC: %d failures"%failures)
 quit(1 if failures else 0)
