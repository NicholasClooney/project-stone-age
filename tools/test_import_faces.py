import unittest
from import_faces import face_base


class FaceNumberTests(unittest.TestCase):
    def test_client_face_formula(self):
        # login.cpp:3401: 30000 + family * 100 + colour * 25 (+ eye * 5 + mouth).
        self.assertEqual(face_base(100000), 30000)
        self.assertEqual(face_base(100005), 30025)
        self.assertEqual(face_base(100020), 30100)
        self.assertEqual(face_base(100235), 31175)

    def test_rejects_non_appearances(self):
        for bad in (99995, 100001, 100240):
            with self.assertRaises(ValueError):
                face_base(bad)


if __name__ == '__main__':
    unittest.main()
