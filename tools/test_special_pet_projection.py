import unittest
from special_pet_projection import SPLITS, bracket, summary


class ProjectionTest(unittest.TestCase):
    def test_point_splits_cover_every_case(self):
        self.assertEqual(len(SPLITS), 286)
        self.assertAlmostEqual(sum(p for _, p in SPLITS), 1.0)

    def test_higher_weight_sums_get_the_lower_bracket(self):
        self.assertEqual(bracket([27, 36, 16, 20]), 1)  # 99: 470-520
        self.assertEqual(bracket([23, 37, 20, 25]), 0)  # 105: 450-500

    def test_full_grade_blue_dragon_matches_pet_quality_doc(self):
        # docs/game-systems/pet-quality.md: mean 616.8 at Lv120 (template 92).
        row = summary({'initial': 29, 'weights': [27, 36, 16, 20]}, 600, True)
        self.assertGreater(row['sum_mean'], 615.8)
        self.assertLess(row['sum_mean'], 617.8)


if __name__ == '__main__':
    unittest.main()
