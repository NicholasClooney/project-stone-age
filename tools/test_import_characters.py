import tempfile
import unittest
from pathlib import Path
from import_characters import equipment_rows


class CharacterSourceTests(unittest.TestCase):
    def test_equipment_table_controls_variant_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'include').mkdir(); (root/'char').mkdir()
            constants, rows = [], []
            for i in range(48):
                name = f'{i:03}'
                constants.extend([f'#define SPR_{name}em {100000+i*5}', f'#define SPR_{name}cl {200000+i}', f'#define SPR_{name}ax {300000+i}'])
                rows.append(f'{{ SPR_{name}em,SPR_{name}ax,SPR_{name}cl,SPR_{name}sp,SPR_{name}bw }},')
            (root/'include/anim_tbl.h').write_text('\n'.join(constants))
            (root/'char/char_data.c').write_text('int CHAR_eqimagetbl[][5]={\n'+'\n'.join(rows)+'\n};')
            mapping = equipment_rows(root)
            self.assertEqual(len(mapping),48)
            self.assertEqual(mapping['100000'],'200000')
            self.assertEqual(mapping['100235'],'200047')
            axes = equipment_rows(root, 'axe')
            self.assertEqual(axes['100000'], '300000')
            self.assertEqual(axes['100235'], '300047')
            # A numeric +2 shortcut would fail these intentionally nonadjacent constants.
            (root/'char/char_data.c').write_text('int CHAR_eqimagetbl[][5]={};')
            with self.assertRaisesRegex(ValueError,'Expected 48'):
                equipment_rows(root)


if __name__ == '__main__':
    unittest.main()
