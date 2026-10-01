import unittest
from build_changelog import build

class ChangelogTest(unittest.TestCase):
    def test_only_feature_and_fix_commits_advance_version(self):
        result=build([('docs: design','2026-01-01'),('feat(client): Village','2026-01-02'),('fix: Sound','2026-01-03'),('chore: refresh log','2026-01-04'),('feat!: Pets','2026-01-05')],{},legacy=99)
        self.assertEqual(result['version'],'v0.3.0')
        self.assertEqual([e['version'] for e in result['entries']],['v0.3.0','v0.2.0','v0.1.0'])
        self.assertEqual((result['feature_count'],result['fix_count']),(2,1))
    def test_curated_player_notes_and_readable_fallback(self):
        result=build([('feat: Pets','today'),('fix(ui): Close button','today')],{'feat: Pets':{'title':'宠物加入','details':['可以骑金虎。']}})
        self.assertEqual(result['entries'][0]['title'],'Close button')
        self.assertEqual(result['entries'][1]['title'],'宠物加入')
        self.assertNotIn('hash',result['entries'][1])
    def test_after_legacy_feat_bumps_minor_and_fix_bumps_patch(self):
        records=[('feat: A','d'),('fix: B','d'),('fix: C','d'),('feat: D','d'),('docs: E','d'),('fix: F','d')]
        result=build(records,{},legacy=1)
        self.assertEqual([e['version'] for e in reversed(result['entries'])],['v0.1.0','v0.1.1','v0.1.2','v0.2.0','v0.2.1'])
        self.assertEqual(result['version'],'v0.2.1')
    def test_legacy_fixes_keep_minor_numbers(self):
        result=build([('feat: A','d'),('fix: B','d'),('fix: C','d')],{},legacy=2)
        self.assertEqual([e['version'] for e in reversed(result['entries'])],['v0.1.0','v0.2.0','v0.2.1'])
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


class MarkdownNotesTest(unittest.TestCase):
    def test_migrated_legacy_notes_are_lossless(self):
        import json, subprocess
        from pathlib import Path
        from build_changelog import read_notes
        root=Path(__file__).resolve().parents[1]
        revision=subprocess.check_output(['git','log','-1','--diff-filter=AM','--format=%H','--','docs/development/changelog-notes.json'],cwd=root,text=True).strip()
        old=json.loads(subprocess.check_output(['git','show',revision+':docs/development/changelog-notes.json'],cwd=root,text=True))
        migrated=read_notes(root/'docs/development/changelog-notes')
        for subject,note in old.items():
            self.assertEqual(migrated[subject],dict(title=note['title'],details=note.get('details',[])))

    def test_roundtrip_and_invalid_notes(self):
        import json, tempfile
        from pathlib import Path
        from build_changelog import read_notes
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            path=root/'20261001T120000Z-unicode.md'
            valid='---\nsubject: '+json.dumps('fix: "引号"',ensure_ascii=False)+'\ntitle: '+json.dumps('多行\n标题',ensure_ascii=False)+'\n---\n\n- 第一行\n  第二行\n  \n  - 嵌套文字\n- 顺序二\n'
            path.write_text(valid)
            self.assertEqual(read_notes(root)['fix: "引号"'],dict(title='多行\n标题',details=['第一行\n第二行\n\n- 嵌套文字','顺序二']))
            other=root/'20261001T120001Z-duplicate.md';other.write_text(valid)
            with self.assertRaisesRegex(ValueError,'duplicate subject'):read_notes(root)
            other.unlink()
            for bad in [valid.replace('subject: ', 'unknown: '),valid.replace('title: ', 'subject: '),valid.replace('---\n','',1),valid.replace('- 第一行','unsupported'),valid.replace('title: "多行\\n标题"','title: 3')]:
                path.write_text(bad)
                with self.assertRaises(ValueError):read_notes(root)
            path.write_text(valid)
            for name in ['bad.md','20260230T120000Z-invalid.md','20261001T250000Z-invalid.md']:
                path.rename(root/name)
                with self.assertRaises(ValueError):read_notes(root)
                (root/name).rename(path)

    def test_real_git_first_parent_cherry_pick_and_rebase(self):
        import json, shutil, subprocess, tempfile
        from pathlib import Path
        source=Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True,stderr=subprocess.STDOUT).strip()
            def commit(subject,file):
                (root/file).write_text(subject);git('add','.');git('commit','-qm',subject)
            def generate():
                subprocess.run(['python3','tools/build_changelog.py'],cwd=root,check=True)
                return json.loads((root/'client/data/changelog.json').read_text())
            git('init','-q','-b','main');git('config','user.name','Test');git('config','user.email','test@example.invalid')
            for folder in ['tools','client/data','docs/development/changelog-notes']:(root/folder).mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source/'tools/build_changelog.py',root/'tools/build_changelog.py')
            (root/'client/project.godot').write_text('[application]\n')
            # Filename dates intentionally oppose the Git ordering.
            for stamp,subject,title in [('20261001T120000Z','fix: Side','侧线'),('20261002T120000Z','feat: Main','主线')]:
                (root/f'docs/development/changelog-notes/{stamp}-note.md').write_text('---\nsubject: '+json.dumps(subject)+'\ntitle: '+json.dumps(title)+'\n---\n\n- 说明\n')
            commit('chore: setup','setup');base=git('rev-parse','HEAD')
            git('checkout','-qb','side');commit('fix: Side','side');side=git('rev-parse','HEAD')
            git('checkout','-q','main');commit('feat: Main','main')
            git('merge','--no-ff','-qm','chore: merge side','side')
            self.assertEqual([e['title'] for e in generate()['entries']],['主线'])
            git('reset','--hard','HEAD^');git('cherry-pick',side)
            self.assertEqual([e['title'] for e in generate()['entries']],['侧线','主线'])
            git('restore','client/project.godot');(root/'client/data/changelog.json').unlink()
            git('checkout','-q','side');commit('fix: Rebased follow-up','follow-up');git('rebase','main')
            self.assertEqual([e['title'] for e in generate()['entries']],['Rebased follow-up','侧线','主线'])
            commit('fix: No curated note','no-note')
            self.assertEqual(generate()['entries'][0]['title'],'No curated note')

if __name__=='__main__':unittest.main()
