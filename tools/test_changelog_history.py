"""StoneAge-only changelog checks; the generic builder tests live in test_build_changelog.py."""
import json
import subprocess
import unittest
from pathlib import Path
from build_changelog import read_notes


class MigratedNotesTest(unittest.TestCase):
    def test_migrated_legacy_notes_are_lossless(self):
        root=Path(__file__).resolve().parents[1]
        revision=subprocess.check_output(['git','log','-1','--diff-filter=AM','--format=%H','--','docs/development/changelog-notes.json'],cwd=root,text=True).strip()
        old=json.loads(subprocess.check_output(['git','show',revision+':docs/development/changelog-notes.json'],cwd=root,text=True))
        migrated=read_notes(root/'docs/development/changelog-notes')
        for subject,note in old.items():
            self.assertEqual(migrated[subject],dict(title=note['title'],details=note.get('details',[])))

if __name__=='__main__':unittest.main()
