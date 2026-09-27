"""World format, collision and portal contracts without proprietary assets."""
import json
from pathlib import Path
import struct
import tempfile
import unittest
from test_import_wilderness import FakeArchive
from import_world import read_map, read_portals, convert, safe_spawn, reachable_cells, select_connected_maps, excluded_reason, disable_conflicting_portals, ordinary_portals, DEV_TRAINING_MAPS, settlement_owner


class WorldImportTests(unittest.TestCase):
    def test_expansion_follows_only_reviewed_unconditional_connected_maps(self):
        paths={1300:Path('map/sainasu/hotoru/hotoru'),1301:Path('map/sainasu/hotoru/1301'),
               1400:Path('map/sainasu/katan/katan'),10001:Path('map/sainasu/dungeon/10001'),
               999:Path('map/family/hotoru/999')}
        portals=[dict(from_map=100,to_map=1300),dict(from_map=1300,to_map=1301),
                 dict(from_map=1300,to_map=10001),dict(from_map=1300,to_map=999)]
        selected=select_connected_maps(paths,portals)
        self.assertTrue({1300,1301}<=selected)
        self.assertFalse({1400,10001,999}&selected)
        self.assertIn('quest',excluded_reason(paths[10001]))
        self.assertIn('missing',excluded_reason(None))

    def test_dev_training_maps_do_not_expand_ordinary_portals(self):
        self.assertEqual(len(DEV_TRAINING_MAPS), 35)
        self.assertTrue({300,400,500,10001,10006,31706,32020} <= DEV_TRAINING_MAPS)
        self.assertNotIn(10007, DEV_TRAINING_MAPS)
        original=dict(from_map=100,to_map=1000)
        links=[original,dict(from_map=100,to_map=10001),dict(from_map=10001,to_map=100),dict(from_map=31701,to_map=31702)]
        self.assertEqual(ordinary_portals(links,{100,1000}),[original])

    def test_giru_settlements_exclude_quest_rooms_and_self_gate_warp(self):
        paths={5000:Path('map/giiru/south/furuudo'),5001:Path('map/giiru/south/5001'),
               5100:Path('map/giiru/north/dana'),5106:Path('map/giiru/north/5106'),
               5107:Path('map/giiru/north/5107'),9355:Path('map/giiru/north/snake_9355')}
        links=[dict(from_map=a,to_map=b) for a,b in
               [(300,5000),(5000,300),(5000,5001),(300,5100),(5100,5106),
                (5106,5107),(5100,9355),(300,300),(300,31701)]]
        selected=select_connected_maps(paths,links)
        self.assertTrue({300,5000,5001,5100,5106} <= selected)
        self.assertFalse({5107,9355,31701} & selected)
        self.assertEqual(ordinary_portals(links,selected),links[:5])
        self.assertEqual(settlement_owner(5001,paths),5000)
        self.assertEqual(settlement_owner(5106,paths),5100)

    def test_conflicting_warps_are_disabled_without_changing_coordinates(self):
        portals=[dict(from_map=200,cell=[229,988],to_map=3413,target=[10,15]),
                 dict(from_map=200,cell=[229,988],to_map=3413,target=[10,16]),
                 dict(from_map=200,cell=[230,988],to_map=3413,target=[10,16])]
        disable_conflicting_portals(portals)
        self.assertTrue(all(p['disabled'] for p in portals[:2]))
        self.assertNotIn('disabled',portals[2])
        self.assertEqual(portals[0]['target'],[10,15])

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
