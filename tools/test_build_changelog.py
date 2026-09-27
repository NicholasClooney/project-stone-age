import unittest
from build_changelog import build

class ChangelogTest(unittest.TestCase):
    def test_only_feature_and_fix_commits_advance_version(self):
        result=build([('docs: design','2026-01-01'),('feat(client): Village','2026-01-02'),('fix: Sound','2026-01-03'),('chore: refresh log','2026-01-04'),('feat!: Pets','2026-01-05')],{})
        self.assertEqual(result['version'],'v0.3.0')
        self.assertEqual([e['version'] for e in result['entries']],['v0.3.0','v0.2.0','v0.1.0'])
        self.assertEqual((result['feature_count'],result['fix_count']),(2,1))
    def test_curated_player_notes_and_readable_fallback(self):
        result=build([('feat: Pets','today'),('fix(ui): Close button','today')],{'feat: Pets':{'title':'宠物加入','details':['可以骑金虎。']}})
        self.assertEqual(result['entries'][0]['title'],'Close button')
        self.assertEqual(result['entries'][1]['title'],'宠物加入')
        self.assertNotIn('hash',result['entries'][1])
    def test_empty_history(self):
        self.assertEqual(build([],{})['version'],'v0.0.0')


class RefreshWorkflowTest(unittest.TestCase):
    def test_refresh_amend_stable_and_preserves_unrelated_index(self):
        import json, shutil, subprocess, tempfile
        from pathlib import Path
        source=Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True,stderr=subprocess.STDOUT).strip()
            git('init','-q');git('config','user.name','Test');git('config','user.email','test@example.invalid')
            for folder in ['client/data','tools','scripts','docs/development']:(root/folder).mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source/'tools/build_changelog.py',root/'tools/build_changelog.py')
            shutil.copyfile(source/'scripts/refresh-changelog.sh',root/'scripts/refresh-changelog.sh')
            (root/'client/project.godot').write_text('[application]\nconfig/name="Fixture"\n')
            (root/'client/data/changelog.json').write_text('{}\n')
            git('add','.');git('commit','-qm','feat: First playable slice')
            (root/'unrelated.txt').write_text('keep staged\n');git('add','unrelated.txt')
            subprocess.run(['sh','scripts/refresh-changelog.sh'],cwd=root,check=True,stdout=subprocess.DEVNULL)
            self.assertEqual(git('diff','--cached','--name-only'),'unrelated.txt')
            data=json.loads((root/'client/data/changelog.json').read_text())
            self.assertEqual(data['version'],'v0.1.0')
            before=git('rev-parse','HEAD')
            subprocess.run(['sh','scripts/refresh-changelog.sh'],cwd=root,check=True,stdout=subprocess.DEVNULL)
            self.assertEqual(git('rev-parse','HEAD'),before)
            (root/'client/project.godot').write_text('[application]\nconfig/name="Unsaved user edit"\n')
            blocked=subprocess.run(['sh','scripts/refresh-changelog.sh'],cwd=root,capture_output=True)
            self.assertNotEqual(blocked.returncode,0)
            self.assertIn('Unsaved user edit',(root/'client/project.godot').read_text())

if __name__=='__main__':unittest.main()
