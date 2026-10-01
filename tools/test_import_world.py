"""World format, collision and portal contracts without proprietary assets."""
import json
from pathlib import Path
import struct
import tempfile
import unittest
from test_import_wilderness import FakeArchive
from world_review import read_reviewed_portals, merge_portals
from world_fallback import FallbackArchive, FALLBACK_BITMAP_BASE
from import_world import read_map, read_portals, convert, safe_spawn, reachable_cells, select_connected_maps, excluded_reason, disable_conflicting_portals, ordinary_portals, DEV_TRAINING_MAPS, settlement_owner, JYARUGA_SCENIC_MAPS, read_scenic_gates, review_scenic_doors


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

    def test_scenic_selection_keeps_service_rooms_excluded(self):
        self.assertTrue({20001,20013,20105,20309,20807,21016,21315} <= JYARUGA_SCENIC_MAPS)
        self.assertFalse({20508,20608,20711,20712,117} & JYARUGA_SCENIC_MAPS)
        paths={20801:Path('map/jyaruga/dungeon/20801'),20711:Path('map/jyaruga/dungeon/20711')}
        selected=select_connected_maps(paths,[dict(from_map=200,to_map=20801),dict(from_map=20801,to_map=20711)])
        self.assertIn(20801,selected)
        self.assertNotIn(20711,selected)

    def test_reviewed_npc_gate_preserves_original_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'gate.create').write_text('{\nfloorid=200\nborncorner=73,696,73,696\nenemy=npcgen_warpman|file:genout/wpm_200_73_696\n}\n{\nfloorid=200\nborncorner=1,2,1,2\nenemy=npcgen_warpman|file:genout/unreviewed\n}')
            (root/'wpm_200_73_696').write_text('WARP:21201,61,46\nFREE:LV>64&ENDEV=4\n')
            gates=read_scenic_gates(root)
            self.assertEqual(len(gates),1)
            self.assertEqual(gates[0]['cell'],[73,696])
            self.assertEqual(gates[0]['target'],[61,46])
            self.assertEqual(gates[0]['to_map'],21201)
            self.assertIn('直接开放',gates[0]['convenience'])

    def test_recursive_reviewed_gate_and_mapwarp_keep_original_direction(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            npc=root/'gmsv/data/npc'
            (npc/'100').mkdir(parents=True)
            maps=root/'gmsv/data/map';maps.mkdir()
            (npc/'100/gate.create').write_text('{\nfloorid=11214\nborncenter=41,36,1,1\nenemy=sb_gate|file:100/gate.arg\n}')
            (npc/'100/gate.arg').write_text('warpfl:11215\nwarpx:9\nwarpy:16\n')
            (maps/'mapwarp.txt').write_text('NONE:NULL:11215,9,17:11214,41,37:NULL\nA:NULL:11215,1,1:999,2,2:NULL\n')
            review={'sainasu':{'maps':[11214,11215],'gate_scripts':['100/gate.arg']}}
            links=read_reviewed_portals(root,review)
            self.assertEqual(len(links),2)
            gate=next(p for p in links if 'gate_source' in p)
            self.assertEqual((gate['cell'],gate['to_map'],gate['target']),([41,36],11215,[9,16]))
            self.assertTrue(any(p['to_map']==11214 for p in links))
            self.assertEqual(len(read_reviewed_portals(root,{'x':{'maps':[11214],'gate_scripts':[]}})),1)
            duplicate=dict(gate);duplicate.pop('gate_source');duplicate.pop('convenience')
            merged=merge_portals([duplicate,gate])
            self.assertEqual(len(merged),1)
            self.assertIn('gate_source',merged[0])

    def test_reviewed_direct_borncenter_door_keeps_original_cell(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            npc=root/'gmsv/data/npc/doujyou';npc.mkdir(parents=True)
            maps=root/'gmsv/data/map';maps.mkdir()
            (maps/'mapwarp.txt').write_text('')
            (npc/'door.create').write_text('{\nfloorid=3021\nborncenter=406,126,1,1\nenemy=npcgen_warp|3022|1|7\n}')
            links=read_reviewed_portals(root,{'jyaruga':{'maps':[3021,3022]}})
            self.assertEqual(len(links),1)
            self.assertEqual((links[0]['cell'],links[0]['to_map'],links[0]['target']),([406,126],3022,[1,7]))
            self.assertNotIn('gate_source',links[0])

    def test_dev_training_maps_do_not_expand_ordinary_portals(self):
        self.assertEqual(len(DEV_TRAINING_MAPS), 35)
        self.assertTrue({300,400,500,10001,10006,31706,32020} <= DEV_TRAINING_MAPS)
        self.assertNotIn(10007, DEV_TRAINING_MAPS)
        original=dict(from_map=100,to_map=1000)
        links=[original,dict(from_map=100,to_map=10001),dict(from_map=10001,to_map=100),dict(from_map=31701,to_map=31702)]
        self.assertEqual(ordinary_portals(links,{100,1000}),[original])

    def test_giru_reviewed_scenery_keeps_training_routes_and_self_gate_closed(self):
        paths={5000:Path('map/giiru/south/furuudo'),5001:Path('map/giiru/south/5001'),
               5100:Path('map/giiru/north/dana'),5106:Path('map/giiru/north/5106'),
               5107:Path('map/giiru/north/5107'),9355:Path('map/giiru/north/snake_9355')}
        links=[dict(from_map=a,to_map=b) for a,b in
               [(300,5000),(5000,300),(5000,5001),(300,5100),(5100,5106),
                (5106,5107),(5100,9355),(300,300),(300,31701)]]
        selected=select_connected_maps(paths,links)
        self.assertTrue({300,5000,5001,5100,5106} <= selected)
        self.assertTrue({5107,9355} <= selected)  # Now reviewed scenery, still requires an original link.
        self.assertNotIn(31701,selected)
        self.assertEqual(ordinary_portals(links,selected),links[:7])
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

    def test_reviewed_scenic_conflict_uses_original_choice_only(self):
        links=[dict(from_map=200,cell=[285,926],to_map=20601,target=[9,59]),
               dict(from_map=200,cell=[285,926],to_map=20601,target=[10,59]),
               dict(from_map=200,cell=[229,988],to_map=3413,target=[10,15]),
               dict(from_map=200,cell=[229,988],to_map=3413,target=[10,16])]
        disable_conflicting_portals(links)
        review_scenic_doors(links)
        self.assertNotIn('disabled',links[0])
        self.assertTrue(all(p['disabled'] for p in links[1:]))
        self.assertEqual(links[0]['target'],[9,59])

    def test_fallback_only_fills_missing_logical_ids_in_separate_namespace(self):
        class Art:
            def __init__(self, name, logical):
                self.name=name;self.map_ids=logical;self.entries={10:dict(id=10,hit=2)}
            def image(self, bitmap):return self.name,bitmap
        primary=Art('classic',{100:10})
        later=Art('later',{100:10,999:10})
        art=FallbackArchive(primary,later,[100,999])
        self.assertEqual(art.map_ids[100],10)
        self.assertEqual(art.map_ids[999],FALLBACK_BITMAP_BASE+10)
        self.assertEqual(art.image(10),('classic',10))
        self.assertEqual(art.image(art.map_ids[999]),('later',10))
        self.assertEqual(primary.map_ids,{100:10})
        self.assertEqual(art.logical_ids,[999])

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

    def test_seimu_padding_rejects_unknown_bytes_even_with_matching_header(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'map'
            raw = bytearray(1644)
            raw[:6] = b'LS2MAP'
            struct.pack_into('>H', raw, 6, 40)
            struct.pack_into('>HH', raw, 40, 20, 20)
            path.write_bytes(raw)
            self.assertEqual(read_map(path)[:4], (40, '', 20, 20))
            # Even the correct ID, dimensions and zero padding need the exact hash.
            for broken in (raw+b'\0', raw+b'X', raw+b'\0\0', raw[:-1]):
                path.write_bytes(broken)
                with self.assertRaises(ValueError):
                    read_map(path)

    def test_seimu_permits_protect_all_sea_directions_without_moving_doors(self):
        from import_world import require_seimu_permits
        pairs = [(40,31401,[1,8],[92,27]), (40,31301,[13,1],[10,104]),
                 (40,31501,[12,18],[32,2]), (31401,40,[94,27],[1,9]),
                 (31301,40,[10,103],[12,1]), (31501,40,[34,2],[11,18])]
        portals = [dict(from_map=a,to_map=b,cell=x,target=y,convenience='open')
                   for a,b,x,y in pairs]
        ordinary = dict(from_map=40,to_map=6000,cell=[6,3],target=[32,68])
        portals.append(ordinary)
        require_seimu_permits(portals)
        self.assertTrue(all(p['requires_travel_pass'] and 'convenience' not in p
                            for p in portals[:-1]))
        self.assertEqual([(p['from_map'],p['to_map'],p['cell'],p['target'])
                          for p in portals[:-1]], pairs)
        self.assertNotIn('requires_travel_pass', ordinary)

    def test_seimu_island_expansion_keeps_unreviewed_destinations_out(self):
        paths = {6000:Path('map/seimu/village/6000'),
                 6005:Path('map/seimu/village/6005'),
                 6012:Path('map/seimu/village/6012')}
        selected = select_connected_maps(paths, [dict(from_map=400,to_map=6000),
            dict(from_map=6000,to_map=6005),dict(from_map=6000,to_map=6012)])
        self.assertTrue({400,6000,6005} <= selected)
        self.assertNotIn(6012, selected)
        self.assertIn(400, DEV_TRAINING_MAPS)

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




class InvisibleWallTest(unittest.TestCase):
    def test_ground_60_to_79_blocks_by_its_hit_flag_without_drawing(self):
        import import_world

        class Archive:
            map_ids = {60: 2, 61: 3, 150: 9}
            entries = {2: dict(hit=0, ex=1, ey=1), 3: dict(hit=2, ex=1, ey=1), 9: dict(hit=1, ex=1, ey=1)}

        tiles = (60, 61, 150, 64)
        data, used, missing = import_world.convert(Archive(), (5, 'w', 4, 1, tiles, (0, 0, 0, 0), b''))
        self.assertEqual(data['blocked'], [1, 0, 0, 0])
        self.assertEqual([g[2] for g in data['ground']], [9])
        self.assertEqual(missing, [])


if __name__=='__main__':unittest.main()
