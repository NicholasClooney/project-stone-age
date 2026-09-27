extends SceneTree
const Battle=preload("res://server/battle_session.gd")
var failures:=0
var view
func _initialize():call_deferred("run")
func check(ok: bool,note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func settle():
 while view.elapsed<view.feedback_until+0.01:
  view._process(1.0/60)
  view.battle_effects._process(1.0/60)
func run():
 view=load("res://scripts/battle_view.gd").new()
 root.add_child(view)
 await process_frame
 view.set_process(false)
 view.battle_effects.set_process(false)
 var allies:Array=[]
 for i in range(4):allies.append({"name":"分身%d"%i,"character_id":100000,"weapon":"club","hp":120,"max_hp":120,"attack":10,"speed":30,"level":5})
 var authority=Battle.new()
 var initial:Dictionary=authority.start_battle({"player_hp":500,"player_max_hp":500,"enemy_hp":1000,"enemy_max_hp":1000})
 initial.allies=allies.duplicate(true)
 check(view.can_render_allies(allies),"mirrored character and club animations available")
 check(not view.can_render_allies([{"character_id":999999}]),"unknown clone art rejected")
 view.open_battle(initial)
 settle()
 check(view.actors.size()==16,"four allies occupy stable slots12 through15")
 var positions=[Vector2(645,528),Vector2(709,480),Vector2(613,552),Vector2(741,456)]
 for i in range(4):
  var actor=12+i
  check(view.actors[actor].home==positions[i],"clone%d native five-person formation"%i)
  check(view.hp_bars[actor].visible and view.displayed_hp[actor]==120,"clone%d independent HP"%i)
  check(view.actors[actor].character_id==str(view.manifest.equipment_variants.club["100000"]),"clone%d original club appearance"%i)
 check(not view.actors[3].sprite.visible and not view.hp_bars[3].visible,"padding enemy slots remain invisible")
 var strike=initial.duplicate(true)
 strike.actor="ally";strike.ally_index=3;strike.target_index=0;strike.outcome="hit";strike.damage=10
 strike.enemies[0].hp-=10
 var hurt=strike.duplicate(true)
 hurt.actor="enemy";hurt.enemy_index=0;hurt.enemy_target="ally";hurt.ally_index=1;hurt.damage=120
 hurt.allies[1].hp=0
 var final=hurt.duplicate(true)
 final.turn=1;final.turn_frames=[strike,hurt];final.active=true;final.outcome=""
 view.show_state(final)
 check(not view.actors[15].motions.is_empty(),"fourth clone runs over and attacks")
 check(view.actors[13].cues.any(func(c):return c.action==2),"enemy hit on clone queues its death animation")
 settle()
 check(view.displayed_hp[13]==0 and not view.hp_bars[13].visible,"dead clone has no live health bar")
 check(view.displayed_hp[0]==500,"damage to clone does not change player health")
 check(view.actors[15].point==positions[3],"attacking clone returns to native home")
 var escape=view.queue_escape(view.elapsed,true,final)
 view.feedback_until=escape.end
 settle()
 check(not view.actors[12].sprite.visible and not view.actors[15].sprite.visible,"living clones depart on successful escape")
 var plain=initial.duplicate(true);plain.erase("allies")
 view.open_battle(plain);settle()
 check(view.actors.size()==3 and not view.hp_bars[12].visible,"normal battle after clones cleans ally nodes and bars")
 var crowded=initial.duplicate(true)
 while crowded.enemies.size()<10:crowded.enemies.append(crowded.enemies[0].duplicate(true))
 view.open_battle(crowded);settle()
 check(view.actors.size()==16 and view.hp_bars[11].visible and view.hp_bars[15].visible,"ten enemies and four clones coexist without reusing actor slots")
 check(view.enemy_index(15)==-1 and view.health_of(crowded,15)==120,"ally slots never map to enemy health or target indices")
 view.queue_free()
 await process_frame
 print("CLONE BATTLE UI: %d failures"%failures)
 quit(1 if failures else 0)
