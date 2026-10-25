import Foundation

/// Resolves the executable used to launch the local HTTP proxy.
///
/// The configured path is user-supplied and commonly points at something that
/// cannot be executed -- most often the npm *package directory*
/// (`/opt/homebrew/lib/node_modules/http-proxy-to-socks`) rather than the
/// `hpts` launcher inside it. `Process.run()` reports those cases as
/// "you don't have permission", which reads like a macOS privacy prompt the
/// user is supposed to approve. There is nothing to approve: the path is
/// simply not an executable file. This type turns that into a precise,
/// actionable diagnosis before the process is ever spawned.
enum HttpProxyExecutable {

    /// Why a configured path cannot be launched, and what to do about it.
    enum Problem: Equatable {
        case missing(path: String)
        case directory(path: String, suggestion: String?)
        case notExecutable(path: String)

        /// Short headline for the alert.
        var title: String {
            switch self {
            case .missing: return "HTTP Proxy Program Not Found"
            case .directory: return "HTTP Proxy Path Is a Folder"
            case .notExecutable: return "HTTP Proxy Program Is Not Executable"
            }
        }

        /// Plain description of the real cause -- never "permission denied".
        var explanation: String {
            switch self {
            case .missing(let path):
                return "Nothing exists at \(path)."
            case .directory(let path, _):
                return "\(path) is a folder, not a program. macOS reports this as a permission error, but no permission can fix it -- the path has to point at the launcher itself."
            case .notExecutable(let path):
                return "\(path) exists but is not marked executable."
            }
        }

        /// The concrete next step the app can take for the user.
        var remedy: Remedy {
            switch self {
            case .directory(_, .some(let suggestion)):
                return .useInstead(path: suggestion)
            case .missing, .directory:
                return .install(command: "brew install node && npm install -g http-proxy-to-socks")
            case .notExecutable(let path):
                return .makeExecutable(path: path)
            }
        }
    }

    enum Remedy: Equatable {
        /// A working executable was found; offer to save it as the setting.
        case useInstead(path: String)
        /// Nothing usable on this machine; show the install command.
        case install(command: String)
        /// The file is right but needs the executable bit.
        case makeExecutable(path: String)
    }

    enum Outcome: Equatable {
        case ready(path: String)
        case problem(Problem)
    }

    /// Directories searched for a working `hpts` when the configured path fails.
    static let searchPaths = [
        "/opt/homebrew/bin/hpts",
        "/usr/local/bin/hpts",
        "/opt/homebrew/lib/node_modules/http-proxy-to-socks/bin/hpts.js",
        "/usr/local/lib/node_modules/http-proxy-to-socks/bin/hpts.js"
    ]

    /// Checks the configured path and, when it cannot be launched, names the
    /// real problem and the best available replacement.
    ///
    /// - Parameters:
    ///   - configuredPath: the value from Settings.
    ///   - probe: injectable file probe, for tests. Returns
    ///     (exists, isDirectory, isExecutable) for a path.
    static func resolve(
        configuredPath: String,
        probe: (String) -> (exists: Bool, isDirectory: Bool, isExecutable: Bool) = HttpProxyExecutable.probeFileSystem
    ) -> Outcome {
        let path = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return .problem(.missing(path: "(no path set)"))
        }

        let state = probe(path)
        if state.exists && !state.isDirectory && state.isExecutable {
            return .ready(path: path)
        }

        if state.exists && state.isDirectory {
            return .problem(.directory(path: path, suggestion: firstWorkingAlternative(near: path, probe: probe)))
        }
        if state.exists {
            return .problem(.notExecutable(path: path))
        }
        if let alternative = firstWorkingAlternative(near: path, probe: probe) {
            return .problem(.directory(path: path, suggestion: alternative))
        }
        return .problem(.missing(path: path))
    }

    /// Looks inside an npm package directory first, then the usual bin paths.
    static func firstWorkingAlternative(
        near path: String,
        probe: (String) -> (exists: Bool, isDirectory: Bool, isExecutable: Bool)
    ) -> String? {
        let insidePackage = ["bin/hpts.js", "bin/hpts", "hpts"].map { (path as NSString).appendingPathComponent($0) }
        for candidate in insidePackage + searchPaths where candidate != path {
            let state = probe(candidate)
            if state.exists && !state.isDirectory && state.isExecutable {
                return candidate
            }
        }
        return nil
    }

    static func probeFileSystem(_ path: String) -> (exists: Bool, isDirectory: Bool, isExecutable: Bool) {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = manager.fileExists(atPath: path, isDirectory: &isDirectory)
        return (exists, isDirectory.boolValue, exists && manager.isExecutableFile(atPath: path))
    }
}
