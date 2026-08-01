# Spec: deployment-generate

## ADDED Requirements

### Requirement: Existing docker-compose.yml preserved

When generating deployment files, the system MUST NOT overwrite an existing `docker-compose.yml` in the deployment directory. Generation SHALL skip the compose file and add a report warning telling the user the existing file was kept and how to regenerate it.

#### Scenario: Fresh deployment directory
- **WHEN** the deployment directory has no `docker-compose.yml`
- **THEN** the compose file is rendered and written

#### Scenario: Existing compose file
- **WHEN** the deployment directory already contains `docker-compose.yml`
- **THEN** the file is left untouched and the report warns that regeneration requires deleting it first

### Requirement: Compose path values are quoted

Path values interpolated into the compose template (deployment directory, nginx config directory) SHALL be emitted as quoted YAML scalars with embedded `"` and `\` escaped, so spaces, `#`, `:`, or newlines in user paths cannot corrupt the file.

#### Scenario: Path containing space and hash
- **WHEN** the deployment path contains a space or ` #`
- **THEN** the rendered compose file remains valid YAML pointing at the correct directory

### Requirement: Skeleton warnings match the active media type

Missing-helper warnings SHALL only list helper files actually imported by the active media server's generated constant files. Plex generation MUST NOT warn about helpers that only Emby templates import.

#### Scenario: Plex without constant-nginx.js
- **WHEN** generating for Plex and `constant-nginx.js` is absent but no Plex template imports it
- **THEN** no warning is emitted for `constant-nginx.js`

### Requirement: Backup file names are unique

Backups created by `TemplateRenderer.writeRendered` SHALL be unique across rapid successive writes, including multiple generations within the same second and identical destination basenames in different deployments.

#### Scenario: Two generations within one second
- **WHEN** generation runs twice within one second over an existing file
- **THEN** both backups exist and neither write fails due to a name collision
