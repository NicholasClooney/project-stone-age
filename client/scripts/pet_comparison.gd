extends RefCounted
const Growth=preload("res://scripts/pet_growth.gd")
const Rules=preload("res://server/progression.gd")
static func species_key(pet:Dictionary)->String:
 var species:=str(pet.get("species",""))
 return {"blue_dragon":"original_92","golden_tiger":"original_194","red_rex":"original_303"}.get(species,species)
static func quality(pet:Dictionary)->Dictionary:
 var definition:=Rules.species_definition(str(pet.get("species","")))
 var weights:Array=pet.get("growth_weights",[])
 var nominal:Array=definition.get("weights",[])
 if weights.size()!=4 or nominal.size()!=4:return {}
 var offsets:=[];var total:=0
 for i in range(4):
  var value:=int(weights[i])-int(nominal[i]);offsets.append(value);total+=value
  if value < -2 or value > 2:return {}
 return {"offsets":offsets,"total":total,"full":total==8}
static func warning(pet:Dictionary)->bool:
 return bool(pet.get("gm_modified",false)) or pet.get("legacy_stat_offset",{}).values().any(func(v):return float(v)!=0)
static var _increment_cache:Dictionary={}
static var _exact_cache:Dictionary={}
# Exact Lv.120 stats from the pet's own growth seed (same grow_pet sequence as
# real levelling); falls back to the average estimate when growth data is missing.
static func expected(pet:Dictionary)->Dictionary:
 if int(pet.get("level",1))<120:
  var key:=str(pet.get("pet_id",""))+"|"+str(pet.get("level"))+"|"+str(pet.get("growth_seed"))+"|"+str(pet.get("base_stats"))+"|"+str(pet.get("legacy_stat_offset",{}))
  if not _exact_cache.has(key):
   var projected:=Rules.project_pet(pet,120)
   _exact_cache[key]={} if projected.is_empty() else {"max_hp":int(projected.max_hp),"attack":int(projected.attack),"defence":int(projected.defence),"speed":int(projected.speed)}
  if not _exact_cache[key].is_empty():return _exact_cache[key]
 return average(pet)
static func average(pet:Dictionary)->Dictionary:
 var base:Dictionary=pet.get("base_stats",{}).duplicate(true)
 if base.is_empty() or pet.get("growth_weights",[]).size()!=4:return pet
 var steps:=maxi(0,120-int(pet.level));var rank:=int(pet.get("growth_rank",0))
 for i in range(4):
  var weight:=int(pet.growth_weights[i]);var key:=str(weight)+":"+str(rank)
  if not _increment_cache.has(key):_increment_cache[key]=Growth.expected_increment(weight,rank)
  base[Rules.STATS[i]]=float(base[Rules.STATS[i]])+steps*float(_increment_cache[key])
 var result:=Rules.derived(base)
 for key in Rules.DERIVED:result[key]=maxi(0 if key=="defence" else 1,int(result[key])+int(pet.get("legacy_stat_offset",{}).get(key,0)))
 return result
## Sort keys in their fixed tie-break order, and the comparison's default order.
const SORT_KEYS:=["stat_total","attack","speed","max_hp","defence"]
const DEFAULT_ORDER:=["stat_total","attack","speed","max_hp"]
const SORT_NAMES:={"stat_total":"三围合","attack":"攻击","speed":"敏捷","max_hp":"体力","defence":"防御"}

## The player's keys (unknown and repeated ones dropped), then every other key
## in SORT_KEYS order, so any two pets with different stats compare the same way.
static func full_order(order:Variant)->Array:
 var result:=[]
 for key in ([order] if order is String else order if order is Array else []):
  if SORT_KEYS.has(key) and not result.has(key):result.append(key)
 for key in SORT_KEYS:
  if not result.has(key):result.append(key)
 return result

static func _id_number(pet:Dictionary)->int:
 var id:=str(pet.get("pet_id",""))
 return int(id.trim_prefix("pet-")) if id.trim_prefix("pet-").is_valid_int() else 1<<62

## Carried pets before warehouse pets; within each group favourites first when
## favorites_first, then each key of order highest first (see full_order), then
## the older pet id. order is an Array of SORT_KEYS or one key as a String.
static func rows(profile:Dictionary,selected:Dictionary,order:Variant=DEFAULT_ORDER,projected:bool=false,favorites_first:bool=true)->Array:
 var keys:=full_order(order)
 var result:=[]
 for location in ["pets","pet_storage"]:
  var pets:Array=profile.get(location,[])
  for index in range(pets.size()):
   var pet:Dictionary=pets[index]
   if species_key(pet)!=species_key(selected):continue
   var forecast:={"expected":expected(pet)}
   result.append({"pet":pet,"location":location,"index":index,"forecast":forecast,"quality":quality(pet)})
 result.sort_custom(func(a,b):
  if a.location!=b.location:return a.location=="pets"
  if favorites_first and bool(a.pet.get("favorite",false))!=bool(b.pet.get("favorite",false)):return bool(a.pet.get("favorite",false))
  var av:Dictionary=a.forecast.get("expected",a.pet) if projected else a.pet
  var bv:Dictionary=b.forecast.get("expected",b.pet) if projected else b.pet
  for key in keys:
   var x:=sort_value(av,key);var y:=sort_value(bv,key)
   if x!=y:return x>y
  if _id_number(a.pet)!=_id_number(b.pet):return _id_number(a.pet)<_id_number(b.pet)
  return str(a.pet.get("pet_id",a.location+str(a.index)))<str(b.pet.get("pet_id",b.location+str(b.index))))
 return result

static func storage_rows(profile:Dictionary)->Array:
 var result:=[]
 var pets:Array=profile.get("pet_storage",[])
 for index in range(pets.size()):result.append({"pet":pets[index],"index":index})
 result.sort_custom(func(a,b):
  if bool(a.pet.get("favorite",false))!=bool(b.pet.get("favorite",false)):return bool(a.pet.get("favorite",false))
  return int(a.index)<int(b.index))
 return result

static func sort_value(stats:Dictionary,key:String)->int:
 if key=="stat_total":return int(stats.get("attack",0))+int(stats.get("defence",0))+int(stats.get("speed",0))
 return int(stats.get(key,0))
