# infravibe 2.12.0

The SOCKS tunnel now restarts itself after unexpected exits.

- Laptop sleep, a network change, or Teleport certificate expiry used to leave the SOCKS port closed until a manual restart, even with a valid login. Unexpected exits now retry with backoff (2/5/10/30/60 seconds) while Teleport credentials remain valid; the retry budget resets after a tunnel that held for ten minutes.
- Waking from sleep triggers an immediate recovery check instead of waiting for SSH keepalives to time out. Recovery only engages when a tunnel had been started in the current session.
- A stop from the menu is remembered as user-requested and never restarts. An expired Teleport session raises a login-required notification instead of retrying.
- A duplicate-start guard prevents a manual start and a scheduled retry from racing.

Validation includes the Swift suite and a typecheck-parity check against the previous release. The auto-restart logic has not yet been exercised through a live sleep/wake cycle; report regressions on the repository.

Signed and notarized Universal macOS application for Apple silicon and Intel. Previous release 2.11.0 remains available for rollback.
