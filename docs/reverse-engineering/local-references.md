# Local reference archive

Keep upstream source available even if GitHub or its owner removes the repositories. The `references/` directory is intentionally ignored by the game repository and should be preserved as research material.

| Reference | Local checkout | Purpose |
| --- | --- | --- |
| `anson1788/stoneage` | `references/anson1788-stoneage/` | Legacy client source, resource formats, UI, sound mappings |
| `chenmingbiao/stone-age` | `references/chenmingbiao-stone-age/` | Legacy server, original Samgir map and NPC definitions |

These are full Git clones with upstream history, not shallow downloads. Each also has a standalone `git bundle` snapshot under `references/archives/`. Bundles preserve the cloned Git objects and refs independently of the working checkouts. The adjacent tracked [archive manifest](local-references.json) records revisions, source URLs, and bundle SHA-256 checksums.

For future research, read the local checkout first. The client source is under `references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/`. The server data is under `references/chenmingbiao-stone-age/gmsv/data/`. Do not edit upstream files in place or execute bundled legacy binaries as part of research.

## Offline recovery

From the game repository root, clone the chosen bundle into a **new** directory:

```sh
git clone references/archives/anson1788-stoneage-2026-09-27.bundle references/restored-client
git clone references/archives/chenmingbiao-stone-age-2026-09-27.bundle references/restored-server
```

The original source client asset archive is separately preserved at `.tools/legacy/client25.rar`; it is not part of these source repositories. Back up `references/` and `.tools/legacy/` with the project. Local copies protect against upstream deletion; another disk or backup service is needed for protection against loss of this Mac.

Git archives preserve repository content/history, not GitHub issues, release attachments, or external download links. Future refreshes should create new dated bundles and retain these original snapshots.
