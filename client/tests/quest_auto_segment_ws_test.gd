extends SceneTree
const Backend=preload("res://server/backend.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
var links:Array=[]
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func poll()->void:
 for link in links:link.poll(0.01)
func rpc(link,command:Dictionary)->Dictionary:
 var answers:Array=[]
 link.request(command,func(reply):answers.append(reply))
 check(await Wait.until(self,func():poll();return not answers.is_empty()),"Actual WS round trip")
 return {} if answers.is_empty() else answers[0]
func ack(b,client:String)->Dictionary:
 var receipt:Dictionary=b.quest_auto.issued[-1]
 var result={"type":"report_position","map_id":receipt.map_id,"cell":receipt.cell.duplicate(),"client":client,"quest_position_seq":receipt.seq}
 for key in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id"]:result[key]=receipt[key]
 return result
func run()->void:
 var b=Backend.new();b.set_process(false);root.add_child(b)
 b.quest_catalog.enabled_events=[2]
 b.session._profile.original_savepoint_bits=2
 b.session._profile.no_random_encounters=true
 b.automation.position_changed(100,Vector2i(637,494))
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"Isolated real WS server")
 for index in range(2):
  var link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
  links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(link):return link.online)),"Two real devices connected")
 check((await rpc(links[0],{"type":"set_automation_settings","settings":{"quest":{"mode":"C"}}})).ok,"WS persists C")
 check((await rpc(links[0],{"type":"quest_auto_start","quest_id":11,"client":"first"})).ok,"WS starts C at actual audited landing")
 for index in range(3):b.quest_auto.tick(b,0.1)
 check(b.quest_auto.phase=="segment_landing","Actual C segment endpoint waits")
 var old:Dictionary=ack(b,"first")
 await rpc(links[1],old)
 check(b.quest_auto.phase=="segment_landing","Second transport cannot reuse first-device complete ACK")
 var incomplete:Dictionary=old.duplicate(true);incomplete.erase("quest_segment_id")
 await rpc(links[0],incomplete)
 check(b.quest_auto.phase=="segment_landing","Actual codec cannot bypass complete identity")
 var fractional:Dictionary=old.duplicate(true);fractional.cell[0]+=0.25
 await rpc(links[0],fractional)
 check(b.quest_auto.phase=="segment_landing","Real fast endpoint rejects fractional ACK")
 var position:Vector2i=b.automation.position_cell
 links[0].close()
 check(await Wait.until(self,func():poll();return b.quest_auto.detached),"Actual socket disconnect detaches runner")
 await rpc(links[1],old)
 check(b.quest_auto.detached,"Old capability cannot rebind after true disconnect")
 await rpc(links[1],{"type":"report_position","map_id":100,"cell":[position.x,position.y],"client":"second"})
 check(not b.quest_auto.detached and b.quest_auto.phase=="segment_landing","New device handshake emits fresh endpoint receipt")
 await rpc(links[1],ack(b,"second"))
 check(b.quest_auto.phase=="travel","Real WS complete new-device ACK resumes")
 b.quest_auto.tick(b,0.1)
 check(b.automation.position_cell!=position,"New segment continues from actual last cell")
 await rpc(links[1],{"type":"quest_auto_stop"})
 position=b.automation.position_cell
 await rpc(links[1],old)
 b.quest_auto.tick(b,100.0)
 check(not b.quest_auto.running and b.automation.position_cell==position,"Late WS ACK never revives cancelled fast run")
 for link in links:link.close()
 server.stop();server.queue_free();b.queue_free()
 await process_frame
 print("QUEST AUTO SEGMENT WS: %d failures"%failures)
 quit(1 if failures else 0)
