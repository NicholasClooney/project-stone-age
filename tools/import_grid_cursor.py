"""Import CG_GRID_CURSOR (25001), the native map-hover selection marker."""
import argparse
import json
from pathlib import Path
from import_legacy import Archive


def run(source, output):
    archive = Archive(source)
    bitmap = next(e for e in archive.entries.values() if e['map_id'] == 25001)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    archive.image(bitmap['id']).save(output / '25001.png')
    metadata = {key: bitmap[key] for key in ('id', 'x', 'y', 'w', 'h')}
    metadata['logical_id'] = 25001
    metadata['source'] = 'map.cpp:2009-2026 drawGrid; anim_tbl.h:1499 CG_GRID_CURSOR'
    (output / 'manifest.json').write_text(json.dumps(metadata, indent=2)+'\n')
    print(metadata)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source')
    p.add_argument('--output', default='client/assets/legacy/grid-cursor')
    a = p.parse_args()
    run(a.source, a.output)
