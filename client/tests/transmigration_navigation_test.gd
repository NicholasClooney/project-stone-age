extends "res://tests/munde_cave_navigation_test.gd"
# Fixture helpers replace live chain helpers in this isolated server.
# Deliberately stale projection exercises the
# final authorization call independently of snapshot/step button state.
class Chain:
 extends RefCounted
 var event:int
 var npc:Dictionary
 var allowed:=true
 var calls:Array=[]
 var stage:Array=[]
 func _init(e:int,n:Dictionary):event=e;npc=n
 func owns(value:Dictionary)->bool:return str(value.get("id",""))==str(npc.id)
 func stage_key(_h,_b)->Array:return stage
 func steps(_h,_b,_p,quest:Dictionary)->void:
  if int(quest.event)!=event:return
  quest.steps.append({"id":"fixture-step","npc_id":npc.id,"map_id":npc.map_id,"cell":npc.cell,"source":{}})
 func can_visit(_h,_b,_step:Dictionary)->bool:return allowed
 func destination(h,b,n:Dictionary,mode:String)->Dictionary:
  calls.append(mode)
  # The chain's independent helper owns geometry. Reuse proven Munde region
  # implementation, including legitimate arrival and near-talk authority.
  return Munde.destination(h,b,n,mode)

func verified(ok:bool,note:String)->bool:
 check(ok,note);return ok
func isolated_setup():
 var b=setup()
 b.quest_catalog.jobs=b.quest_catalog.jobs.filter(func(job):return not int(job.event) in [39,40,41,42,46])
 b.quest_catalog.enabled_events=b.quest_catalog.enabled_events.filter(func(event):return not int(event) in [39,40,41,42,46])
 b.quest_helper.transmigration.helpers.clear();b.quest_helper.cached_key=""
 return b
func install(b,chain)->void:
 #41/42 share one production owner; swap the isolated owner explicitly so
 # each event's dispatch is exercised rather than overwriting41 with42.
 b.quest_helper.transmigration.helpers[b.quest_helper.transmigration.EVENTS[chain.event]]=chain
 b.quest_helper.cached_key=""
func source_projection(b)->void:
 for script in ["sainasu/event/event12","fixture-only"]:
  var filtered:Array=b.quest_catalog.active_npcs().filter(func(n):return str(n.get("source_script",""))==script)
  check(b.quest_catalog.active_npcs_by_source(script)==filtered,"by_source retains exact ordered fresh projection "+script)
 check(b.quest_catalog.active_npcs_by_source("sainasu/event/event12").size()==1,"fixture clones cannot replace the unique real Munde source")
func run()->void:
 var b=isolated_setup()
 var chief:Dictionary=b.original_quests.npc_by_id(CHIEF)
 var baseline:Array=b.quest_helper.navigation_key(b)
 var chains:Array=[]
 for event in [39,40,41,42,46]:
  var npc:Dictionary=chief.duplicate(true)
  npc.id="fixture-chain-"+str(event);npc.events=[event];npc.source_script="fixture-only"
  for branch in npc.branches:branch.events=[event]
  b.quest_catalog.jobs.append({"id":900+event,"event":event,"title":"isolated fixture"})
  b.quest_catalog.npcs.append(npc);b.quest_catalog.enabled_events.append(event)
  var chain=Chain.new(event,npc);chains.append(chain);install(b,chain)
 check(b.quest_helper.navigation_key(b)==baseline,"empty chain stage keys do not invalidate unrelated maps")
 source_projection(b)
 # The negative backend never obtains arrival authority. Project probes must
 # not invalidate the one real route used by all positive dispatch checks.
 var probe=isolated_setup()
 probe.quest_catalog.npcs=b.quest_catalog.npcs.duplicate(true)
 probe.quest_catalog.jobs=b.quest_catalog.jobs.duplicate(true)
 probe.quest_catalog.enabled_events=b.quest_catalog.enabled_events.duplicate()
 for chain in chains:install(probe,chain)
 Rules.set_flag(b.session._profile,"ended",4,true)
 check(trade(b,KOLK).ok and trade(b,KATAN).ok and trade(b,HOTOR).ok,"real three requests establish original Munde predicates")
 if not verified(enter_original(b),"actual keyword enters first Munde floor"):finish(b,probe);return
 if not verified(Route.walk(b,11107,Vector2i(18,41),range(11101,11108)).ok,"actual six staircases reach guard-front component"):finish(b,probe);return
 check(b.quest_arrival.has_arrival(b,11107,b.automation.position_cell),"guard-front route comes from real entrance and stairs")
 check(Munde.region_at(b.quest_helper,b,b.automation.position_cell)!=Munde.region_at(b.quest_helper,b,Vector2i(chief.cell[0],chief.cell[1])),"actual guard separates source landing and chief component")
 for chain in chains:
  install(b,chain)
  for mode in ["near","arrival"]:
   check(not b.handle({"type":"quest_visit","npc_id":chain.npc.id,"mode":mode}).ok,"chain final geometry cannot cross original guard "+str(chain.event)+mode)
 var guard:Dictionary=b.original_quests.npc_by_id("100/sb_go.arg@11107:22:41")
 if not verified(Walk.walk_near(b,guard,[11107]),"walk original guard component to talk range"):finish(b,probe);return
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":guard.id})
 if not verified(choose(b,r,"yes").ok and b.battle_open,"real original guard starts"):finish(b,probe);return
 fight(b)
 if not verified(b.handle({"type":"battle_close"}).ok and b.automation.position_cell==Vector2i(23,35),"saved original guard victory Warp creates final authority"):finish(b,probe);return
 for chain in chains:
  install(b,chain)
  for mode in ["near","arrival"]:
   check(not b.handle({"type":"quest_visit","npc_id":chain.npc.id,"mode":mode}).ok,"victory alone cannot skip near-talk corridor "+str(chain.event)+mode)
 if not verified(Walk.walk_near(b,chief,[11107]),"ordinary walking reaches chief after victory"):finish(b,probe);return
 var legitimate_cell:Vector2i=b.automation.position_cell
 check(Munde.can_navigate(b.quest_helper,b,chief),"real Munde source passes current branch, arrival and near checks")
 for chain in chains:
  install(b,chain);install(probe,chain);chain.calls.clear()
  var event:int=chain.event
  var job_id:int=900+event
  check(b.quest_catalog.jobs.any(func(job):return int(job.id)==job_id and int(job.event)==event),"isolated job maps independent chain event "+str(event))
  check(not b.quest_helper.resolve_step(b,job_id,"fixture-step").is_empty(),"enabled fixture resolves permitted chain step "+str(event))
  chain.allowed=false
  for mode in ["near","arrival"]:
   check(not b.handle({"type":"quest_visit","npc_id":chain.npc.id,"mode":mode}).ok,"raw chain NPC rechecks can_visit "+str(event)+mode)
   check(not b.handle({"type":"quest_visit","quest_id":job_id,"step_id":"fixture-step","mode":mode}).ok,"cached old step rechecks can_visit "+str(event)+mode)
   check(b.automation.position_cell==legitimate_cell and chain.calls.is_empty(),"denied chain never reaches destination or moves")
  chain.allowed=true
  probe.automation.position_changed(11107,legitimate_cell)
  check(not probe.quest_arrival.has_arrival(probe,11107,legitimate_cell),"same actual near point cannot manufacture route proof")
  for mode in ["near","arrival"]:
   check(not probe.handle({"type":"quest_visit","npc_id":chain.npc.id,"mode":mode}).ok,"project-near raw call remains denied "+str(event)+mode)
   check(not probe.handle({"type":"quest_visit","quest_id":job_id,"step_id":"fixture-step","mode":mode}).ok,"project-near old step remains denied "+str(event)+mode)
   check(b.handle({"type":"quest_visit","npc_id":chain.npc.id,"mode":mode}).ok,"independent chain destination dispatch "+str(event)+mode)
   check(b.handle({"type":"quest_visit","quest_id":job_id,"step_id":"fixture-step","mode":mode}).ok,"independent chain step dispatch "+str(event)+mode)
   check(b.automation.position_cell==legitimate_cell and Munde.region_at(b.quest_helper,b,legitimate_cell)==Munde.region_at(b.quest_helper,b,Vector2i(23,35)),"actual chain landing remains at original point in same component")
  check(chain.calls.has("near") and chain.calls.has("arrival"),"both modes reach own chain helper")
  b.quest_catalog.enabled_events.erase(event);b.quest_helper.cached_key=""
  for mode in ["near","arrival"]:
   check(not b.handle({"type":"quest_visit","npc_id":chain.npc.id,"mode":mode}).ok,"closed chain rejects raw NPC "+str(event)+mode)
   check(not b.handle({"type":"quest_visit","quest_id":job_id,"step_id":"fixture-step","mode":mode}).ok,"closed chain rejects old step "+str(event)+mode)
  b.quest_catalog.enabled_events.append(event);b.quest_helper.cached_key="";chain.calls.clear()
 source_projection(b)
 # Shared event12 retains one source instance and original branch order.
 var wind=chains[2];wind.npc=b.original_quests.npc_by_id(CHIEF);wind.allowed=false
 install(b,wind);install(probe,wind)
 for mode in ["near","arrival"]:
  probe.automation.position_changed(11107,Vector2i(18,41));probe.quest_helper.cached_key=""
  check(not probe.handle({"type":"quest_visit","npc_id":CHIEF,"mode":mode}).ok,"shared wind cannot override Munde guard")
  check(b.handle({"type":"quest_visit","npc_id":CHIEF,"mode":mode}).ok and b.automation.position_cell==legitimate_cell,"locked wind does not revoke enabled Munde access")
  check(not b.handle({"type":"quest_visit","quest_id":941,"step_id":"fixture-step","mode":mode}).ok,"shared Munde access cannot authorize a locked wind step")
 b.quest_catalog.enabled_events.erase(9);b.quest_helper.cached_key=""
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":CHIEF,"mode":mode}).ok,"wind-only shared owner still needs can_visit")
 wind.allowed=true;b.quest_helper.cached_key=""
 for mode in ["near","arrival"]:
  check(b.handle({"type":"quest_visit","npc_id":CHIEF,"mode":mode}).ok and b.automation.position_cell==legitimate_cell,"wind-only shared owner uses own destination with Munde boundary")
 b.quest_helper.transmigration.helpers.clear();b.quest_helper.cached_key=""
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":chains[0].npc.id,"mode":mode}).ok,"missing helper fails closed at final destination")
 finish(b,probe)
func finish(b,probe)->void:
 b.free();probe.free();print("TRANSMIGRATION NAVIGATION: %d failures"%failures);quit(1 if failures else 0)
