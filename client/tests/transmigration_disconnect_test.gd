extends "res://tests/original_fixed_guards_test.gd"
func run()->void:
 var dir:="user://rebirth-disconnect-%d"%OS.get_process_id()
 DirAccess.make_dir_recursive_absolute(dir)
 var hub=Hub.new(dir+"/accounts.json");hub.tick=false;hub.backups=false;hub.share_dir="";root.add_child(hub)
 check(hub.start(),"real isolated profile Hub starts")
 var server=Server.new(hub,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"real websocket profile server starts")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
  check(await Wait.until(self,func():poll();return link.awaiting_login),"device reaches actual login")
  var replies:=[{}]
  link.login({"type":"create_profile" if i==0 else "login","name":"RebirthProof","pin":"1234"},func(r):replies[0]=r)
  check(await Wait.until(self,func():poll();return link.online and not replies[0].is_empty()),"device authenticates same character")
 var b=hub.backends.values()[0]
 for id in [2771,2772,2773,2774]:Session.OriginalEquipment.add(b.session._profile,id)
 check(b.save(),"history proof inventory persisted before network disconnect")
 var before:Dictionary=b.session.snapshot()
 var id:String=str(hub.backends.keys()[0])
 links[0].close()
 check(await Wait.until(self,func():poll();return hub.connections_of(id).size()==1),"first socket genuinely disconnects")
 check(b.session.snapshot()==before,"one device disconnect never clears history items")
 links[1].close()
 check(await Wait.until(self,func():poll();return hub.connections_of(id).is_empty()),"last socket genuinely disconnects")
 check(b.session.snapshot()==before,"zero connected devices still do not perform character load")
 var token:String=links[0].login_token
 var reconnect=Link.new("ws://127.0.0.1:%d"%server.port);reconnect.login_name="RebirthProof";reconnect.login_token=token;links=[reconnect];reconnect.connect_now()
 check(await Wait.until(self,func():poll();return reconnect.online),"authenticated reconnect uses remembered device token")
 await request(reconnect,{"type":"ping"})
 check(hub.backends.values()[0]==b and b.session.snapshot()==before,"reconnect retains same Backend and all four proof UIDs")
 var path:String=b.save_path
 var loaded=Session.new()
 check(loaded.load_game(path) and loaded.snapshot().original_items.is_empty(),"genuine new character load clears only reviewed proof items")
 for link in links:link.close()
 links=[];server.stop();hub.shut_down();server.queue_free();hub.queue_free()
 print("TRANSMIGRATION DISCONNECT: %d failures"%failures);quit(1 if failures else 0)
