# Example manifests

These are proposed schema examples, not loadable artifacts shipped with this documentation. IDs, hashes, rules, and packs must be implemented before use. Historical feature combinations remain unverified.

## Minimal development profile

```json
{
  "schema_version": 1,
  "id": "samgir-dev",
  "revision": 1,
  "historical_target": null,
  "ruleset": "prototype-world@1",
  "features": ["world_movement"],
  "content_packs": [
    {"id": "project.samgir", "revision": 1, "sha256": "REPLACE_WITH_PACK_SHA256"}
  ],
  "protocol": "modern-dev-1",
  "legacy_adapter": null,
  "entry": {"map": "project.samgir.village", "spawn": "start"}
}
```

M000 may express this selection as direct scene configuration. Its protocol field names the intended later connection; it does not require a server for the first scene. Placeholder hashes must be rejected by an actual resolver.

## Historical candidate template

```json
{
  "schema_version": 1,
  "id": "sa-2-5-candidate",
  "revision": 1,
  "historical_target": {
    "label": "2.5",
    "region": "UNVERIFIED",
    "build": "UNVERIFIED",
    "evidence_id": "PENDING"
  },
  "ruleset": "sa-2-5-research@1",
  "features": ["world_movement"],
  "content_packs": [
    {"id": "project.common", "revision": 1, "sha256": "REPLACE_WITH_PACK_SHA256"},
    {"id": "project.sa25", "revision": 1, "sha256": "REPLACE_WITH_PACK_SHA256"}
  ],
  "protocol": "modern-dev-1",
  "legacy_adapter": null,
  "entry": {"map": "project.samgir.village", "spawn": "start"}
}
```

Do not publish this candidate as supported until its dependencies, rules, and evidence exist. Add pets/riding only after their behavior and edition association are verified. A custom profile can select later content with earlier rules only when definition requirements and rules are compatible.

## Separate client preferences

```json
{
  "presentation": "modern",
  "transitions": "seamless",
  "ui_scale": 1.0,
  "music_volume": 0.6,
  "sfx_volume": 0.8
}
```

Classic defaults can select classic transitions; an accessibility preference may override flashes/fades. These settings do not change the profile's authoritative digest.
