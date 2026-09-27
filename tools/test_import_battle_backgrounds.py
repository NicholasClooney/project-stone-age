import tempfile
import unittest
from pathlib import Path
from import_battle_backgrounds import read_mapping

class BattlefieldMappingTests(unittest.TestCase):
    def test_source_three_slot_semantics_and_ranges(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'mapping.txt'
            path.write_text('# ignored\n$ 6 7\n100 to 102\n$ 9\n103\n$ 12 13 14\n104\n')
            result = read_mapping(path)
        self.assertEqual(result['100'], [6,7,6])
        self.assertEqual(result['102'], [6,7,6])
        self.assertEqual(result['103'], [9,9,9])
        self.assertEqual(result['104'], [12,13,14])
        self.assertNotIn('105', result)

if __name__ == '__main__': unittest.main()
