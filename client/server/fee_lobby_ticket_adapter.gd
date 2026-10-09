extends RefCounted
## Project convenience: buy one original-price ticket in the matching lobby.
## No fake ticket, vendor relocation, dialogue export, Warp or entry authority.
const Exact=preload("res://server/fee_start_journal_writer.gd")
const Journal=preload("res://server/fee_attempt_lifecycle.gd")
const Rules=preload("res://server/original_quests.gd")
const Source=preload("res://server/quest_auto_source_actions.gd")
const Plan=preload("res://server/quest_auto_golden_bui_plan.gd")
const Sources=preload("res://server/quest_auto_golden_bui_sources.gd")
const CATALOG="res://assets/legacy/quests/catalog.json"
const CATALOG_SHA="c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92"
static func offer(b)->Dictionary:
 if not Source.job_enabled(b,2):return {}
 var p:Dictionary=b.session._profile
 if not p.get("player") is Dictionary or not Journal.strict_int(p.player.get("level"),30):return {}
 if not Journal.strict_int(p.player.get("gold"),0,1000000000) or not p.get("original_items") is Array:return {}
 if not Journal.strict_int(p.get("next_original_uid"),1,2147483646) or not p.get("original_instances") is Array:return {}
 if p.original_items.size()!=p.original_instances.size():return {}
 for entry in p.original_instances:
  if not entry is Dictionary or not Journal.strict_int(entry.get("uid"),1) or not Journal.strict_int(entry.get("item_id"),1) or not Journal.strict_int(entry.get("durability")):return {}
 if Rules.flag(p,"ended",44) or Rules.flag(p,"now",44):return {}
 if b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or not b.original_quests.pending.is_empty():return {}
 if b.automation.running or b.automation.hunt_running or b.automation.flow_active() or b.stationary.running:return {}
 if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():return {}
 var level:int=p.player.level
 var high:bool=level>=70
 var item:int=2757 if high else (2756 if level>=50 else 2755)
 var price:int=level*(20 if level<50 else 40)
 var map_id:int=b.automation.position_map
 if item in p.original_items or p.player.gold<price or price>1000000000 or Rules.Session.bag_slots(p)+1>15:return {}
 if not map_id in [811,831,851] or high!=(map_id==851):return {}
 var source:String="quiz/uketuke2" if high else "quiz/uketuke"
 var index:int=0 if high else (1 if level>=50 else 2)
 var vendor_id:String="%s@%d:18:13"%[source,4020 if high else 2020]
 var text:String=FileAccess.get_file_as_string(CATALOG)
 if text.sha256_text()!=CATALOG_SHA:return {}
 var catalog:Variant=JSON.parse_string(text)
 if not catalog is Dictionary:return {}
 var expected:Dictionary={}
 for row in catalog.get("npcs",[]):
  if row.get("id")==vendor_id:expected=row;break
 if expected.is_empty():return {}
 var matches:Array=[]
 for row in b.quest_catalog.active_npcs():
  if row.get("id")==vendor_id:matches.append(row)
 if matches.size()!=1 or not Sources.same(matches[0],expected):return {}
 var branch:Dictionary=b.original_quests.branch_for(matches[0],p)
 if not Sources.same(branch,expected.branches[index]):return {}
 if branch.get("event")!=-1 or branch.get("type")!="ACCEPT" or branch.get("actions")!={"DelStone":"LV*20" if level<50 else "LV*40","GetItem":str(item)}:return {}
 var x:int=29 if high else (28 if level>=50 else 30)
 var gate:String="genout/wpm_%d_%d_20"%[map_id,x]
 var proposed:Dictionary=Plan.service(b,Sources.table(),gate,map_id,"entry")
 if proposed.get("status")!="step" or not Exact.strict_true(Source.validate_step(b,2,proposed.step).get("ok")):return {}
 return {"source_id":source,"offer_id":"%s:%d"%[vendor_id,index],"branch_index":index,"item_id":item,"amount":price,"level":level,"map_id":map_id,"cell":b.automation.position_cell,"step":proposed.step.duplicate(true)}
