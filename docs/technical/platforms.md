# Platform policy

| Component | Now | Future |
| --- | --- | --- |
| Godot client | macOS development and playable local scene | Desktop exports, then mobile/device-specific work |
| Swift server | Easiest macOS executable and debugger workflow | Linux and Windows dedicated servers |
| Bundled local server | macOS child process after M001 | Other desktop bundles; investigate mobile in-process integration |

Linux/Windows portability is an architectural constraint, not a release claim or MVP acceptance criterion. No cross-compilation, containers, CI matrix, or Windows wrapper is required before Samgir works.

Prefer portable Swift/Foundation and transport APIs when equally simple. Keep app launching, filesystem locations, platform logging, and OS-specific integration at small boundaries. If an Apple-only API is the fastest reasonable option, use it and record the dependency plus likely replacement in a short note.

Trigger portability work when a concrete deployment target is requested. At that time verify the selected Swift toolchain, dependencies, database driver, networking, shutdown behavior, path handling, and packaging on that OS. A shared language does not establish a working port.

Record actual engine/toolchain versions and tested machines in implementation handoffs. Avoid unsupported promises about iOS, Android, visionOS, or server deployment targets.
