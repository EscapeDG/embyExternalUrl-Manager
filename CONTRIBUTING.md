# Contributing

Thanks for helping improve `embyExternalUrl-Manager`.

## Development Setup

Requirements:

- macOS 14 or newer
- Swift 5.9 or newer
- Rust toolchain
- Docker Desktop or OrbStack for runtime validation

Useful checks:

```bash
swift build
cargo test --manifest-path RustCore/Cargo.toml
cargo build --release --manifest-path RustCore/Cargo.toml
```

Packaging scripts create local artifacts in `dist/`:

```bash
./Scripts/build_app.sh
./Scripts/package_dmg.sh
```

## Contribution Guidelines

- Keep changes focused and explain the user-facing impact.
- Do not commit `.build/`, `RustCore/target/`, `dist/`, `.DS_Store`, local
  rules, generated app bundles, DMG files, tokens, cookies, certificates, or
  private keys.
- Preserve UTF-8 without BOM for source, scripts, and documentation.
- Prefer small validation steps that match the changed area.
- If a change affects upstream sync, nginx templates, Docker behavior, or
  certificate handling, include the smallest reproducible verification path.

## Upstream Relationship

This project is a graphical manager around `bpking1/embyExternalUrl`. Core
upstream script behavior should stay compatible with upstream unless a change is
clearly documented and intentionally scoped.
