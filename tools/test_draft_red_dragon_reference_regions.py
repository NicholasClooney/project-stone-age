import unittest
import json
import tempfile
from pathlib import Path
from unittest.mock import patch
import numpy as np
import draft_red_dragon_reference_regions as regions
from draft_red_dragon_reference_regions import merge_references, row_runs, enclosed, respect_target_protection, draft_guard, matching_references
from recolor_red_dragon_samples import raster_runs


class ReferenceRegionTest(unittest.TestCase):
    def test_target_only_book_preserves_guard_without_becoming_reference(self):
        pixels=np.full((8,8),213,np.uint8)
        record={'source_rd_sha256':'rd','source_indices_sha256':regions.digest(pixels.tobytes()),
                'geometry':{'x':0,'y':0,'w':8,'h':8},
                'slots':[{'clip':'3_4','frame':0,'sprite_frame':{}}]}
        reference=dict(record,dragon_envelopes=[[[0,0],[7,0],[7,7],[0,7]]])
        target=dict(reference,rider_runs=[[2,2,2]],uncertain_runs=[[3,3,3]])
        ledger={'source_palette_sha256':'palette','records':{str(k):record for k in (1,2,3)},
                'pages':[{'bitmaps':[1,2,3],'slots':[{'clip':'3_4','frame':0}]}]}
        def aligned(_archive,_bitmap,array,_frame):
            canvas=np.zeros((384,384),array.dtype);canvas[:8,:8]=array
            return canvas,(0,0)
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            def write(name,value):
                path=root/name;path.write_text(json.dumps(value));return path
            lp=write('ledger.json',ledger)
            rp=write('refs.json',{'source_palette_sha256':'palette','rider_boundary_dilation':0,
                                  'records':{'1':reference,'2':reference}})
            tp=write('targets.json',{'source_palette_sha256':'palette','rider_boundary_dilation':0,
                                    'records':{'3':target}})
            with patch.object(regions,'Archive'), patch.object(regions,'validate_source',return_value=pixels), \
                 patch.object(regions,'indices',return_value=(pixels,'rd')), patch.object(regions,'align',side_effect=aligned):
                regions.run(root,lp,[rp],[0],root/'out.json',False,True,[tp])
            output=json.loads((root/'out.json').read_text())['records']['3']
            provenance=output['reference_regions']
            self.assertEqual(provenance['bitmaps'],[1,2])
            self.assertTrue(provenance['existing_target_protection_applied'])
            self.assertEqual(provenance['target_protection_rule_sha256'],
                             regions.digest(json.dumps(target,sort_keys=True).encode()))
            dragon=raster_runs((8,8),output['dragon_runs'])
            self.assertFalse(dragon[2,2]);self.assertFalse(dragon[3,3])
            self.assertTrue(dragon[4,4])

    def test_conflict_is_rejected_even_against_repeated_matching_references(self):
        original=np.zeros((384,384),np.uint8);original[5,5]=213
        red=original.copy();red[5,5]=225
        known=np.zeros_like(original,dtype=bool);known[5,5]=True
        conflicting=red.copy();conflicting[5,5]=226
        _,_,result,conflict=merge_references([(original,red,known),(original,red,known),
                                             (original,conflicting,known),(original,red,known)])
        self.assertTrue(conflict[5,5]);self.assertFalse(result[5,5])

    def test_source_variants_require_exact_target_colour_and_unambiguous_output(self):
        label=np.ones((2,2),bool)
        first=np.full((2,2),213,np.uint8);second=np.full((2,2),214,np.uint8)
        r1=np.full((2,2),225,np.uint8);r2=np.full((2,2),226,np.uint8)
        _,red,known,conflict=matching_references(second,[(first,r1,label),(second,r2,label)])
        self.assertTrue(known.all());self.assertTrue((red==226).all());self.assertFalse(conflict.any())
        _,_,known,conflict=matching_references(second,[(second,r2,label),(second,r1,label),(second,r2,label)])
        self.assertFalse(known.any());self.assertTrue(conflict.all())
        unknown=np.full((2,2),80,np.uint8)
        self.assertFalse(matching_references(unknown,[(first,r1,label),(second,r2,label)])[2].any())

    def test_inclusive_runs_preserve_disconnected_single_pixels(self):
        mask=np.zeros((5,8),bool);mask[1,0]=True;mask[1,3:6]=True;mask[3,7]=True
        runs=row_runs(mask)
        self.assertEqual(runs,[[1,0,0],[1,3,5],[3,7,7]])
        self.assertTrue(np.array_equal(mask,raster_runs((8,5),runs)))
        with self.assertRaises(ValueError):raster_runs((8,5),[[1,3,8]])

    def test_existing_protection_wins_over_matching_reference(self):
        candidate=np.ones((3,4),bool)
        rider=np.zeros_like(candidate);rider[1,1]=True
        unknown=np.zeros_like(candidate);unknown[1,2]=True
        result,collisions=respect_target_protection(candidate,rider,unknown)
        self.assertEqual(int(collisions.sum()),2)
        self.assertFalse(result[1,1]);self.assertFalse(result[1,2])
        self.assertTrue(result[0,0])
        self.assertTrue(candidate.all())

    def test_local_draft_does_not_infer_rider_inside_arm_ring(self):
        original=np.full((15,15),213,np.uint8)
        pixels=original.copy();pixels[3:12,3:12]=80;pixels[5:10,5:10]=213
        known=np.ones_like(pixels,bool)
        filled=draft_guard(pixels,original,known,True)[0]
        local=draft_guard(pixels,original,known,False)[0]
        self.assertTrue(filled[7,7]);self.assertFalse(local[7,7])
        self.assertTrue(local[3,3])

    def test_enclosure_is_only_a_geometric_guard(self):
        ring=np.zeros((9,9),bool);ring[2:7,2:7]=True;ring[3:6,3:6]=False
        filled=enclosed(ring)
        self.assertTrue(filled[4,4]);self.assertFalse(filled[0,0])
        ring[2,4]=False
        self.assertFalse(enclosed(ring)[4,4])


if __name__=='__main__':unittest.main()
