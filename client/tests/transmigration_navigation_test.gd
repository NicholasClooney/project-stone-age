extends "res://tests/munde_cave_navigation_test.gd"
# Enabled helpers are injected only into this isolated server. Production
# descriptors remain disabled. Deliberately stale projection exercises the
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
  quest.steps.append({"id":"fixture-step","npc_id":npc.id,"map_id":npc.map_id,"cell":npc.cell,"source":{}})
 func can_visit(_h,_b,_step:Dictionary)->bool:return allowed
 func destination(h,b,n:Dictionary,mode:String)->Dictionary:
  calls.append(mode)
  # The chain's independent helper owns geometry. Reuse proven Munde region
  # implementation here to test a real wall/guard, never fabricate a landing.
  return Munde.destination(h,b,n,mode)

func run()->void:
 var b=setup()
 var chief:Dictionary=b.original_quests.npc_by_id(CHIEF)
 var baseline:Array=b.quest_helper.navigation_key(b)
 var chains:Array=[]
 for event in [39,40,41,46]:
  var npc:Dictionary=chief.duplicate(true)
  npc.id="fixture-chain-"+str(event);npc.events=[event];npc.source_script="fixture-only"
  for branch in npc.branches:branch.events=[event]
  b.quest_catalog.jobs.append({"id":900+event,"event":event,"title":"isolated fixture"})
  b.quest_catalog.npcs.append(npc)
  b.quest_catalog.enabled_events.append(event)
  var chain=Chain.new(event,npc);chains.append(chain)
  b.quest_helper.transmigration.helpers[b.quest_helper.transmigration.EVENTS[event]]=chain
 check(b.quest_helper.navigation_key(b)==baseline,"empty chain stage keys do not invalidate unrelated maps")
 for chain in chains:
  var event:int=chain.event
  var job_id:=-1
  for job in b.quest_catalog.jobs:
   if int(job.event)==event:job_id=int(job.id)
  check(job_id>=0,"isolated job maps independent chain event")
  b.automation.position_changed(11107,Vector2i(23,35))
  b.quest_helper.cached_key=""
  check(not b.quest_helper.resolve_step(b,job_id,"fixture-step").is_empty(),"enabled fixture resolves permitted chain step")
  chain.allowed=false
  for mode in ["near","arrival"]:
   var before:Vector2i=b.automation.position_cell
   check(not b.handle({"type":"quest_visit","npc_id":chain.npc.id,"mode":mode}).ok,"raw chain NPC rechecks can_visit "+str(event)+mode)
   check(not b.handle({"type":"quest_visit","quest_id":job_id,"step_id":"fixture-step","mode":mode}).ok,"cached old step rechecks can_visit "+str(event)+mode)
   check(b.automation.position_cell==before and chain.calls.is_empty(),"denied chain never reaches destination or moves")
  chain.allowed=true
  for mode in ["near","arrival"]:
   b.automation.position_changed(11107,Vector2i(18,41));b.quest_helper.cached_key=""
   check(not b.handle({"type":"quest_visit","npc_id":chain.npc.id,"mode":mode}).ok,"chain final geometry cannot cross original guard")
   b.automation.position_changed(11107,Vector2i(23,35));b.quest_helper.cached_key=""
   check(b.handle({"type":"quest_visit","npc_id":chain.npc.id,"mode":mode}).ok,"independent chain destination dispatch "+str(event)+mode)
   check(Munde.region_at(b.quest_helper,b,b.automation.position_cell)==Munde.region_at(b.quest_helper,b,Vector2i(23,35)),"actual chain landing remains in same original component")
  check(chain.calls.has("near") and chain.calls.has("arrival"),"both modes reach own chain helper")
  chain.calls.clear()
 # Shared event12 remains navigable under existing Munde rights, while wind
 # rights can never bypass the original boundary. Inactive wind is no veto.
 for npc in b.quest_catalog.npcs:
  if str(npc.id)==CHIEF:npc.events.append_array([41,42])
 var wind=chains[2];wind.npc=chief;wind.allowed=false
 for mode in ["near","arrival"]:
  b.automation.position_changed(11107,Vector2i(18,41));b.quest_helper.cached_key=""
  check(not b.handle({"type":"quest_visit","npc_id":CHIEF,"mode":mode}).ok,"shared wind cannot override Munde guard")
  b.automation.position_changed(11107,Vector2i(23,35));b.quest_helper.cached_key=""
  check(b.handle({"type":"quest_visit","npc_id":CHIEF,"mode":mode}).ok,"locked wind does not revoke enabled Munde access")
  check(not b.handle({"type":"quest_visit","quest_id":941,"step_id":"fixture-step","mode":mode}).ok,"shared Munde access cannot authorize a locked wind step")
 b.quest_catalog.enabled_events.erase(9);b.quest_helper.cached_key=""
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":CHIEF,"mode":mode}).ok,"wind-only shared owner still needs can_visit")
 wind.allowed=true;b.quest_helper.cached_key=""
 for mode in ["near","arrival"]:
  check(b.handle({"type":"quest_visit","npc_id":CHIEF,"mode":mode}).ok,"wind-only shared owner uses own destination with Munde boundary")
 b.quest_helper.transmigration.helpers.clear();b.quest_helper.cached_key=""
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":chains[0].npc.id,"mode":mode}).ok,"missing helper fails closed at final destination")
 b.free();print("TRANSMIGRATION NAVIGATION: %d failures"%failures);quit(1 if failures else 0)
