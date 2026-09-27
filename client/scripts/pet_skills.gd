extends RefCounted
## Authoritative subset of gmsv/data/petskill.txt; executable arguments win over stale descriptions.
const SKILLS := {
	3:{"name":"破除防御","cost":1500,"description":"破除敌人的防御。","handler":"PETSKILL_GuardBreak","guard_break":true},
	10:{"name":"连续攻击","cost":2000,"description":"连续攻击两次，每次伤害按两段分摊。","handler":"PETSKILL_ContinuationAttack","hits":2},
	50:{"name":"背水之战其之１","cost":2000,"description":"攻击力增加25%，防御力减少35%。","handler":"PETSKILL_PowerBalance","attack_percent":125,"defence_percent":65},
}
const TRAINERS := {1003:{"cell":[18,13],"name":"超级饲育员","graphic":16047,"skills":[3,10,50],"rate":1.0}}
static func available(map_id: int) -> Array:
	return TRAINERS.get(map_id,{}).get("skills",[]).duplicate()
