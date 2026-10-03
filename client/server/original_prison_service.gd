extends RefCounted
## Reviewed prison plans; the existing quest transaction owns saving and warping.
const KIND="original_prison"
const DELETE="2521,2522,2523,2524,2602,2597,2598,2599,2600,2601,2609"
const BIRTH=["1006,15,22","2006,20,16","3006,21,16","4006,14,20"]
const GUARD="genout/wpm_117_6_5@117:6:5"
static func guide_index(npc:Dictionary)->int:
 for i in range(4):
  if str(npc.get("id",""))=="genout/wpm_110_37_%d@110:37:%d"%[20+4*i,20+4*i]:return i
 return -1
static func valid(npc:Dictionary)->bool:
 var guard:bool=str(npc.get("id",""))==GUARD
 var i:=guide_index(npc)
 if not guard and i<0:return false
 var script:String="genout/wpm_117_6_5" if guard else "genout/wpm_110_37_%d"%(20+4*i)
 if str(npc.get("kind",""))!=KIND or str(npc.get("handler",""))!="Prison" or str(npc.get("service_id",""))!=script or str(npc.get("source_script",""))!=script:return false
 var payload:Dictionary=npc.get("prison",{})
 var expected:Dictionary={"role":"guard" if guard else "guide","warp":"110,23,27" if guard else "%d,13,13"%(1012+1000*i),"condition":"" if guard else "ITEM=%d*1"%(2521+i),"money":"1" if guard else "-1","del_item":"" if guard else DELETE}
 if payload!=expected or npc.get("branches",[])!=[]:return false
 if str(npc.get("source_create",""))!="gmsv/data/npc/genout/"+("manmoshall.create" if guard else "chatroom.create"):return false
 if int(npc.get("source_create_index",-1))!=(18 if guard else 14+i) or int(npc.get("map_id",-1))!=(117 if guard else 110):return false
 var cell:Array=npc.get("cell",[])
 if cell.size()!=2 or cell[0]!=(6 if guard else 37) or cell[1]!=(5 if guard else 20+4*i):return false
 var f:Dictionary=npc.get("source_fields",{})
 return str(f.get("WARP",""))==("110,23,27" if guard else "%d,13,13"%(1012+1000*i)) and f.get("FREE",null)==("" if guard else "ITEM=%d*1"%(2521+i)) and str(f.get("MONEY",""))==("1" if guard else "-1") and str(f.get("DelItem",""))==("" if guard else DELETE)
static func birth(profile:Dictionary)->String:
 var bits:int=int(profile.get("original_savepoint_bits",0))
 for i in range(4):
  if bits&(1<<i):return BIRTH[i]
 return ""
static func ticket_uids(profile:Dictionary,item:int)->Array:
 var result:=[]
 for entry in profile.get("original_instances",[]):
  if int(entry.item_id)==item:result.append(int(entry.uid))
 result.sort()
 return result
static func guide_state(npc:Dictionary,profile:Dictionary)->Dictionary:
 var i:=guide_index(npc)
 var uids:=ticket_uids(profile,2521+i)
 if not uids.is_empty():
  var consumed:=[]
  for entry in profile.get("original_instances",[]):
   if str(int(entry.item_id)) in DELETE.split(","):consumed.append(int(entry.uid))
  consumed.sort()
  return {"phase":"confirm","route":"ticket","target":str(npc.source_fields.WARP),"ticket_uids":uids,"consumed_uids":consumed}
 return {"phase":"confirm","route":"birth","target":birth(profile),"ticket_uids":[]}
static func window(state:Dictionary,text:String)->Dictionary:
 return {"ok":true,"state":state,"dialogue":{"text":text,"choices":[{"id":"yes","text":"确定"},{"id":"no","text":"取消"}]}}
static func done(actions:Dictionary,text:String)->Dictionary:
 return {"ok":true,"close":true,"actions":actions,"result":{"text":text}}
static func open(npc:Dictionary,profile:Dictionary)->Dictionary:
 if not valid(npc):return {"ok":false,"reason":"监狱服务来源无效。"}
 if str(npc.id)==GUARD:
  var gold:int=int(profile.player.gold)
  if gold==0:return done({"Warp":"117,225,13"},"没有石币，仍留在监狱。")
  var fee:int=mini(gold,10)
  return window({"phase":"confirm","route":"fine","quoted_fee":fee,"target":"110,23,27"},"【项目改动】监狱罚金固定10石币；不足10时收取全部，替代原版90%%收费。\n本次报价：%d石币。确认后前往聊天室。"%fee)
 var state:=guide_state(npc,profile)
 if str(state.target).is_empty():return {"ok":false,"reason":"无法确认出生村，请保留当前角色资料并联系管理员；未消耗物品或石币。"}
 var text:String="持有对应村落门票，按原路线退场；原退场票券将收回。" if state.route=="ticket" else "【项目改动】未持对应门票，免费返回出生村，无须登出；不消耗其它门票或道具。"
 return window(state,text)
static func reply(npc:Dictionary,profile:Dictionary,state:Dictionary,choice:String,text:String)->Dictionary:
 if not valid(npc) or str(state.get("phase",""))!="confirm" or not text.is_empty():return {"ok":false,"reason":"监狱对话状态无效。"}
 if choice=="no":return {"ok":true,"close":true}
 if choice!="yes":return {"ok":false,"reason":"无效选择。"}
 if str(npc.id)==GUARD:
  var fee:int=int(state.get("quoted_fee",0))
  if state.get("route","")!="fine" or state.get("target","")!="110,23,27" or fee<1 or fee>10:return {"ok":false,"reason":"监狱报价无效，请重新交谈。"}
  if int(profile.player.gold)<fee:return {"ok":false,"reason":"石币不足以支付本次报价%d；请重新交谈。"%fee}
  return done({"DelStone":str(fee),"Warp":"110,23,27"},"支付%d石币，离开监狱。"%fee)
 if state!=guide_state(npc,profile):return {"ok":false,"reason":"门票或出生资料已经改变，请重新交谈；未消耗物品。"}
 if str(state.target).is_empty():return {"ok":false,"reason":"无法确认出生村。"}
 var actions:Dictionary={"Warp":str(state.target)}
 if state.route=="ticket":actions.DelItem=DELETE
 return done(actions,"已按门票返回原目的地。" if state.route=="ticket" else "【项目改动】已免费返回出生村，无须登出。")
static func valid_actions(npc:Dictionary,actions:Dictionary)->bool:
 if not valid(npc):return false
 if actions.is_empty():return true
 if str(npc.id)==GUARD:
  if actions=={"Warp":"117,225,13"}:return true
  for fee in range(1,11):
   if actions=={"DelStone":str(fee),"Warp":"110,23,27"}:return true
  return false
 if actions=={"DelItem":DELETE,"Warp":str(npc.source_fields.WARP)}:return true
 return actions.size()==1 and actions.get("Warp","") in BIRTH
