"""A shared pool of git worktrees for every agent (Claude, Codex, their subagents).

Agents borrow a slot instead of creating new worktrees. Slots live in
.claude/worktrees/pool-<letter> and are reused: their read-only folders are
symlinks to the main checkout, and their Godot import cache is a copy-on-write
clone kept between tasks (see AGENTS.md "Worktree pool").

The pool starts at START slots and grows by itself up to MAX. Beyond MAX it
stops and asks for the user's approval (--approved-by-user).

Leases are kept in <git common dir>/worktree-pool.json, which every worktree
shares and git never tracks; a file lock serialises concurrent agents.

    python3 tools/worktree_pool.py status
    python3 tools/worktree_pool.py acquire --owner codex --branch feat/x --task "..."
    python3 tools/worktree_pool.py acquire ... --import     # branch changes an importer
    python3 tools/worktree_pool.py release pool-b           # branch merged into main
    python3 tools/worktree_pool.py release pool-b --abandon # drop unmerged work on purpose
"""
import argparse
import fcntl
import json
import os
import shutil
import string
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path

START = 5
MAX = 10
STALE_HOURS = 12
SYMLINKED = ['.tools', 'references']
ASSETS = 'client/assets/legacy'
CACHE = 'client/.godot'


def git(*args, cwd=None, check=True):
    result = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise SystemExit('git %s failed: %s' % (' '.join(args), result.stderr.strip()))
    return result.stdout.strip()


def main_checkout() -> Path:
    common = Path(git('rev-parse', '--path-format=absolute', '--git-common-dir'))
    return common.parent


MAIN = main_checkout()
COMMON = MAIN / '.git'
STATE = COMMON / 'worktree-pool.json'
LOCK = COMMON / 'worktree-pool.lock'
POOL = MAIN / '.claude' / 'worktrees'


@contextmanager
def locked():
    with open(LOCK, 'w') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def load() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text())
    return {'slots': {}}


def save(state: dict) -> None:
    tmp = STATE.with_suffix('.tmp')
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2) + '\n')
    tmp.replace(STATE)


def slot_names(count: int) -> list:
    return ['pool-' + string.ascii_lowercase[i] for i in range(count)]


def slot_path(name: str) -> Path:
    return POOL / name


def registered_worktrees() -> set:
    paths = set()
    for line in git('worktree', 'list', '--porcelain').splitlines():
        if line.startswith('worktree '):
            paths.add(str(Path(line[len('worktree '):]).resolve()))
    return paths


def link(path: Path, target: Path) -> None:
    """Points path at target, replacing a stale link; never touches a real folder."""
    if path.is_symlink():
        if Path(os.readlink(path)) == target:
            return
        path.unlink()
    elif path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.symlink_to(target)


def clone(source: Path, dest: Path) -> None:
    """APFS copy-on-write clone (cp -c), replacing an older clone."""
    if dest.is_symlink():
        dest.unlink()
    elif dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['cp', '-c', '-R', str(source), str(dest)], check=True)


def newest_mtime(folder: Path) -> float:
    marker = folder / 'imported'
    return marker.stat().st_mtime if marker.exists() else (folder.stat().st_mtime if folder.exists() else 0.0)


def prepare(name: str, importing: bool) -> None:
    """Makes the slot's ignored folders match the pool rules."""
    path = slot_path(name)
    for folder in SYMLINKED:
        link(path / folder, MAIN / folder)
    assets = path / ASSETS
    if importing:
        if assets.is_symlink() or not assets.exists():
            clone(MAIN / ASSETS, assets)
    else:
        if assets.exists() and not assets.is_symlink():
            shutil.rmtree(assets)
        link(assets, MAIN / ASSETS)
    cache = path / CACHE
    stamp = path / CACHE / '.pool-cache-stamp'
    source_time = newest_mtime(MAIN / CACHE)
    cloned_time = float(stamp.read_text()) if stamp.exists() else -1.0
    if not cache.exists() or cache.is_symlink() or cloned_time < source_time:
        clone(MAIN / CACHE, cache)
        stamp.write_text(str(source_time))


def create(name: str) -> None:
    path = slot_path(name)
    POOL.mkdir(parents=True, exist_ok=True)
    git('worktree', 'add', '--detach', str(path), 'main')


def dirty(name: str) -> list:
    out = git('status', '--porcelain', cwd=slot_path(name))
    return [line for line in out.splitlines() if line.strip()]


def cmd_status(_args) -> None:
    state = load()
    created = state.get('created', [])
    now = time.time()
    for name in slot_names(max(START, len(created))):
        lease = state['slots'].get(name)
        if not lease:
            print('%-7s free%s' % (name, '' if name in created else ' (created on first use)'))
            continue
        hours = (now - lease['since']) / 3600
        stale = '  STALE?' if hours > STALE_HOURS else ''
        print('%-7s %-28s %-36s %5.1fh  %s%s' % (name, lease['owner'], lease['branch'], hours, lease.get('task', ''), stale))
    print('pool: %d created, %d leased; grows by itself up to %d, more needs the user' % (len(created), len(state['slots']), MAX))


def cmd_acquire(args) -> None:
    with locked():
        state = load()
        created = state.setdefault('created', [])
        free = [name for name in created if name not in state['slots']]
        if free:
            chosen = free[0]
        else:
            if len(created) >= MAX and not args.approved_by_user:
                cmd_status(args)
                raise SystemExit('pool is full (%d slots, all leased). More than %d needs the user\'s approval: ask them, then rerun with --approved-by-user.' % (len(created), MAX))
            chosen = slot_names(len(created) + 1)[-1]
        path = slot_path(chosen)
        if str(path.resolve()) not in registered_worktrees():
            if path.exists():
                raise SystemExit('%s exists but is not a registered worktree; inspect it before reusing.' % path)
            create(chosen)
        if chosen not in created:
            created.append(chosen)
        leftover = dirty(chosen)
        if leftover:
            raise SystemExit('%s has uncommitted changes from an earlier lease:\n%s' % (chosen, '\n'.join(leftover[:20])))
        exists = subprocess.run(['git', 'show-ref', '--verify', '--quiet', 'refs/heads/' + args.branch], cwd=MAIN).returncode == 0
        if exists:
            git('switch', args.branch, cwd=path)
        else:
            git('switch', '-c', args.branch, args.base, cwd=path)
        prepare(chosen, args.import_assets)
        state['slots'][chosen] = {'owner': args.owner, 'branch': args.branch, 'task': args.task or '', 'since': time.time(), 'importing': bool(args.import_assets)}
        save(state)
    print(path)


def resolve_slot(text: str, state: dict) -> str:
    name = Path(text).name if text.startswith(('/', '.')) else text
    if name not in state['slots']:
        raise SystemExit('%s is not leased (see status).' % name)
    return name


def landed(branch: str) -> bool:
    """True when main contains the branch, merged or cherry-picked (git cherry finds no '+' commit)."""
    if subprocess.run(['git', 'merge-base', '--is-ancestor', branch, 'main'], cwd=MAIN).returncode == 0:
        return True
    pending = git('cherry', 'main', branch, cwd=MAIN)
    return not any(line.startswith('+') for line in pending.splitlines())


def cmd_release(args) -> None:
    with locked():
        state = load()
        name = resolve_slot(args.slot, state)
        lease = state['slots'][name]
        path = slot_path(name)
        if path.exists():
            leftover = dirty(name)
            if leftover and not args.abandon:
                raise SystemExit('%s has uncommitted changes; commit them, or rerun with --abandon to drop them:\n%s' % (name, '\n'.join(leftover[:20])))
            merged = landed(lease['branch'])
            if not merged and not args.abandon:
                raise SystemExit('%s is not merged into main; merge it first, or rerun with --abandon (the branch and its commits stay).' % lease['branch'])
            if leftover:
                git('reset', '--hard', cwd=path)
                git('clean', '-fd', cwd=path)
            git('switch', '--detach', 'main', cwd=path)
            prepare(name, False)
        del state['slots'][name]
        save(state)
    print('released %s (branch %s kept)' % (name, lease['branch']))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('status')
    acquire = sub.add_parser('acquire')
    acquire.add_argument('--owner', required=True, help='agent name, e.g. codex-projects-stone-age-1')
    acquire.add_argument('--branch', required=True)
    acquire.add_argument('--base', default='main')
    acquire.add_argument('--task', default='')
    acquire.add_argument('--import', dest='import_assets', action='store_true', help='clone client/assets/legacy: the branch changes an importer')
    acquire.add_argument('--approved-by-user', action='store_true', help='grow past %d slots; only after the user said yes' % MAX)
    release = sub.add_parser('release')
    release.add_argument('slot', help='pool-<letter> or its path')
    release.add_argument('--abandon', action='store_true', help='release although unmerged or dirty (drops uncommitted changes)')
    args = parser.parse_args()
    {'status': cmd_status, 'acquire': cmd_acquire, 'release': cmd_release}[args.command](args)


if __name__ == '__main__':
    main()
