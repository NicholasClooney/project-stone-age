"""Project pets of original templates to a level (default 120) by simulation.

Rewrites the project's rules in Python: birth in client/server/progression.gd
species_actor (four grades rolled -2..+2, or all +2 for 满档, then 10 points
spread at random, times the template's initial value) and grow_pet (each
level another 10 random points plus one shared multiplier drawn from the
species' bracket, added per stat with integer division). The bracket comes
from the template's nominal weight sum (>=100: 450-500, 95-99: 470-520, ...).
Each level's outcome is drawn from its exact distribution (286 point splits x
51 multipliers), so a sample costs one draw per level.

Stats are derived as in progression.gd `derived`; the three-stat sum is
attack + defence + speed, as in the pet stat filter. Check: template 92 (蓝人龙)
at full grade gives a mean of about 616.8, as in docs/game-systems/pet-quality.md.

  python3 tools/special_pet_projection.py 92 303 304 --full 30000 --random 10000

Templates come from client/assets/legacy/encounters/catalog.json.
"""
import argparse
import itertools
import json
import math
import random
from functools import lru_cache
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[1] / 'client/assets/legacy/encounters/catalog.json'
BRACKETS = [100, 95, 90, 85, 80, 0]


def splits():
    """Every way to spread 10 points over four stats, with its probability."""
    result = []
    for v in range(11):
        for s in range(11 - v):
            for t in range(11 - v - s):
                counts = (v, s, t, 10 - v - s - t)
                p = math.factorial(10) / 4 ** 10
                for c in counts:
                    p /= math.factorial(c)
                result.append((counts, p))
    return result


SPLITS = splits()


def bracket(weights):
    total = sum(weights)
    return next(i for i, floor in enumerate(BRACKETS) if total >= floor)


@lru_cache(None)
def level_outcomes(weights, rank):
    low = 450 + rank * 20
    outcomes, probabilities = [], []
    for counts, p in SPLITS:
        for roll in range(low, low + 51):
            outcomes.append(tuple((weights[i] + counts[i]) * roll // 100 for i in range(4)))
            probabilities.append(p / 51)
    return outcomes, list(itertools.accumulate(probabilities))


def derived(v, s, t, d):
    return dict(hp=max(1, (4 * v + s + t + d) // 100), attack=max(1, (20 * s + 2 * t + 2 * v + d) // 2000),
                defence=max(0, (20 * t + 2 * s + 2 * v + d) // 2000), speed=max(1, d // 100))


def simulate(template, count, full, level=120, rng=None):
    rng = rng or random.Random(1)
    nominal = [int(w) for w in template['weights']]
    rank = bracket(nominal)
    result = []
    for _ in range(count):
        grades = tuple(w + (2 if full else rng.randint(-2, 2)) for w in nominal)
        birth = list(grades)
        for _ in range(10):
            birth[rng.randint(0, 3)] += 1
        stats = [b * int(template['initial']) for b in birth]
        outcomes, cumulative = level_outcomes(grades, rank)
        for gain in rng.choices(outcomes, cum_weights=cumulative, k=level - 1):
            for i in range(4):
                stats[i] += gain[i]
        result.append(derived(*stats))
    return result


def quantile(values, fraction):
    values = sorted(values)
    return values[min(len(values) - 1, int(fraction * len(values)))]


def summary(template, count, full, level=120):
    pets = simulate(template, count, full, level)
    sums = [p['attack'] + p['defence'] + p['speed'] for p in pets]
    mean = {k: sum(p[k] for p in pets) / count for k in ('hp', 'attack', 'defence', 'speed')}
    return dict(mean=mean, sum_mean=sum(sums) / count, p99=quantile(sums, 0.99), p999=quantile(sums, 0.999), best=max(sums),
                at_least_624=sum(s >= 624 for s in sums) / count)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('templates', nargs='+', type=int)
    parser.add_argument('--full', type=int, default=30000, help='满档 samples per template')
    parser.add_argument('--random', type=int, default=10000, help='random-grade samples per template')
    parser.add_argument('--level', type=int, default=120)
    args = parser.parse_args()
    templates = json.loads(CATALOG.read_text())['templates']
    for ident in args.templates:
        template = templates[str(ident)]
        for full, count in ((True, args.full), (False, args.random)):
            if count <= 0:
                continue
            row = summary(template, count, full, args.level)
            m = row['mean']
            print(f"{ident} {template['name']} {'满档' if full else '随机'}: 血 {m['hp']:.0f} 攻 {m['attack']:.0f} 防 {m['defence']:.0f} 敏 {m['speed']:.0f}"
                  f" 三围合 均值 {row['sum_mean']:.1f} 前1% {row['p99']} 前0.1% {row['p999']} 最高 {row['best']} ≥624 {row['at_least_624']:.2%}")


if __name__ == '__main__':
    main()
