#!/bin/sh
# Run after a successful feat/fix commit. Amend only generated files, preserving
# unrelated staged and unstaged work. No hash is stored in either output.
set -eu
cd "$(dirname "$0")/.."
if ! git diff --quiet HEAD -- client/data/changelog.json client/project.godot; then
  echo "Commit or preserve existing version-file edits before refreshing the changelog." >&2
  exit 1
fi
python3 tools/build_changelog.py
if ! git diff --quiet HEAD -- client/data/changelog.json client/project.godot; then
  git add client/data/changelog.json client/project.godot
  git commit --amend --no-edit --only -- client/data/changelog.json client/project.godot
fi
python3 tools/build_changelog.py --check
