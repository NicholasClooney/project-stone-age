"""Safety checks for the diagnostic; these do not certify semantic masks."""
import unittest
import numpy as np
from audit_red_dragon_recolor import candidate


class CandidateTest(unittest.TestCase):
    def test_preserves_transparency_and_unselected_colours(self):
        original = np.array([[0, 168, 240, 213], [214, 215, 159, 75]], np.uint8)
        support = np.array([[12,12,12,6], [5,12,12,7]])
        output, mask = candidate(original, support, 6)
        self.assertTrue(np.array_equal(output == 0, original == 0))
        self.assertTrue(np.array_equal(output[~mask], original[~mask]))
        self.assertTrue(np.array_equal(original, [[0,168,240,213],[214,215,159,75]]))

    def test_threshold_is_not_rider_ground_truth(self):
        # A gold rider pixel can equal six other composite pixels. There is no
        # semantic label in support, so a high consensus alone changes it.
        output, mask = candidate(np.array([[213]], np.uint8), np.array([[12]]), 12)
        self.assertTrue(mask[0,0])
        self.assertNotEqual(output[0,0], 213)

    def test_reproducible(self):
        p = np.array([[212,213,214,0]], np.uint8)
        s = np.full_like(p, 8)
        self.assertTrue(np.array_equal(candidate(p,s,6)[0], candidate(p,s,6)[0]))


if __name__ == '__main__':
    unittest.main()
