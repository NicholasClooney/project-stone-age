extends "res://tests/original_drops_test.gd"
const Equipment=preload("res://server/original_equipment.gd")
const Storage=preload("res://server/item_storage.gd")
const ENEMIES=[1404,1406,1407,1405,1408,1410,1409,1411,1412,1413]
const Route=preload("res://tests/support/transmigration_arrival_route.gd")
const Rules=preload("res://server/original_quests.gd")
func drop_seed(catalog)->int:
 var rng:=RandomNumberGenerator.new()
 for seed_value in range(1000):
  rng.seed=seed_value
  var troop:Array=[]
  for id in ENEMIES:troop.append(catalog.actor(id,rng))
  if troop[3].generated_drops==[2138]:return seed_value
 check(false,"find deterministic original 100/1000 drop seed")
 return -1
func begin_guard(b,script:String)->bool:
 var npc:Dictionary=Route.npc(b,script)
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":npc.id})
 if not r.get("ok",false):check(false,"legal guard talk: "+str(r));return false
 r=b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":"yes"})
 check(r.get("ok",false) and b.battle_open,"real guarded transaction begins "+script)
 return r.get("ok",false) and b.battle_open
func reach_terminal(b)->bool:
 # Only prerequisite profile and publicly accessible initial cell are fixtures.
 # No fixture portal/catalog installation and no arrival/stage grants.
 check(b.session.gm_raise_level(-1,80),"prior level fixture")
 for event in [39,40,42,46]:Rules.set_flag(b.session._profile,"ended",event,true)
 if not Route.entry(b):check(false,"real public outer/pocket/cave entry");return false
 if not Route.near(b,"300/sb_skr.arg",range(32001,32011)):check(false,"real first ten floors");return false
 if not begin_guard(b,"300/sb_skr.arg"):return false
 check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==[1399,1401,1402,1400,1403],"original first five-enemy formation")
 win_troop(b)
 check(b.handle({"type":"battle_close"}).get("ok",false),"actual first victory saves Warp")
 if not Route.near(b,"genout/wpm_32016_31_39",range(32011,32017)) or not Route.commit(b,"genout/wpm_32016_31_39"):
  check(false,"real middle floors and source four-END gate");return false
 var reached:bool=Route.near(b,"300/sb_skt.arg",range(32016,32021))
 check(reached,"real later floors reach terminal guardian")
 return reached
func open_troop(b)->bool:
 b.encounter_rng.seed=drop_seed(b.encounter_catalog)
 if not begin_guard(b,"300/sb_skt.arg"):return false
 var pending:Dictionary=b.session._pending
 check(pending.enemies.map(func(e):return int(e.source_enemy_id))==ENEMIES,"unchanged original ten-enemy order with fourth drop actor")
 check(pending.has("quest_guard") and b.quest_arrival.check_battle(b,pending.quest_guard).is_empty(),"drop battle has genuine current route receipt")
 check(pending.enemies[3].generated_drops==[2138],"original RNG freezes fourth-enemy meat drop")
 return true
func win_troop(b)->void:
 var state:Dictionary=b.battle.snapshot()
 for i in range(200):
  if not bool(state.active):break
  var target:int=0
  for j in range(state.enemies.size()):
   if int(state.enemies[j].hp)>0:target=j;break
  state=b.battle_command({"action":"attack","target":target})
 check(not bool(state.active) and str(state.get("outcome",""))=="win","actual battle resolves original source formation")
func run()->void:
 var trusted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/quests/catalog.json"))
 var original:Dictionary=trusted.duplicate(true)
 check(bool(trusted.reviewed_drops["transmigration-final"].active),"production descriptor enables audited original drop")
 var closed:Dictionary=trusted.duplicate(true)
 closed.reviewed_drops["transmigration-final"].active=false
 Catalog.configure_reviewed_drops(closed)
 var closed_catalog=Catalog.new()
 check(not Catalog.drop_enemy_allowed(1405) and closed_catalog.actor(1405,rng_for(99)).generated_drops.is_empty(),"explicit disabled fixture suppresses original drop")
 Catalog.configure_reviewed_drops(trusted)
 var c=Catalog.new()
 check(c.roll_drops(c.data.enemies["1405"],rng_for(99))==[2138],"original100/1000 includes99")
 check(c.roll_drops(c.data.enemies["1405"],rng_for(100)).is_empty(),"original100/1000 excludes100")
 var b=backend()
 # Backend restores real production activation; no override grants authority.
 for stat in ["vitality","toughness","dexterity"]:check(b.session.gm_set_base_stat(-1,stat,10000),"GM battle fixture "+stat)
 check(b.session.gm_heal(),"GM battle fixture restored HP")
 var item:Dictionary=b.quest_catalog.items["2138"]
 check(Storage.reason(item).is_empty(),"original flags allow meat warehouse storage")
 check(item.effects.size()==1 and not bool(item.effects[0].active) and not item.has("use"),"meat recovery explicitly inactive; no use action metadata")
 if not reach_terminal(b) or not open_troop(b):b.queue_free();quit(1);return
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-final-meat/fail.json"
 win_troop(b)
 check(b.session.snapshot()==before and not b.session._pending.is_empty(),"failed drop save rolls back profile and UID retaining frozen pending")
 b.save_path="user://final-meat-saved.json"
 check(b.handle({"type":"battle_close"}).ok,"same frozen drop retries successfully")
 var state:Dictionary=b.session.snapshot()
 check(state.original_items.count(2138)==1,"exactly one original meat instance delivered")
 var uid:int=-1
 for instance in state.original_instances:
  if int(instance.item_id)==2138:uid=int(instance.uid)
 check(uid>0,"drop owns a stable instance UID")
 b.handle({"type":"battle_close"})
 check(b.session.snapshot()==state,"duplicate close never duplicates original loot")
 var cmd:Dictionary={"type":"item_storage_transfer","direction":"deposit","revision":int(state.item_storage_revision),"items":[{"uid":uid}]}
 check(b.handle(cmd).ok,"source-allowed meat deposits through actual storage transaction")
 var copy=Backend.new()
 check(copy.load_profile(b.save_path),"drop/storage actual saved profile loads")
 check(copy.session.snapshot().item_storage==b.session.snapshot().item_storage,"warehouse preserves drop UID on durable reload")
 copy.free()
 check(Route.near(b,"300/sb_skt.arg",[32020,32021]),"real reward exit returns to terminal guardian without project move")
 for stat in ["vitality","toughness","dexterity"]:check(b.session.gm_set_base_stat(-1,stat,10000),"GM battle fixture "+stat)
 check(b.session.gm_heal(),"GM battle fixture restored HP")
 while Session.bag_slots(b.session._profile)<15:Equipment.add(b.session._profile,2468)
 var next_uid:int=int(b.session._profile.next_original_uid)
 if not open_troop(b):b.queue_free();quit(1);return
 win_troop(b)
 check(b.handle({"type":"battle_close"}).ok,"full bag still settles ordinary battle")
 state=b.session.snapshot()
 check(state.original_items.count(2138)==0 and int(state.next_original_uid)==next_uid and Session.bag_slots(state)==15,"full bag neither merges meat nor allocates hidden UID")
 b.queue_free();Catalog.configure_reviewed_drops(original)
 print("TRANSMIGRATION FINAL DROPS: %d failures"%failures)
 quit(1 if failures else 0)
