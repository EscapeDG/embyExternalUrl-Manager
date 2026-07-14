# Spec: config-persistence

## ADDED Requirements

### Requirement: Save reports failure

The system SHALL NOT claim configuration was saved when the write fails.

#### Scenario: Disk write failure

- **WHEN** save cannot encode or write config.json
- **THEN** the UI shows an error, not “已保存”

### Requirement: Load failure does not silently wipe without backup

The system SHALL backup unreadable config.json before falling back to defaults.

#### Scenario: Corrupt config.json

- **WHEN** config.json exists but cannot be decoded
- **THEN** a backup is written under Application Support Backups
- **AND** lastPersistenceError is set
