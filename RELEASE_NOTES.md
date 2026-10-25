# infravibe 2.12.1

Tailscale no longer flashes in the menu bar every few seconds.

- The Remote Access view refreshed on a 10-second timer, and each refresh ran `tailscale status --json`. On machines where Tailscale is installed as the GUI app, that path resolves to the app binary itself, so every refresh launched a short-lived Tailscale process: the icon appeared in the menu bar and vanished again, continuously, for as long as InfraProxy was running.
- Timer-driven refreshes now query Tailscale only while a Tailscale tunnel is actually running, and at most once per 60 seconds. Refreshes you trigger yourself, such as opening the menu panel or using a share action, still query immediately as before.
- When a refresh skips the query, the last known Tailnet status is retained instead of being cleared.

The Tailnet status shown in Remote Access can therefore be up to one panel-open stale while no Tailscale tunnel is running; opening the panel always refreshes it. The Tailscale tunnel itself was never affected by the old behavior.

Validation includes the Swift suite, with new unit coverage for the polling decision. The fix has not yet been observed across a multi-hour run of the installed build; report regressions on the repository.

Signed and notarized Universal macOS application for Apple silicon and Intel. Previous release 2.12.0 remains available for rollback.
