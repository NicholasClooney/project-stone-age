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
 var mounted=initial.duplicate(true)
 mounted.enemies[0].level=30
 mounted.ally_pets=[]
 for i in range(4):
  mounted.allies[i].mounted_sprite=101006
  mounted.allies[i].mount={"name":"金虎","hp":100,"max_hp":100,"sprite":100330}
  mounted.ally_pets.append({"name":"乌力","sprite":100250,"hp":80,"max_hp":80,"level":7})
 view.open_battle(mounted);settle()
 check(view.actors.size()==20,"four independent companion slots added to five-human formation")
 check(view.hover_actor_text(1).contains("Lv.30"),"enemy hover shows authoritative level")
 for i in range(4):
  check(view.actors[12+i].character_id=="101006" and view.ally_mount_bars[i].visible,"clone%d uses original rider and mount meter"%i)
  check(view.actors[16+i].home==view.ally_pet_home(i) and view.displayed_hp[16+i]==80,"clone%d pet own formation and HP"%i)
  check(view.hover_actor_text(12+i).contains("金虎") and view.hover_actor_text(16+i).contains("Lv.7"),"clone%d hover includes pet and mount data"%i)
 var pet_hit=mounted.duplicate(true)
 pet_hit.actor="ally_pet";pet_hit.ally_index=2;pet_hit.target_index=0;pet_hit.outcome="hit";pet_hit.damage=10
 pet_hit.enemies[0].hp-=10
 var pet_hurt=pet_hit.duplicate(true)
 pet_hurt.actor="enemy";pet_hurt.enemy_index=0;pet_hurt.enemy_target="ally_pet";pet_hurt.ally_index=3;pet_hurt.damage=80
 pet_hurt.ally_pets[3].hp=0
 var dismount=pet_hurt.duplicate(true)
 dismount.enemy_target="ally";dismount.ally_index=1;dismount.damage=100
 dismount.allies[1].mount.hp=0;dismount.allies[1].mounted_sprite=-1
 var mounted_final=dismount.duplicate(true)
 mounted_final.turn=1;mounted_final.turn_frames=[pet_hit,pet_hurt,dismount];mounted_final.outcome="";mounted_final.active=true
 view.show_state(mounted_final)
 check(not view.actors[18].motions.is_empty(),"clone companion runs to attack independently")
 check(view.actors[19].cues.any(func(c):return c.action==2),"clone companion receives original death pose")
 check(view.actors[13].character_id=="101006" and view.ally_mount_bars[1].visible,"clone dismount waits for impact rather than final snapshot")
 settle()
 check(view.displayed_hp[19]==0 and view.displayed_hp[18]==80,"clone pet damage affects only its own meter")
 check(view.actors[13].character_id==view.ally_art(mounted_final.allies[1],false) and not view.ally_mount_bars[1].visible,"dead clone mount dismounts at impact")
 check(view.actors[12].character_id=="101006" and view.ally_mount_bars[0].visible,"other clone mounts remain independent")
 var pet_escape=view.queue_escape(view.elapsed,true,mounted_final)
 view.feedback_until=pet_escape.end;settle()
 check(not view.actors[16].sprite.visible and not view.actors[18].sprite.visible,"clone companions follow successful escape")
 view.open_battle(plain);settle()
 check(view.actors.size()==3 and not view.ally_mount_bars[0].visible and not view.hp_bars[16].visible,"ordinary battle clears clone pets and riding meters")
 view.queue_free()
 await process_frame
 print("CLONE BATTLE UI: %d failures"%failures)
 quit(1 if failures else 0)
