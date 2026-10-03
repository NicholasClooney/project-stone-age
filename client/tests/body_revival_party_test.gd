extends "res://tests/lan_party_battle_test.gd"
const Equipment=preload("res://server/original_equipment.gd")
const Session=preload("res://server/game_session.gd")
func run() -> void:
 dir="user://body-revival-party-%d"%OS.get_process_id()
 remove_tree(dir);DirAccess.make_dir_recursive_absolute(dir)
 var server=party_hub()[0]
 for failing in [["alice"],["bob"],["cid"],["alice","bob","cid"]]:await revival_and_retry(server,failing)
 await party_pet(server)
 await close(server)
 await race_and_enemy()
 remove_tree(dir)
 print("BODY REVIVAL PARTY: %d failures"%failures)
 quit(1 if failures else 0)
func revival_and_retry(server, failing:Array) -> void:
 for id in ["alice","bob","cid"]:
  server.backends[id].session.gm_raise_level(-1,80)
  server.backends[id].session.gm_heal(-2)
 Equipment.add(server.backends.bob.session._profile,2450)
 var uid:int=server.backends.bob.session.snapshot().original_instances.back().uid
 for id in ["alice","bob","cid"]:check(server.backends[id].save(),"baseline saved %s"%id)
 check(server.handle(1,{"type":"begin_battle","enemy_count":2}).ok,"real hub starts revival party")
 var entry:Dictionary=entry_of(server,"alice");var resolver=entry.session
 for enemy in resolver._state.enemies:enemy.source_wait_only=true
 check(["alice","bob","cid"].all(func(id):return server.backends[id].session._pending.get("revival_transaction",false)),"all participants receive trusted atomic marker, including recipient without medicine")
 resolver._state.allies[1].hp=0
 var before:Dictionary={};var paths:Dictionary={}
 for id in ["alice","bob","cid"]:
  before[id]=server.backends[id].session.snapshot()
  paths[id]=server.backends[id].save_path
  if id in failing:DirAccess.make_dir_absolute(str(paths[id])+".tmp")
 check(send(server,2,"revival:%d"%uid,{"target":4}).ok,"member selects dead teammate via own view")
 check(send(server,1,"defend").ok,"living leader completes round while recipient is dead")
 var hp:int=resolver._state.allies[1].hp
 check(hp>=mini(450,int(resolver._state.allies[1].max_hp)) and hp<=mini(550,int(resolver._state.allies[1].max_hp)),"actual party action revives teammate within450..550")
 check(resolver._state.allies[0].original_revival_items.is_empty(),"only medicine owner's battle inventory consumed")
 # Finish with actual attacks so XP, gold and successful members also commit.
 for round_index in range(20):
  if not resolver.snapshot().active:break
  send(server,1,"attack",{"target":resolver._first_enemy()})
  send(server,2,"defend");send(server,3,"defend")
 check(not resolver.snapshot().active and resolver.snapshot().outcome=="win","real attacks reach normal rewarding victory")
 var frozen:Dictionary={}
 for id in failing:
  var b=server.backends[id]
  check(b.session.snapshot()==before[id],"save failure restores profile including UID/HP/rewards %s"%id)
  check(b.session._pending.has("party_settlement"),"personal result frozen for retry %s"%id)
  frozen[id]=b.session._pending.party_settlement.duplicate(true)
  b.handle({"type":"battle_close"})
  check(b.session.snapshot()==before[id] and b.session._pending.party_settlement==frozen[id],"second failure preserves exact frozen result %s"%id)
  DirAccess.remove_absolute(str(paths[id])+".tmp")
  b.handle({"type":"battle_close"})
  check(b.session._pending.is_empty(),"successful retry clears only own pending %s"%id)
 for id in ["alice","bob","cid"]:
  var b=server.backends[id];var after:Dictionary=b.session.snapshot()
  check(after.player.gold>before[id].player.gold and after.player.xp>before[id].player.xp,"victory rewards committed exactly once %s"%id)
  check(after.original_items.count(2450)==0,"no medicine remains after exactly one owner's consumption %s"%id)
  if id=="cid":check(after.player.hp==hp,"recipient HP equals frozen original random roll")
  var loaded=Session.new()
  check(loaded.load_game(paths[id]) and loaded.snapshot().original_instances==after.original_instances and loaded.snapshot().original_equipment==after.original_equipment and loaded.snapshot().player.hp==after.player.hp and loaded.snapshot().completed_battles==after.completed_battles and loaded.snapshot().player.gold==after.player.gold and loaded.snapshot().player.xp==after.player.xp,"disk readback matches complete committed profile %s"%id)
  b.handle({"type":"battle_close"})
  check(b.session.snapshot()==after,"duplicate close cannot consume or reward again %s"%id)
func race_and_enemy() -> void:
 var server=party_hub()[0]
 for id in ["alice","bob","cid"]:server.backends[id].session.gm_raise_level(-1,80)
 Equipment.add(server.backends.alice.session._profile,2450)
 Equipment.add(server.backends.bob.session._profile,2450)
 var alice_uid:int=server.backends.alice.session.snapshot().original_instances.back().uid
 var bob_uid:int=server.backends.bob.session.snapshot().original_instances.back().uid
 server.handle(1,{"type":"begin_battle","enemy_count":2})
 var resolver=entry_of(server,"alice").session
 for enemy in resolver._state.enemies:enemy.source_wait_only=true
 resolver._state.allies[1].hp=0
 check(send(server,1,"revival:%d"%alice_uid,{"target":4}).ok and send(server,2,"revival:%d"%bob_uid,{"target":4}).ok,"two players queue one dead target")
 check(resolver._state.original_revival_items.is_empty() and resolver._state.allies[0].original_revival_items.is_empty(),"both consume once when earlier actor already revived target")
 check(resolver._state.events.any(func(line):return str(line).contains("仍然消耗")),"race retains visible original living-target consumption note")
 var enemy:Dictionary=resolver._state.enemies[0]
 enemy.hp=0;enemy.generated_drops=[2401]
 resolver._credit_kills("player")
 var killer=enemy.get("killer")
 var claims:Array=resolver.drop_claims_for(0)
 check(claims==[{"enemy":0,"item":0}],"first death credits one concrete original-item claim")
 # Give a new trusted admission item only for this focused lifecycle fixture.
 resolver._state.original_revival_items=[Equipment.instance(2450,900)]
 resolver._cast_revival({"kind":"player","index":-1},"revival:900",{"kind":"enemy","index":0})
 check(enemy.hp>0 and enemy.get("killer")==killer,"enemy revival preserves original killer attribution")
 check(resolver.drop_claims_for(0).is_empty(),"revived live enemy cannot pay cached claims")
 enemy.hp=0;resolver._credit_kills("ally")
 check(enemy.get("killer")==killer and resolver.drop_claims_for(0)==claims,"second death cannot create new loot or overwrite killer")
 enemy.captured=true
 check(resolver.drop_claims_for(0).is_empty(),"captured revived enemy cannot pay cached death claims")
 enemy.captured=false;enemy.hp=1;enemy.generated_drops=[];resolver._drop_claims.clear()
 server.backends.alice.battle.developer_escape()
 await close(server)

func party_pet(server) -> void:
 var receiver=server.backends.cid
 receiver.session.grant_starter_pets();receiver.session.select_pet(0)
 receiver.session._profile.pets[0].variable_ai=0
 Equipment.add(server.backends.bob.session._profile,2450)
 var uid:int=server.backends.bob.session.snapshot().original_instances.back().uid
 for id in ["alice","bob","cid"]:check(server.backends[id].save(),"pet revival baseline saved %s"%id)
 server.handle(1,{"type":"begin_battle","enemy_count":2})
 var resolver=entry_of(server,"alice").session
 for enemy in resolver._state.enemies:enemy.source_wait_only=true
 resolver._state.ally_pets[1].hp=0
 var before:Dictionary=receiver.session.snapshot()
 DirAccess.make_dir_absolute(receiver.save_path+".tmp")
 check(send(server,2,"revival:%d"%uid,{"target":5}).ok,"member uses medicine on another member's participating dead pet")
 send(server,1,"defend");send(server,3,"defend")
 check(resolver._state.ally_pets[1].hp>0 and resolver._state.ally_pets[1].get("original_revival_count",0)==1,"party pet receives one revival and source loyalty counter")
 server.backends.alice.battle.developer_escape()
 check(receiver.session.snapshot()==before,"pet recipient save failure restores HP and loyalty")
 receiver.handle({"type":"battle_close"})
 check(receiver.session.snapshot()==before,"repeated failed pet save never applies loyalty early")
 DirAccess.remove_absolute(receiver.save_path+".tmp")
 receiver.handle({"type":"battle_close"})
 check(receiver.session._pending.is_empty() and receiver.session.snapshot().pets[0].variable_ai==300,"pet recipient retry adds source +300 once, despite owning no medicine")
 var loaded=Session.new()
 check(loaded.load_game(receiver.save_path) and loaded.snapshot().pets[0].variable_ai==300 and loaded.snapshot().pets[0].hp>0,"party revived pet HP/loyalty persisted")
 for id in ["alice","bob","cid"]:server.backends[id].handle({"type":"battle_close"})
