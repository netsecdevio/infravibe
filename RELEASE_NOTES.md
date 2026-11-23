# infravibe 2.13.1 (build 19)

Menu-bar reliability, working proxy lifecycle controls, and native visibility for browser terminal sessions.

## Menu bar and sessions

- The menu popup now dismisses reliably on outside clicks, cancels stale context menus, and cleans up its event monitors when closed.
- The menu bar shows the number of running browser terminal sessions alongside Teleport expiry.
- The native popup and Server page show named live and exited browser sessions, matching the browser Dashboard's session state.

## IA and HTTP proxy lifecycle

- The Outbound page now exposes Start, Stop, and Restart controls for both listeners in addition to the right-click menu.
- Restart waits for the old managed process to terminate before launching its replacement instead of relying on a fixed delay.
- Existing listeners that outlive an app restart can be stopped or restarted; context-menu state is refreshed immediately before display.
- User-requested IA stops suppress pending automatic recovery, including when recovering an orphaned listener.
- The HTTP proxy is launched with an explicit SOCKS destination using the configured IA proxy port, so it forwards through the IA listener rather than relying on the tool's default.
- GUI launches now preserve the configured HTTP proxy path and augment the child `PATH` with its directory and Homebrew locations, allowing the `hpts` shebang to find `node`.

## Validation and distribution

- Regression coverage includes popover dismissal, restart ordering, process-generation cleanup, orphaned listeners, simultaneous proxy ports, and menu enablement.
- Full Swift and browser integration suites pass; the Universal app supports Apple silicon and Intel on macOS 15.5 or later.
- Signed and notarized DMG, with the existing Sparkle update-signing identity preserved.

Users on 2.12.x still need the one-time manual installation described in the 2.13.0 release because the bundle identifier changed. Users on 2.13.0 can update normally through Sparkle or download this DMG.
