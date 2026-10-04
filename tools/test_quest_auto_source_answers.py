"""Source and reproducibility checks, independent of services or imported assets."""
import hashlib
import json
import re
import shutil
import tempfile
import unittest
from collections import Counter
from pathlib import Path
import build_quest_auto_source_answers as builder


class SourceAnswersTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reference = builder.ROOT / 'references/chenmingbiao-stone-age'
        cls.data = builder.build(cls.reference)

    def test_committed_table_and_runtime_digest(self):
        raw = builder.serialize(self.data)
        self.assertEqual(builder.OUTPUT.read_text(), raw)
        code = (builder.ROOT / 'client/server/quest_auto_source_answers.gd').read_text()
        pin = re.search(r'const DATA_SHA256="([a-f0-9]+)"', code)[1]
        self.assertEqual(hashlib.sha256(raw.encode()).hexdigest(), pin)
        self.assertEqual(len(self.data['sources']), 28)

    def test_original_forms_and_skipped_eighth_line(self):
        questions = self.data['questions']
        self.assertEqual(len(questions), 149)
        self.assertEqual(Counter(q['answer_type'] for q in questions), {1: 22, 2: 84, 4: 43})
        self.assertNotIn(8, [q['id'] for q in questions])
        source = (self.reference / builder.QUESTION_SOURCE).read_bytes().decode('gb18030').splitlines()
        self.assertEqual(len(source[7].split(',')), 8)
        for q in questions:
            fields = source[q['source_line'] - 1].split(',')
            self.assertEqual(q['text'], fields[5])
            self.assertEqual(q['options'], fields[6:9])
            self.assertEqual(q['answer'], int(fields[4]) - 1)

    def test_exact_scope_and_mask_eligibility(self):
        services = self.data['services']
        self.assertEqual(len(services), 21)
        for base in (800, 820, 840):
            for offset, count, pool in zip((0, 1, 3, 5, 6, 8, 9), (1, 2, 3, 5, 5, 7, 10), (23, 67, 55, 59, 84, 82, 59)):
                key = f'genout/quz_{base+offset}_{29 if offset%2==0 else 18}_19'
                self.assertEqual(services[key]['count'], count)
                self.assertEqual(len(services[key]['question_ids']), pool)
        self.assertEqual(set(self.data['keywords']), set(builder.KEYWORDS))
        self.assertFalse(any('812' in key for key in services))
        self.assertEqual([v['answer'] for v in self.data['keywords'].values()],
                         ['在卡坦有梦德', '红色月亮的光芒', '蓝色山脉即力量', '白色之风即速度'])

    def test_exact_text_and_consistent_duplicates(self):
        by_id = {q['id']: q for q in self.data['questions']}
        self.assertEqual(by_id[1]['options'][2], '眯斯 ')
        self.assertEqual(by_id[36]['options'], ['地１０', '地９\u3000风１', '地８\u3000风２ '])
        for a, b in ((1, 22), (10, 47)):
            for field in ('text', 'options', 'answer', 'answer_type'):
                self.assertEqual(by_id[a][field], by_id[b][field])

    def test_source_hash_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in builder.SOURCES:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(self.reference / name, target)
            target = root / builder.QUESTION_SOURCE
            target.write_bytes(target.read_bytes() + b'\n')
            with self.assertRaisesRegex(ValueError, 'Unreviewed answer source'):
                builder.build(root)

    def test_parser_does_not_repair_or_trim(self):
        text = '8,1,1,1,1,prompt,a,b\n9,1,1,4,1,prompt, raw answer ,,\n'
        parsed = builder.parse_questions(text)
        self.assertEqual([q['id'] for q in parsed], [9])
        self.assertEqual(parsed[0]['options'][0], ' raw answer ')
        for row in ('1,1,1,1,3,p,a,b,c', '1,1,1,4,2,p,a,b,c', '1,1,1,8,1,p,a,b,c'):
            with self.assertRaises(ValueError):
                builder.parse_questions(row)


if __name__ == '__main__':
    unittest.main()
