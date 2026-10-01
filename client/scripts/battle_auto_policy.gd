extends RefCounted
## A capture is thrown only when it wins at least this many rolls out of 100.
const MIN_CAPTURE_ODDS := 10
## Single-player convenience decisions; never mutate battle state or grant rewards.
static func decide(state: Dictionary, settings: Dictionary, target: int) -> Dictionary:
 if int(state.get("clear_capture_target",-1))>=0:return clear_capture_decision(state,settings,target)
 if state.get("healing_available",false) and int(state.get("pet_hp",0))>0 and int(state.get("pet_hp",0))*2<=int(state.get("pet_max_hp",0)):
  return {"action":"heal_pet","pet":"defend","target":maxi(0,target)}
 var enemies: Array=state.get("enemies",[])
 if str(settings.get("preset","attack"))!="capture":
  for i in range(enemies.size()):
   if int(enemies[i].hp)>0 and not enemies[i].get("captured",false):return {"action":"attack","pet":"attack","target":i}
  return {"stop":"找不到可攻击目标"}
 if target<0 or target>=enemies.size():return {"stop":"请先选择要捕捉的敌人"}
 var enemy: Dictionary=enemies[target]
 if enemy.get("captured",false):return {"stop":"目标已捕获，已停止自动操作"}
 if int(enemy.hp)<=0:return {"stop":"捕捉目标已倒下，已停止；不会改抓其他敌人"}
 if not state.get("can_capture",true):return {"stop":"当前战斗不可继续捕捉，可能已达捕获数量上限"}
 if not enemy.get("can_capture",false) or state.get("boss",false):return {"stop":"所选目标不可捕捉"}
 # capture_odds (battle_session snapshot): rolls out of 100 a capture wins now.
 # Below MIN_CAPTURE_ODDS the target is weakened first (斑尼迪克 at full HP: 0).
 var odds:=int(enemy.get("capture_odds",-1))
 var low_enough:=int(enemy.hp)*100<=int(enemy.get("max_hp",1))*int(settings.get("capture_hp",100))
 if low_enough and (odds<0 or odds>=MIN_CAPTURE_ODDS):
  return {"action":"capture","pet":"defend","target":target}
 var choice:=capture_pet_choice(state,settings,int(enemy.get("level",1)))
 if choice.has("stop"):
  # Weakening only because of the odds: without a weaken pet, keep throwing
  # while any roll wins, and stop with the reason when none can.
  if low_enough and odds>0:return {"action":"capture","pet":"defend","target":target}
  if low_enough and odds==0:return {"stop":"捕获率为0：需要削血宠先削血（%s）"%str(choice.stop)}
  return choice
 var best:=int(choice.index)
 if best!=int(state.get("active_pet",-1)):return {"action":"switch","pet":"defend","target":target,"switch":best}
 return {"action":"defend","pet":"attack","target":target}

## Why a run stops at the 停机线 (`line` percent), or "": the player, the
## battle pet, the mount, and the mount the run started on (`starting_ride`).
static func health_stop(state:Dictionary,line:int,starting_ride:int=-1)->String:
 if float(state.player_hp)/maxf(1,float(state.player_max_hp))*100<=line:return "玩家体力达到停机线"
 for index in [int(state.get("active_pet",-1)),int(state.get("ride_pet",-1)),starting_ride]:
  if index>=0 and index<state.get("pets",[]).size():
   var pet:Dictionary=state.pets[index]
   if float(pet.hp)/maxf(1,float(pet.max_hp))*100<=line:return "%s 体力达到停机线"%str(pet.get("name","宠物"))
 return ""

static func capture_pet_choice(state:Dictionary,settings:Dictionary,target_level:int)->Dictionary:
 var selected:=int(settings.get("capture_pet",-1))
 var pets: Array=state.get("pets",[])
 var ident:=str(settings.get("capture_pet_id",""))
 if not ident.is_empty():
  selected=-1
  for i in range(pets.size()):
   if str(pets[i].get("pet_id",""))==ident:selected=i;break
  if selected<0:return {"stop":"指定削血宠 %s 不在随身队伍，请先从仓库取回或重新选择"%ident}
 var best:=-1
 for i in range(pets.size()):
  if selected>=0 and i!=selected:continue
  if i==int(state.get("ride_pet",-1)) or int(pets[i].get("hp",0))<=0:continue
  var limit:=int(settings.get("capture_pet_max_level",10))
  if selected<0:limit=mini(limit,target_level)
  if int(pets[i].get("level",1))>limit:continue
  if best<0 or int(pets[i].get("level",1))<int(pets[best].get("level",1)):best=i
 if best<0 and selected>=0:return {"stop":"指定削血宠 %s 不符合条件：须存活、非骑乘且等级不超过上限"%(ident if not ident.is_empty() else str(selected+1))}
 if best<0:return {"stop":"没有可用低等级宠物：请选存活、非骑乘且符合等级上限的宠物"}
 return {"index":best}

## 用精灵补血: which healing 精灵 the automation casts this turn, or {}.
## `state` is the battle as the caster sees it (player_mp, spirits, its own
## pet and mount, allies and their pets). At or below `line` percent: the
## caster itself (治愈, else 滋润 or 恩惠 on itself), its mount (the rider's
## heal is shared with the mount), its pet; a fallen pet gets 复活精灵. With
## `team` (a party battle) also a fallen teammate (复活精灵) and the lowest
## teammate at the line (滋润, or 恩惠 when two or more are). Only spirits
## whose 气力 the caster still has; a 回复药 is the caller's fallback.
## `side_line` (全体补血, training.side_heal, 0 off): first of all, a worn
## 恩惠 on the whole side when anyone standing on it (the caster, its pet
## and mount, allies and their pets and mounts) is below that percent;
## exactly at it does not count. `side_taken`: another caster already casts
## 恩惠 this turn (party battles), so this one does not.
static func spirit_choice(state: Dictionary, line: int, team: bool = false, side_line: int = 0, side_taken: bool = false) -> Dictionary:
 var spirits: Dictionary = state.get("spirits",{})
 var mp := int(state.get("player_mp",0))
 var by_target := {}
 var revive := ""
 for slot in spirits:
  var spirit: Dictionary = spirits[slot]
  if int(spirit.get("mp",0))>mp or int(spirit.get("field",0))==2:continue
  if str(spirit.get("kind",""))=="ressurect":revive = "spirit:"+str(slot)
  elif str(spirit.get("kind",""))=="recovery":by_target[int(spirit.get("target",-1))] = "spirit:"+str(slot)
 if by_target.is_empty() and revive.is_empty():return {}
 if side_line>0 and not side_taken and by_target.has(8) and side_below(state,side_line):return {"action":by_target[8],"target":20}
 var own_hp := int(state.get("player_hp",0))
 var own_max := maxi(1,int(state.get("player_max_hp",1)))
 var mount_low := false
 var ride := int(state.get("ride_pet",-1))
 var pets: Array = state.get("pets",[])
 if ride>=0 and ride<pets.size():mount_low = _at_line(int(pets[ride].get("hp",0)),int(pets[ride].get("max_hp",1)),line)
 if _at_line(own_hp,own_max,line) or (own_hp>0 and mount_low):
  for target in [0,1,8]:
   if by_target.has(target):return {"action":by_target[target],"target":20 if target==8 else 0}
 var pet: Dictionary = state.get("pet",{})
 if not pet.is_empty():
  var pet_hp := int(state.get("pet_hp",pet.get("hp",0)))
  if pet_hp<=0 and not revive.is_empty():return {"action":revive,"target":1}
  if _at_line(pet_hp,int(state.get("pet_max_hp",pet.get("max_hp",1))),line):
   for target in [1,8]:
    if by_target.has(target):return {"action":by_target[target],"target":20 if target==8 else 1}
 if not team:return {}
 var allies: Array = state.get("allies",[])
 var lowest := -1
 var count := 0
 for i in range(mini(4,allies.size())):
  var ally: Dictionary = allies[i]
  if bool(ally.get("escaped",false)):continue
  if int(ally.get("hp",0))<=0 and not revive.is_empty():return {"action":revive,"target":2+2*i}
  if _at_line(int(ally.get("hp",0)),int(ally.get("max_hp",1)),line):
   count += 1
   if lowest<0 or int(ally.hp)*int(allies[lowest].max_hp)<int(allies[lowest].hp)*int(ally.max_hp):lowest = i
 if lowest<0:return {}
 if count>=2 and by_target.has(8):return {"action":by_target[8],"target":20}
 if by_target.has(1):return {"action":by_target[1],"target":2+2*lowest}
 if by_target.has(8):return {"action":by_target[8],"target":20}
 return {}

## Someone standing on the caster's side is below `percent` of their HP:
## the caster, its pet and mount, the allies (not escaped), their pets and
## mounts. Exactly at `percent` is not below.
static func side_below(state: Dictionary, percent: int) -> bool:
 var members: Array = [[int(state.get("player_hp",0)),int(state.get("player_max_hp",1))]]
 var pet: Dictionary = state.get("pet",{})
 if not pet.is_empty():members.append([int(state.get("pet_hp",pet.get("hp",0))),int(state.get("pet_max_hp",pet.get("max_hp",1)))])
 var ride := int(state.get("ride_pet",-1))
 var pets: Array = state.get("pets",[])
 if ride>=0 and ride<pets.size():members.append([int(pets[ride].get("hp",0)),int(pets[ride].get("max_hp",1))])
 var allies: Array = state.get("allies",[])
 var ally_pets: Array = state.get("ally_pets",[])
 for i in range(allies.size()):
  var ally: Dictionary = allies[i]
  if bool(ally.get("escaped",false)):continue
  members.append([int(ally.get("hp",0)),int(ally.get("max_hp",1))])
  var mount: Dictionary = ally.get("mount",{})
  if not mount.is_empty():members.append([int(mount.get("hp",0)),int(mount.get("max_hp",1))])
  if i<ally_pets.size() and not ally_pets[i].is_empty():members.append([int(ally_pets[i].get("hp",0)),int(ally_pets[i].get("max_hp",1))])
 for member in members:
  if int(member[0])>0 and int(member[0])*100<int(member[1])*percent:return true
 return false

## Standing, hurt and at or below the 停机线 (`line` percent).
static func _at_line(hp: int, max_hp: int, line: int) -> bool:
 return hp>0 and hp<max_hp and hp*100<=max_hp*line

## Shared by live automation and the five real-core forecast trials. The
## battle pins the slot; changing settings never changes that identity.
static func clear_capture_decision(state: Dictionary, settings: Dictionary, target: int) -> Dictionary:
 var pinned := int(state.clear_capture_target)
 var enemies: Array = state.get("enemies",[])
 if target!=pinned or target<0 or target>=enemies.size():return {"stop":"捕捉目标引用已失效"}
 var enemy: Dictionary = enemies[target]
 if str(enemy.get("battle_uid",""))!=str(state.get("clear_capture_uid","")):return {"stop":"捕捉目标引用已失效"}
 if bool(enemy.get("captured",false)):return {"action":"escape","pet":"defend","target":target,"assist":true}
 if int(enemy.hp)<=0:return {"stop":"捕捉目标已倒下，已停止；不会改抓其他敌人"}
 if not bool(state.get("can_capture",true)) or not bool(enemy.get("can_capture",false)):return {"stop":"当前战斗不可继续捕捉，可能已达捕获数量上限"}
 for i in range(enemies.size()):
  if int(enemies[i].hp)>0 and int(enemies[i].get("level",0))!=1:
   return {"action":"attack","pet":"defend","target":i,"assist":false}
 var attempts := int(state.get("capture_attempts",0))
 var evaluation: Dictionary = preload("res://server/capture_rules.gd").evaluate(state.get("capture_player",{}),enemy)
 var hard := attempts>=clampi(int(settings.get("capture_fallback_attempts",5)),1,30) or int(evaluation.get("winning_rolls",0))<clampi(int(settings.get("capture_fallback_rate",20)),0,98)
 var line := mini(int(settings.get("capture_hp",100)),clampi(int(settings.get("capture_fallback_hp",50)),1,99))
 if hard and int(enemy.hp)*100>int(enemy.get("max_hp",1))*line:
  var choice := capture_pet_choice(state,settings,int(enemy.get("level",1)))
  if choice.has("stop"):return choice
  if int(choice.index)!=int(state.get("active_pet",-1)):return {"action":"switch","pet":"defend","target":target,"switch":int(choice.index),"assist":true}
  return {"action":"defend","pet":"attack","target":target,"assist":true}
 return {"action":"capture","pet":"defend","target":target,"assist":true}
