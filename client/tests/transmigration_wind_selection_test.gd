extends "res://tests/original_fixed_guards_test.gd"
var selection_fixture:Dictionary={}
func setup():
 var b=fresh()
 selection_fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-wind-selection.json"))
 b.quest_catalog.npcs.append_array(selection_fixture.npcs.duplicate(true))
 b.quest_catalog.items.merge(selection_fixture.items)
 b.quest_catalog.enabled_events.append_array([41,42])
 b.session._profile.pets=[]
 b.session.gm_grant_pet(95)
 var template:Dictionary=b.session._profile.pets[0].duplicate(true)
 b.session._profile.pets=[]
 for pair in [["pet-101",61,0],["pet-102",60,0],["pet-103",70,1]]:
  var pet:Dictionary=template.duplicate(true)
  pet.pet_id=pair[0];pet.level=pair[1];pet.original_end_event=pair[2]
  b.session._profile.pets.append(pet)
 b.session._profile.next_pet_id=104
 Rules.set_flag(b.session._profile,"ended",4,true)
 Rules.set_flag(b.session._profile,"ended",42,true)
 return b
func offer(b)->Dictionary:return source_talk(b,selection_fixture.npcs[0])
func selected(b,r:Dictionary,ids:Variant)->Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":"yes","pet_ids":ids})
func run()->void:
 matrix()
 transactions()
 await selected_lan()
 print("WIND SELECTION: %d failures"%failures)
 quit(1 if failures else 0)
func matrix()->void:
 var b=setup();var npc:Dictionary=selection_fixture.npcs[0]
 for end4 in [false,true]:
  for end42 in [false,true]:
   for bracelet in [false,true]:
    for level in [1,42,43,59,60,61]:
     for event in [0,1]:
      Rules.set_flag(b.session._profile,"ended",4,end4);Rules.set_flag(b.session._profile,"ended",42,end42)
      b.session._profile.original_items=[];b.session._profile.original_instances=[]
      if bracelet:Session.OriginalEquipment.add(b.session._profile,2758)
      b.session._profile.pets=b.session._profile.pets.slice(0,1)
      b.session._profile.pets[0].level=level;b.session._profile.pets[0].original_end_event=event
      var expected:int=0 if end4 and end42 and level>=61 and event==0 else (1 if bracelet and level>=43 and event==0 else (2 if bracelet and event==0 else -1))
      var branch:Dictionary=b.original_quests.branch_for(npc,b.session.snapshot())
      var actual:int=int(branch.get("source_branch_index",-1))
      check(actual==expected if expected>=0 else actual>=3,"original C matrix END4=%s END42=%s ring=%s Lv%d event%d"%[end4,end42,bracelet,level,event])
 b.free()
func transactions()->void:
 var b=setup();var r:=offer(b)
 check(r.dialogue.kind=="original_pet_selection" and r.dialogue.pet_candidates.map(func(p):return p.pet_id)==["pet-101","pet-102"],"candidate eligibility uses deletion >=60, excludes event pet")
 var before:Dictionary=b.session.snapshot()
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"multiple candidates require explicit UID")
 for invalid in [["pet-103"],["missing"],["pet-101","pet-102"],[1],"pet-102"]:
  r=offer(b);check(not selected(b,r,invalid).ok and b.session.snapshot()==before,"invalid selection rejected "+str(invalid))
 r=offer(b);check(choose(b,r,"no").ok and b.session.snapshot()==before,"cancel does not consume")
 r=selected(b,offer(b),["pet-102"])
 b.session._profile.pets.reverse()
 check(choose(b,r,"ok").ok,"reordered roster commits selected UID")
 check(b.session.snapshot().pets.map(func(p):return p.pet_id)==["pet-103","pet-101"],"60 consumed and61 retained despite slot reorder")
 check(b.session.snapshot().original_items.size()==1 and not choose(b,r,"ok").ok,"no bracelet high reward once and replay refused")
 b.free();b=setup();r=selected(b,offer(b),["pet-102"])
 b.session._profile.pets.remove_at(1);before=b.session.snapshot()
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"missing chosen UID cannot fall back to first")
 b.free();b=setup();r=selected(b,offer(b),["pet-102"])
 b.session._profile.pets[0].level=60;before=b.session.snapshot()
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"high predicate revalidated independently from deletion")
 b.free();b=setup();r=selected(b,offer(b),["pet-102"])
 b.session._profile.pets[1].original_end_event=1;before=b.session.snapshot()
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"chosen UID event mutation rejected")
 b.free();b=setup()
 b.session._profile.active_pet=1;b.session._profile.ride_pet=1
 before=b.session.snapshot();r=selected(b,offer(b),["pet-102"])
 b.save_path="user://missing-wind-selection-parent/fail.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"save failure preserves pet, active/ride references and rewards")
 b.save_path="user://wind-selection.json";r=selected(b,offer(b),["pet-102"])
 check(choose(b,r,"ok").ok and b.session.snapshot().active_pet==-1 and b.session.snapshot().ride_pet==-1,"saved selected active/ride pet clears references")
 var loaded=Backend.new();check(loaded.load_profile(b.save_path),"selected reward reload")
 check(loaded.session.snapshot().pets.map(func(p):return p.pet_id)==["pet-101","pet-103"],"saved identity survives reload")
 loaded.free();b.free()
func selected_lan()->void:
 var b=setup();root.add_child(b);offer(b);b.original_quests.pending={}
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"selection LAN port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two selection devices online")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var a:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":selection_fixture.npcs[0].id})
 var c:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":selection_fixture.npcs[0].id})
 check(not (await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes","pet_ids":["pet-101"]})).ok,"new device invalidates old selection token")
 c=await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"yes","pet_ids":["pet-102"]})
 check((await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"ok"})).ok,"selected UID commits via real websocket")
 check(b.session.snapshot().pets.map(func(p):return p.pet_id)==["pet-101","pet-103"],"LAN preserves unselected61")
 check(not (await request(links[0],{"type":"quest_choose","token":c.dialogue.token,"choice":"ok","pet_ids":["pet-101"]})).ok,"other device cannot replay or substitute UID")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
