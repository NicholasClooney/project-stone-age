"""Verify the narrow 100612 import against local original art, in temporary output.

Run with the asset venv: python tools/test_revival_effect_import.py CLIENT25.
Never writes the shared legacy folder.
"""
import argparse
import json
import tempfile
from pathlib import Path
from PIL import Image
import import_mirror
import plan_web_packs


def verify(source, baseline):
    old = json.loads((baseline / 'mvp/mirror-effects.json').read_text())
    with tempfile.TemporaryDirectory(prefix='revival-effect-') as directory:
        output = Path(directory)
        import_mirror.run(source, output)
        root = output / 'mvp'
        new = json.loads((root / 'mirror-effects.json').read_text())
        assert set(new['characters']) == {str(i) for i in import_mirror.EFFECTS}
        clip = new['characters']['100612']['0_0']
        assert clip['duration_ms'] == 1500
        assert [f['image'] for f in clip['frames']] == list(range(7232, 7246))
        assert all(f['x'] == f['y'] == f['sound'] == 0 for f in clip['frames'])
        for ident, actions in old['characters'].items():
            assert new['characters'][ident] == actions, ident
        for bitmap, metadata in old['images'].items():
            assert new['images'][bitmap] == metadata, bitmap
            with Image.open(baseline / 'mvp/mirror-effects' / f'{bitmap}.png') as before:
                with Image.open(root / 'mirror-effects' / f'{bitmap}.png') as after:
                    assert before.convert('RGBA').tobytes() == after.convert('RGBA').tobytes(), bitmap
        for bitmap, metadata in new['images'].items():
            with Image.open(root / 'mirror-effects' / f'{bitmap}.png') as frame:
                assert frame.size == (metadata['w'], metadata['h'])
        # Minimal unrelated catalogs exercise the production pack planner's
        # ownership rules without copying or changing the shared asset tree.
        for name, data in [('world/manifest.json', {'maps': {}}),
                           ('characters/catalog.json', {}), ('battle/manifest.json', {})]:
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data))
        original = plan_web_packs.LEGACY
        try:
            plan_web_packs.LEGACY = output
            plan = plan_web_packs.plan()
        finally:
            plan_web_packs.LEGACY = original
        expected = {'res://assets/legacy/mvp/mirror-effects.json'} | {
            f'res://assets/legacy/mvp/mirror-effects/{i}.png' for i in range(7232, 7246)}
        assert expected <= set(plan['packs']['core'])
        assert all(not expected.intersection(files) for pack, files in plan['packs'].items() if pack != 'core')
        print('PASS: 100612 14 frames / 1500ms / index and dimensions; '
              f'{len(old["characters"])} existing effects and {len(old["images"])} images preserved; new art belongs to core')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--baseline', type=Path, default=Path('client/assets/legacy'))
    args = parser.parse_args()
    verify(args.source, args.baseline)
