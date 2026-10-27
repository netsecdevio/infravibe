import Foundation
import Security
import ServiceManagement

/// One-time migration from the pre-2.13.0 identity (`com.dynadobe.infraproxy`, `InfraProxy.app`)
/// to the current one (`com.dynadobe.infravibe`, `infravibe.app`).
///
/// macOS keys preferences, Keychain ACLs, TCC grants and login items to the bundle identifier, so
/// the renamed build is a different application to the system. Everything here is best effort and
/// non-fatal: a failed migration must never stop the app from launching, it only means the user
/// re-enters something. Original data is copied, never moved, so downgrading to 2.12.1 still works.
enum IdentityMigration {
    private static let legacyBundleID = "com.dynadobe.infraproxy"
    private static let currentBundleID = "com.dynadobe.infravibe"
    private static let marker = "IdentityMigration.2.13.0.completed"

    private static var supportRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    /// Call once, before any component reads Application Support or the Keychain.
    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: marker) else { return }
        var notes: [String] = []
        if let legacy = UserDefaults.standard.persistentDomain(forName: legacyBundleID) {
            notes.append(contentsOf: migrateDefaults(legacy, to: .standard))
        }
        notes.append(contentsOf: migrateSupportDirectory(root: supportRoot))
        notes.append(contentsOf: migrateKeychain())
        notes.append(contentsOf: retireLegacyApp())
        if !notes.isEmpty { NSLog("[infravibe] identity migration: %@", notes.joined(separator: "; ")) }
        // Every step is idempotent, so a partial failure (locked file, denied Keychain prompt) is retried
        // on the next launch instead of being recorded as done.
        if shouldMarkComplete(notes) { UserDefaults.standard.set(true, forKey: marker) }
    }

    /// Failure notes carry one of these phrases; anything else is a completed or skipped step.
    static let failurePhrases = ["failed", "could not"]

    static func shouldMarkComplete(_ notes: [String]) -> Bool {
        !notes.contains { note in failurePhrases.contains { note.contains($0) } }
    }

    // MARK: - Preferences

    /// Copies the legacy preferences domain (approved session workspaces, Sparkle state, window and
    /// panel settings). Keys already set under the new identity win, so a re-run never reverts a
    /// choice made after upgrading. Both sides are injectable for tests.
    /// Only the legacy app's own persistent domain is read, never global or registration defaults.
    static func migrateDefaults(_ legacy: [String: Any], to current: UserDefaults) -> [String] {
        var copied = 0
        for (key, value) in legacy where key != marker && current.object(forKey: key) == nil {
            current.set(value, forKey: key); copied += 1
        }
        return copied > 0 ? ["copied \(copied) preference(s)"] : []
    }

    // MARK: - Application Support

    /// Copies `Application Support/InfraProxy` to `Application Support/infravibe`.
    /// Carries AgentAccess.json (agent grants) and TerminalHistory/ (session scrollback).
    /// `root` is injectable so the copy rules can be exercised against a temporary directory in tests.
    static func migrateSupportDirectory(root: URL) -> [String] {
        let manager = FileManager.default
        let legacy = root.appendingPathComponent("InfraProxy", isDirectory: true)
        let current = root.appendingPathComponent("infravibe", isDirectory: true)
        guard manager.fileExists(atPath: legacy.path) else { return [] }
        // A case-insensitive volume may resolve both names to the same directory; nothing to do.
        if legacy.resolvingSymlinksInPath().standardizedFileURL == current.resolvingSymlinksInPath().standardizedFileURL {
            return ["support directory already shared (case-insensitive volume)"]
        }
        guard !manager.fileExists(atPath: current.path) else { return ["support directory already present, left untouched"] }
        // Copy into a staging directory and rename it into place, so an interrupted or failed copy
        // never leaves a partial `infravibe` directory that a later launch would accept as complete.
        let staging = root.appendingPathComponent(".infravibe-migrating", isDirectory: true)
        do {
            if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
            try manager.copyItem(at: legacy, to: staging)
            try manager.moveItem(at: staging, to: current)
            return ["copied support directory"]
        } catch {
            try? manager.removeItem(at: staging)
            return ["support directory copy failed: \(error.localizedDescription)"]
        }
    }

    // MARK: - Keychain

    /// Re-creates the DevOps monitor secret under the new service name.
    ///
    /// The legacy item's ACL names the old bundle, so macOS may show a one-time authorization
    /// prompt here even though both builds carry the same Developer ID. Denying it is survivable:
    /// the user re-enters the monitor credentials in Settings.
    private static func migrateKeychain() -> [String] {
        let account = "monitors"
        let legacyService = legacyBundleID + ".devops"
        let currentService = currentBundleID + ".devops"

        var exists: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: currentService,
                                     kSecAttrAccount as String: account]
        if SecItemCopyMatching(exists as CFDictionary, nil) == errSecSuccess {
            return ["keychain item already present, left untouched"]
        }

        exists[kSecAttrService as String] = legacyService
        exists[kSecReturnData as String] = true
        var value: CFTypeRef?
        let read = SecItemCopyMatching(exists as CFDictionary, &value)
        if read == errSecItemNotFound { return [] }
        guard read == errSecSuccess, let data = value as? Data else {
            return ["keychain read failed (OSStatus \(read)); re-enter DevOps credentials in Settings"]
        }

        let insert: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: currentService,
                                     kSecAttrAccount as String: account,
                                     kSecValueData as String: data]
        let write = SecItemAdd(insert as CFDictionary, nil)
        guard write == errSecSuccess else {
            return ["keychain write failed (OSStatus \(write)); re-enter DevOps credentials in Settings"]
        }
        return ["migrated keychain item"]
    }

    // MARK: - Legacy app bundle and login item

    /// Moves `InfraProxy.app` to the Trash so the machine cannot end up running both builds.
    ///
    /// A login item registered by the old bundle cannot be unregistered from here — `SMAppService`
    /// only addresses the calling app — but retiring the bundle makes that registration inert and
    /// macOS prunes it. If the old build launched at login, re-register this one so the behaviour
    /// the user chose survives the rename.
    private static func retireLegacyApp() -> [String] {
        let manager = FileManager.default
        let running = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        var notes: [String] = []

        for candidate in ["/Applications/InfraProxy.app",
                          manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/InfraProxy.app").path] {
            let url = URL(fileURLWithPath: candidate)
            guard manager.fileExists(atPath: url.path) else { continue }
            // Never trash ourselves: on a case-insensitive volume this path can resolve to the running bundle.
            guard url.resolvingSymlinksInPath().standardizedFileURL != running else { continue }
            guard legacyBundleIdentifier(at: url) == legacyBundleID else {
                notes.append("left \(candidate) alone (unexpected bundle identifier)")
                continue
            }
            do {
                try manager.trashItem(at: url, resultingItemURL: nil)
                notes.append("moved \(candidate) to Trash")
            } catch {
                notes.append("could not retire \(candidate): \(error.localizedDescription)")
            }
        }

        if !notes.isEmpty, SMAppService.mainApp.status != .enabled {
            do { try SMAppService.mainApp.register(); notes.append("re-registered login item") }
            catch { notes.append("login item re-registration failed: \(error.localizedDescription)") }
        }
        return notes
    }

    private static func legacyBundleIdentifier(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }
}
