extends SceneTree
const Backend=preload("res://server/backend.gd")
const Charm=preload("res://server/original_charm.gd")
const Session=preload("res://server/game_session.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func talk(b,id:String="original/charm/1005") -> Dictionary:
 var npc: Dictionary=b.original_quests.npc_by_id(id)
 b.automation.position_map=npc.map_id;b.automation.position_cell=Vector2i(npc.cell[0]-1,npc.cell[1])
 return b.handle({"type":"quest_talk","npc_id":id})
func choose(b,r:Dictionary,c:String) -> Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":c})
func trade(b,id:String="original/charm/1005") -> Dictionary:
 return choose(b,choose(b,talk(b,id),"charm"),"yes")
func run() -> void:
 var b=Backend.new()
 for id in ["original/charm/1005","original/charm/2005"]:
  var npc:Dictionary=b.original_quests.npc_by_id(id)
  check(npc.graphic==16065 and npc.name=="美容师" and npc.branches.is_empty() and FileAccess.file_exists("res://assets/legacy/"+str(npc.path)),"reviewed original actor and art "+id)
  check(npc.cell.map(func(v):return int(v))==([25,15] if int(npc.map_id)==1005 else [19,15]),"exact original cell")
 var boundary:Dictionary=b.session.snapshot()
 for level in [1,1000000]:
  boundary.player.level=level;boundary.player.charm=99;boundary.player.gold=1000000000
  check(Charm.cost(boundary)==level*330,"minimum/maximum valid level and currency "+str(level))
 boundary.player.level=0
 check(Charm.cost(boundary)==-2,"level zero rejected")
 boundary.player.level=1;boundary.player.gold=1000000001
 check(Charm.cost(boundary)==-2,"currency above save limit rejected")
 var before:Dictionary=b.session.snapshot()
 var r:=talk(b)
 check(r.dialogue.choices.map(func(c):return c.id)==["charm","leave"],"original choices")
 check(choose(b,r,"leave").closed and b.session.snapshot()==before,"leave never charges")
 r=choose(b,talk(b),"charm")
 check(r.dialogue.text.contains("200") and r.dialogue.choices.map(func(c):return c.id)==["yes","no"],"Lv1 base60 quote200 and yes/no")
 check(choose(b,r,"no").closed and b.session.snapshot()==before,"no never charges")
 r=trade(b)
 check(r.dialogue.text.contains("钱不够") and b.session.snapshot()==before,"insufficient stone original message")
 b.session._profile.player.charm=60
 for coins in [199,200,201]:
  b.session._profile.player.gold=coins
  before=b.session.snapshot();r=trade(b)
  check(r.ok and b.session.snapshot().player.charm==(60 if coins<200 else 65) and b.session.snapshot().player.gold==(coins if coins<200 else coins-200),"exact original affordability boundary "+str(coins))
  b.session._profile.player.charm=60
 b.session._profile.player.gold=0;b.session._profile.player.charm=2
 check(trade(b).ok and b.session.snapshot().player.gold==0 and b.session.snapshot().player.charm==7,"C charm2 free service with zero stone")
 b.session._profile.player.gold=100000
 for charm in [0,1,2,3,59,94,95,96,99]:
  b.session._profile.player.charm=charm
  b.session._profile.player.level=3
  var amount:=30*(1 if charm<=1 else int(charm/3))
  before=b.session.snapshot()
  r=trade(b,"original/charm/2005")
  check(r.ok and b.session.snapshot().player.gold==before.player.gold-amount and b.session.snapshot().player.charm==mini(100,charm+5),"C integer cost and capped +5 at "+str(charm))
  check(not choose(b,r,"yes").ok,"end window cannot charge again")
 b.session._profile.player.charm=100
 before=b.session.snapshot();r=choose(b,talk(b),"charm")
 check(r.dialogue.text.contains("完美") and r.dialogue.choices.size()==1 and b.session.snapshot()==before,"full charm refused")
 b.session._profile.player.charm=60;b.session._profile.player.level=2
 b.session._profile.player.transmigration=2
 check(Charm.cost(b.session.snapshot())==1200,"optional original transmigration multiplier")
 for field in ["transmigration","level","charm","gold"]:
  var old=b.session._profile.player[field]
  for bad in [-1,0.5,"1",true]:
   b.session._profile.player[field]=bad
   check(not talk(b).ok,"reject invalid "+field+" "+str(bad))
  b.session._profile.player[field]=old
 b.session._profile.player.transmigration=2147483647
 check(not talk(b).ok,"C int overflow rejected without charging")
 # v7 requires the explicit count; optional legacy cost inputs are separate
 # dictionaries, not a partially deleted current profile used for disk IO.
 var missing_count:Dictionary=b.session.snapshot();missing_count.player.erase("transmigration")
 check(not b.session._valid_profile(missing_count),"v7 missing mandatory count is rejected instead of inventing history")
 b.session._profile.player.transmigration=0
 var legacy_cost:Dictionary=b.session.snapshot();legacy_cost.player.erase("transmigration")
 check(Charm.cost(legacy_cost)==400,"legacy optional count remains zero for pure cost calculation")
 var p:Dictionary=b.session._profile
 Session.OriginalEquipment.add(p,2427)
 p.original_equipment.amulet=p.original_instances[-1].uid
 var low_level:Dictionary=b.session.snapshot()
 check(Charm.cost(low_level)==400 and not Session.OriginalEquipment.valid(low_level),"Lv2 cost remains400 but direct Lv10 amulet fixture is invalid")
 check(b.session.gm_raise_level(-1,10) and Session.OriginalEquipment.valid(b.session.snapshot()),"use legal original Lv10 equipment before transaction and persistence")
 before=b.session.snapshot();r=trade(b)
 check(r.ok and b.session.snapshot().player.charm==65 and Charm.cost(before)==2000 and b.session.snapshot().player.gold==before.player.gold-2000 and b.session.equipment_mods().charm==-1,"equipment modifier never changes charge or permanent base")
 b.session._profile.player.charm=60
 check(b.session.gm_grant_pet(74),"real pet participates in loyalty recomputation")
 r=choose(b,talk(b),"charm")
 var oldtoken:String=r.dialogue.token
 b.save_path="user://missing-charm-directory/save.json"
 before=b.session.snapshot()
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"save failure rolls back all profile state")
 check(not b.handle({"type":"quest_choose","token":oldtoken,"choice":"yes"}).ok,"failed token cannot replay")
 b.save_path=""
 r=choose(b,talk(b),"charm")
 oldtoken=r.dialogue.token
 check(choose(b,r,"yes").ok and not b.handle({"type":"quest_choose","token":oldtoken,"choice":"yes"}).ok,"successful transaction token cannot replay")
 r=choose(b,talk(b),"charm")
 b.session._profile.player.charm=100
 before=b.session.snapshot()
 check(choose(b,r,"yes").dialogue.text.contains("完美") and b.session.snapshot()==before,"confirmation rechecks full base charm")
 b.session._profile.player.charm=60
 r=choose(b,talk(b),"charm")
 b.automation.position_cell+=Vector2i(10,0)
 before=b.session.snapshot()
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"walk away invalidates transaction")
 r=choose(b,talk(b),"charm")
 before=b.session.snapshot()
 check(not choose(b,r,"arbitrary").ok and b.session.snapshot()==before,"invalid choice consumes token without mutation")
 r=talk(b);var stale:String=r.dialogue.token
 talk(b)
 check(not b.handle({"type":"quest_choose","token":stale,"choice":"charm"}).ok,"replaced token expires")
 b.save_path="user://original-charm-test.json"
 b.session._profile.player.charm=60
 check(b.session._valid_profile(b.session.snapshot()),"complete v7 profile is valid before real charm transaction")
 check(trade(b).ok,"file-backed service commits")
 var written:Variant=JSON.parse_string(FileAccess.get_file_as_string(b.save_path))
 check(written is Dictionary and b.session._valid_profile(written),"actual written full profile validates before readback")
 var loaded=Backend.new()
 check(loaded.load_profile(b.save_path) and loaded.session.snapshot().player.charm==65 and loaded.session.snapshot().player.gold==b.session.snapshot().player.gold,"real save round-trip retains stone and base charm")
 var invalid:Dictionary=b.session.snapshot();invalid.player.transmigration=-1
 check(not b.session._valid_profile(invalid),"save validation rejects invalid optional transmigration")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(b.save_path))
 b.free();loaded.free()
 print("ORIGINAL CHARM: ","PASS" if failures==0 else "FAIL")
 quit(1 if failures else 0)
