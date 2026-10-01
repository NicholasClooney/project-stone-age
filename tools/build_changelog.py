"""Build the in-game log from first-parent conventional feat/fix commits.

No commit hash is embedded, so refreshing and amending the current commit is stable.
"""
import argparse
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERN = re.compile(r'^(feat|fix)(?:\([^)]*\))?!?:\s+(.+)$')


# Entries 1..43 predate patch releases and keep their v0.N.0 numbers (tag v0.43.0).
# Afterwards feat bumps the minor version and fix bumps the patch version.
LEGACY_ENTRIES = 43


def build(records, notes, legacy=LEGACY_ENTRIES):
    entries = []
    minor = patch = 0
    for subject, date in records:
        match = PATTERN.match(subject)
        if not match:
            continue
        kind = match.group(1)
        if len(entries) < legacy or kind == 'feat':
            minor, patch = minor+1, 0
        else:
            patch += 1
        entry = notes.get(subject, {})
        entries.append(dict(version=f'v0.{minor}.{patch}', date=date,
                            kind=kind, title=entry.get('title', match.group(2)),
                            details=entry.get('details', [])))
    return dict(version=f'v0.{minor}.{patch}', count=len(entries),
                feature_count=sum(e['kind']=='feat' for e in entries),
                fix_count=sum(e['kind']=='fix' for e in entries), entries=list(reversed(entries)))


# Deliberately small frontmatter subset: exactly two JSON-quoted string values.
# JSON escaping preserves Unicode, quotes and newlines without a YAML dependency.
NOTE_FILENAME = re.compile(r"^(\d{8}T\d{6}Z)-[a-z0-9]+(?:-[a-z0-9]+)*\.md$")


def read_notes(directory):
    notes = {}
    if not directory.exists():
        return notes
    for path in sorted(directory.glob('*.md')):
        try:
            match = NOTE_FILENAME.fullmatch(path.name)
            if not match:
                raise ValueError('expected <YYYYMMDDTHHMMSSZ>-<slug>.md')
            datetime.strptime(match.group(1), '%Y%m%dT%H%M%SZ')
            lines = path.read_text(encoding='utf-8').split('\n')
            if lines[0] != '---':
                raise ValueError('missing opening frontmatter delimiter')
            end = lines.index('---', 1)
            metadata = {}
            for line in lines[1:end]:
                key, separator, value = line.partition(': ')
                if not separator or key not in ('subject', 'title') or key in metadata:
                    raise ValueError('frontmatter requires unique subject and title fields')
                metadata[key] = json.loads(value)
                if not isinstance(metadata[key], str) or not metadata[key]:
                    raise ValueError('frontmatter values must be nonempty JSON strings')
            if set(metadata) != {'subject', 'title'}:
                raise ValueError('frontmatter requires subject and title')
            details = []
            body = lines[end+1:]
            while body and body[0] == '': body.pop(0)
            if body and body[-1] == '': body.pop()
            for line in body:
                if line.startswith('- '):
                    details.append(line[2:])
                elif line.startswith('  ') and details:
                    details[-1] += '\n' + line[2:]
                else:
                    raise ValueError('body requires - list items and two-space continuations')
            subject = metadata['subject']
            if subject in notes:
                raise ValueError('duplicate subject: ' + subject)
            notes[subject] = dict(title=metadata['title'], details=details)
        except (ValueError, IndexError) as error:
            raise ValueError(f'{path}: {error}') from error
    return notes


def outputs():

    log = subprocess.check_output(['git','log','--first-parent','--reverse','--date=short','--format=%s%x1f%ad'], cwd=ROOT, text=True)
    records = [line.rsplit('\x1f',1) for line in log.splitlines() if '\x1f' in line]
    data = build(records, read_notes(ROOT/'docs/development/changelog-notes'))
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
