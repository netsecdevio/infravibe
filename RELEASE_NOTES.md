# infravibe 2.13.0 (build 18)

A VibeTunnel-style native interface, a real browser Dashboard, safer headless Tailscale integration, and the completed infravibe identity migration.

## Identity migration

The app is now infravibe all the way down: `infravibe.app`, bundle identifier `com.dynadobe.infravibe`, and settings in `~/Library/Application Support/infravibe`.

- **Install this version by hand once.** macOS and Sparkle treat a new bundle identifier as a different app, so 2.12.x shows this release as informational and links here instead of installing it. Download the DMG, drag infravibe to Applications, and launch it.
- On first launch infravibe copies your preferences, Application Support data (agent grants and terminal history), and the DevOps monitor Keychain item from the InfraProxy identity. Originals are copied, never moved, so 2.12.2 still runs if you go back. macOS may ask once to allow Keychain access; denying it only means re-entering monitor credentials.
- `InfraProxy.app` is moved to the Trash only after all other migration steps succeed. Any failed step is retried on the next launch. The login item is not re-registered automatically; review and enable **Open infravibe at login** yourself in Settings if desired.
- Build numbers continue one sequence across releases: 2.12.2 shipped as build 17, so 2.13.0 is build 18.

## Dashboard and interface

- **Dashboard** now starts the local browser server when needed and opens the actual browser login page. It no longer opens the native server-settings page or embeds an access key in the URL.
- The native configuration page is named **Server**, with Start/Stop/Restart, port, workspace, tunnel, and access-key controls.
- Browser key management supports named generated keys and importing unencrypted OpenSSH or PKCS#8 Ed25519 private keys. Imported private keys stay in the browser as non-extractable CryptoKeys, are never sent to the host, and are cleared from the import form. Copy public key and Download produce the complete public key line with the key name as its comment.
- The menu-bar panel now follows VibeTunnel's compact layout: app icon and status badge, endpoint rows, grouped session content, and Dashboard / Settings / Quit actions.
- Main settings use native grouped forms and navigation titles. Window resizing, keyboard focus, and VoiceOver labels are improved.

## Tailscale

- Infravibe uses the installed daemon CLI directly. Status checks never launch the Tailscale GUI, its wrapper, or a symlink to it, so they do not recreate the macOS VPN On Demand profile.
- Tailnet DNS remains enabled. Background status refreshes stay current without relaunching the GUI client.
- Explicit Tailscale sign-in opens the authentication URL, supports cancellation and a 90-second timeout, and reports connection state clearly.
- Refresh coordination prevents stale authentication messages and repeated refresh loops.

## Validation and distribution

- Expanded regression coverage for identity migration, CLI validation, authentication URLs, process lifetime, refresh races, Dashboard startup, window sizing, and accessibility.
- Full Swift and browser integration suites pass.
- Signed and notarized Universal macOS application for Apple silicon and Intel, built against macOS 15.5 or later.

Previous release 2.12.2 remains available for rollback.
