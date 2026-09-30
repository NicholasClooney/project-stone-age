"""Name the not-yet-imported maps that imported maps have original exits to.

The world manifest lists those exits (caves, mountain passes, 庄园 and other
deferred areas) under provenance.unsupported_portals without a name, because
their maps are not imported. 地图导航 labels them with the floor name from
each original LS2MAP header (bytes 8-40, GBK, "name|flag").
"""
import argparse
import json
from pathlib import Path
import struct


def map_names(map_root, wanted):
    names = {}
    for path in sorted(Path(map_root).rglob('*')):
        if not path.is_file():
            continue
        raw = path.read_bytes()
        if raw[:6] != b'LS2MAP' or len(raw) < 44:
            continue
        ident = struct.unpack_from('>H', raw, 6)[0]
        if ident in wanted and ident not in names:
            names[ident] = raw[8:40].split(b'\0')[0].decode('gbk', errors='replace').split('|')[0]
    return names


def build(manifest, map_root):
    wanted = {int(p['to_map']) for p in manifest.get('provenance', {}).get('unsupported_portals', [])}
    names = map_names(map_root, wanted)
    return dict(schema=1, source='gmsv/data/map LS2MAP floor names of unsupported_portals destinations',
                maps={str(i): names[i] for i in sorted(names)})


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest', default='client/assets/legacy/world/manifest.json')
    p.add_argument('--maps', default='references/chenmingbiao-stone-age/gmsv/data/map')
    p.add_argument('--output', default='client/data/exit-names.json')
    a = p.parse_args()
    result = build(json.loads(Path(a.manifest).read_text()), a.maps)
    Path(a.output).write_text(json.dumps(result, ensure_ascii=False, indent=1)+'\n')
    print(f"{len(result['maps'])} exit destination names")
