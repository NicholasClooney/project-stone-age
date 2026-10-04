"""Translation evidence never becomes semantic approval."""
import unittest
import numpy as np
from draft_red_dragon_pose_rules import translate_part


class TranslationDraftTest(unittest.TestCase):
    def test_exact_part_match_still_requires_occlusion_review(self):
        source=np.zeros((12,12),np.uint8)
        source[2:5,2:5]=np.arange(9,dtype=np.uint8).reshape(3,3)+73
        target=np.zeros_like(source);target[4:7,3:6]=source[2:5,2:5]
        proposal,score=translate_part(source,target,[[2,2],[4,2],[4,4],[2,4]],(1,2),0)
        self.assertEqual(proposal,[[3,4],[5,4],[5,6],[3,6]])
        self.assertEqual(score['matched_pixels'],9)
        self.assertEqual(score['status'],'DRAFT_REQUIRES_OCCLUSION_REVIEW')

    def test_unrelated_texture_is_not_a_usable_template(self):
        source=np.full((12,12),213,np.uint8);target=np.full((12,12),73,np.uint8)
        _,score=translate_part(source,target,[[2,2],[4,2],[4,4],[2,4]],(0,0),0)
        self.assertEqual(score['status'],'TEMPLATE_NOT_COMPARABLE')
        self.assertEqual(score['matched_pixels'],0)


if __name__=='__main__':unittest.main()
