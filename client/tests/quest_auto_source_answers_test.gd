extends SceneTree
const Answers=preload("res://server/quest_auto_source_answers.gd")
var failures:=0
var assertions:=0
var permutations_checked:=0
var table:Dictionary={}
var resolver
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func permutations(form:int)->Array:
 if form==4:return [[]]
 if form==1:return [[0,1],[1,0]]
 return [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]
func service_for(question:Dictionary)->String:
 for source in table.services:
  if table.services[source].question_ids.has(question.id):return source
 return ""
func question_by_id(ident:int)->Dictionary:
 for question in table.questions:
  if int(question.id)==ident:return question
 return {}
func dialogue(source:String,question:Dictionary,order:Array)->Dictionary:
 var choices:Array=[]
 if int(question.answer_type)==4:choices=[{"id":"submit","text":"回答"}]
 else:
  for index in range(order.size()):choices.append({"id":str(index+1),"text":question.options[order[index]]})
 choices.append({"id":"cancel","text":"取消"})
 return {"token":"public-token-is-not-an-output","npc_id":table.services[source].npc_id,"kind":"golden_bui_quiz","input":"text" if int(question.answer_type)==4 else "choice","text":"猜谜 第 1 / %d 题\n%s"%[table.services[source].count,str(question.text).replace("\\n","\n")],"choices":choices}
func assert_answer(reply:Dictionary,question:Dictionary,order:Array,label:String)->void:
 check(reply.status=="answer",label)
 if reply.status!="answer":return
 check(not reply.has("token") and not reply.has("actions") and not reply.has("Warp") and not reply.has("run_id"),"Lookup has no transaction/identity authority")
 if int(question.answer_type)==4:check(reply.choice=="submit" and reply.text==question.options[0],"Fill-in emits the original unnormalized string")
 else:check(reply.choice==str(order.find(int(question.answer))+1) and not reply.has("text"),"Original option text resolves the current shuffled id")
 check(reply.evidence.question_ids.has(int(question.id)) and reply.evidence.question_sha==table.sources[table.question_source],"Answer retains exact source evidence")
func run()->void:
 table=JSON.parse_string(FileAccess.get_file_as_string(Answers.DATA_PATH))
 resolver=Answers.new()
 var forms:Dictionary={1:0,2:0,4:0}
 for question in table.questions:
  forms[int(question.answer_type)]+=1
  var source:=service_for(question)
  for order in permutations(int(question.answer_type)):
   var public:Dictionary=dialogue(source,question,order)
   var before:=public.duplicate(true)
   assert_answer(resolver.resolve_quiz(source,public),question,order,"Every original question and full shuffle resolves")
   check(public==before,"Lookup never changes the published question")
   permutations_checked+=1
   # Width folding applies to lookup only; the protocol header remains exact.
   var marker:int=str(public.text).find("\n")
   public.text=str(public.text).left(marker+1)+Answers._width(str(public.text).substr(marker+1))
   for option in public.choices:
    if option.id!="cancel":option.text=Answers._width(option.text)
   assert_answer(resolver.resolve_quiz(source,public),question,order,"Reviewed width variants resolve with the same output")
 check(forms=={1:22,2:84,4:43} and permutations_checked==591,"149 source rows cover all 591 original option permutations")
 for source in table.services:
  for ident in table.services[source].question_ids:
   var question:=question_by_id(int(ident))
   check(resolver.resolve_quiz(source,dialogue(source,question,permutations(int(question.answer_type))[0])).status=="answer","Every declared service pool remains eligible")
 negative_cases()
 keyword_cases()
 check(resolver.resolve_quiz("genout/quz_812_28_14",{}).status=="manual","Unopened question services stay unavailable")
 var raw:=FileAccess.get_file_as_string(Answers.DATA_PATH)
 resolver._load(raw.replace(str(table.sources[table.question_source]),"0".repeat(64)))
 check(resolver.resolve_quiz("genout/quz_800_29_19",{}).status=="manual" and resolver.resolve_keyword("genout/wpm_100_443_127",{}).status=="manual","Wrong source SHA invalidates the entire static table")
 resolver._load(raw+" ")
 check(resolver.resolve_quiz("genout/quz_800_29_19",{}).status=="manual","Unexpected serialized table bytes fail closed")
 print("SOURCE ANSWERS: %d failures; %d assertions; %d permutations"%[failures,assertions,permutations_checked])
 quit(1 if failures else 0)
func negative_cases()->void:
 var question:=question_by_id(1)
 var source:=service_for(question)
 var original:=dialogue(source,question,[2,0,1])
 for key in ["unknown","wrong_npc","wrong_kind","wrong_input","missing","extra","duplicate_id","duplicate_answer","changed_distractor","trim_distractor","order","count","type"]:
  var bad:=original.duplicate(true)
  match key:
   "unknown":bad.text="猜谜 第 1 / %d 题\nUnknown prompt"%table.services[source].count
   "wrong_npc":bad.npc_id="elsewhere"
   "wrong_kind":bad.kind="original_keyword"
   "wrong_input":bad.input="text"
   "missing":bad.choices.remove_at(0)
   "extra":bad.choices.append({"id":"4","text":"extra"})
   "duplicate_id":bad.choices[1].id=bad.choices[0].id
   "duplicate_answer":bad.choices[0].text=bad.choices[1].text
   "changed_distractor":bad.choices[0].text="changed but same correct answer"
   "trim_distractor":bad.choices[0].text=str(bad.choices[0].text).strip_edges()
   "order":bad.text=str(bad.text).replace("第 1 /","第 0 /")
   "count":bad.text=str(bad.text).replace(" / %d " % table.services[source].count," / 999 ")
   "type":bad.choices[0]=17
  check(resolver.resolve_quiz(source,bad).status=="manual","Reject malformed or unknown public question: "+key)
 var crlf:=original.duplicate(true)
 crlf.text=str(crlf.text).replace("\n","\r\n")
 check(resolver.resolve_quiz(source,crlf).status=="answer","CRLF is a presentation-only line ending")
 var ineligible:Dictionary={}
 for q in table.questions:
  if not table.services[source].question_ids.has(q.id):ineligible=q;break
 check(resolver.resolve_quiz(source,dialogue(source,ineligible,permutations(int(ineligible.answer_type))[0])).status=="manual","Known question outside this service's source mask stays manual")
 # Inject conflicting static candidates only into the pure comparison helper;
 # this never reads or controls a real service's private state.
 var conflict:=question.duplicate(true);conflict.answer=1
 var options:=Answers._choices(original)
 check(Answers._resolve_candidates([question,conflict],options,2,false).status=="manual","Conflicting source candidates cannot choose a guessed answer")
 var text_question:=question_by_id(10)
 var text_conflict:=text_question.duplicate(true);text_conflict.options[0]="another answer"
 check(Answers._resolve_candidates([text_question,text_conflict],{},4,true).status=="manual","Conflicting fill-in answers never concatenate into a contains bypass")
 var spaced:=text_question.duplicate(true);spaced.options[0]=" raw answer "
 check(Answers._resolve_candidates([spaced],{},4,true).text==" raw answer ","Lookup normalization never trims submitted source text")
 var ambiguous:=question.duplicate(true)
 ambiguous.options=["A","Ａ","B"];ambiguous.answer=0
 check(Answers._resolve_candidates([ambiguous],{"1":"A","2":"A","3":"B"},2,true).status=="manual","Width-only duplicate choices remain ambiguous")
func keyword_cases()->void:
 for source in table.keywords:
  var rule:Dictionary=table.keywords[source]
  var public:Dictionary={"token":"ignored","npc_id":rule.npc_id,"kind":"original_keyword","input":"text","text":rule.prompt,"choices":[{"id":"submit","text":"说出口令"},{"id":"no","text":"取消"}]}
  var before:=public.duplicate(true)
  var reply:Dictionary=resolver.resolve_keyword(source,public)
  check(reply.status=="answer" and reply.choice=="submit" and reply.text==rule.answer,"Each of four gates emits its exact original keyword")
  check(reply.evidence.source_sha==table.sources["gmsv/data/npc/"+source] and public==before and not reply.has("token"),"Keyword lookup is read-only and source pinned")
  public.text=Answers._width(public.text)
  check(resolver.resolve_keyword(source,public).status=="answer","Keyword public prompt accepts reviewed width lookup")
  public.npc_id="wrong"
  check(resolver.resolve_keyword(source,public).status=="manual","Keyword source cannot be used at a different NPC")
  public=before.duplicate(true);public.text="Unknown gate"
  check(resolver.resolve_keyword(source,public).status=="manual","Unknown prompt cannot trigger an otherwise known keyword")
  public=before.duplicate(true);public.choices.append({"id":"yes","text":"是"})
  check(resolver.resolve_keyword(source,public).status=="manual","Keyword lookup does not choose a later confirmation phase")
 check(resolver.resolve_keyword("giiru/event/sink/sink03",{}).status=="manual","Fire amounts remain outside this first source slice")
