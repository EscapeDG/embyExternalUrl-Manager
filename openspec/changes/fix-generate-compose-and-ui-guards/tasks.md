# Tasks: fix-generate-compose-and-ui-guards

## 1. ConfigService

- [x] 1.1 Write `docker-compose.yml` in `generateDeployment`
- [x] 1.2 Add nginx skeleton warnings
- [x] 1.3 Harden `load()` / `save() -> Bool` + `lastPersistenceError`
- [x] 1.4 PathMapping / OpenList / Mount resilient decode

## 2. DockerService

- [x] 2.1 Add `isBusy` around up/down/restart
- [x] 2.2 Prefer exact container name match only

## 3. UI

- [x] 3.1 Dashboard Jellyfin badge
- [x] 3.2 Generate: busy disable + show warnings
- [x] 3.3 Connection: save success/fail + reset confirm
- [x] 3.4 Menubar: skip ops when busy + failure alert

## 4. Verify

- [x] 4.1 `swift build` PASS
- [x] 4.2 Tasks complete; LMV update next
