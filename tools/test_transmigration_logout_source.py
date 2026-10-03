"""Exact source rows for the Session's four-item logout-list increment."""
import hashlib
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class LogoutSource(unittest.TestCase):
    def test_exact_original_rows(self):
        raw = (ROOT/'references/chenmingbiao-stone-age/gmsv/data/itemset.txt').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), 'c997393a4806f01833de102939830fc0000bb2a9d445eb214b8501c2b28c4f5d')
        lines = raw.splitlines()
        for line, item in zip(range(2282, 2286), range(2771, 2775)):
            row = lines[line-1].split(b',')
            self.assertEqual(row[16], str(item).encode())
            self.assertEqual(row[78], b'1')
if __name__ == '__main__':
    unittest.main()
