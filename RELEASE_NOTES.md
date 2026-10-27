# infravibe 2.13.0 (build 18)

The app is now infravibe all the way down: `infravibe.app`, bundle identifier `com.dynadobe.infravibe`, settings in `~/Library/Application Support/infravibe`.

- **Install this version by hand once.** macOS and Sparkle treat a new bundle identifier as a different app, so 2.12.x shows this release as informational and links here instead of installing it. Download the DMG, drag infravibe to Applications, and launch it.
- On first launch infravibe copies your preferences, Application Support data (agent grants, terminal history) and the DevOps monitor Keychain item from the InfraProxy identity. Originals are copied, never moved, so 2.12.2 still runs if you go back. macOS may ask once to allow Keychain access; denying it only means re-entering monitor credentials.
- `InfraProxy.app` is moved to the Trash after a successful migration, and the login item is re-registered if the old app launched at login. Any step that fails is retried on the next launch.
- Build numbers continue one sequence across releases: 2.12.2 shipped as build 17, so 2.13.0 is build 18.

Signed and notarized Universal macOS application for Apple silicon and Intel. 2.12.2 remains available for rollback.
