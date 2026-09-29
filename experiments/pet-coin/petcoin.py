#!/usr/bin/env python3
"""Offline proof-of-work "pet coin" learning experiment.

Every mined block is a pet. The block hash seeds a SHA-256 byte stream that
replaces every RNG call in the game's pet rules (client/server/progression.gd):
species (by rarity weight), the four growth-grade offsets, the ten birth points
and every level 2..120 growth draw. A pet's Lv.120 stats are therefore fixed at
mint time and anyone can re-derive them in milliseconds.

No network, no signatures, no transfers, no consensus between peers. Python 3
standard library only. Not a currency: see README.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import multiprocessing as mp
import os
import statistics
import sys
import time
from dataclasses import asdict, dataclass

# ---------------------------------------------------------------------------
# Game rules ported from client/server/progression.gd
# ---------------------------------------------------------------------------

# Values from the ignored catalogue client/assets/legacy/encounters/catalog.json
# (itself imported from gmsv/data/enemybase.txt), hardcoded so this folder runs
# in a fresh worktree without the original assets. "rarity" is ours, not the
# game's: it is the relative mint weight in this experiment.
SPECIES = {
    "blue_dragon": {"alias": "蓝人龙", "name": "扬奇洛斯", "template": 92,
                    "initial": 29, "weights": [27, 36, 16, 20], "rarity": 700},
    "golden_tiger": {"alias": "金虎", "name": "金格萨贝鲁", "template": 194,
                     "initial": 25, "weights": [19, 29, 18, 29], "rarity": 200},
    "red_rex": {"alias": "红暴龙", "name": "巴朵兰恩", "template": 303,
                "initial": 27, "weights": [23, 37, 20, 25], "rarity": 80},
    "mech_rex": {"alias": "机暴", "name": "帖拉所伊朵", "template": 304,
                 "initial": 28, "weights": [23, 35, 25, 21], "rarity": 20},
}
SPECIES_ORDER = list(SPECIES)
RARITY_TOTAL = sum(SPECIES[k]["rarity"] for k in SPECIES_ORDER)
assert RARITY_TOTAL == 1000  # pet_prefix's fast path decodes a 2-byte draw below 1000
RANK_THRESHOLDS = [100, 95, 90, 85, 80, 0]
MAX_LEVEL = 120


def growth_rank(species: str) -> int:
    total = sum(SPECIES[species]["weights"])
    for i, threshold in enumerate(RANK_THRESHOLDS):
        if total >= threshold:
            return i
    return 5


def derived(base: list[int]) -> dict:
    """progression.gd derived(): base stats are [vitality, strength, toughness, dexterity]."""
    v, s, t, d = base
    return {
        "max_hp": max(1, (4 * v + s + t + d) // 100),
        "attack": max(1, (20 * s + 2 * t + 2 * v + d) // 2000),
        "defence": max(0, (20 * t + 2 * s + 2 * v + d) // 2000),
        "speed": max(1, d // 100),
    }


def score(stats: dict) -> int:
    """三围合: attack + defence + speed (HP excluded), as in docs/game-systems/pet-quality.md."""
    return stats["attack"] + stats["defence"] + stats["speed"]


# ---------------------------------------------------------------------------
# Hash stream: the only source of randomness
# ---------------------------------------------------------------------------

class HashStream:
    """Bytes of SHA-256(seed || counter) for counter = 0, 1, 2, ...

    below(n) draws an unbiased integer in [0, n) by rejection sampling.
    """

    __slots__ = ("seed", "counter", "buf", "pos")

    def __init__(self, seed: bytes):
        self.seed = seed
        self.counter = 0
        self.buf = b""
        self.pos = 32  # empty: first read refills

    def _refill(self) -> None:
        self.buf = hashlib.sha256(self.seed + self.counter.to_bytes(8, "big")).digest()
        self.counter += 1
        self.pos = 0

    def byte(self) -> int:
        if self.pos >= 32:
            self._refill()
        b = self.buf[self.pos]
        self.pos += 1
        return b

    def below(self, n: int) -> int:
        if n <= 0:
            raise ValueError("n must be positive")
        if n == 1:
            return 0
        nbytes = ((n - 1).bit_length() + 7) // 8
        span = 1 << (8 * nbytes)
        limit = span - span % n
        while True:
            x = 0
            for _ in range(nbytes):
                x = (x << 8) | self.byte()
            if x < limit:
                return x % n


def draw_species(stream: HashStream) -> str:
    r = stream.below(RARITY_TOTAL)
    for key in SPECIES_ORDER:
        r -= SPECIES[key]["rarity"]
        if r < 0:
            return key
    raise AssertionError("unreachable")


def draw_prefix(stream: HashStream) -> tuple[str, list[int]]:
    """Species and the four grade offsets: randi_range(-2, 2) each."""
    species = draw_species(stream)
    grades = [stream.below(5) - 2 for _ in range(4)]
    return species, grades


def grow(stream: HashStream, species: str, grades: list[int], level: int = MAX_LEVEL) -> dict:
    """species_actor(level 1) then grow_pet for levels 2..level, drawing from stream."""
    data = SPECIES[species]
    weights = [w + g for w, g in zip(data["weights"], grades)]
    initial = list(weights)
    birth = [0, 0, 0, 0]
    for _ in range(10):
        birth[stream.below(4)] += 1
    for i in range(4):
        initial[i] += birth[i]
    rank = growth_rank(species)
    # int(initial * (data.initial + (1 - 1) * wild_growth)) is exact at level 1.
    base = [initial[i] * data["initial"] for i in range(4)]
    lv1 = derived(base)
    low = 450 + rank * 20
    w0, w1, w2, w3 = weights
    # Inlined stream reads: 256 % 4 == 0 so byte & 3 is unbiased, and a roll in
    # 51 values rejects byte 255 (limit 255). Same draws as stream.below().
    buf, pos = stream.buf, stream.pos
    for _lv in range(2, level + 1):
        e0 = e1 = e2 = e3 = 0
        for _ in range(10):
            if pos >= 32:
                stream.pos = pos
                stream._refill()
                buf, pos = stream.buf, 0
            k = buf[pos] & 3
            pos += 1
            if k == 0:
                e0 += 1
            elif k == 1:
                e1 += 1
            elif k == 2:
                e2 += 1
            else:
                e3 += 1
        while True:
            if pos >= 32:
                stream.pos = pos
                stream._refill()
                buf, pos = stream.buf, 0
            x = buf[pos]
            pos += 1
            if x < 255:
                roll = low + x % 51
                break
        base[0] += (w0 + e0) * roll // 100
        base[1] += (w1 + e1) * roll // 100
        base[2] += (w2 + e2) * roll // 100
        base[3] += (w3 + e3) * roll // 100
    stream.pos = pos
    stats = derived(base)
    return {
        "species": species,
        "alias": data["alias"],
        "grades": grades,
        "growth_weights": weights,
        "birth_points": birth,
        "growth_rank": rank,
        "level": level,
        "lv1": lv1,
        "base_stats": base,
        "stats": stats,
        "score": score(stats),
    }


def derive_pet(block_hash: bytes, level: int = MAX_LEVEL) -> dict:
    stream = HashStream(block_hash)
    species, grades = draw_prefix(stream)
    return grow(stream, species, grades, level)


_ZERO_COUNTER = bytes(8)
_SPECIES_BY_ROLL = [k for k in SPECIES_ORDER for _ in range(SPECIES[k]["rarity"])]


def pet_prefix(block_hash: bytes) -> tuple[str, list[int]]:
    """Cheap early-exit view: species and grades from the first 6 bytes of the stream.

    Same result as draw_prefix(HashStream(block_hash)) but decoded straight from
    one SHA-256 block; the rare rejections (about 2.4%) fall back to the stream.
    """
    d = hashlib.sha256(block_hash + _ZERO_COUNTER).digest()
    r = (d[0] << 8) | d[1]
    if r < 65000 and d[2] < 255 and d[3] < 255 and d[4] < 255 and d[5] < 255:
        return _SPECIES_BY_ROLL[r % 1000], [d[2] % 5 - 2, d[3] % 5 - 2, d[4] % 5 - 2, d[5] % 5 - 2]
    return draw_prefix(HashStream(block_hash))


def pet_summary(pet: dict) -> dict:
    """Fields a block stores as a claim; verify_chain recomputes and compares them."""
    return {"species": pet["species"], "grades": pet["grades"],
            "birth_points": pet["birth_points"], "stats": pet["stats"], "score": pet["score"]}


# ---------------------------------------------------------------------------
# Blocks and chain
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Params:
    rule: str = "target"             # "target" (hash < target) or "quality" (grade tier)
    initial_target: int = 1 << 234   # about 2**22 expected hashes per block
    max_target: int = (1 << 256) - 1
    target_block_ms: int = 2000
    retarget_every: int = 10
    max_adjust: int = 4              # clamp each retarget to x4 or /4
    initial_tier: int = 12           # quality rule: grade sum >= tier - 8
    max_tier: int = 16


DEFAULT_PARAMS = Params()
GENESIS_PREV = bytes(32)


def header_bytes(prev_hash: bytes, target: int, timestamp_ms: int, miner_id: str) -> bytes:
    miner = miner_id.encode("utf-8")
    if not 1 <= len(miner) <= 255:
        raise ValueError("miner id must be 1..255 UTF-8 bytes")
    return (prev_hash + target.to_bytes(32, "big") + timestamp_ms.to_bytes(8, "big")
            + bytes([len(miner)]) + miner)


def block_hash(prev_hash: bytes, target: int, timestamp_ms: int, miner_id: str, nonce: int) -> bytes:
    """seed = SHA-256(prev_hash || target || timestamp || miner_id || nonce).

    This is the discussed SHA-256(prev || miner || nonce) with target and
    timestamp also committed, so neither can be edited after mining.
    """
    return hashlib.sha256(header_bytes(prev_hash, target, timestamp_ms, miner_id)
                          + nonce.to_bytes(8, "big")).digest()


def tier_probability(tier: int) -> float:
    """P(grade sum >= tier - 8) for four independent uniform draws in -2..2."""
    need = tier - 8
    count = 0
    for a in range(-2, 3):
        for b in range(-2, 3):
            for c in range(-2, 3):
                for d in range(-2, 3):
                    if a + b + c + d >= need:
                        count += 1
    return count / 625


def meets(params: Params, h: bytes, target: int) -> bool:
    if params.rule == "target":
        return int.from_bytes(h, "big") < target
    _species, grades = pet_prefix(h)
    return sum(grades) >= target - 8


def next_target(params: Params, blocks: list[dict]) -> int:
    """Target (or quality tier) required for the block at height len(blocks)."""
    height = len(blocks)
    if height == 0:
        return params.initial_target if params.rule == "target" else params.initial_tier
    prev = int(blocks[-1]["target"], 16) if params.rule == "target" else int(blocks[-1]["target"])
    n = params.retarget_every
    if height % n != 0:
        return prev
    actual = blocks[-1]["timestamp"] - blocks[-n]["timestamp"]
    expected = (n - 1) * params.target_block_ms
    if params.rule == "quality":
        # Only whole tiers exist: one step up or down, never a 1.3x nudge.
        if actual * 2 < expected:
            return min(params.max_tier, prev + 1)
        if actual > expected * 2:
            return max(0, prev - 1)
        return prev
    actual = max(expected // params.max_adjust, min(expected * params.max_adjust, actual))
    return max(1, min(params.max_target, prev * actual // expected))


def encode_target(params: Params, target: int) -> str:
    return f"{target:064x}" if params.rule == "target" else str(target)


def make_block(params: Params, blocks: list[dict], miner_id: str, nonce: int, timestamp_ms: int) -> dict:
    prev = bytes.fromhex(blocks[-1]["hash"]) if blocks else GENESIS_PREV
    target = next_target(params, blocks)
    h = block_hash(prev, target, timestamp_ms, miner_id, nonce)
    return {
        "height": len(blocks),
        "prev_hash": prev.hex(),
        "miner_id": miner_id,
        "nonce": nonce,
        "target": encode_target(params, target),
        "timestamp": timestamp_ms,
        "hash": h.hex(),
        "pet": pet_summary(derive_pet(h)),
    }


def mine_block(params: Params, blocks: list[dict], miner_id: str, clock=None,
               start_nonce: int = 0) -> dict:
    """Grind nonces until the rule is met. clock() returns milliseconds."""
    clock = clock or (lambda: int(time.time() * 1000))
    prev = bytes.fromhex(blocks[-1]["hash"]) if blocks else GENESIS_PREV
    target = next_target(params, blocks)
    nonce = start_nonce
    while True:
        ts = clock()
        if blocks:
            ts = max(ts, blocks[-1]["timestamp"])
        base = hashlib.sha256(header_bytes(prev, target, ts, miner_id))
        # Refresh the timestamp every 2**16 nonces, like a real miner would.
        stop = nonce + (1 << 16)
        if params.rule == "target":
            target_bytes = target.to_bytes(32, "big")
            while nonce < stop:
                c = base.copy()
                c.update(nonce.to_bytes(8, "big"))
                if c.digest() < target_bytes:
                    return make_block(params, blocks, miner_id, nonce, ts)
                nonce += 1
        else:
            while nonce < stop:
                c = base.copy()
                c.update(nonce.to_bytes(8, "big"))
                if meets(params, c.digest(), target):
                    return make_block(params, blocks, miner_id, nonce, ts)
                nonce += 1


class ChainError(ValueError):
    pass


def verify_chain(blocks: list[dict], params: Params = DEFAULT_PARAMS, now_ms: int | None = None) -> None:
    """Recompute linking, targets, retargets, proof of work and every pet. Raises ChainError."""
    now_ms = now_ms if now_ms is not None else int(time.time() * 1000)
    for height, block in enumerate(blocks):
        where = f"block {height}"
        if block.get("height") != height:
            raise ChainError(f"{where}: height {block.get('height')} out of order")
        expected_prev = blocks[height - 1]["hash"] if height else GENESIS_PREV.hex()
        if block["prev_hash"] != expected_prev:
            raise ChainError(f"{where}: prev_hash does not link to the previous block")
        target = next_target(params, blocks[:height])
        if block["target"] != encode_target(params, target):
            raise ChainError(f"{where}: target {block['target']} != recomputed {encode_target(params, target)}")
        if height and block["timestamp"] < blocks[height - 1]["timestamp"]:
            raise ChainError(f"{where}: timestamp goes backwards")
        if block["timestamp"] > now_ms + 2 * 3600 * 1000:
            raise ChainError(f"{where}: timestamp too far in the future")
        h = block_hash(bytes.fromhex(block["prev_hash"]), target, block["timestamp"],
                       block["miner_id"], int(block["nonce"]))
        if h.hex() != block["hash"]:
            raise ChainError(f"{where}: stored hash does not match the header")
        if not meets(params, h, target):
            raise ChainError(f"{where}: proof of work does not meet the target")
        if pet_summary(derive_pet(h)) != block["pet"]:
            raise ChainError(f"{where}: pet traits do not match the hash")


def load_chain(path: str) -> list[dict]:
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f)["blocks"]


def save_chain(path: str, blocks: list[dict], params: Params) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"params": {k: (hex(v) if isinstance(v, int) and v > 1 << 32 else v)
                              for k, v in asdict(params).items()},
                   "blocks": blocks}, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def params_for(rule: str) -> Params:
    return Params(rule=rule)


def describe(pet: dict) -> str:
    s = pet["stats"]
    grades = "/".join(f"{g:+d}" for g in pet["grades"])
    return (f"{SPECIES[pet['species']]['alias']} 档{grades} (总{sum(pet['grades']):+d}) "
            f"Lv120 血{s['max_hp']} 攻{s['attack']} 防{s['defence']} 敏{s['speed']} 三围合{pet['score']}")


# ---------------------------------------------------------------------------
# Benchmark and Monte Carlo
# ---------------------------------------------------------------------------

def _rate_worker(args) -> int:
    seconds, mode, worker = args
    base = hashlib.sha256(b"bench" + worker.to_bytes(4, "big"))
    deadline = time.perf_counter() + seconds
    n = 0
    target_bytes = (1 << 238).to_bytes(32, "big")
    while time.perf_counter() < deadline:
        for _ in range(4096):
            c = base.copy()
            c.update(n.to_bytes(8, "big"))
            h = c.digest()
            if mode == "hash":
                if h < target_bytes:
                    pass
            elif mode == "prefix":
                species, grades = pet_prefix(h)
                if species == "blue_dragon" and grades == [2, 2, 2, 2]:
                    pass
            n += 1
    return n


def _pet_rate(seconds: float) -> float:
    n = 0
    start = time.perf_counter()
    while time.perf_counter() - start < seconds:
        derive_pet(hashlib.sha256(n.to_bytes(8, "big")).digest())
        n += 1
    return n / (time.perf_counter() - start)


def _grow_worker(args) -> list[tuple[int, int]]:
    """Pets of one species with fixed grades; rest of the stream from hashed seeds."""
    species, grades, start, count = args
    out = []
    for i in range(start, start + count):
        seed = hashlib.sha256(b"mc|" + species.encode() + bytes(g + 2 for g in grades)
                              + i.to_bytes(8, "big")).digest()
        pet = grow(HashStream(seed), species, list(grades))
        out.append((pet["score"], pet["stats"]["attack"]))
    return out


def _birth_worker(args) -> list[tuple[int, int]]:
    """Whole births of one species: grades drawn from the stream too."""
    species, start, count = args
    out = []
    for i in range(start, start + count):
        stream = HashStream(hashlib.sha256(b"birth|" + species.encode() + i.to_bytes(8, "big")).digest())
        grades = [stream.below(5) - 2 for _ in range(4)]
        pet = grow(stream, species, grades)
        out.append((pet["score"], sum(grades)))
    return out


def _chunks(total: int, parts: int):
    size = -(-total // parts)
    return [(s, min(size, total - s)) for s in range(0, total, size)]


def sample_fixed(species, grades, n, workers):
    jobs = [(species, tuple(grades), s, c) for s, c in _chunks(n, max(1, workers * 4))]
    if workers > 1:
        with mp.Pool(workers) as pool:
            parts = pool.map(_grow_worker, jobs)
    else:
        parts = list(map(_grow_worker, jobs))
    return [x for p in parts for x in p]


def sample_births(species, n, workers):
    jobs = [(species, s, c) for s, c in _chunks(n, max(1, workers * 4))]
    if workers > 1:
        with mp.Pool(workers) as pool:
            parts = pool.map(_birth_worker, jobs)
    else:
        parts = list(map(_birth_worker, jobs))
    return [x for p in parts for x in p]


def fmt_time(seconds: float) -> str:
    if seconds < 120:
        return f"{seconds:.1f} 秒"
    if seconds < 7200:
        return f"{seconds / 60:.1f} 分钟"
    if seconds < 172800:
        return f"{seconds / 3600:.1f} 小时"
    return f"{seconds / 86400:.1f} 天"


def bench(seconds: float, workers: int, samples: int, prefix_samples: int) -> dict:
    print(f"== 哈希速率 (每项 {seconds:.0f} 秒) ==")
    single = _rate_worker((seconds, "hash", 0)) / seconds
    prefix = _rate_worker((seconds, "prefix", 0)) / seconds
    pets = _pet_rate(seconds)
    print(f"单核: 区块头哈希+比较 {single:,.0f} 次/秒")
    print(f"单核: 区块头哈希+物种/资质早筛 {prefix:,.0f} 次/秒 (每次约2个SHA-256)")
    print(f"单核: 完整推导Lv120宠物 {pets:,.0f} 只/秒 (约 {1000 / pets:.2f} 毫秒/只, 即验证成本)")
    multi = single
    multi_prefix = prefix
    if workers > 1:
        with mp.Pool(workers) as pool:
            multi = sum(pool.map(_rate_worker, [(seconds, "hash", w) for w in range(workers)])) / seconds
            multi_prefix = sum(pool.map(_rate_worker, [(seconds, "prefix", w) for w in range(workers)])) / seconds
        print(f"{workers} 进程: 区块头哈希 {multi:,.0f} 次/秒, 带早筛 {multi_prefix:,.0f} 次/秒")

    print(f"\n== 哈希派生宠物的蒙特卡洛 ==")
    counts = {k: 0 for k in SPECIES_ORDER}
    full_blue = 0
    for i in range(prefix_samples):
        species, grades = pet_prefix(hashlib.sha256(b"prefix|" + i.to_bytes(8, "big")).digest())
        counts[species] += 1
        if species == "blue_dragon" and grades == [2, 2, 2, 2]:
            full_blue += 1
    for k in SPECIES_ORDER:
        print(f"  {SPECIES[k]['alias']}: {counts[k] / prefix_samples:.4f} (设计 {SPECIES[k]['rarity'] / RARITY_TOTAL:.3f})")
    p_blue = SPECIES["blue_dragon"]["rarity"] / RARITY_TOTAL
    p_full_blue = p_blue / 625
    print(f"  满档蓝人龙: 抽样 {full_blue}/{prefix_samples} = 1/{prefix_samples / max(1, full_blue):,.0f}, "
          f"精确 1/{1 / p_full_blue:,.0f}")

    full = sample_fixed("blue_dragon", [2, 2, 2, 2], samples, workers)
    scores = [s for s, _ in full]
    mean = statistics.fmean(scores)
    ge624_full = sum(s >= 624 for s in scores) / len(scores)
    print(f"  满档蓝人龙 Lv1->120 三围合: 均值 {mean:.2f} (文档 616.8), 最高 {max(scores)}, "
          f"≥624 占 {ge624_full:.6f} (1/{1 / max(ge624_full, 1e-12):,.0f}), n={len(scores):,}")

    # >=624 among all blue births: stratify by grade vector near the top.
    near = sample_births("blue_dragon", max(20000, samples // 10), workers)
    best_nonfull = max((s for s, g in near if g < 8), default=0)
    seven = [[1, 2, 2, 2], [2, 1, 2, 2], [2, 2, 1, 2], [2, 2, 2, 1]]
    ge624_seven = 0.0
    for g in seven:
        part = sample_fixed("blue_dragon", g, max(5000, samples // 20), workers)
        ge624_seven += sum(s >= 624 for s, _ in part) / len(part) / 625
    p624_given_blue = ge624_full / 625 + ge624_seven
    print(f"  随机资质蓝人龙样本最高(非满档) {best_nonfull}; 总档+7 四种向量贡献 {ge624_seven:.2e}")
    print(f"  所有出生蓝人龙中 ≥624: {p624_given_blue:.3e} (1/{1 / max(p624_given_blue, 1e-18):,.0f})")

    red = sample_births("red_rex", samples, workers)
    red_scores = sorted((s for s, _ in red), reverse=True)
    q = red_scores[max(0, len(red_scores) // 1000 - 1)]
    p_top_red = sum(s >= q for s in red_scores) / len(red_scores)
    print(f"  红暴龙所有出生 Lv120 三围合: 均值 {statistics.fmean(red_scores):.1f}, 前0.1%门槛 ≥{q} "
          f"(实际占 {p_top_red:.5f}, 取整导致不是正好0.1%), n={len(red_scores):,}")

    p_red = SPECIES["red_rex"]["rarity"] / RARITY_TOTAL
    targets = [
        ("满档蓝人龙", p_full_blue),
        ("≥624 蓝人龙(所有出生中)", p_blue * p624_given_blue),
        (f"红暴龙前0.1% (三围合≥{q})", p_red * p_top_red),
    ]
    difficulty = (1 << 256) / DEFAULT_PARAMS.initial_target
    print(f"\n== 期望尝试次数与时间 (本机) ==")
    print("A. 只看宠物 (质量规则, 或无难度门槛): 每次尝试 = 区块头哈希 + 早筛, 按带早筛速率")
    print(f"B. 目标规则: 宠物只由合格区块给出, 期望哈希 = 难度 {difficulty:,.0f} / p, 按纯哈希速率")
    results = {}
    for label, p in targets:
        tries = 1 / p
        pow_hashes = difficulty / p
        print(f"  {label}: p={p:.3e}, 期望 {tries:,.0f} 次尝试")
        print(f"      A: 单核 {fmt_time(tries / prefix)}, {workers}进程 {fmt_time(tries / multi_prefix)}")
        print(f"      B: {tries:,.0f} 个区块 = {pow_hashes:.2e} 次哈希; 单核 {fmt_time(pow_hashes / single)}, "
              f"{workers}进程 {fmt_time(pow_hashes / multi)}; 按每块 {DEFAULT_PARAMS.target_block_ms / 1000:g} 秒出块 "
              f"{fmt_time(tries * DEFAULT_PARAMS.target_block_ms / 1000)}")
        results[label] = {"p": p, "tries": tries, "a_single_s": tries / prefix,
                          "a_multi_s": tries / multi_prefix, "b_multi_s": pow_hashes / multi}
    print("早筛: 物种和资质来自扩展流的前6字节, 不合格候选只花 2 个 SHA-256 就丢弃;"
          f" 只有约 1/{1 / p_full_blue:,.0f} 的候选才需要 {1000 / pets:.2f} 毫秒的完整成长推导,"
          " 摊到每次尝试可以忽略。安全性取决于 SHA-256, 而不是游戏公式。")
    return {"single": single, "prefix": prefix, "pets_per_s": pets, "multi": multi,
            "multi_prefix": multi_prefix, "mean_full_blue": mean, "red_q": q, "results": results}


def ladder(samples: int, workers: int) -> None:
    print("== 质量规则的难度阶梯 (总档 ≥ tier-8, 物种不限) ==")
    prev = None
    for tier in range(0, 17):
        p = tier_probability(tier)
        step = f"x{prev / p:.3f}" if prev else ""
        print(f"  tier {tier:2d}: 总档≥{tier - 8:+d}  p={p:.5f}  期望 {1 / p:8.1f} 次  {step}")
        prev = p
    print("  tier 16 之后没有下一级: 资质已满档, 只能改用 Lv120 三围合等门槛。")
    scores = [s for s, _ in sample_fixed("blue_dragon", [2, 2, 2, 2], samples, workers)]
    print(f"\n== 满档蓝人龙再按 Lv120 三围合 (n={len(scores):,}) ==")
    prev = None
    for t in range(614, max(scores) + 1):
        c = sum(s >= t for s in scores)
        p = c / len(scores)
        step = f"x{prev / p:.1f}" if prev and p else ""
        print(f"  ≥{t}: {c:7d}  p={p:.6f}  {step}")
        prev = p
    print("\n目标规则可把难度调到任意倍数 (target 是 256 位整数); 质量规则只能在这些台阶间跳,"
          " 低端每步几乎不变, 高端一步就是 x3 到 x10 以上, 所以出块时间无法平稳。")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_mine(args) -> None:
    params = params_for(args.rule)
    blocks = load_chain(args.chain)
    if blocks:
        verify_chain(blocks, params)
    for _ in range(args.blocks):
        t0 = time.perf_counter()
        block = mine_block(params, blocks, args.miner)
        blocks.append(block)
        save_chain(args.chain, blocks, params)
        dt = time.perf_counter() - t0
        target = block["target"] if params.rule == "quality" else f"2^{int(block['target'], 16).bit_length() - 1}"
        print(f"#{block['height']:3d} nonce={block['nonce']:>9} {dt:6.2f}s target={target:>6} "
              f"{describe(derive_pet(bytes.fromhex(block['hash'])))}")


def cmd_verify(args) -> None:
    params = params_for(args.rule)
    blocks = load_chain(args.chain)
    t0 = time.perf_counter()
    try:
        verify_chain(blocks, params)
    except ChainError as e:
        print(f"无效: {e}")
        sys.exit(1)
    dt = time.perf_counter() - t0
    print(f"有效: {len(blocks)} 个区块, 验证耗时 {dt * 1000:.1f} 毫秒 ({dt * 1000 / max(1, len(blocks)):.2f} 毫秒/块)")


def cmd_show(args) -> None:
    blocks = load_chain(args.chain)
    chosen = blocks if args.height is None else [blocks[args.height]]
    for b in chosen:
        pet = derive_pet(bytes.fromhex(b["hash"]))
        print(f"#{b['height']:3d} {b['miner_id']:>8} {b['hash'][:16]}… {describe(pet)}")
    if args.height is not None:
        print(json.dumps(chosen[0], ensure_ascii=False, indent=1))


def cmd_steal(args) -> None:
    """Copy a block's nonce under another miner id: different hash, different pet."""
    params = params_for(args.rule)
    blocks = load_chain(args.chain)
    b = blocks[args.height]
    target = next_target(params, blocks[:args.height])
    prev = bytes.fromhex(b["prev_hash"])
    stolen = block_hash(prev, target, b["timestamp"], args.miner, int(b["nonce"]))
    print(f"原矿工 {b['miner_id']}: {b['hash'][:16]}… {describe(derive_pet(bytes.fromhex(b['hash'])))}")
    print(f"冒用者 {args.miner}: {stolen.hex()[:16]}… {describe(derive_pet(stolen))}")
    print(f"冒用者的哈希满足难度吗? {meets(params, stolen, target)}")


def cmd_bench(args) -> None:
    bench(args.seconds, args.workers, args.samples, args.prefix_samples)


def cmd_ladder(args) -> None:
    ladder(args.samples, args.workers)


def main(argv=None) -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="离线工作量证明宠物币实验")
    ap.add_argument("--chain", help="默认 chain.json (目标规则) 或 chain-quality.json")
    ap.add_argument("--rule", choices=["target", "quality"], default="target")
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("mine")
    m.add_argument("--blocks", type=int, default=5)
    m.add_argument("--miner", default="alice")
    m.set_defaults(func=cmd_mine)
    sub.add_parser("verify").set_defaults(func=cmd_verify)
    s = sub.add_parser("show")
    s.add_argument("--height", type=int)
    s.set_defaults(func=cmd_show)
    st = sub.add_parser("steal")
    st.add_argument("--height", type=int, default=0)
    st.add_argument("--miner", default="eve")
    st.set_defaults(func=cmd_steal)
    cpu = os.cpu_count() or 1
    b = sub.add_parser("bench")
    b.add_argument("--seconds", type=float, default=3.0)
    b.add_argument("--workers", type=int, default=cpu)
    b.add_argument("--samples", type=int, default=200000)
    b.add_argument("--prefix-samples", type=int, default=500000)
    b.set_defaults(func=cmd_bench)
    la = sub.add_parser("ladder")
    la.add_argument("--samples", type=int, default=200000)
    la.add_argument("--workers", type=int, default=cpu)
    la.set_defaults(func=cmd_ladder)
    args = ap.parse_args(argv)
    if args.chain is None:
        args.chain = os.path.join(here, "chain.json" if args.rule == "target" else "chain-quality.json")
    args.func(args)


if __name__ == "__main__":
    main()
