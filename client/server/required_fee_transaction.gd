extends RefCounted
# TMP review candidate. Exact original shop/gate transactions; not a generic service.
const Session=preload("res://server/game_session.gd")
const Brothers=preload("res://server/brothers_quests.gd")
const GATE="genout/wpm_40_13_1@40:13:1"
const LOCK_SHA="e2dab78068f21af19e406f0f0eee10933d5c907596d4554fa59a6f227a6f0958"
const LOCK_PATH="res://data/required-fees.json"
static func refused(reason:String)->Dictionary:return {"ok":false,"reason":reason}
static func lock_data()->Dictionary:
 var raw:String=FileAccess.get_file_as_string(LOCK_PATH)
 if raw.sha256_text()!=LOCK_SHA:return {}
 var parser=JSON.new()
 if parser.parse(raw)!=OK or not parser.data is Dictionary:return {}
 return parser.data
static func vendor(b,id:String)->Dictionary:
 var lock:Dictionary=lock_data()
 if not lock.get("shops",{}).has(id):return {}
 var expected:Dictionary=lock.shops[id]
 var found:Array=[]
 for resident in b.quest_helper.places.residents:
  if resident.get("dialogue_source","")==expected.dialogue_source:found.append(resident)
 return found[0].duplicate(true) if found.size()==1 and found[0]==expected else {}
static func gate_matches(b,npc_id:String,branch:Dictionary)->bool:
 if npc_id!=GATE:return false
 var lock:Dictionary=lock_data()
 if not lock.has("seimu"):return false
 var npc:Dictionary=b.original_quests.npc_by_id(GATE)
 return npc==lock.seimu and npc.get("branches",[]).size()==1 and branch==lock.seimu.branches[0]
static func arrival(b)->Dictionary:
 var a=b.quest_arrival
 return {"epoch":a._epoch,"serial":a._serial,"scope":a._scope,"map":a._map,"cell":a._cell,"marks":a._marks.duplicate(true),"stages":a._stages.duplicate(true),"action":a._action.duplicate(true),"approach":a._approach.duplicate(true),"warp":a._warp.duplicate(true),"battles":a._battles.duplicate(true),"wild":a._wild.duplicate(true)}
static func capture(b,kind:String,source:String)->Dictionary:
 # Short stack frame only. Never install this dictionary on b/session/router.
 var q=b.quest_auto
 return {"call":RefCounted.new(),"backend":b,"session":b.session,"path":b.save_path,"router":b.original_quests,"q":q,"identity":q.identity,"identity_value":q.identity.snapshot().duplicate(true),"connection":q.connection,"client":q.client,"running":q.running,"internal":q.internal,"detached":q.detached,"phase":q.phase,"auto":b.automation,"auto_token":b.automation.start_lifetime,"auto_settings":b.automation.settings.duplicate(true),"auto_running":b.automation.running,"hunt_running":b.automation.hunt_running,"compact":b.automation.compact_active,"profile":b.session._profile,"before":b.session.snapshot(),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"pending":b.session._pending.duplicate(true),"page":b.original_quests.pending.duplicate(true),"battle":b.battle,"battle_open":b.battle_open,"map":b.automation.position_map,"cell":b.automation.position_cell,"arrival":arrival(b),"guard":b.quest_visit_guard,"kind":kind,"source":source,"marked":false}
static func same_owner(b,f:Dictionary)->bool:
 if f.is_empty() or b!=f.backend or b.session!=f.session or b.save_path!=f.path or b.original_quests!=f.router or b.quest_auto!=f.q or b.automation!=f.auto or b.battle!=f.battle:return false
 if f.has("transport") and b._fee_bindings.get(f.transport_connection)!=f.transport:return false
 var q=b.quest_auto
 return b.automation.start_lifetime==f.auto_token and b.automation.settings==f.auto_settings and b.automation.running==f.auto_running and b.automation.hunt_running==f.hunt_running and b.automation.compact_active==f.compact and q.identity==f.identity and q.identity.snapshot()==f.identity_value and q.connection==f.connection and q.client==f.client and q.running==f.running and q.internal==f.internal and q.detached==f.detached and q.phase==f.phase and b.battle_open==f.battle_open and b.session._pending==f.pending and b.original_quests.pending==f.page and b.automation.position_map==f.map and b.automation.position_cell==f.cell and arrival(b)==f.arrival and b.quest_visit_guard==f.guard
static func current(b,f:Dictionary)->bool:
 return same_owner(b,f) and is_same(b.session._profile,f.profile) and b.session._profile==f.before and b.last_saved_payload==f.cache and b.quest_save_serial==f.serial
static func busy(b)->bool:
 return b.stationary.running or b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active() or (b.quest_auto.running and not b.quest_auto.internal)
static func near(b,npc:Dictionary)->bool:
 return not npc.is_empty() and b.automation.position_map==int(npc.map_id) and maxi(absi(b.automation.position_cell.x-int(npc.cell[0])),absi(b.automation.position_cell.y-int(npc.cell[1])))<=2
static func guard_error(b,f:Dictionary)->String:
 if not current(b,f) or busy(b):return "费用操作状态已经改变。"
 if f.kind=="seimu" and b.quest_visit_guard.is_valid():
  var reason:String=str(b.quest_visit_guard.call())
  if not current(b,f):return "费用操作状态已经改变。"
  if not reason.is_empty():return reason
 return ""
static func binding_current(b,command:Dictionary)->bool:
 var connection=command.get("_quest_connection")
 return connection is int and connection!=-1 and command.get("_fee_binding") is RefCounted and b._fee_bindings.get(connection)==command._fee_binding
static func page_owned(b,p:Dictionary,command:Dictionary)->bool:
 return p.get("phase","")=="permit_shop" and binding_current(b,command) and p.get("permit_connection")==command._quest_connection and p.get("permit_binding")==command._fee_binding and p.get("permit_session") is WeakRef and p.permit_session.get_ref()==b.session and p.get("permit_path")==b.save_path
static func entry_error(b,command:Dictionary)->String:
 var kind:String=str(command.get("type",""))
 if not binding_current(b,command):return "缺少当前传输绑定。"
 if kind=="permit_shop_open":
  if not command.get("source_id") is String or not command.get("open_id") is String or command.open_id.is_empty() or command.open_id.length()>128:return "无效的售证页面请求。"
  if not b.original_quests.pending.is_empty():return "请先关闭当前对话。"
 elif kind=="permit_shop_choose":
  if not command.get("token") is String or not command.get("choice") is String:return "无效的原售证确认。"
  var page:Dictionary=b.original_quests.pending
  if not page_owned(b,page,command) or page.get("token","")!=command.token:return "售证页已过期或不属于本连接。"
 else:return "无效售证入口。"
 return ""
static func close_shop(b,command:Dictionary)->Dictionary:
 var p:Dictionary=b.original_quests.pending
 if not page_owned(b,p,command):return refused("售证页已过期或不属于本连接。")
 var matches:bool=false
 if command.get("type","")=="permit_shop_cancel":
  matches=command.get("open_id") is String and command.open_id==p.get("open_id","")
 else:matches=command.get("token") is String and command.token==p.get("token","")
 if not matches:return refused("售证页已过期。")
 # No callback, save, auto/navigation mutation; retire only this exact page.
 b.original_quests.pending={}
 return {"ok":true,"closed":true}
static func open_shop(b,id:String,command:Dictionary)->Dictionary:
 if not binding_current(b,command):return refused("缺少当前传输绑定。")
 if not command.get("open_id") is String or command.open_id.is_empty() or command.open_id.length()>128:return refused("缺少本次页面标识。")
 if not b.original_quests.pending.is_empty():return refused("请先关闭当前对话。")
 var f:Dictionary=capture(b,"permit",id)
 f.transport=command._fee_binding;f.transport_connection=command._quest_connection
 var npc:Dictionary=vendor(b,id)
 if not near(b,npc):return refused("请接近原售证商人。")
 var error:String=guard_error(b,f)
 if not error.is_empty():return refused(error)
 if b.session.has_travel_pass():return {"ok":true,"already_owned":true,"closed":true}
 b.original_quests.serial+=1
 var token:String="permit-%d-%d"%[Time.get_ticks_usec(),b.original_quests.serial]
 b.original_quests.pending={"token":token,"permit_source":id,"phase":"permit_shop","open_id":command.open_id,"permit_connection":command._quest_connection,"permit_binding":command._fee_binding,"permit_session":weakref(b.session),"permit_path":b.save_path}
 return {"ok":true,"dialogue":{"token":token,"kind":"original_permit_shop","open_id":command.open_id,"name":npc.name,"text":"通行证：200 石币。购买一张？（项目确认窗口）","choices":[{"id":"buy_one","text":"购买一张"},{"id":"no","text":"取消"}]}}
static func choose_shop(b,token:String,choice:String,command:Dictionary)->Dictionary:
 var p:Dictionary=b.original_quests.pending
 if not page_owned(b,p,command) or p.get("token","")!=token:return refused("对话已过期。")
 var id:String=p.permit_source
 b.original_quests.pending={}
 if choice=="no":return {"ok":true,"closed":true}
 if choice!="buy_one":return refused("无效的售证选择。")
 var f:Dictionary=capture(b,"permit",id)
 f.transport=command._fee_binding;f.transport_connection=command._quest_connection
 var error:String=guard_error(b,f)
 if not error.is_empty():return refused(error)
 if not near(b,vendor(b,id)):return refused("原售证来源或位置改变。")
 if b.session.has_travel_pass():return {"ok":true,"already_owned":true,"closed":true}
 return commit(b,f)
static func candidate(b,f:Dictionary)->Dictionary:
 if not current(b,f) or busy(b):return {}
 var c:Dictionary=f.before.duplicate(true)
 if f.kind=="permit":
  if not near(b,vendor(b,f.source)) or b.session.has_travel_pass() or Session.bag_slots(c)>=15 or int(c.player.gold)<200:return {}
  c.player.gold-=200
  Session.OriginalEquipment.add(c,2422)
 elif f.kind=="seimu":
  var branch:Dictionary=f.branch
  if not gate_matches(b,f.source,branch) or not b.original_quests.allowed(b,lock_data().seimu) or b.original_quests.branch_for(lock_data().seimu,c)!=branch or not b.session.has_travel_pass() or int(c.player.gold)<300:return {}
  var info:Dictionary=b.session.world_catalog.info(31301)
  if info.is_empty() or int(info.width)<=10 or int(info.height)<=104:return {}
  c.player.gold-=300
  Brothers.warp_profile(c,"31301,10,104")
 else:return {}
 return c if b.session._valid_profile(c) else {}
static func seimu(b,profile:Dictionary,branch:Dictionary,f:Dictionary)->Dictionary:
 if not current(b,f) or profile!=f.before or not gate_matches(b,GATE,branch):return refused("原收费门来源或事务已经改变。")
 f.branch=branch.duplicate(true)
 var reason:String=b.quest_arrival.check_action(b,lock_data().seimu,branch,"FREEWARP")
 if not current(b,f):return refused("费用操作状态已经改变。")
 if not reason.is_empty():return refused(reason)
 reason=guard_error(b,f)
 if not reason.is_empty():return refused(reason)
 return commit(b,f)
static func commit(b,f:Dictionary)->Dictionary:
 if b._depth<=0:return refused("原收费事务必须由请求分发执行。")
 var c:Dictionary=candidate(b,f)
 if c.is_empty():return refused("费用不足、道具栏已满或原条件已经改变。")
 # No user callback from final checks through candidate installation.
 f.candidate=c
 f.expected=c.duplicate(true)
 f.payload=JSON.stringify(c)
 var saved:bool=b._save_required_fee(f)
 # Only the actual base writer may mark, before virtual-return observation.
 if not f.marked:
  if same_owner(b,f) and is_same(b.session._profile,c) and b.session._profile==f.expected and b.last_saved_payload==f.cache and b.quest_save_serial==f.serial:
   b.session._profile=f.profile
  var failed:Dictionary=refused("save_failed" if not saved else "费用提交无法确认。")
  # This is tail ownership, NEVER a successful-save mark or public capability.
  failed["_required_fee_call"]=f.call
  return failed
 # Base writer already queued committed facts before virtual return observers.
 return {"ok":true,"committed":true,"closed":true,"_required_fee_call":f.call}
static func publish_committed(b,f:Dictionary)->void:
 # Only inside the original handle queue: position/profile delivery follows return.
 # No repeat publication from a virtual writer override returning again.
 if not f.marked or f.get("published",false):return
 f.published=true
 if f.kind=="seimu":
  b.quest_arrival.action_committed(b,lock_data().seimu,f.branch,"FREEWARP")
  Brothers.publish_warp(b,"31301,10,104")
 var fee:int=200 if f.kind=="permit" else 300
 b._emit({"type":"quest_result","text":("原商店通行证" if f.kind=="permit" else "赛姆原通行费")+"：扣除%d石币，提交后余额%d。"%[fee,int(f.committed.player.gold)]})
 b.publish()
static func writer_ready(b,f:Dictionary)->bool:
 if not current(b,f) or f.marked or b.save_path.is_empty() or not b.session._pending.is_empty():return false
 var rebuilt:Dictionary=candidate(b,f)
 return not rebuilt.is_empty() and rebuilt==f.expected and f.candidate==f.expected and JSON.stringify(rebuilt)==f.payload
static func mark_written(b,f:Dictionary)->void:
 # Called only by the actual private save body, after its cache update; no callbacks.
 if f.marked or not same_owner(b,f) or not is_same(b.session._profile,f.candidate) or JSON.stringify(b.session._profile)!=f.payload:return
 f.marked=true
 f.committed=f.expected.duplicate(true)
 f.committed_serial=b.quest_save_serial
