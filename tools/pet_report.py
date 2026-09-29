"""Summarize pets of one species in the local save (read-only).

Counts carried and warehouse pets, auto-hunt keepers, and how many meet the
blue dragon hunt rule (sum >= 624 OR attack > 292), then lists the best ones.
"""
import argparse
import json
from pathlib import Path

SAVE = Path.home() / "Library/Application Support/Godot/app_userdata/Stone Age — 萨姆吉尔村/single-player.json"


def stat_sum(pet):
    return int(pet["attack"]) + int(pet["defence"]) + int(pet["speed"])


def rows(profile, species):
    for where, label in (("pets", "随身"), ("pet_storage", "仓库")):
        for pet in profile.get(where, []):
            if pet.get("species") in species:
                yield label, pet


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--save", type=Path, default=SAVE)
    parser.add_argument("--template", type=int, default=92, help="original template id (92 = blue dragon)")
    parser.add_argument("--sum", type=int, default=624, help="stat-sum threshold (>=)")
    parser.add_argument("--attack", type=int, default=292, help="attack threshold (strictly >)")
    parser.add_argument("--top", type=int, default=20)
    args = parser.parse_args()

    profile = json.loads(args.save.read_text(encoding="utf-8"))
    species = {f"original_{args.template}"} | ({"blue_dragon"} if args.template == 92 else set())
    found = list(rows(profile, species))
    level120 = [(where, pet) for where, pet in found if int(pet.get("level", 0)) >= 120]
    hunted = [(where, pet) for where, pet in found if pet.get("auto_hunt") or pet.get("auto_reject")]
    by_sum = [p for _, p in found if stat_sum(p) >= args.sum]
    by_attack = [p for _, p in found if int(p["attack"]) > args.attack]
    matches = [p for _, p in found if stat_sum(p) >= args.sum or int(p["attack"]) > args.attack]

    print(f"存档: {args.save}")
    print(f"原表 {args.template}: 共 {len(found)} 只（随身 {sum(w == '随身' for w, _ in found)} · 仓库 {sum(w == '仓库' for w, _ in found)}）· 120级 {len(level120)} 只")
    print(f"自动找宠存入（auto_hunt）: {len(hunted)} 只")
    print(f"三围合≥{args.sum}: {len(by_sum)} · 攻击>{args.attack}: {len(by_attack)} · 任一满足: {len(matches)}")
    print()
    print(f"最好 {args.top} 只（按三围合，再按攻击）:")
    print(f"{'ID':<10} {'位置':<4} {'Lv':>3} {'三围合':>5} {'攻':>4} {'防':>4} {'敏':>4} {'血':>5}  标记")
    ranked = sorted(found, key=lambda item: (-stat_sum(item[1]), -int(item[1]["attack"]), str(item[1].get("pet_id"))))
    for where, pet in ranked[:args.top]:
        flags = [name for name, on in (("自动", pet.get("auto_hunt") or pet.get("auto_reject")), ("达标", pet.get("auto_qualified")), ("收藏", pet.get("favorite")), ("GM", pet.get("gm_modified"))) if on]
        print(f"{str(pet.get('pet_id')):<10} {where:<4} {int(pet['level']):>3} {stat_sum(pet):>5} {int(pet['attack']):>4} {int(pet['defence']):>4} {int(pet['speed']):>4} {int(pet['max_hp']):>5}  {' '.join(flags)}")


if __name__ == "__main__":
    main()
