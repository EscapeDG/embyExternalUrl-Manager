# Security Policy

## Supported Versions

Security fixes are handled for the latest tagged release on `main`.

## Reporting a Vulnerability

Please do not publish secrets, tokens, certificates, private keys, real server
addresses, or exploitable details in a public issue.

Preferred reporting path:

1. Use GitHub private vulnerability reporting for this repository if it is enabled.
2. If private reporting is not available, open a minimal public issue that says
   you have a security concern and asks for a private contact path. Do not include
   sensitive data in that issue.

## Sensitive Data

`embyExternalUrl-Manager` manages local deployment configuration for media
servers, OpenList, Docker, nginx, certificates, and upstream script sync.

Current security boundaries:

- The app stores its local configuration under the user's Application Support
  directory.
- OpenList tokens and service URLs may be stored in the local configuration file.
- Certificate files are written only to the nginx certificate directory selected
  by the user.
- Command output and visible command strings mask password arguments handled by
  the bundled Rust core.
- The app does not intentionally collect telemetry.

Do not commit real config files, Docker overrides, tokens, cookies, certificates,
private keys, or generated release artifacts.

## Known Limitations

- OpenList token storage has not yet been migrated to macOS Keychain.
- Public DMG builds that are not signed with Developer ID and notarized may be
  blocked by Gatekeeper.
