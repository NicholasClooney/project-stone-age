import unittest
import numpy as np
from draft_red_dragon_reference_regions import merge_references, row_runs, enclosed, respect_target_protection, draft_guard, matching_references
from recolor_red_dragon_samples import raster_runs


class ReferenceRegionTest(unittest.TestCase):
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
