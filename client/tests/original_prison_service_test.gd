extends "res://tests/original_fixed_guards_test.gd"
const Prison=preload("res://server/original_prison_service.gd")
var guard:Dictionary={}
func setup():
 var b=Backend.new()
 b.session.snapshot()
 for event in range(48,53):
  if not event in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(event)
 guard=b.original_quests.npc_by_id(Prison.GUARD)
 return b
func position(b,npc:Dictionary)->void:
 b.automation.position_changed(int(npc.map_id),Vector2i(int(npc.cell[0])+1,int(npc.cell[1])))
func prison_talk(b,npc:Dictionary)->Dictionary:
 position(b,npc)
 return b.handle({"type":"quest_talk","npc_id":str(npc.id)})
func location(b,map_id:int,x:int,y:int)->bool:
 return b.session.snapshot().get("location",{})=={"map_id":map_id,"x":x,"y":y} and b.automation.position_map==map_id and b.automation.position_cell==Vector2i(x,y)
func run()->void:
 var probe=setup()
 check(Prison.valid(guard),"actual imported guard v1.1 catalog")
 if not Prison.valid(guard):probe.free();quit(1);return
 probe.free()
 fees()
 guides()
 await devices()
 print("ORIGINAL PRISON SERVICE: %d failures"%failures);quit(1 if failures else 0)
func fees()->void:
 var b=setup()
 for gold in [0,1,9,10,11,1000000000]:
  b.session._profile.player.gold=gold
  var r:=prison_talk(b,guard)
  if gold>0:r=choose(b,r,"yes")
  check(r.get("ok",false) and int(b.session.snapshot().player.gold)==gold-mini(gold,10),"real frozen fine "+str(gold)+": "+str(r))
  check(location(b,117,225,13) if gold==0 else location(b,110,23,27),"persistent and runtime warp "+str(gold))
 b.session._profile.player.gold=9;var r:=prison_talk(b,guard);b.session._profile.player.gold=100
 check(choose(b,r,"yes").get("ok",false) and int(b.session.snapshot().player.gold)==91,"increased balance pays frozen9")
 b.session._profile.player.gold=10;r=prison_talk(b,guard);b.session._profile.player.gold=9
 var before:Dictionary=b.session.snapshot()
 check(not choose(b,r,"yes").get("ok",false) and b.session.snapshot()==before,"insufficient confirm does not requote")
 b.session._profile.player.gold=11;r=prison_talk(b,guard);before=b.session.snapshot()
 check(choose(b,r,"no").get("ok",false) and b.session.snapshot()==before,"cancel unchanged")
 r=prison_talk(b,guard);b.quest_visit_guard=func():return "party"
 check(not choose(b,r,"yes").get("ok",false) and not prison_talk(b,guard).get("ok",false),"party rejected at open and confirm")
 b.quest_visit_guard=Callable();r=prison_talk(b,guard);b.automation.position_changed(117,Vector2i(20,20))
 check(not choose(b,r,"yes").get("ok",false),"walk away rejected")
 r=prison_talk(b,guard);b.battle_open=true
 check(not choose(b,r,"yes").get("ok",false),"battle rejected")
 b.battle_open=false;r=prison_talk(b,guard);before=b.session.snapshot()
 var pending:Dictionary=b.original_quests.pending.duplicate(true)
 var old_cell:Vector2i=b.automation.position_cell
 b.save_path="user://missing-prison-parent/save.json"
 var failed:=choose(b,r,"yes")
 check(failed.get("reason","")=="save_failed" and b.session.snapshot()==before and b.automation.position_cell==old_cell and b.automation.position_map==117,"savefail rolls back whole profile and live move")
 check(b.original_quests.pending==pending,"savefail retains same token and quote")
 b.save_path="user://prison-saved.json"
 check(choose(b,r,"yes").get("ok",false) and location(b,110,23,27),"same quote retries saved atomically")
 check(not choose(b,r,"yes").get("ok",false),"success replay rejected")
 var loaded=Backend.new()
 check(loaded.load_profile(b.save_path) and loaded.session.snapshot().location==b.session.snapshot().location and loaded.session.snapshot().player.gold==b.session.snapshot().player.gold,"reload persists balance and location")
 loaded.free();b.free()
func guides()->void:
 var b=setup();b.session._profile.player.gold=100
 for i in range(4):
  var id:String="genout/wpm_110_37_%d@110:37:%d"%[20+4*i,20+4*i]
  var npc:Dictionary=b.original_quests.npc_by_id(id)
  check(Prison.valid(npc),"real guide identity "+id)
  if npc.is_empty():continue
  b.session._profile.original_items=[];b.session._profile.original_instances=[]
  for item in Prison.DELETE.split(","):Session.OriginalEquipment.add(b.session._profile,int(item))
  Session.OriginalEquipment.add(b.session._profile,2708)
  var r:=prison_talk(b,npc)
  var before:Dictionary=b.session.snapshot()
  var frozen:Dictionary=b.original_quests.pending.duplicate(true)
  b.save_path="user://missing-prison-guide-parent/save.json"
  check(choose(b,r,"yes").get("reason","")=="save_failed" and b.session.snapshot()==before and b.original_quests.pending==frozen and b.automation.position_map==110,"guide ticket savefail preserves original consumed UIDs and same token")
  b.save_path="user://prison-guide-%d.json"%i
  check(choose(b,r,"yes").get("ok",false) and location(b,1012+1000*i,13,13) and b.session.snapshot().original_items==[2708],"ticket source deletion entire list and original destination")
  b.save_path=""
  for bits in [1,2,4,8,10,15,0]:
   b.session._profile.original_savepoint_bits=bits
   b.session._profile.original_items=[];b.session._profile.original_instances=[]
   Session.OriginalEquipment.add(b.session._profile,2521+(i+1)%4)
   Session.OriginalEquipment.add(b.session._profile,2708)
   var items:Array=b.session.snapshot().original_instances.duplicate(true)
   r=prison_talk(b,npc)
   if bits==0:check(not r.get("ok",false),"missing birth refuses recoverably");continue
   var target:PackedStringArray=Prison.birth(b.session.snapshot()).split(",")
   check(choose(b,r,"yes").get("ok",false) and location(b,int(target[0]),int(target[1]),int(target[2])) and b.session.snapshot().original_instances==items and int(b.session.snapshot().player.gold)==100,"no-ticket birth first bit with foreign ticket UIDs preserved")
 b.free()
func devices()->void:
 var b=setup();root.add_child(b);b.session._profile.player.gold=100;position(b,guard)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"prison LAN port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two prison devices")
 var first:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":Prison.GUARD})
 var second:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":Prison.GUARD})
 check(not (await request(links[0],{"type":"quest_choose","token":first.dialogue.token,"choice":"yes"})).ok,"old token rejected without clearing newer quote")
 var confirm:Dictionary={"type":"quest_choose","token":second.dialogue.token,"choice":"yes","price":0,"quantity":100,"map_id":1000}
 b.save_path="user://missing-prison-ws-parent/save.json"
 var frozen:Dictionary=b.original_quests.pending.duplicate(true)
 var before:Dictionary=b.session.snapshot()
 check((await request(links[0],confirm)).get("reason","")=="save_failed" and b.original_quests.pending==frozen and b.session.snapshot()==before,"WS savefail retains quote and whole profile")
 b.save_path="user://prison-ws-save.json"
 check((await request(links[1],confirm)).ok and int(b.session.snapshot().player.gold)==90 and location(b,110,23,27),"shared token with forged client economics ignored")
 check(not (await request(links[1],confirm)).ok and int(b.session.snapshot().player.gold)==90,"second device replay cannot pay or warp again")
 for link in links:link.close()
 links.clear();server.stop();server.queue_free();b.queue_free();await process_frame
