extends RefCounted
## Public300 doorway placement only. Upstream birth→door route is NOT tested.
## The interior position and arrival are produced by real Backend report_position.
static func enter(b)->bool:
 # Fixed manifest includes one reviewed active original door and a disabled duplicate.
 # JSON numeric fields are read as int only after the whole source bytes lock.

 if not source_locks():return false
 var portal:Dictionary={}
 for link in b.quest_helper.places.links(300).values():
  if int(link.get("to_map",-1))==31701:
   portal=link;break
 if portal.is_empty() or portal.get("disabled",false) or portal.has("gate_source") or portal.get("requires_travel_pass",false):return false
 if portal.get("source")!="dungeon02.create:791" or int(portal.cell[0])!=343 or int(portal.cell[1])!=191 or int(portal.target[0])!=29 or int(portal.target[1])!=49:return false
 b.automation.position_changed(300,Vector2i(int(portal.cell[0]),int(portal.cell[1])),true,"project")
 if b.quest_arrival.has_arrival(b,31701,Vector2i(int(portal.target[0]),int(portal.target[1]))):return false
 var result:Dictionary=b.handle({"type":"report_position","map_id":31701,"cell":portal.target.duplicate(),"client":"brothers6d"})
 return result.get("ok",false) and b.automation.position_map==31701 and b.quest_arrival.has_arrival(b,31701,b.automation.position_cell)

static func source_locks()->bool:
 if not source_hash("res://assets/legacy/world/manifest.json","5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639"):return false
 if not source_hash("res://assets/legacy/quests/catalog.json","c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92"):return false
 if not source_hash("res://assets/legacy/world/300.map","b0f936cc464d3f30a24a46a45d5ca29834c5009b3aa5d81787158cead3445d9b"):return false
 if not source_hash("res://assets/legacy/world/31701.map","c45162761a32b6588e8c1ded9b02d41c24229ab145911af5ed5252da20718653"):return false
 return true
static func source_hash(path:String,expected:String)->bool:
 var digest=HashingContext.new()
 if digest.start(HashingContext.HASH_SHA256)!=OK:return false
 if digest.update(FileAccess.get_file_as_bytes(path))!=OK:return false
 return digest.finish().hex_encode()==expected
