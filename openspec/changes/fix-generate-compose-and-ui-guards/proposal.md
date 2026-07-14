# Proposal: fix-generate-compose-and-ui-guards

## Why

Code review found that Generate claims to write `docker-compose.yml` but never does, so container start fails after “successful” generate. Load/save can silently wipe or fail; Jellyfin dashboard ports are wrong; container ops lack busy guards; reset-to-defaults has no confirm.

## What Changes

1. **Generate** writes `docker-compose.yml` into the deployment directory from the existing template.
2. **Generate** warns when nginx skeleton (`nginx.conf`, active conf, imported constant helpers) is missing; guide upstream sync first.
3. **Config load/save** surfaces errors; on load failure keep previous in-memory config when possible and backup corrupt file; `save()` returns success/failure.
4. **Dashboard** Jellyfin port badge uses jellyfin ports.
5. **DockerService / UI / menubar** busy flag for container start/stop/restart.
6. **ConnectionView** confirm before 恢复默认; save alert reflects success/failure.

## Out of Scope

- Real Docker/Plex/OpenList 302 smoke (environment still required).
- Notarization / Gatekeeper.
- Full scan → generate round-trip field parity for Emby 115 flags.
- Migrating tokens to Keychain.

## Success Criteria

- After Generate, deploy dir contains `docker-compose.yml` with correct `CONTAINER_NAME` / paths.
- Missing nginx skeleton produces warnings (not silent broken deploy).
- Save failure does not show “已保存”.
- Jellyfin badge matches jellyfin proxy ports.
- Concurrent container ops blocked while busy.
- Reset requires confirmation.
