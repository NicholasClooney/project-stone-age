extends SceneTree
const Service=preload("res://server/original_prison_service.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;printerr("FAIL: "+label)
static func actor(index:int)->Dictionary:
 var guard:bool=index<0
 var script:String="genout/wpm_117_6_5" if guard else "genout/wpm_110_37_%d"%(20+4*index)
 var cell:Array=[6,5] if guard else [37,20+4*index]
 var map_id:int=117 if guard else 110
 var payload:Dictionary={"role":"guard" if guard else "guide","warp":"110,23,27" if guard else "%d,13,13"%(1012+1000*index),"condition":"" if guard else "ITEM=%d*1"%(2521+index),"money":"1" if guard else "-1","del_item":"" if guard else Service.DELETE}
 return {"id":"%s@%d:%d:%d"%[script,map_id,cell[0],cell[1]],"name":"监狱测试","kind":Service.KIND,"handler":"Prison","service_id":script,"source_script":script,"source_create":"gmsv/data/npc/genout/"+("manmoshall.create" if guard else "chatroom.create"),"source_create_index":18 if guard else 14+index,"map_id":map_id,"cell":cell,"branches":[],"prison":payload,"source_fields":{"WARP":payload.warp,"FREE":payload.condition,"MONEY":payload.money,"DelItem":payload.del_item}}
static func profile(gold:int=0,bits:int=1)->Dictionary:
 return {"player":{"gold":gold},"original_savepoint_bits":bits,"original_instances":[],"original_equipment":{}}
func run()->void:
 var guard:=actor(-1)
 for gold in [0,1,9,10,11,1000000000]:
  var p:=profile(gold);var before:Dictionary=p.duplicate(true);var plan:=Service.open(guard,p)
  check(plan.ok and p==before,"pure guard open")
  if gold==0:check(plan.actions=={"Warp":"117,225,13"},"zero gold original prison warp");continue
  var state:Dictionary=plan.state
  check(int(state.quoted_fee)==mini(gold,10),"fixed cap quote")
  check(str(plan.dialogue.text).contains("项目改动") and str(plan.dialogue.text).contains("本次报价：%d石币"%mini(gold,10)),"explicit project quote")
  var r:=Service.reply(guard,p,state,"yes","")
  check(r.actions=={"DelStone":str(mini(gold,10)),"Warp":"110,23,27"} and Service.valid_actions(guard,r.actions),"exact frozen fee actions")
  p.player.gold=1000000000
  check(Service.reply(guard,p,state,"yes","").actions==r.actions,"balance increase never requotes")
  p.player.gold=mini(gold,10)-1
  check(not Service.reply(guard,p,state,"yes","").ok,"reduced insufficient funds reject")
  check(Service.reply(guard,p,state,"no","")=={"ok":true,"close":true},"cancel no transaction")
 for i in range(4):
  var npc:=actor(i)
  check(Service.valid(npc),"exact guide identity")
  for bits in range(16):
   var p:=profile(100,bits);var plan:=Service.open(npc,p)
   if bits==0:check(not plan.ok,"zero birth recoverable refusal");continue
   var expected:int=0
   while not bits&(1<<expected):expected+=1
   check(plan.state.target==Service.BIRTH[expected],"low first birth bit")
   var r:=Service.reply(npc,p,plan.state,"yes","")
   check(r.actions=={"Warp":Service.BIRTH[expected]},"no ticket no deletion")
  var p:=profile(100,8)
  p.original_instances=[{"item_id":2521+i,"uid":11},{"item_id":2601,"uid":12}]
  var plan:=Service.open(npc,p);var r:=Service.reply(npc,p,plan.state,"yes","")
  check(r.actions=={"Warp":"%d,13,13"%(1012+1000*i),"DelItem":Service.DELETE},"ticket preserves all original deletions")
  p.original_equipment={"arm":11}
  check(Service.reply(npc,p,plan.state,"yes","").ok,"quantified source ticket condition includes carried equipped slots")
  p.original_instances[0].uid=13
  check(not Service.reply(npc,p,plan.state,"yes","").ok,"replacement ticket UID rejects")
  p.original_instances=[{"item_id":2521+(i+1)%4,"uid":14}]
  plan=Service.open(npc,p);r=Service.reply(npc,p,plan.state,"yes","")
  check(r.actions=={"Warp":Service.BIRTH[3]},"foreign ticket unconsumed")
  for field in ["id","kind","handler","service_id","source_script","source_create","source_create_index","map_id","cell","prison"]:
   var altered:Dictionary=npc.duplicate(true);altered.erase(field)
   check(not Service.valid(altered),"missing pinned field "+field)
  for field in ["role","warp","condition","money","del_item"]:
   var altered:Dictionary=npc.duplicate(true);altered.prison[field]="tampered"
   check(not Service.valid(altered),"mutated payload "+field)
 check(Service.valid(JSON.parse_string(JSON.stringify(guard))),"JSON numeric identity representation")
 check(not Service.valid_actions(guard,{"DelStone":"90","Warp":"110,23,27"}),"old90 percent action forbidden")
 print("ORIGINAL PRISON RULES: %d failures"%failures);quit(1 if failures else 0)
