# Spec: process-execution

## ADDED Requirements

### Requirement: Concurrent stdout/stderr draining

All external process execution in `DockerService` SHALL drain stdout and stderr concurrently while the process runs, so that a child process producing more output than the pipe buffer capacity cannot block. This applies to both the async and synchronous runners.

#### Scenario: Large output completes normally
- **WHEN** a docker command produces output larger than the pipe buffer (e.g. > 64 KB)
- **THEN** the command completes with its real exit code and full output, without being killed as a timeout

#### Scenario: Timeout still terminates
- **WHEN** a command exceeds its timeout
- **THEN** the process is terminated, partial output is returned, and the result reports the timeout

### Requirement: Busy flag always released

Container lifecycle operations SHALL release the busy flag on every exit path, including command failure and timeout.

#### Scenario: Failing up command releases busy
- **WHEN** `up` returns a non-zero exit code
- **THEN** `isBusy` returns to false and subsequent operations are not blocked
