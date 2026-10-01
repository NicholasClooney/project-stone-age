import tempfile
import unittest
from pathlib import Path
from import_original_charm import catalog
REFERENCE=Path(__file__).resolve().parents[1]/'references/chenmingbiao-stone-age'
class CharmImportTests(unittest.TestCase):
    def test_original_packet(self):
        npcs,sources=catalog(REFERENCE)
        self.assertEqual([(n['map_id'],n['cell'],n['graphic']) for n in npcs],[(1005,[25,15],16065),(2005,[19,15],16065)])
        self.assertEqual(npcs[0]['handler'],'Charm')
        self.assertEqual(npcs[0]['image_types']['100000'],'CHILDBOY')
        self.assertIn('需要%6d的stone',npcs[0]['dialogue']['confirm'])
        self.assertIn('帅多了',npcs[0]['dialogue']['success']['BOY'])
        self.assertEqual(len(sources),4)
    def test_unreviewed_source_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            for path in catalog(REFERENCE)[1]:
                target=Path(directory)/path
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes((REFERENCE/path).read_bytes()+b'\n')
            with self.assertRaisesRegex(ValueError,'Unreviewed Charm source'):
                catalog(directory)
if __name__=='__main__':unittest.main()
