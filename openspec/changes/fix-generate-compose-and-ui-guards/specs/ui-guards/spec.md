# Spec: ui-guards

## ADDED Requirements

### Requirement: Jellyfin ports on dashboard

Dashboard media badge SHALL show jellyfin proxy ports when media server type is Jellyfin.

### Requirement: Container operation busy guard

While a container start/stop/restart is in progress, the system SHALL disable concurrent container operations from Generate view and menubar.

### Requirement: Reset confirmation

Restoring defaults SHALL require explicit user confirmation.
