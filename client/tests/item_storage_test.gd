extends SceneTree
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Storage=preload("res://server/item_storage.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, text: String) -> void:
 if not ok:failures+=1;push_error(text)
func fresh():
 var b=Backend.new();root.add_child(b);b.session._profile.default_companions_claimed=true
 b.session.snapshot();return b
func add(b,id:int) -> int:
 Equipment.add(b.session._profile,id);return int(b.session._profile.original_instances.back().uid)
func command(b,items:Array,direction:String="deposit") -> Dictionary:
 return {"type":"item_storage_transfer","direction":direction,"revision":int(b.session.snapshot().item_storage_revision),"items":items}
func one(b,uid:int,direction:String="deposit") -> Dictionary:
 return b.handle(command(b,[{"uid":uid} if direction=="deposit" else {"uids":[uid]}],direction))
func unchanged(b,cmd:Dictionary,label:String) -> void:
 var before:Dictionary=b.session.snapshot();var rev:int=b.rev
 check(not b.handle(cmd).ok and b.session.snapshot()==before and b.rev==rev,label)
func run() -> void:
 var b=fresh();var profile:Dictionary=b.session.snapshot()
 check(Storage.capacity(profile)==3000,"Project capacity is 3000")
 for n in [0,1,2,5,100]:
  profile.player.transmigration=n
  check(Storage.original_capacity(profile)==mini(10+4*n,30) and Storage.capacity(profile)==3000,"Original rebirth hook remains disabled")
 # Original no-mail/disappear flags and absent catalogue metadata do not bar storage.
 for id in [2401,2416,2507,2547,2548,2708,2468,2424,2450,2605,2147483647]:
  var test_uid:=add(b,id)
  var exact:Dictionary=b.session.snapshot().original_instances.back().duplicate(true)
  var quest_before:Dictionary=b.session.snapshot().quest.duplicate(true)
  var events_before:Dictionary=b.session.snapshot().original_events.duplicate(true)
  check(one(b,test_uid).ok,"Every original item type can deposit %d"%id)
  check(b.session.snapshot().item_storage==[exact],"Stored instance remains exact %d"%id)
  check(not preload("res://server/original_quests.gd").matches(b.session.snapshot(),"ITEM=%d"%id),"Stored quest item is not carried %d"%id)
  check(one(b,test_uid,"withdraw").ok,"Every original item type can withdraw %d"%id)
  check(b.session.snapshot().original_instances.back()==exact and b.session.snapshot().quest==quest_before and b.session.snapshot().original_events==events_before,"Round trip retains instance and quest state %d"%id)
  Equipment.remove(b.session._profile,id)
 var uid:=add(b,2605)
 unchanged(b,command(b,[{"uid":uid},{"uid":uid}]),"Duplicate selection refuses entire batch")
 unchanged(b,command(b,[{"uid":uid},{"uid":99999}]),"Foreign UID refuses entire batch")
 b.session._profile.player.level=60
 b.session.equip_item("original:%d"%uid)
 # Use the exact authoritative slot fixture, independent of equipment UI.
 b.session._profile.original_equipment.head=uid
 unchanged(b,command(b,[{"uid":uid}]),"Worn equipment must be explicitly removed")
 b.session._profile.original_equipment.head=0
 b.session._pending={"battle_id":"frozen"}
 unchanged(b,command(b,[{"uid":uid}]),"Frozen pending battle refuses warehouse without clearing claims")
 b.session._pending={}
 b.stationary.running=true
 unchanged(b,command(b,[{"uid":uid}]),"Stationary activity refuses without stopping the runner")
 b.stationary.running=false
 var sent:=command(b,[{"uid":uid}]);var before:Dictionary=b.session.snapshot()
 check(b.handle(sent).ok,"Deposit exact equipment UID")
 var stored:Dictionary=b.session.snapshot()
 check(stored.item_storage==[before.original_instances[0]] and uid not in stored.original_instances.map(func(e):return e.uid),"All instance fields preserved; no carried membership")
 check(not 2605 in stored.original_items and Session.bag_slots(stored)==Session.bag_slots(before)-1,"Warehouse excluded from ITEM predicates and bag count")
 check(not b.session.equip_item("original:%d"%uid),"Stored UID cannot equip")
 unchanged(b,sent,"Repeated RPC rejected without changes")
 check(one(b,uid,"withdraw").ok,"Withdraw exact UID")
 unchanged(b,sent,"Old deposit replay still rejected after round trip")
 # Real disk failure, migration, strict cross-container checks, readback.
 var path:="user://item-storage-%d.json"%OS.get_process_id();b.save_path=path
 check(b.save(),"Save initial fixture")
 DirAccess.make_dir_absolute(path+".tmp")
 unchanged(b,command(b,[{"uid":uid}]),"Save failure rolls back profile/revision and publishes nothing")
 var loaded=Session.new();check(loaded.load_game(path) and loaded.snapshot().item_storage.is_empty(),"Failed deposit leaves disk unchanged")
 DirAccess.remove_absolute(path+".tmp")
 check(one(b,uid).ok and loaded.load_game(path) and loaded.snapshot().item_storage==b.session.snapshot().item_storage,"Deposit readback preserves exact UID/durability")
 DirAccess.make_dir_absolute(path+".tmp")
 unchanged(b,command(b,[{"uids":[uid]}],"withdraw"),"Failed withdrawal rolls back")
 DirAccess.remove_absolute(path+".tmp")
 var invalid:Dictionary=b.session.snapshot();invalid.original_instances.append(invalid.item_storage[0].duplicate());invalid.original_items.append(2605)
 check(not b.session._valid_profile(invalid),"Cross-container duplicated UID rejected")
 invalid=b.session.snapshot();invalid.item_storage[0].uid=invalid.next_original_uid
 check(not b.session._valid_profile(invalid),"Storage UID must precede next allocator")
 invalid=b.session.snapshot();invalid.item_storage[0].binding="unique"
 check(not b.session._valid_profile(invalid),"Unknown instance schema cannot silently discard binding state")
 invalid=b.session.snapshot();invalid.erase("legacy_item_storage")
 check(not b.session._valid_profile(invalid),"Half present schema rejected")
 var old:Dictionary=before.duplicate(true)
 for key in Storage.FIELDS:old.erase(key)
 var file:=FileAccess.open(path+".old",FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
 check(loaded.load_game(path+".old") and loaded.snapshot().item_storage.is_empty(),"Old v6 absent fields migrate to empty warehouse")
 b.queue_free()
 b=fresh();var medicine:=add(b,2450)
 check(one(b,medicine).ok and preload("res://server/original_revival.gd").inventory(b.session.snapshot()).is_empty(),"Battle item inventory never references a warehouse UID")
 b.queue_free()
 # 65 actual UIDs -> 64 + 1; deterministic split into unstacked backpack.
 b=fresh()
 for i in range(65):
  var next:=int(b.session._profile.next_original_uid);b.session._profile.next_original_uid=next+1
  b.session._profile.item_storage.append(Equipment.instance(2468,next))
 check(Storage.used(b.session._profile)==2 and b.session._valid_profile(b.session.snapshot()),"65 eligible originals consume two warehouse slots")
 var rows:=Storage.rows(b.session.snapshot(),b.quest_catalog.items,false)
 check(rows.size()==2 and rows[0].count==64 and rows[1].count==1,"64 stack limit")
 check(b.handle(command(b,[Storage.take(rows[0],3)],"withdraw")).ok,"Partial stack withdraw succeeds")
 check(b.session.snapshot().original_instances.map(func(e):return e.uid)==[1,2,3],"Deterministic exact members enter backpack independently")
 check(Session.bag_slots(b.session.snapshot())==4,"Three ordinary originals occupy three bag slots")
 # Full bag refusal is atomic even for an otherwise legal split.
 rows=Storage.rows(b.session.snapshot(),b.quest_catalog.items,false)
 unchanged(b,command(b,[Storage.take(rows[0],15)],"withdraw"),"Full bag refuses entire split")
 var next_uid:=add(b,2605)
 b.session._profile.item_storage=[]
 for i in range(3000):
  var next:=int(b.session._profile.next_original_uid);b.session._profile.next_original_uid=next+1
  b.session._profile.item_storage.append(Equipment.instance(2605,next))
 check(Storage.used(b.session._profile)==3000,"Every equipment instance consumes its own slot")
 unchanged(b,command(b,[{"uid":next_uid}]),"3000 full warehouse rejects full batch")
 check(one(b,int(b.session._profile.item_storage[0].uid),"withdraw").ok,"Can withdraw from full warehouse")
 check(one(b,next_uid).ok,"Freed independent slot accepts one item")
 b.queue_free()
 # Existing count model remains separate: potions split 64, equipment one slot each.
 b=fresh();b.session._profile.inventory.potion=99;b.session._profile.inventory.club=2
 var selections:=[{"key":"potion","count":99,"offset":0},{"key":"club","count":2,"offset":0}]
 check(b.handle(command(b,selections)).ok and Storage.used(b.session.snapshot())==4,"99 potions=2 stacks, two old clubs=2 independent slots")
 rows=Storage.rows(b.session.snapshot(),b.quest_catalog.items,false)
 check(rows.size()==4 and rows[0].count==64 and rows[1].count==35 and rows[2].count==1,"Count-model storage row boundaries")
 check(b.handle(command(b,[Storage.take(rows[0],10)],"withdraw")).ok and b.session.snapshot().inventory.potion==10,"Partial old-count withdrawal retains existing inventory model")
 # User chose free storage; even client-supplied prices are ignored.
 b.session._profile.player.gold=0
 var free:=command(b,[{"key":"potion","count":10,"offset":0}]);free.cost=999999
 check(b.handle(free).ok and b.session.snapshot().player.gold==0,"Deposit never charges or accepts client price")
 rows=Storage.rows(b.session.snapshot(),b.quest_catalog.items,false)
 check(b.handle(command(b,[Storage.take(rows[0],2)],"withdraw")).ok and b.session.snapshot().player.gold==0,"Withdrawal is also free")
 b.queue_free()
 b=fresh();b.session._profile.inventory.healing_charm=2
 var helper:=[{"key":"healing_charm","count":2,"offset":0}]
 var helper_reply:Dictionary=b.handle(command(b,helper))
 check(helper_reply.ok and b.session.snapshot().inventory.healing_charm==0,"Project helper item can deposit: "+str(helper_reply))
 check(b.session._valid_profile(b.session.snapshot()),"Stored helper validates")
 rows=Storage.rows(b.session.snapshot(),b.quest_catalog.items,false)
 check(not rows.is_empty() and b.handle(command(b,[Storage.take(rows[0],1)],"withdraw")).ok and b.session.snapshot().inventory.healing_charm==1,"Project helper withdraws without loss")
 b.save_path=path
 check(b.save() and loaded.load_game(path) and loaded.snapshot()==b.session.snapshot(),"Helper storage persists exactly")
 b.queue_free()
 for suffix in ["",".bak",".tmp",".old",".old.bak"]:DirAccess.remove_absolute(path+suffix)
 await process_frame
 print("ITEM STORAGE: %d failures"%failures)
 quit(1 if failures else 0)
