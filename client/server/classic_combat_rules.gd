extends RefCounted
## Neutral-element, unmounted physical combat from gmsv/battle/battle_event.c.
## DuckCheck:667; DamageCalc:1041; CriticalCheck:1136; CounterCalc:1205.
static func odds(a: Dictionary, d: Dictionary, mode: String) -> float:
	var attack := float(a.get("dex",a.get("speed",10)))
	var defence := float(d.get("dex",d.get("speed",7)))
	var ak := str(a.get("kind","enemy"))
	var dk := str(d.get("kind","enemy"))
	var divisor := 0.02 if mode == "miss" else 0.09 if mode == "critical" else 0.08
	var root := true
	if mode == "miss":
		if ak == "enemy" and dk == "pet": attack = int(attack * 0.8)
		elif ak != "enemy" and dk == "pet": defence = int(defence * 0.8)
		elif ak != "player" and dk == "player": attack = int(attack * 0.6)
		elif ak == "player" and dk != "player": defence = int(defence * 0.6)
	else:
		if ak == "pet" and dk == "enemy": defence = int(defence * 0.8)
		elif (ak == "enemy" and dk == "pet") or (ak != "player" and dk == "player"):
			divisor = 10.0
			root = false
		elif ak == "player" and dk != "player": defence = int(defence * 0.6)
	var big := maxf(attack,defence)
	var small := minf(attack,defence)
	var ratio := 1.0 if (defence >= attack if mode == "miss" else attack >= defence) else small / maxf(big,1)
	var work := (big-small)/divisor
	if mode == "counter": work = int(work)
	var percent := (sqrt(work) if root else work) * ratio
	if mode == "miss": percent += float(d.get("luck",0)) if dk == "player" else 0.0
	elif mode == "critical": percent += float(a.get("luck",0)) + float(a.get("critical",0))*0.5*ratio
	elif ak == "player":
		# CounterTbl fist/fist9, club/fist8, fist/club7, club/club10.
		var club := str(a.get("weapon","")) == "club"
		var other_club := str(d.get("weapon","")) == "club"
		percent *= (10.0 if other_club else 8.0) * 0.1 if club else (7.0 if other_club else 9.0)*0.1
		percent += float(a.get("luck",0))
	return clampf(percent,0.01,75.0 if mode == "miss" else 100.0)

static func resolve(a: Dictionary, d: Dictionary, rng: RandomNumberGenerator, guard: bool, profile: String = "classic") -> Dictionary:
	if not guard and rng.randi_range(1,10000) <= int(odds(a,d,"miss")*100):
		return {"outcome":"miss","damage":0}
	var critical := rng.randi_range(1,10000) < int(odds(a,d,"critical")*100)
	var attack := float(a.get("attack",10))
	var defence := float(d.get("defence",0))*0.45 + float(d.get("speed",7))*0.2 + float(d.get("vital",0))*(0.05 if d.get("mounted",false) else 0.1)
	if profile == "reference": defence = float(d.get("defence",0))*0.70
	var damage: int
	if defence > attack: damage = rng.randi_range(0,1)
	elif attack < defence*8.0/7.0: damage = rng.randi_range(0,int(attack/16.0))
	else: damage = int((attack-defence)*2.0 + rng.randi_range(0,int(attack/8.0))-attack/16.0)
	if critical: damage += int(float(d.get("critical_defence",d.get("defence",0)))*float(a.get("level",1))/maxf(1,float(d.get("level",1)))*0.5)
	if guard:
		# BATTLE_GuardAdjust:1013: weighted retention of 0/10/20/30/40/50%.
		var roll := rng.randi_range(1,100)
		var factor := 0.0 if roll <= 25 else 0.1 if roll <= 50 else 0.2 if roll <= 70 else 0.3 if roll <= 85 else 0.4 if roll <= 95 else 0.5
		damage = int(damage*factor)
	if damage < 1: damage = rng.randi_range(0,1)
	return {"outcome":"critical" if critical else "hit","damage":maxi(0,damage)}
