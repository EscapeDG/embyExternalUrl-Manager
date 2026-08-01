# Spec: config-persistence

## ADDED Requirements

### Requirement: Corrupt config backup failure preserves user data

When loading `config.json` fails to decode, the system SHALL attempt to copy the corrupt file into the Backups directory before any fallback. If the backup copy fails, the system MUST NOT delete or overwrite the original file, MUST retain the current in-memory configuration, and MUST surface the failure via `lastPersistenceError`. A backup success message SHALL only be produced when the copy actually succeeded.

#### Scenario: Decode fails and backup succeeds
- **WHEN** `config.json` contains invalid JSON and the Backups directory is writable
- **THEN** the corrupt file is copied to Backups, in-memory config falls back to defaults, and `lastPersistenceError` names the backup file

#### Scenario: Decode fails and backup fails
- **WHEN** `config.json` contains invalid JSON and the backup copy throws
- **THEN** the original file remains on disk, the previous in-memory config is kept, and `lastPersistenceError` reports that the backup failed

### Requirement: Save failure surfaced at every call site

Every UI action that persists configuration SHALL check the `save()` return value and MUST NOT show a success confirmation when saving fails. Failure alerts SHALL include the `lastPersistenceError` message.

#### Scenario: Save succeeds
- **WHEN** the user taps 保存配置 and the write succeeds
- **THEN** a 已保存 confirmation is shown

#### Scenario: Save fails on any page
- **WHEN** the user taps 保存配置 on PathMapping, RedirectSettings, Connection, UpstreamSync, or Certificate pages and the write throws
- **THEN** an error alert with the persistence error is shown and no success message appears

#### Scenario: Reset to defaults fails to persist
- **WHEN** the user confirms 恢复默认 and the subsequent save fails
- **THEN** the failure is surfaced and the UI does not claim the reset succeeded
