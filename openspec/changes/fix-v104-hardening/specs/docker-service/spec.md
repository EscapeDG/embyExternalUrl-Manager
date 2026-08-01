# Spec: docker-service

## ADDED Requirements

### Requirement: Exact container name matching only

Container status detection SHALL only report a container whose name exactly equals one of the active media server's candidate names. Docker's substring `name=` filter results that do not exactly match MUST NOT be treated as the managed container.

#### Scenario: Only similarly named container exists
- **WHEN** `docker ps -a` returns a container named `old-plex2Alist-nginx-test` but none of the exact candidate names
- **THEN** the service reports the managed container as not found

#### Scenario: Exact match among substring results
- **WHEN** the filter output includes both an exact candidate name and unrelated substring matches
- **THEN** the exact candidate is selected
