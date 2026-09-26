# Proposed game repository conventions

These conventions describe a future game repository. This documentation package does not create that repository or supersede instructions in the directory where it is used.

```text
client/          Godot project and scenes
server/          Swift package/executable when M001 starts
content/         Runtime definitions and approved assets
tools/           Focused import/research utilities as needed
tests/fixtures/  Small reproducible protocol/resource samples
docs/            This specification and evolving decisions
```

Create folders only when used. Raw reference material should remain unchanged and separate from generated output; large or redistribution-restricted inputs may need local-only storage with an inventory of hashes.

Use stable namespaced content IDs, explicit configuration, and reproducible generation. Keep generated files identifiable and record how to rebuild them. Never hand-edit converted output as the only record of a format fix.

Pin engine/toolchain/dependency versions when establishing the runnable project. Add a short real launch guide with exact commands only after verifying them. Keep local credentials, saves, caches, and derived editor state out of source control.

Commit focused playable changes using the host repository's existing conventions. Do not initialize a nested repository or alter release numbering merely because this docs package is copied into an existing project.
