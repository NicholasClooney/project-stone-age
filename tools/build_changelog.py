"""Build the in-game log from first-parent conventional feat/fix commits.

No commit hash is embedded, so refreshing and amending the current commit is stable.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERN = re.compile(r'^(feat|fix)(?:\([^)]*\))?!?:\s+(.+)$')


def build(records, notes):
    entries = []
    for subject, date in records:
        match = PATTERN.match(subject)
        if not match:
            continue
        number = len(entries)+1
        entry = notes.get(subject, {})
        entries.append(dict(version=f'v0.{number}.0', date=date,
                            kind=match.group(1), title=entry.get('title', match.group(2)),
                            details=entry.get('details', [])))
    return dict(version=f'v0.{len(entries)}.0', count=len(entries),
                feature_count=sum(e['kind']=='feat' for e in entries),
                fix_count=sum(e['kind']=='fix' for e in entries), entries=list(reversed(entries)))


def outputs():
    log = subprocess.check_output(['git','log','--first-parent','--reverse','--date=short','--format=%s%x1f%ad'], cwd=ROOT, text=True)
    records = [line.rsplit('\x1f',1) for line in log.splitlines() if '\x1f' in line]
    notes_path = ROOT/'docs/development/changelog-notes.json'
    data = build(records, json.loads(notes_path.read_text()) if notes_path.exists() else {})
    project = ROOT/'client/project.godot'
    current = project.read_text()
    line = 'config/version="'+data['version']+'"'
    if re.search(r'^config/version=', current, re.M):
        config = re.sub(r'^config/version=.*$', line, current, flags=re.M)
    else:
        config = current.replace('[application]', '[application]\n\n'+line, 1)
    return {ROOT/'client/data/changelog.json':json.dumps(data,ensure_ascii=False,indent=2)+'\n', project:config}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args = parser.parse_args()
    stale = []
    for path, content in outputs().items():
        if args.check:
            if not path.exists() or path.read_text()!=content:stale.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(content)
    if stale:raise SystemExit('Changelog needs refresh: '+', '.join(stale))

if __name__=='__main__':main()
