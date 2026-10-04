extends SceneTree
## Direct dispatcher boundary, not original route/source qualification. Spies
## prove rejected plans never capture a capability or create a dialogue.
class ObservedBackend:
 extends "res://server/backend.gd"
 var captures:=0
 var captured_id:=""
 var witness:Dictionary={}
 var live:=true
 var live_checks:=0
 func capture_quest_source_call(npc_id:String)->Dictionary:
  captures+=1;captured_id=npc_id
  return witness
 func quest_source_call_live(source:Dictionary)->bool:
  live_checks+=1
  return source==witness and live
var failures:=0
var assertions:=0
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var b=ObservedBackend.new();b.set_process(false)
 var router=b.original_quests
 router.pending={"token":"later-manual-page","fixture":true}
 var profile:Dictionary=b.session.snapshot()
 var pending:Dictionary=router.pending.duplicate(true)
 var serial:int=router.serial
 var saved:int=b.quest_save_serial
 var messages:Array=[]
 b.event.connect(func(message):messages.append(message.duplicate(true)))
 for npc in [{},{"kind":"golden_bui_quiz"}]:
  var result:Dictionary=router.services.apply(router,b,npc,{"ok":false,"reason":"original refusal"})
  check(result=={"ok":false,"reason":"original refusal"},"Original negative plan preserved without npc.id")
 var bad:Dictionary=router.services.apply(router,b,{"kind":"golden_bui_quiz"},{"ok":true,"close":true,"actions":{"DelStone":"1150"}})
 check(not bad.get("ok",true) and bad.get("reason")=="尚未支持的原服务动作。","Jug test's malformed golden NPC reaches original action refusal")
 for npc in [{"kind":"unknown"},{"kind":"original_jug_shop"}]:
  bad=router.services.apply(router,b,npc,{"ok":true,"close":true,"actions":{}})
  check(not bad.get("ok",true),"Original unsupported/invalid service refuses missing identity")
 for kind in ["golden_bui_quiz","golden_bui_janken","golden_bui_gate"]:
  for id in [null,"",true,3,3.5,[],{}]:
   bad=router.services.apply(router,b,{"kind":kind,"id":id},{"ok":true,"close":true,"actions":{}})
   check(not bad.get("ok",true) and bad.get("reason")=="原服务来源无效。","Invalid service identity safely refused "+kind+" "+str(id))
 check(b.captures==0 and b.live_checks==0,"All refused plans avoid source capability access")
 check(b.session.snapshot()==profile and router.pending==pending and router.serial==serial and b.quest_save_serial==saved and messages.is_empty(),"Rejections preserve profile/manual page/serial/save/events")
 # No-action dispatcher spy only; does not stand in for a real service route.
 var npc:Dictionary={"id":"fixture/service","kind":"golden_bui_quiz","name":"fixture"}
 var plan:Dictionary={"ok":true,"dialogue":{"text":"fixture page","choices":[]}}
 b.witness={"fixture_call":true};b.live=false
 var cancelled:Dictionary=router.services.apply(router,b,npc,plan)
 check(cancelled=={"ok":true,"closed":true} and b.captures==1 and b.captured_id==npc.id and b.live_checks==1,"Validated identity captured before retained tail liveness guard")
 check(router.pending==pending and router.serial==serial,"Dead source tail does not replace later manual page")
 b.witness={};b.live=true
 var manual:Dictionary=router.services.apply(router,b,npc,plan)
 check(manual.get("ok",false) and manual.get("dialogue",{}).get("npc_id")==npc.id,"Ordinary non-source page retains original path")
 check(router.serial==serial+1 and b.captures==2 and b.live_checks==1,"Manual page created once without source-tail authority")
 b.free()
 print("QUEST SERVICE REJECTION IDENTITY: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
