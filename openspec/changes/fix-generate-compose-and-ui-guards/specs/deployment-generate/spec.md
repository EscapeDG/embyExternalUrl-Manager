# Spec: deployment-generate

## ADDED Requirements

### Requirement: Generate writes docker-compose.yml

The system SHALL write a rendered `docker-compose.yml` into the deployment directory when the user generates deployment files.

#### Scenario: Successful generate includes compose

- **WHEN** the user runs 生成配置 with valid templates
- **THEN** `{deploymentDirectory}/docker-compose.yml` exists
- **AND** it contains the current media server container name and nginx conf path

### Requirement: Missing nginx skeleton is warned

The system SHALL add warnings when required nginx skeleton files are absent after generate.

#### Scenario: Empty deploy without upstream sync

- **WHEN** generate runs and `nginx.conf` or active conf is missing
- **THEN** DeploymentReport.warnings is non-empty
- **AND** the UI surfaces those warnings
