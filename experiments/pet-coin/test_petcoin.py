"""Run with: python3 -m unittest test_petcoin (from experiments/pet-coin)."""

import copy
import hashlib
import statistics
import unittest

import petcoin as pc

# Easy difficulty so tests mine in milliseconds.
EASY = pc.Params(initial_target=1 << 248, target_block_ms=1000, retarget_every=4)


def fake_clock(step_ms):
    state = {"t": 1_000_000}

    def clock():
        state["t"] += step_ms
        return state["t"]
    return clock


def mine_chain(n, params=EASY, miner="alice", step_ms=10):
    blocks = []
    clock = fake_clock(step_ms)
    for _ in range(n):
        blocks.append(pc.mine_block(params, blocks, miner, clock=clock))
    return blocks


def reference_grow(stream, species, grades, level=pc.MAX_LEVEL):
    """Straight port of progression.gd using only stream.below(), no inlining."""
    data = pc.SPECIES[species]
    weights = [w + g for w, g in zip(data["weights"], grades)]
    initial = list(weights)
    for _ in range(10):
        initial[stream.below(4)] += 1
    total = sum(data["weights"])
    rank = next(i for i, t in enumerate([100, 95, 90, 85, 80, 0]) if total >= t)
    base = [int(initial[i] * (float(data["initial"]) + 0 * 4.5)) for i in range(4)]
    for _lv in range(2, level + 1):
        extra = [0, 0, 0, 0]
        for _ in range(10):
            extra[stream.below(4)] += 1
        low = 450 + rank * 20
        roll = low + stream.below(51)
        for i in range(4):
            base[i] += int((weights[i] + extra[i]) * roll / 100)
    return base


class DerivationTest(unittest.TestCase):
    def test_deterministic(self):
        h = hashlib.sha256(b"x").digest()
        self.assertEqual(pc.derive_pet(h), pc.derive_pet(h))
        self.assertNotEqual(pc.derive_pet(h), pc.derive_pet(hashlib.sha256(b"y").digest()))

    def test_fast_path_matches_reference(self):
        for i in range(200):
            seed = hashlib.sha256(i.to_bytes(4, "big")).digest()
            s1 = pc.HashStream(seed)
            species, grades = pc.draw_prefix(s1)
            fast = pc.grow(s1, species, grades)["base_stats"]
            s2 = pc.HashStream(seed)
            pc.draw_prefix(s2)
            self.assertEqual(fast, reference_grow(s2, species, grades))

    def test_prefix_is_start_of_full_pet(self):
        h = hashlib.sha256(b"prefix").digest()
        species, grades = pc.pet_prefix(h)
        pet = pc.derive_pet(h)
        self.assertEqual((species, grades), (pet["species"], pet["grades"]))

    def test_fast_prefix_matches_stream_including_rejections(self):
        fallbacks = 0
        for i in range(5000):
            h = hashlib.sha256(b"p" + i.to_bytes(4, "big")).digest()
            self.assertEqual(pc.pet_prefix(h), pc.draw_prefix(pc.HashStream(h)))
            d = hashlib.sha256(h + bytes(8)).digest()
            fallbacks += ((d[0] << 8) | d[1]) >= 65000 or 255 in d[2:6]
        self.assertGreater(fallbacks, 0)

    def test_below_is_unbiased_range(self):
        s = pc.HashStream(b"seed")
        counts = [0] * 5
        for _ in range(50000):
            counts[s.below(5)] += 1
        for c in counts:
            self.assertAlmostEqual(c / 50000, 0.2, delta=0.01)
        self.assertTrue(all(0 <= s.below(1000) < 1000 for _ in range(1000)))

    def test_blue_dragon_full_grade_mean_matches_port(self):
        # docs/game-systems/pet-quality.md: mean 616.8 for 20k full-grade blue dragons.
        scores = [s for s, _ in pc.sample_fixed("blue_dragon", [2, 2, 2, 2], 3000, 1)]
        self.assertAlmostEqual(statistics.fmean(scores), 616.8, delta=0.3)

    def test_growth_ranks(self):
        self.assertEqual(pc.growth_rank("blue_dragon"), 1)  # 99
        self.assertEqual(pc.growth_rank("red_rex"), 0)      # 105


class ChainTest(unittest.TestCase):
    def setUp(self):
        self.blocks = mine_chain(6)

    def assertRejected(self, blocks, fragment):
        with self.assertRaises(pc.ChainError) as ctx:
            pc.verify_chain(blocks, EASY)
        self.assertIn(fragment, str(ctx.exception))

    def test_valid_chain_verifies(self):
        pc.verify_chain(self.blocks, EASY)

    def test_tampered_pet(self):
        b = copy.deepcopy(self.blocks)
        b[2]["pet"]["grades"] = [2, 2, 2, 2]
        self.assertRejected(b, "pet traits")
        b = copy.deepcopy(self.blocks)
        b[2]["pet"]["stats"]["attack"] += 1
        self.assertRejected(b, "pet traits")

    def test_tampered_nonce(self):
        b = copy.deepcopy(self.blocks)
        b[3]["nonce"] += 1
        self.assertRejected(b, "stored hash")

    def test_tampered_prev_hash(self):
        b = copy.deepcopy(self.blocks)
        b[4]["prev_hash"] = "00" * 32
        self.assertRejected(b, "prev_hash")

    def test_tampered_target(self):
        b = copy.deepcopy(self.blocks)
        b[1]["target"] = f"{(1 << 255):064x}"
        self.assertRejected(b, "target")

    def test_recomputed_hash_still_fails(self):
        # Fix up the hash after editing the nonce: proof of work or pet check catches it.
        b = copy.deepcopy(self.blocks)
        blk = b[-1]
        blk["nonce"] += 1
        h = pc.block_hash(bytes.fromhex(blk["prev_hash"]), int(blk["target"], 16),
                          blk["timestamp"], blk["miner_id"], blk["nonce"])
        blk["hash"] = h.hex()
        with self.assertRaises(pc.ChainError):
            pc.verify_chain(b, EASY)


class RetargetTest(unittest.TestCase):
    def test_no_change_between_boundaries(self):
        blocks = mine_chain(3)
        self.assertEqual(pc.next_target(EASY, blocks), EASY.initial_target)

    def test_fast_blocks_make_it_harder(self):
        # 4 blocks 10 ms apart: actual 30 ms vs expected 3000 ms, clamped to /4.
        blocks = mine_chain(4, step_ms=10)
        self.assertEqual(pc.next_target(EASY, blocks), EASY.initial_target // 4)

    def test_exact_ratio(self):
        blocks = mine_chain(4, step_ms=10)
        for i, b in enumerate(blocks):
            b["timestamp"] = 1_000_000 + i * 1500  # actual 4500 vs expected 3000
        self.assertEqual(pc.next_target(EASY, blocks), EASY.initial_target * 4500 // 3000)

    def test_slow_blocks_clamped_and_capped(self):
        blocks = mine_chain(4)
        for i, b in enumerate(blocks):
            b["timestamp"] = 1_000_000 + i * 10**9
        self.assertEqual(pc.next_target(EASY, blocks), EASY.initial_target * 4)

    def test_chain_across_retarget_verifies(self):
        blocks = mine_chain(9)
        pc.verify_chain(blocks, EASY)
        self.assertEqual(int(blocks[4]["target"], 16), EASY.initial_target // 4)

    def test_quality_rule_only_moves_whole_tiers(self):
        q = pc.Params(rule="quality", initial_tier=10, retarget_every=4, target_block_ms=1000)
        blocks = mine_chain(9, params=q)
        pc.verify_chain(blocks, q)
        self.assertEqual([b["target"] for b in blocks], ["10"] * 4 + ["11"] * 4 + ["12"])
        self.assertEqual(pc.tier_probability(16), 1 / 625)
        self.assertEqual(pc.tier_probability(15), 5 / 625)


class IdentityTest(unittest.TestCase):
    def test_copied_nonce_under_other_id_gives_other_pet(self):
        blocks = mine_chain(1)
        b = blocks[0]
        target = int(b["target"], 16)
        stolen = pc.block_hash(pc.GENESIS_PREV, target, b["timestamp"], "eve", b["nonce"])
        self.assertNotEqual(stolen.hex(), b["hash"])
        self.assertNotEqual(pc.pet_summary(pc.derive_pet(stolen)), b["pet"])
        forged = dict(b, miner_id="eve")
        with self.assertRaises(pc.ChainError):
            pc.verify_chain([forged], EASY)


if __name__ == "__main__":
    unittest.main()
