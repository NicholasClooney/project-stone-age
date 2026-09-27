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
static func expected(pet:Dictionary)->Dictionary:
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
static func rows(profile:Dictionary,selected:Dictionary,sort_key:String="attack",projected:bool=false)->Array:
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
  var av:Dictionary=a.forecast.get("expected",a.pet) if projected else a.pet
  var bv:Dictionary=b.forecast.get("expected",b.pet) if projected else b.pet
  var x:=int(av.get(sort_key,0));var y:=int(bv.get(sort_key,0))
  if x!=y:return x>y
  return str(a.pet.get("pet_id",a.location+str(a.index)))<str(b.pet.get("pet_id",b.location+str(b.index))))
 return result
