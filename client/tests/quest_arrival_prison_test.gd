extends "res://tests/quest_arrival_transmigration_test.gd"
const WaterTravel=preload("res://tests/support/water_route_driver.gd")
const EarthTravel=preload("res://tests/support/earth_route_driver.gd")
const ScopePolicy=preload("res://server/quest_arrival_policy.gd")
var prison_portals:Array=[]
func install_prison(b)->void:
 var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-final-source.json"))
 var services:Array=source.npcs.filter(func(n):return str(n.get("kind",""))=="original_prison")
 var ids:Array=services.map(func(n):return str(n.id))
 b.quest_catalog.npcs=b.quest_catalog.npcs.filter(func(n):return str(n.id) not in ids)
 b.quest_catalog.npcs.append_array(services)
 for e in range(48,53):
  if e not in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(e)
 b.quest_helper.places.set_quest_catalog(b.quest_catalog)
func leave_prison_service(b,scope_name:String,preview:Dictionary)->void:
 check(RouteDriver.walk(b,117,Vector2i(6,6),[117]).get("ok",false),"walk actual prison maze from source landing to fee NPC")
 var guard:Dictionary=b.original_quests.npc_by_id("genout/wpm_117_6_5@117:6:5")
 var result:Dictionary=b.handle({"type":"quest_talk","npc_id":guard.id})
 check(result.has("dialogue"),"real prison service freezes positive fine")
 if not result.has("dialogue"):return
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-arrival-prison-parent/save.json"
 check(choose(b,result,"yes").get("reason","")=="save_failed" and b.session.snapshot()==before,"fee save failure restores profile and location")
 check(not b.quest_arrival.check_action_context(b,preview).is_empty(),"fee rollback never restores pre-prison arrival proof")
 var path:String="user://arrival-prison-"+scope_name+".json"
 b.save_path=path
 check(choose(b,result,"yes").get("ok",false) and b.automation.position_map==110 and int(b.session.snapshot().player.gold)==int(before.player.gold)-mini(10,int(before.player.gold)),"same quoted token saves real fee and moves to110")
 check(not b.quest_arrival.check_action_context(b,preview).is_empty(),"successful fee grants no cave qualification")
 check(FinalRoute.near(b,"genout/wpm_110_37_20",[110]),"walk original exit hall to actual guide")
 var gold:int=int(b.session.snapshot().player.gold)
 check(FinalRoute.commit(b,"genout/wpm_110_37_20") and b.automation.position_map==1006 and b.automation.position_cell==Vector2i(15,22) and int(b.session.snapshot().player.gold)==gold,"actual no-ticket guide returns original birth village for free")
 check(not b.quest_arrival.check_action_context(b,preview).is_empty() and not b.quest_arrival.has_stage(b,FIRST) and not b.quest_arrival.has_stage(b,LAST),"actual prison/guide return cannot recover old preview or stages")
 var loaded=fresh()
 check(loaded.load_profile(path) and loaded.session.snapshot().location==b.session.snapshot().location and not loaded.quest_arrival.check_action_context(loaded,preview).is_empty(),"saved actual prison return reloads at birth without old proof")
 loaded.free();b.save_path=""
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
func final_backend():
 var b=fresh();FinalRoute.install(b,false) # Actual imported world; no test portals.
 for e in [39,40,42,46]:Rules.set_flag(b.session._profile,"ended",e,true)
 return b
func verify_world(b)->void:
 check(not b.quest_helper.places.info(117).is_empty() and not b.quest_helper.places.info(110).is_empty(),"actual private imported world has original prison maps")
 check(ScopePolicy.scope(117).is_empty() and ScopePolicy.scope(110).is_empty(),"prison and exit hall are outside all protected scopes")
 var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/prison-arrival-portals.json"))
 prison_portals=source.portals
 var found:=0
 for p in prison_portals:
  var link:Dictionary=b.quest_helper.places.links(int(p.from_map)).get(Vector2i(int(p.cell[0]),int(p.cell[1])),{})
  var exact:bool=not link.is_empty() and int(link.to_map)==117 and Vector2i(int(link.target[0]),int(link.target[1]))==Vector2i(int(p.target[0]),int(p.target[1])) and not link.get("disabled",false)
  check(exact,"source/world endpoint exact: %d:%s"%[int(p.from_map),str(p.cell)])
  if exact:found+=1
 check(found==18,"all eighteen source endpoints present; not eighteen independent walkable routes")
func win_original(b,script:String)->bool:
 if not FinalRoute.commit(b,script) or not b.battle_open:return false
 fight(b)
 return b.handle({"type":"battle_close"}).get("ok",false)
func leave_via_prison(b,scope_name:String,source_map:int,allowed_maps:Array,preview:Dictionary)->void:
 # Source/world endpoints do not imply a naturally walkable route through
 # occupied guardians. Independent eight-direction source audit agrees.
 var reachable:Array=[]
 for p in prison_portals:
  if int(p.from_map)!=source_map:continue
  if not RouteDriver.path(b,source_map,Vector2i(int(p.cell[0]),int(p.cell[1])),allowed_maps).is_empty():reachable.append(p.cell)
 check(reachable.is_empty(),"current original occupied-guardian geometry has no post-reward prison walk: "+scope_name)
 check(b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell) and b.quest_arrival.check_action_context(b,preview).is_empty(),"real reward route and old preview remain valid before project relocation")
 var original_map:int=b.automation.position_map
 var original_cell:Vector2i=b.automation.position_cell
 var before_exit:Dictionary=b.quest_arrival.wild_context(b)
 check(b.quest_arrival.check_wild(b,before_exit,scope_name).is_empty(),"server receipt observes actual qualified pre-exit position")
 # Actual central server project-position hook, explicitly NOT a source walk
 # or a defeat Warp. No test ever assigns an arrival scope/stage/mark.
 b.automation.position_changed(117,Vector2i(180,99))
 check(b.automation.position_map==117 and not b.quest_arrival.check_wild(b,before_exit,scope_name).is_empty() and not b.quest_arrival.check_action_context(b,preview).is_empty(),"project entry to prison revokes real route and old task preview")
 check(not b.quest_arrival.has_stage(b,FIRST) and not b.quest_arrival.has_stage(b,LAST),"prison never retains or awards final-cave battle stages")
 for p in prison_portals:
  if int(p.from_map)!=source_map:continue
  # Probe every actual imported endpoint from an EXPLICIT project position.
  # Qualification was already revoked; this cannot prove natural reachability.
  b.automation.position_changed(source_map,Vector2i(int(p.cell[0]),int(p.cell[1])))
  check(not b.quest_arrival.has_arrival(b,source_map,b.automation.position_cell),"project source endpoint has no original-route proof: "+str(p.cell))
  check(b.handle({"type":"report_position","map_id":117,"cell":p.target}).get("ok",false),"actual imported portal works after explicit project placement: "+str(p.cell))
  check(not b.quest_arrival.check_action_context(b,preview).is_empty(),"ordinary prison portal never launders old preview: "+str(p.cell))
 leave_prison_service(b,scope_name,preview)
 b.automation.position_changed(original_map,original_cell)
 check(not b.quest_arrival.has_arrival(b,original_map,original_cell) and not b.quest_arrival.check_action_context(b,preview).is_empty(),"project return to exact old reward cell cannot restore route or mark")
func final_case()->void:
 var b=final_backend();verify_world(b)
 check(FinalRoute.entry(b) and FinalRoute.near(b,"300/sb_skr.arg",range(32001,32011)) and win_original(b,"300/sb_skr.arg"),"private production world original entrance and first Boss")
 check(FinalRoute.near(b,"genout/wpm_32016_31_39",range(32011,32017)) and FinalRoute.commit(b,"genout/wpm_32016_31_39"),"private production world original middle gate")
 check(FinalRoute.near(b,"300/sb_skt.arg",range(32016,32021)) and win_original(b,"300/sb_skt.arg"),"private production world actual terminal Boss")
 check(FinalRoute.near(b,"genout/wpm_32021_31_51",[32021]) and FinalRoute.commit(b,"genout/wpm_32021_31_51") and FinalRoute.near(b,"777/ten.arg",[32021]),"private production world final gate and king room")
 var n:Dictionary=FinalRoute.npc(b,"777/ten.arg")
 var preview:Dictionary=b.quest_arrival.action_context(b,n,{},"SERVICE")
 check(not preview.is_empty(),"actual king route creates preview before prison detour")
 leave_via_prison(b,"transmigration",32020,range(32011,32022),preview)
 b.free()
func water_case()->void:
 var b=fresh();WaterTravel.install_fixture(b);install_prison(b)
 Rules.set_flag(b.session._profile,"ended",4,true);Rules.set_flag(b.session._profile,"now",46,true)
 Equipment.add(b.session._profile,2769) # Preexisting quest inventory, not arrival.
 check(WaterTravel.cave(b,"jaruga/event/hekisei01"),"water original entrance and both actual guardians reach goddess")
 var n:Dictionary=WaterTravel.npc(b,"jaruga/event/hekisei01")
 var preview:Dictionary=b.quest_arrival.action_context(b,n,b.original_quests.branch_for(n,b.session.snapshot()),"reward")
 check(not preview.is_empty(),"water real arrival creates old reward preview")
 leave_via_prison(b,"water",21214,range(21201,21216)+range(21301,21316),preview)
 b.free()
func earth_case()->void:
 var b=fresh()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-earth-source.json"))
 var ids:Array=fixture.npcs.map(func(n):return str(n.id))
 b.quest_catalog.npcs=b.quest_catalog.npcs.filter(func(n):return str(n.id) not in ids)
 b.quest_catalog.npcs.append_array(fixture.npcs);b.quest_catalog.items.merge(fixture.items,true)
 if 39 not in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(39)
 b.quest_helper.places.set_quest_catalog(b.quest_catalog);install_prison(b)
 Rules.set_flag(b.session._profile,"ended",4,true);Rules.set_flag(b.session._profile,"now",39,true)
 for item in [2698,2699,2700]:Equipment.add(b.session._profile,item)
 check(EarthTravel.reach_goddess(b,self),"earth original entrance, middle gate and actual guards reach goddess")
 var n:Dictionary=EarthTravel.npc(b,"jaruga/event/ruri01")
 check(EarthTravel.approach(b,n),"earth source reward room approach")
 var preview:Dictionary=b.quest_arrival.action_context(b,n,b.original_quests.branch_for(n,b.session.snapshot()),"reward")
 check(not preview.is_empty(),"earth real final mark creates old reward preview")
 leave_via_prison(b,"earth",21014,range(21001,21017),preview)
 b.free()
func run()->void:
 final_case();water_case();earth_case()
 print("QUEST ARRIVAL PRISON: %d failures"%failures);quit(1 if failures else 0)
