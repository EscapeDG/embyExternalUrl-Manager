# Spec: ui-guards

## ADDED Requirements

### Requirement: Jellyfin ports on dashboard

Dashboard media badge SHALL show jellyfin proxy ports when media server type is Jellyfin.

#### Scenario: Jellyfin type selected
- **WHEN** the active media server type is Jellyfin
- **THEN** the dashboard badge displays the Jellyfin HTTP/HTTPS proxy ports

### Requirement: Container operation busy guard

While a container start/stop/restart is in progress, the system SHALL disable concurrent container operations from Generate view and menubar.

#### Scenario: Operation in progress
- **WHEN** a container start/stop/restart command is running
- **THEN** Generate view buttons and menubar container actions are disabled or rejected with a busy message

### Requirement: Reset confirmation

Restoring defaults SHALL require explicit user confirmation.

#### Scenario: User taps reset
- **WHEN** the user taps 恢复默认 in Connection view
- **THEN** a confirmation dialog appears and defaults are only applied after the user confirms
