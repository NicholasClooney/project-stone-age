extends RefCounted
## Pure plans. The existing quest router owns position, tokens, UID and saving.
const KIND="original_jug_shop"
const ID="genout/ss_30504_10_11@30504:10:11"
const PURCHASE={"item_id":2708,"quantity":1,"price":1150,"base_cost":500,"buy_rate":"2.3"}
static func valid(npc:Dictionary)->bool:
 var purchase:Dictionary=npc.get("purchase",{})
 if purchase.size()!=PURCHASE.size():return false
 for key in PURCHASE:
  if not purchase.has(key) or purchase[key]!=PURCHASE[key]:return false
 var cell:Array=npc.get("cell",[])
 if cell.size()!=2 or cell[0]!=10 or cell[1]!=11:return false
 return str(npc.get("kind",""))==KIND and str(npc.get("id",""))==ID and str(npc.get("source_script",""))=="genout/ss_30504_10_11" and str(npc.get("source_create",""))=="gmsv/data/npc/genout/shop_m3.create" and int(npc.get("source_create_index",-1))==41 and int(npc.get("map_id",-1))==30504 and str(npc.get("handler",""))=="ItemShop"
static func open(npc:Dictionary,_profile:Dictionary)->Dictionary:
 if not valid(npc):return {"ok":false,"reason":"原水壶商店来源无效。"}
 return {"ok":true,"state":{"phase":"confirm"},"dialogue":{"text":"巴那姆的水壶，每只1150石币。\n购买一只空壶吗？\n【项目界面】每次购买一只；可重新交谈继续购买。","choices":[{"id":"buy_one","text":"购买一只 · 1150石币"},{"id":"no","text":"取消"}]}}
static func reply(npc:Dictionary,_profile:Dictionary,state:Dictionary,choice:String,text:String)->Dictionary:
 if not valid(npc) or state!={"phase":"confirm"} or not text.is_empty():return {"ok":false,"reason":"水壶购买状态或输入无效。"}
 if choice=="no":return {"ok":true,"close":true}
 if choice!="buy_one":return {"ok":false,"reason":"无效选择。"}
 return {"ok":true,"close":true,"actions":{"DelStone":"1150","GetItem":"2708"},"result":{"text":"花费1150石币购买了一个巴那姆的水壶。"}}
