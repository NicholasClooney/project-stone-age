extends "res://tests/original_wood_equipment_test.gd"
const AdultCheckpoint=preload("res://server/adult_battle_checkpoint.gd")
func run() -> void:
 helmet_rules()
 helmet_saves()
 await helmet_battle()
 await helmet_remote()
 print("ORIGINAL HELMET EQUIPMENT: %d failures"%failures)
 quit(1 if failures else 0)
func helmet_rules():
 var s=strong(29);var uid:=add(s,2418)
 check(not equip(s,uid) and s.last_error==preload("res://server/spirits.gd").TOO_WEAK,"helmet uses original red-text Lv30 admission rule")
 check(s.gm_raise_level(-1,30) and equip(s,uid),"2418 equips in native HEAD at Lv30")
 s._profile.inventory.haru_armor=1;s.equip_item("haru_armor")
 var axe:=add(s,2485);var bracelet:=add(s,2481);var amulet:=add(s,2427)
 equip(s,axe);equip(s,bracelet);equip(s,amulet)
 check(s.snapshot().equipment.body=="haru_armor" and int(s.snapshot().original_equipment.head)==uid,"HEAD does not displace BODY")
 check(Equipment.mods(s.snapshot())=={"attack":41,"defence":10,"speed":-18,"charm":-6} and Equipment.resistances(s.snapshot())==[5,5,5,5,5,5],"helmet exact defence15/speed-3 and metadata resistance3 combine with real accessories")
 var config:Dictionary=s.start_battle_config()
 check(config.equipment_occupied==[true,true,true,true,true] and config.player_weapon=="axe" and int(config.player_defence)==int(s.effective_player_stats().defence),"real admission marks all five C slots and uses effective stats without helmet weapon art")
 s.cancel_pending_battle(str(config.battle_id))
 # Count maximum original ownership separately from the BODY spirit item.
 s.equip_item("haru_armor")
 for key in s._profile.inventory:s._profile.inventory[key]=0
 while Session.bag_slots(s.snapshot())<15:add(s,100)
 check(s.snapshot().original_items.size()==19 and Session.bag_slots(s.snapshot())==15 and s._valid_profile(s.snapshot()),"fifteen bag entries plus HEAD ARM and two decorations accept nineteen original instances")
 var before:Dictionary=s.snapshot()
 check(not equip(s,uid) and s.snapshot()==before,"full bag refuses helmet removal atomically")
 var bad:=before.duplicate(true);bad.original_equipment.head=bad.original_equipment.arm
 check(not s._valid_profile(bad),"wrong-slot HEAD UID is rejected")
 bad=before.duplicate(true);bad.original_equipment.extra=0
 check(not s._valid_profile(bad),"unknown slot does not widen v6 schema")
 bad=before.duplicate(true);bad.original_items[0]=2427
 check(not s._valid_profile(bad),"canonical integer projection must match instance identity")
func helmet_saves():
 var s=strong();var uid:=add(s,2418);var axe:=add(s,2485)
 equip(s,axe);s._profile.original_instances[1].durability=4321
 # Actual old v6: the unsupported reward was a bag item with durability 0.
 var old:Dictionary=s.snapshot();old.original_equipment.erase("head");old.original_equipment.erase("body");old.original_instances[0].durability=0
 var path:="user://helmet-v6.json";remove_files(path);write(path,old)
 var loaded=Session.new()
 check(loaded.load_game(path),"genuine v6 without optional HEAD loads")
 var migrated:Dictionary=loaded.snapshot()
 check(migrated.original_items==old.original_items and int(migrated.original_instances[0].uid)==uid and int(migrated.original_instances[0].durability)==2500000 and int(migrated.original_instances[1].durability)==4321 and int(migrated.original_equipment.arm)==axe and int(migrated.original_equipment.head)==0 and int(migrated.version)==6,"legacy reward initialized once, other UID/wear/ownership preserved without gifts")
 check(equip(loaded,uid),"migrated real reward equips")
 loaded._profile.original_instances[0].durability=12345
 check(loaded.save_game(path),"worn helmet saves")
 var again=Session.new()
 check(again.load_game(path) and again.snapshot().original_instances==loaded.snapshot().original_instances and again.snapshot().original_equipment==loaded.snapshot().original_equipment,"HEAD UID and worn durability survive file restore without reset")
 var invalid:Dictionary=loaded.snapshot();invalid.original_instances[0].durability=0
 check(not loaded._valid_profile(invalid),"new HEAD schema cannot resurrect a destroyed helmet")
 invalid=old.duplicate(true);invalid.original_instances[0].durability=1
 check(not loaded._valid_profile(invalid),"old schema's unsupported helmet cannot forge positive durability")
 remove_files(path)
func helmet_battle():
 var b=Backend.new();b.set_process(false);root.add_child(b);b.session.gm_raise_level(-1,30)
 var uid:=add(b.session,2418);equip(b.session,uid)
 b.session._profile.original_instances[0].durability=17
 var path:="user://helmet-checkpoint.json";remove_files(path);remove_files(path+".resume.json")
 b.save_path=path;b.resume_path=path+".resume.json";check(b.save(),"helmet profile saves before real adult encounter")
 var rng:=RandomNumberGenerator.new();rng.seed=91
 var actor:Dictionary=b.encounter_catalog.actor(450,rng)
 var config:Dictionary=b.session.start_wild_battle_config({"enemies":[actor]})
 b.open_battle(config)
 # Real enemy physical attacks wear HEAD by the C non-arm selector. Defend
 # keeps this adult encounter open while accumulating real received damage.
 for turn in range(200):
  if not b.battle.snapshot().active or int(b.battle.snapshot().original_equipment_items[0].durability)<17:break
  b.battle_command({"action":"defend","target":0})
 var live:Dictionary=b.battle.snapshot()
 check(live.active and int(live.original_equipment_items[0].uid)==uid and int(live.original_equipment_items[0].durability)<17,"real received damage persistently wears actual HEAD instance")
 # Checkpoint API is the actual adult resume mechanism, with genuine profile,
 # pending and battle state. Only its routing shell is seeded for this test.
 b.automation.position_map=10204;b.automation.position_cell=Vector2i(14,7)
 b.quest_auto.quest_id=1
 var checkpoint:Dictionary={"version":1,"map_id":10204,"cell":[14,7],"battle_id":config.battle_id,"turn":live.turn,"profile":b.session.snapshot(),"pending":b.session._pending.duplicate(true),"state":live,"rng_state":b.battle._rng.state,"rng_seed":b.battle.rng_seed}
 write(path+".resume.json",checkpoint)
 var restored=Backend.new();restored.set_process(false);root.add_child(restored)
 check(restored.load_profile(path),"restart restores actual helmet profile file")
 var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path+".resume.json"))
 check(AdultCheckpoint.restore(restored,saved),"adult checkpoint file restores HEAD battle wear")
 check(restored.battle.snapshot().original_equipment_items==live.original_equipment_items and int(restored.battle.snapshot().original_equipment_items[0].uid)==uid,"file checkpoint preserves exact helmet UID and reduced durability")
 var forged:=saved.duplicate(true);forged.state.original_equipment_items[0].durability=2500000
 var reject=Backend.new();reject.set_process(false);root.add_child(reject)
 check(not AdultCheckpoint.restore(reject,forged),"adult restore rejects forged increased helmet durability")
 reject.queue_free()
 # Force no artificial wear: additional real defended turns exhaust the
 # admitted small remaining durability, then settle through normal escape.
 for turn in range(200):
  if not restored.battle.snapshot().active or int(restored.battle.snapshot().original_equipment_items[0].durability)==0:break
  restored.battle_command({"action":"defend","target":0})
 check(int(restored.battle.snapshot().original_equipment_items[0].durability)==0 and not restored.battle.snapshot().equipment_occupied[0] and int(restored.battle._config.player_defence)==int(restored.session.snapshot().player.defence),"actual HEAD destruction clears occupied slot and recomputes defence immediately")
 checkpoint.profile=restored.session.snapshot();checkpoint.pending=restored.session._pending.duplicate(true);checkpoint.state=restored.battle.snapshot();checkpoint.turn=checkpoint.state.turn;checkpoint.rng_state=restored.battle._rng.state
 write(path+".resume.json",checkpoint)
 var broken=Backend.new();broken.set_process(false);root.add_child(broken)
 check(broken.load_profile(path) and AdultCheckpoint.restore(broken,JSON.parse_string(FileAccess.get_file_as_string(path+".resume.json"))),"a file checkpoint after real helmet destruction restores")
 check(int(broken.battle.snapshot().original_equipment_items[0].durability)==0 and int(broken.battle._config.player_defence)==int(broken.session.snapshot().player.defence) and not broken.battle.snapshot().equipment_occupied[0],"broken HEAD is not re-equipped or granted admission defence on restart")
 restored.queue_free();restored=broken
 for turn in range(200):
  if not restored.battle.snapshot().active:break
  restored.battle_command({"action":"escape","target":0})
 check(not restored.battle.snapshot().active and not restored.session.snapshot().original_items.has(2418) and int(restored.session.snapshot().original_equipment.head)==0,"real settlement removes exhausted helmet and HEAD UID without awarding a replacement")
 b.queue_free();restored.queue_free();await process_frame;remove_files(path);remove_files(path+".resume.json")
func helmet_remote():
 var backend=Backend.new();backend.set_process(false);root.add_child(backend);backend.session.gm_raise_level(-1,30)
 var uid:=add(backend.session,2418);backend.session._profile.original_instances[0].durability=12345
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"helmet remote port-zero server")
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 var world=load("res://scenes/main.tscn").instantiate();script.server_url_override="";world.profile_persistence=false;world.viewer_prefs_path="user://helmet-viewer.cfg";root.add_child(world)
 check(await Wait.until(self,func():return world.link.online and not world.data.is_empty()) and await Wait.settle(self,world) and world.backend==null,"real remote helmet viewer has no backend")
 world.adventure_menu.open_menu("inventory");await process_frame;var menu=world.adventure_menu
 await click(menu.panel.get_node("OriginalItemSlot_0"))
 check(menu.panel.find_child("OriginalEquipmentDetails",true,false).text.contains("12345 / 2500000") and menu.panel.find_child("OriginalEquipmentDetails",true,false).text.contains("等级 30") and menu.panel.find_child("OriginalEquipmentDetails",true,false).text.contains("防 +15 敏 -3") and menu.panel.find_child("OriginalEffectsMetadata",true,false).text.contains("【未生效】毒耐性 +3"),"remote item details show exact modifiers, wear and unavailable status resistance")
 await click(menu.panel.get_node("EquipOriginalItem"))
 check(await Wait.until(self,func():return int(world.session.snapshot().original_equipment.head)==uid) and await Wait.settle(self,world),"actual remote equip button uses server authority")
 check(menu.panel.get_node("OriginalItemIcon_0").texture!=null,"existing original2418 icon loads without new asset import")
 check(menu.panel.get_node("OriginalItemSlot_0").position==Vector2(113,36),"worn helmet uses source HEAD centre136,59")
 await click(menu.panel.get_node("OriginalItemSlot_0"));await click(menu.panel.get_node("EquipOriginalItem"))
 check(await Wait.until(self,func():return int(world.session.snapshot().original_equipment.head)==0) and await Wait.settle(self,world),"actual remote unequip returns exact UID to bag")
 world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 remove_files("user://helmet-viewer.cfg")
