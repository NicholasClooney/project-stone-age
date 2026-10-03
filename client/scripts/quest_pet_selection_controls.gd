extends VBoxContainer
## Display only server-published candidates; selection has no client rules.
signal submitted(choice:String, pet_ids:Array)
var buttons:Array[Button]=[]
var candidates:Array=[]
var selected:String=""
var confirm:Button
var group:ButtonGroup
func configure(dialogue:Dictionary)->void:
 candidates=dialogue.get("pet_candidates",[]).duplicate(true)
 var note:=Label.new()
 note.text=str(dialogue.get("selection_note",""))
 note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 note.custom_minimum_size.x=300
 add_child(note)
 group=ButtonGroup.new()
 for pet in candidates:
  var button:=Button.new()
  button.name="QuestPet_"+str(pet.pet_id)
  button.text="%s · Lv%d · %s"%[str(pet.name),int(pet.level),str(pet.pet_id)]
  button.toggle_mode=true;button.button_group=group
  button.custom_minimum_size.y=44
  button.pressed.connect(func():selected=str(pet.pet_id);confirm.disabled=false)
  add_child(button);buttons.append(button)
  if candidates.size()==1:selected=str(pet.pet_id);button.button_pressed=true
 confirm=Button.new();confirm.name="QuestPetConfirm";confirm.text="确认交付所选宠物"
 confirm.disabled=selected.is_empty();confirm.custom_minimum_size.y=44
 confirm.pressed.connect(func():submitted.emit("yes",[selected]))
 add_child(confirm);buttons.append(confirm)
 var cancel:=Button.new();cancel.name="QuestPetCancel";cancel.text="取消"
 cancel.custom_minimum_size.y=44
 cancel.pressed.connect(func():submitted.emit("no",[]))
 add_child(cancel);buttons.append(cancel)
func set_busy(value:bool)->void:
 for button in buttons:button.disabled=value
 if not value:confirm.disabled=selected.is_empty()
