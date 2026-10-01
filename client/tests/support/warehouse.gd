extends RefCounted
## Check the visible warehouse against authoritative session data, including
## UID order, current stats, tooltip and capacity-dependent actions.
const Comparison=preload("res://scripts/pet_comparison.gd")
const Table=preload("res://scripts/pet_table.gd")
static func matches(menu,profile:Dictionary)->bool:
	var rows:Array=Comparison.storage_rows(profile,menu.storage_order,menu.storage_favorites_first,menu.storage_ascending,menu.storage_species).slice(menu.pet_storage_page*20,(menu.pet_storage_page+1)*20)
	var nodes:Array=menu.panel.find_children("StorageRow_*","",true,false)
	if nodes.size()!=rows.size():return false
	var subtitle:String="%d只 · 携带%d/%d"%[profile.pet_storage.size(),profile.pets.size(),menu.world.session.PET_CAPACITY]
	if menu.panel.get_child(0).get_child(0).get_child(1).text!=subtitle:return false
	for i in range(rows.size()):
		var pet:Dictionary=rows[i].pet
		var row:Control=nodes[i]
		if str(row.name)!="StorageRow_"+str(pet.pet_id):return false
		if row.tooltip_text!="%s Lv.%d · %s\n攻%d 防%d 敏%d · 三围合%d"%[pet.name,pet.level,pet.pet_id,pet.attack,pet.defence,pet.speed,int(pet.attack)+int(pet.defence)+int(pet.speed)]:return false
		var line:Node=row.get_child(0)
		if line.get_child(1).get_child(0).text!=str(pet.name):return false
		for j in range(Table.COLUMNS.size()):
			if line.get_child(j+2).text!=str(Table.value_of(pet,Table.COLUMNS[j][0])):return false
		var retrieve:Button=line.get_child(line.get_child_count()-1).get_child(0)
		if retrieve.disabled!=(profile.pets.size()>=menu.world.session.PET_CAPACITY):return false
	return true
