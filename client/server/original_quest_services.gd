extends RefCounted
## Explicit reviewed service dispatch. Never put this catalog in a snapshot.
const GoldenBui=preload("res://server/golden_bui_service.gd")
const JugShop=preload("res://server/original_jug_shop_service.gd")
const KINDS := ["golden_bui_quiz","golden_bui_janken","golden_bui_gate","original_jug_shop"]
var private_catalog: Dictionary = {}
var rng := RandomNumberGenerator.new()
func _init()->void:rng.randomize()
func context(backend)->Dictionary:
 if private_catalog.is_empty() and FileAccess.file_exists(GoldenBui.CATALOG_PATH):
  var parsed=JSON.parse_string(FileAccess.get_file_as_string(GoldenBui.CATALOG_PATH))
  if parsed is Dictionary:private_catalog=parsed
 return {"catalog":private_catalog,"rng":rng,"in_party":backend.quest_visit_guard.is_valid() and not str(backend.quest_visit_guard.call()).is_empty()}
func open(router,backend,npc:Dictionary)->Dictionary:
 if str(npc.get("kind",""))==JugShop.KIND:return apply(router,backend,npc,JugShop.open(npc,backend.session.snapshot()))
 return apply(router,backend,npc,GoldenBui.open(npc,backend.session.snapshot(),context(backend)))
func reply(router,backend,current:Dictionary,choice:String,text:String)->Dictionary:
 if str(current.npc.get("kind",""))==JugShop.KIND:return apply(router,backend,current.npc,JugShop.reply(current.npc,backend.session.snapshot(),current.service_state,choice,text))
 if text.length()>120:return {"ok":false,"reason":"输入内容过长。"}
 var authority:=context(backend)
 if authority.in_party:return {"ok":false,"reason":"请先退出团队再挑战。"}
 return apply(router,backend,current.npc,GoldenBui.reply(current.npc,backend.session.snapshot(),current.service_state,choice,text,authority))
func apply(router,backend,npc:Dictionary,plan:Dictionary)->Dictionary:
 if not bool(plan.get("ok",false)):return {"ok":false,"reason":str(plan.get("reason","无法交谈。"))}
 var actions:Dictionary=plan.get("actions",{})
 if str(npc.get("kind",""))==JugShop.KIND:
  if not JugShop.valid(npc) or (not actions.is_empty() and (actions!={"DelStone":"1150","GetItem":"2708"} or not bool(plan.get("close",false)))):return {"ok":false,"reason":"无效的原水壶购买计划。"}
 else:
  if str(npc.get("kind","")) not in ["golden_bui_quiz","golden_bui_janken","golden_bui_gate"]:return {"ok":false,"reason":"尚未支持的原服务。"}
  for key in actions:
   if key not in ["GetItem","DelItem","Warp"]:return {"ok":false,"reason":"尚未支持的原服务动作。"}
 var result:Dictionary=plan.get("result",{})
 var notice := result_text(result)
 if not actions.is_empty():
  var transaction:Dictionary=router.transact(backend,backend.session.snapshot(),{"event":-1,"actions":actions,"texts":{}},"SERVICE",notice)
  if not transaction.ok:return transaction
 elif not notice.is_empty():backend._emit({"type":"quest_result","text":notice})
 if bool(plan.get("close",false)):return {"ok":true,"closed":true}
 var raw:Dictionary=plan.get("dialogue",{})
 if raw.is_empty():return {"ok":false,"reason":"原服务没有返回对白。"}
 router.serial+=1
 var token:="%d-%d"%[Time.get_ticks_usec(),router.serial]
 router.pending={"token":token,"npc":npc,"service_state":plan.get("state",{}).duplicate(true)}
 # Copy only presentation fields. Correct answers and private service state
 # remain exclusively in router.pending, even if a future service adds fields.
 var choices:=[]
 for entry in raw.get("choices",[]):choices.append({"id":str(entry.id),"text":str(entry.text)})
 return {"ok":true,"dialogue":{"token":token,"npc_id":npc.id,"name":str(raw.get("name",npc.name)),"text":str(raw.get("text","")),"choices":choices,"input":str(raw.get("input","choice")),"kind":str(npc.kind)}}
static func result_text(result:Dictionary)->String:
 if result.has("win"):
  return "你出%s，对方出%s：%s。"%[str(result.get("player","")),str(result.get("opponent","")),"获胜" if bool(result.win) else "落败"]
 var text:=str(result.get("text",""))
 if result.has("correct"):text+="\n答对 %d / %d 题"%[int(result.correct),int(result.get("total",0))]
 return text.strip_edges()
