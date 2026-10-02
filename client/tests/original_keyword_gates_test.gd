extends "res://tests/bonus_quest_transactions_test.gd"
var gates:Array=[]
func setup():
 var b=Backend.new()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-keyword-gates.json"))
 gates=fixture.npcs
 b.quest_catalog.npcs.append_array(gates)
 b.quest_catalog.enabled_events.append_array([9,20,21,22])
 b.session.gm_raise_level(-1,30)
 return b
func answer(b,r:Dictionary,text:String)->Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":"submit","text":text})
func run()->void:
 var b=setup()
 for npc in gates:
  var phrase:String=npc.branches[0].keyword
  var r:=talk(b,npc.id)
  check(r.dialogue.choices.map(func(choice):return str(choice.id))==["submit","no"],"public keyword controls replace yes/no with submit/no")
  check(r.dialogue.input=="text" and not JSON.stringify(r).contains(phrase),"keyword is not exposed in public prompt")
  var before:Dictionary=b.session.snapshot()
  check(not answer(b,r,phrase+" ").ok and b.session.snapshot()==before,"trailing space is not exact original strcmp")
  r=talk(b,npc.id)
  check(choose(b,r,"no").ok and b.session.snapshot()==before,"cancel preserves profile")
  r=talk(b,npc.id);b.save_path="user://missing-keyword-parent/fail.json"
  check(not answer(b,r,phrase).ok and b.session.snapshot()==before,"save failure restores original location")
  check(not answer(b,r,phrase).ok,"failed transaction token cannot replay")
  b.save_path="user://keyword-gates.json"
  r=talk(b,npc.id)
  check(answer(b,r,phrase).ok,"exact original keyword commits")
  var target:PackedStringArray=str(npc.branches[0].actions.Warp).split(",")
  check(b.automation.position_map==int(target[0]) and b.automation.position_cell==Vector2i(int(target[1]),int(target[2])),"source Warp updates authoritative position")
  var loaded=Session.new()
  check(loaded.load_game(b.save_path) and loaded.snapshot().location==b.session.snapshot().location,"keyword destination survives real save validation")
  check(not answer(b,r,phrase).ok,"successful token cannot replay")
 b.free()
 await keyword_lan()
 DirAccess.remove_absolute(ProjectSettings.globalize_path("user://keyword-gates.json"))
 print("ORIGINAL KEYWORD GATES: %d failures"%failures)
 quit(1 if failures else 0)
func keyword_lan()->void:
 var b=setup();root.add_child(b)
 var npc:Dictionary=gates[0];place(b,npc.id)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"keyword LAN server on ephemeral port")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port)
  links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two keyword devices connect")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var one:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":npc.id})
 var two:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":npc.id})
 var command:Dictionary={"type":"quest_choose","token":one.dialogue.token,"choice":"submit","text":npc.branches[0].keyword}
 check(not (await request(links[0],command)).ok,"other device invalidates old keyword token")
 command.token=two.dialogue.token
 # Forged destination fields are ignored; only the pinned source Warp applies.
 command.actions={"Warp":"1000,1,1"}
 check((await request(links[1],command)).ok and b.automation.position_map==11101,"LAN source keyword ignores client forged destination")
 check(not (await request(links[0],command)).ok,"other device cannot replay committed keyword")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
