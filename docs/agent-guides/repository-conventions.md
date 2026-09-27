# Repository conventions

```text
client/          Existing Godot project: presentation and future authority
client/server/   GDScript authority rules/state, added with first consumer
client/shared/   Commands, definitions and logical geometry, when needed
client/network/  Local delivery first; remote adapter when needed
tools/           Resource import/research utilities
docs/            Specification, evidence and delivery status
references/      Ignored upstream clones and verified offline bundles
```

Create folders only when used. Keep one Godot project; dedicated-server exports reuse it. Do not create a separate Swift package. Use stable content IDs and reproducible import tools. Preserve upstream reference files unchanged. Keep raw/derived legacy assets, saves, credentials and editor caches out of tracked source as configured by `.gitignore`.

Use conventional commits, such as `feat(client): ...`, `feat(server): ...` and `docs(architecture): ...`. Verify a playable change before committing it. Documentation estimates and future architecture do not imply completed implementation.
