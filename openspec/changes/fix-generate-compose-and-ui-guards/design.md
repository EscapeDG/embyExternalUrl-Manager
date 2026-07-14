# Design: fix-generate-compose-and-ui-guards

## Approach

Minimal, localized fixes in ConfigService, DockerService, Dashboard, Generate, Connection, AppDelegate.

### generateDeployment

- Append template entry for `docker-compose.yml` → `{deployDir}/docker-compose.yml` using common Templates path (not plex/emby subfolder).
- Variables already include `CONTAINER_NAME`, `DEPLOY_DIR`, `NGINX_CONF`.
- After writes, check:
  - `{nginxDir}/nginx.conf`
  - `{nginxConfDir}/{activeConfName}`
  - imported helpers if constant.js expects them (`config/constant-common.js` etc.)
- Missing → `warnings` on `DeploymentReport` (generate still succeeds for parameter files).

### load / save

- `save() -> Bool` (or throws); UI checks return value.
- `load()`: if file missing → defaults; if decode fails → copy to `Backups/config.corrupt.<ts>.json`, set `lastError`, **do not** overwrite good in-memory if already loaded (init still defaults).
- Publish `@Published var lastPersistenceError: String?`.

### PathMapping decode

- Custom `init(from:)` with `decodeIfPresent` for id/note/enabled so partial JSON does not fail whole AppConfig.

### Docker busy

- `@Published var isBusy: Bool` on DockerService; set true around up/down/restart.
- UI disable buttons when `isBusy`; menubar skip or alert if busy.

### UI

- Dashboard badge: use same `httpPort`/`httpsPort` computed props.
- Connection: `.confirmationDialog` before reset; save shows success or error alert.
