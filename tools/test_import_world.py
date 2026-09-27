"""World format, collision and portal contracts without proprietary assets."""
import json
from pathlib import Path
import struct
import tempfile
import unittest
from test_import_wilderness import FakeArchive
from import_world import read_map, read_portals, convert, safe_spawn, reachable_cells


class WorldImportTests(unittest.TestCase):
    def test_original_header_and_dimensions(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'map'
            raw=bytearray(44+3*2*4);raw[:6]=b'LS2MAP'
            struct.pack_into('>H',raw,6,200);struct.pack_into('>HH',raw,40,3,2)
            raw[8:12]='村庄'.encode('gbk');struct.pack_into('>6H',raw,44,*range(100,106))
            path.write_bytes(raw);data=read_map(path)
            self.assertEqual(data[:4],(200,'村庄',3,2));self.assertEqual(data[4],tuple(range(100,106)))
            for broken in (raw[:-1],raw+b'X',b'INVALID'+raw[7:]):
                path.write_bytes(broken)
                with self.assertRaises(ValueError):read_map(path)

    def test_missing_art_stays_blocked_under_walkable_prop(self):
        data,used,missing=convert(FakeArchive(None),(1,'map',3,2,[100,999,100,100,100,100],[0,102,0,0,0,0],b''))
        self.assertEqual(missing,[[1,0,999]]);self.assertEqual(data['blocked'][1],1)
        self.assertEqual(data['origin'],[0,0]);self.assertEqual(used,{10,12})

    def test_object_footprint_and_music_markers(self):
        data,_,_=convert(FakeArchive(None),(1,'map',3,3,[100]*9,[45,0,0,0,101,0,0,0,0],b''))
        for i in (1,2,4,5):self.assertEqual(data['blocked'][i],1)
        self.assertEqual(data['music_markers'],[dict(cell=[0,0],tone=45,music='world/audio/sabgm_f0.wav')])

    def test_safe_spawn_excludes_warps_and_clamps(self):
        data=dict(map_id=1,width=3,height=2,blocked=[1,0,0,1,1,1])
        self.assertEqual(safe_spawn(data,[-20,0],[[1,0]]),[2,0])
        data['blocked']=[1]*6
        with self.assertRaises(ValueError):safe_spawn(data,[1,0])

    def test_spawn_fallback_stays_in_arrival_component_and_avoids_npc(self):
        data=dict(map_id=1,width=3,height=3,blocked=[0,1,0,0,1,0,0,1,0])
        region=reachable_cells(data,[0,0])
        self.assertEqual(safe_spawn(data,[2,0],[[0,0]],region),[0,1])

    def test_portal_rectangles_and_exact_destinations(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory,'warp.create').write_text('NPCCREATE\n{\nfloorid=100\nborncorner=2,3,3,4\nenemy=npcgen_warp|1000|50|118\n}\n')
            portals=read_portals(directory)
            self.assertEqual([p['cell'] for p in portals],[[2,3],[3,3],[2,4],[3,4]])
            self.assertTrue(all(p['target']==[50,118] and p['from_map']==100 and p['to_map']==1000 for p in portals))

    def test_reachability_rejects_disconnected_walkable_pocket(self):
        data=dict(width=3,height=3,blocked=[0,1,0,0,1,0,0,1,0])
        seen=reachable_cells(data,[0,0])
        self.assertEqual(list(seen),[1,0,0,1,0,0,1,0,0])

    def test_duplicate_identical_portals_deduplicated(self):
        with tempfile.TemporaryDirectory() as directory:
            entry='{\nfloorid=100\nborncorner=2,3,2,3\nenemy=npcgen_warp|1000|50|118\n}'
            Path(directory,'a.create').write_text(entry);Path(directory,'b.create').write_text(entry)
            self.assertEqual(len(read_portals(directory)),1)


if __name__=='__main__':unittest.main()
