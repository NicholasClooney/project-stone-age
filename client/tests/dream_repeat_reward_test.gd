extends "res://tests/original_fixed_guards_test.gd"
const Dream=preload("res://server/dream_cave_helper.gd")
const Equipment=preload("res://server/original_equipment.gd")
const ELDER="seimu/event/event01_1@6000:73:54"
const SAGE="seimu/event/event01_2@41:34:25"
const Natural=preload("res://tests/support/dream_backend_route.gd")
const POOL=[450,451,449,549,552,543,653,646,12623,12648,11895,11926,11936,12052,11803,11814,11824,11833,11843,11853]
func local_trade(b,id:String,map_id:int,point:Vector2i)->Dictionary:
 b.automation.position_changed(map_id,point)
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":id})
 r=choose(b,r,"yes")
 return choose(b,r,"ok") if r.has("dialogue") else r
func run()->void:
 var b=Backend.new()
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 check(b.session.gm_raise_level(-1,34),"fixture reaches actual level34")
 var elder:Dictionary=b.original_quests.npc_by_id(ELDER)
 check(b.original_quests.branch_for(elder,b.session.snapshot()).is_empty(),"level34 without prerequisite cannot receive free light")
 b.session.gm_raise_level(-1,35)
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 check(int(b.original_quests.branch_for(elder,b.session.snapshot()).source_branch_index)==4,"original LV>34 OR alternative permits repeat branch without adult flag")
 check(trade(b,ELDER).ok and b.session.snapshot().original_items.count(2603)==1,"actual elder free repeat light")
 var initial_flags:Dictionary=b.session.snapshot().original_events.duplicate(true)
 check(Natural.win(b).ok,"actual original entrance maze battle and saved Warp grant reward arrival")
 var r:=choose(b,talk(b,SAGE),"yes")
 var before:Dictionary=b.session.snapshot();b.save_path="user://dream-repeat-no-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"repeat exchange failed save retains light flags and UID")
 b.save_path=""
 check(trade(b,SAGE).ok,"repeat original sage exchange succeeds after retry")
 var state:Dictionary=b.session.snapshot()
 check(not 2603 in state.original_items and state.original_items.size()==1 and int(state.original_items[0]) in POOL,"one light becomes exactly one original pool item")
 check(state.original_events==initial_flags,"repeat branch never writes END34 or other progress flags")
 check(not choose(b,r,"ok").ok,"old token cannot duplicate random reward")
 var seen:Dictionary={}
 for i in range(3):
  for item in b.session.snapshot().original_items:Equipment.remove(b.session._profile,int(item))
  # Every new visit completes the actual maze and final guard before exchange.
  if not local_trade(b,ELDER,6000,Vector2i(73,55)).ok:check(false,"repeated source request");break
  check(Natural.win(b).ok,"actual original entrance maze battle and saved Warp grant reward arrival")
  if not trade(b,SAGE).ok:check(false,"repeated source reward");break
  state=b.session.snapshot()
  if state.original_items.size()!=1 or int(state.original_items[0]) not in POOL:check(false,"pool item integrity");break
  seen[int(state.original_items[0])]=true
  if seen.size()==20:break
 check(not seen.is_empty(),"successive original repeat transactions draw only from the fully source-audited twenty-item pool")
 check(b.session.snapshot().original_events==initial_flags,"unlimited repeats preserve all event words")
 var helper:Dictionary=b.quest_helper.snapshot(b)
 check(str(helper).contains("原版行为：") and str(helper).contains("可重复"),"helper exposes original repeat policy")
 b.free()
 print("DREAM REPEAT REWARD: %d failures"%failures);quit(1 if failures else 0)
