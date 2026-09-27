import tempfile
import unittest
from pathlib import Path
from import_riding import mappings

class RidingImportTest(unittest.TestCase):
    def test_exact_pair_selection(self):
        source='''
{101006,100010,100330,310},
{101004,100000,100329,309},
// {199999,100010,100330,310},
{101000,100700,100352,331},
{101000,100000,100352,331},
'''
        with tempfile.TemporaryDirectory() as folder:
            file=Path(folder)/'table.c';file.write_text(source)
            result=mappings(file)
        self.assertEqual(set(result),{'100010:100330','100000:100352'})
        self.assertEqual(result['100010:100330']['sprite'],101006)
        self.assertNotIn('100000:100330',result)

if __name__=='__main__': unittest.main()
