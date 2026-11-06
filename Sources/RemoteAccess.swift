import Cocoa
import SwiftUI
import Combine

struct TailPeer: Decodable, Identifiable {
    let nodeID: String?
    enum CodingKeys: String, CodingKey { case nodeID = "ID", HostName, DNSName, TailscaleIPs, Online }
    let HostName: String?
    let DNSName: String?
    let TailscaleIPs: [String]?
    let Online: Bool?
    var id: String { nodeID ?? DNSName ?? HostName ?? address }
    var name: String { HostName ?? DNSName ?? "Device" }
    var address: String { TailscaleIPs?.first ?? "" }
}
struct TailStatus: Decodable {
    let backendState: String
    let selfNode: TailPeer?
    let peerMap: [String: TailPeer]?
    enum CodingKeys: String, CodingKey { case backendState = "BackendState", selfNode = "Self", peerMap = "Peer" }
    var connected: Bool { backendState == "Running" }
    var displayState: String {
        switch backendState {
        case "Running": return "Connected"
        case "NeedsLogin": return "Sign in required"
        case "Stopped": return "Stopped"
        default: return backendState.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }
    }
    var hostname: String { selfNode?.DNSName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? "" }
    var peers: [TailPeer] { (peerMap ?? [:]).values.sorted { ($0.Online == true ? 0 : 1, $0.name) < ($1.Online == true ? 0 : 1, $1.name) } }
}
enum RemoteProvider: String, CaseIterable, Identifiable {
    case tailscale = "Tailscale Serve", funnel = "Tailscale Funnel", cloudflare = "Cloudflare", ngrok = "ngrok"
    var id: String { rawValue }
    var isPublic: Bool { self != .tailscale }
}
enum RemoteCommands {
    /// Background status checks must use the daemon CLI. Invoking the GUI app
    /// executable can recreate its NetworkExtension VPN profile and On Demand policy.
    static func tailscaleActionTitle(connected: Bool, hasCLI: Bool, connecting: Bool = false) -> String {
        if connecting { return "Cancel" }
        return connected ? "Refresh" : (hasCLI ? "Connect Tailscale" : "Install Tailscale")
    }
    static func shouldProbeTailscale(background: Bool, tunnelRunning: Bool, lastProbe: Date, now: Date, minimumInterval: TimeInterval = 60) -> Bool {
        guard background else { return true }
        return now.timeIntervalSince(lastProbe) >= minimumInterval
    }
    static func executableCandidates(_ name: String, path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> [String] {
        let installed = ["/opt/homebrew/bin/" + name, "/usr/local/bin/" + name]
        guard name != "tailscale" else { return installed }
        return installed + path.split(separator: ":").map { String($0) + "/" + name }
    }
    static func isUsableTailscaleCLI(atPath path: String) -> Bool {
        let resolvedURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let isTailscaleAppBinary = resolvedURL.pathComponents.suffix(4) == ["Tailscale.app", "Contents", "MacOS", "Tailscale"]
        guard !isTailscaleAppBinary, FileManager.default.isExecutableFile(atPath: resolvedURL.path) else { return false }
        guard let data = try? Data(contentsOf: resolvedURL, options: [.mappedIfSafe]), data.starts(with: Data("#!".utf8)) else { return true }
        let header = String(decoding: data.prefix(8192), as: UTF8.self)
        return !header.contains("Tailscale.app/Contents/MacOS/Tailscale")
    }
    static func executable(_ name: String) -> String? {
        return executableCandidates(name).first { path in
            guard path.hasPrefix("/") else { return false }
            return name == "tailscale" ? isUsableTailscaleCLI(atPath: path) : FileManager.default.isExecutableFile(atPath: path)
        }
    }
    static func port(_ text: String, blocked: Set<Int>) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let port = Int(text), (1...65535).contains(port), !blocked.contains(port) else { return nil }
        return port
    }
    static func arguments(_ provider: RemoteProvider, port: Int) -> [String] {
        let target = "http://127.0.0.1:\(port)"
        switch provider {
        case .tailscale: return ["serve", "--https=8443", target]
        case .funnel: return ["funnel", "--https=8443", target]
        case .cloudflare: return ["tunnel", "--no-autoupdate", "--url", target]
        case .ngrok: return ["http", target, "--log=stdout", "--log-format=json", "--log-level=info", "--inspect=false"]
        }
    }
    static func portInUse(_ json: String) throws -> Bool {
        let root = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
        if root is NSNull { return false }
        guard let config = root as? [String: Any] else { throw NSError(domain: "RemoteAccess", code: 1) }
        // Foreground Serve sessions can be nested under Foreground in current clients.
        func occupied(_ object: [String: Any]) -> Bool {
            if (object["TCP"] as? [String: Any])?["8443"] != nil { return true }
            if (object["Web"] as? [String: Any])?.keys.contains(where: { $0.hasSuffix(":8443") }) == true { return true }
            return (object["Foreground"] as? [String: [String: Any]] ?? [:]).values.contains(where: occupied)
        }
        return occupied(config)
    }
    static func authenticationURL(in output: String) -> URL? {
        for line in output.components(separatedBy: .newlines) {
            let candidate = line.trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: candidate), url.scheme == "https", url.host == "login.tailscale.com", url.path.hasPrefix("/a/"), url.port == nil || url.port == 443, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { continue }
            return url
        }
        return nil
    }
    static func endpoint(in output: String, provider: RemoteProvider) -> URL? {
        if provider == .ngrok {
            return output.split(separator: "\n").compactMap { line -> URL? in
                guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], row["msg"] as? String == "started tunnel",
                      let value = row["url"] as? String, let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
                return url
            }.last
        }
        let pattern = provider == .cloudflare ? #"https://[a-z0-9]+(?:-[a-z0-9]+)*\.trycloudflare\.com(?=[\s/]|$)"# : #"https://[a-zA-Z0-9.-]+\.ts\.net:8443(?=[\s/]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)), let range = Range(match.range, in: output) else { return nil }
        return URL(string: String(output[range]))
    }
}

// Starts the daemon CLI only when the user explicitly asks to connect. The
// authentication URL is opened as soon as the CLI emits it.
final class TailscaleConnector: ObservableObject {
    @Published private(set) var connecting = false
    var onAuthenticationURL: ((URL) -> Void)?
    var onFinish: (() -> Void)?
    private var process: Process?
    private var control: CommandControl?
    private var output = ""
    private var openedAuthenticationURL = false
    private var startupTimeout: DispatchWorkItem?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 90) {
        self.timeout = timeout
    }

    func start(executable: String) {
        guard process == nil else { return }
        output = ""
        openedAuthenticationURL = false
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["up", "--accept-dns=true"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let control = CommandControl()
        self.process = process
        self.control = control
        connecting = true
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let chunk = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                guard let self, self.process === process else { return }
                self.output = String((self.output + chunk).suffix(8000))
                if !self.openedAuthenticationURL, let url = RemoteCommands.authenticationURL(in: self.output) {
                    self.openedAuthenticationURL = true
                    self.onAuthenticationURL?(url)
                }
            }
        }
        process.terminationHandler = { [weak self] ended in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self, self.process === ended else { return }
                self.process = nil
                self.control = nil
                self.startupTimeout?.cancel()
                self.startupTimeout = nil
                self.connecting = false
                self.onFinish?()
            }
        }
        do {
            try process.run()
            control.attach(process)
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.process === process else { return }
                control.cancel()
            }
            startupTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + self.timeout, execute: timeout)
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            startupTimeout?.cancel()
            startupTimeout = nil
            self.process = nil
            self.control = nil
            connecting = false
            onFinish?()
        }
    }

    func stop() { startupTimeout?.cancel(); control?.cancel() }
}

// Own only the foreground process started here. Never kill or reset another app's tunnels.
final class SharedTunnel: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var ready = false
    @Published private(set) var url: URL?
    @Published private(set) var message = "Not sharing"
    @Published private(set) var provider: RemoteProvider?
    @Published private(set) var localPort: Int?
    private var process: Process?
    private var control: CommandControl?
    private var output = ""
    private var startupTimeout: DispatchWorkItem?
    private var timedOut = false
    func start(executable: String, arguments: [String], provider: RemoteProvider, localPort: Int? = nil) {
        guard process == nil else { return }
        self.provider = provider
        self.localPort = localPort
        timedOut = false
        ready = false
        url = nil
        output = ""
        message = "Starting…"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let control = CommandControl()
        self.process = process
        self.control = control
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let chunk = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                guard let self, self.process === process else { return }
                self.output = String((self.output + chunk).suffix(16000))
                if let endpoint = RemoteCommands.endpoint(in: self.output, provider: provider) { self.url = endpoint }
                if provider == .cloudflare {
                    if chunk.contains("failed to serve tunnel connection") { self.ready = false; self.message = "Reconnecting…" }
                    if self.url != nil && chunk.contains("Registered tunnel connection") { self.ready = true }
                } else if provider == .ngrok { self.ready = self.url != nil }
                else if self.url != nil && self.output.contains("Press Ctrl+C") { self.ready = true }
                if self.ready { self.message = provider.isPublic ? "Public sharing" : "Private tailnet sharing"; self.startupTimeout?.cancel() }
            }
        }
        process.terminationHandler = { [weak self] ended in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self, self.process === ended else { return }
                self.process = nil
                self.control = nil
                self.running = false
                self.ready = false
                self.url = nil
                self.localPort = nil
                self.startupTimeout?.cancel()
                self.message = self.timedOut ? "Setup timed out. Check provider permissions or tunnel configuration." : control.isCancelled ? "Stopped" : "Tunnel exited (\(ended.terminationStatus)). Check provider access and the local service."
            }
        }
        do {
            try process.run()
            control.attach(process)
            running = true
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.process === process, !self.ready else { return }
                self.timedOut = true
                self.stop()
                self.message = "Setup timed out. Check the provider's HTTPS/Funnel permissions or tunnel configuration."
            }
            startupTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            self.control = nil
            message = "Could not start: \(error.localizedDescription)"
        }
    }
    func stop() { startupTimeout?.cancel(); control?.cancel(); ready = false; url = nil; message = "Stopping…" }
}

final class RemoteAccessModel: ObservableObject {
    @Published private(set) var tailscale: TailStatus?
    @Published private(set) var tailMessage = "Checking Tailscale…"
    @Published private(set) var tailscalePath: String?
    @Published private(set) var cloudflarePath: String?
    @Published private(set) var ngrokPath: String?
    @Published private(set) var ngrokMessage = "Checking ngrok…"
    @Published private(set) var refreshing = false
    @Published var localPort = ""
    @Published private(set) var preparing = false
    @Published var error: String?
    let tailTunnel = SharedTunnel()
    let cloudTunnel = SharedTunnel()
    let ngrokTunnel = SharedTunnel()
    let tailscaleConnector = TailscaleConnector()
    var readyURLs: [URL] { [tailTunnel, cloudTunnel, ngrokTunnel].filter(\.ready).compactMap(\.url) }
    var tailscaleActionTitle: String { RemoteCommands.tailscaleActionTitle(connected: tailscale?.connected == true, hasCLI: tailscalePath != nil, connecting: tailscaleConnector.connecting) }
    func stopDashboardTunnels(port: Int) { generation += 1; preparing = false; for tunnel in [tailTunnel, cloudTunnel, ngrokTunnel] where tunnel.localPort == port { tunnel.stop() } }
    private var timer: Timer?
    private var generation = 0
    private var lastTailscaleProbe = Date.distantPast
    private var refreshQueued = false
    private var tunnelChanges = Set<AnyCancellable>()
    init(openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        for tunnel in [tailTunnel, cloudTunnel, ngrokTunnel] {
            tunnel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &tunnelChanges)
        }
        tailscaleConnector.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &tunnelChanges)
        tailscaleConnector.onAuthenticationURL = { [weak self] url in
            self?.tailMessage = "Complete Tailscale sign-in in your browser"
            openURL(url)
        }
        tailscaleConnector.onFinish = { [weak self] in self?.refresh() }
    }
    func start() {
        refresh()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refresh(background: true) }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    deinit { timer?.invalidate() }
    func refresh() { refresh(background: false) }
    func refresh(background: Bool) {
        guard !refreshing else { refreshQueued = true; return }
        refreshing = true
        let probe = RemoteCommands.shouldProbeTailscale(background: background, tunnelRunning: tailTunnel.running, lastProbe: lastTailscaleProbe, now: Date())
        if probe { lastTailscaleProbe = Date() }
        let tail = RemoteCommands.executable("tailscale")
        tailscalePath = tail
        cloudflarePath = RemoteCommands.executable("cloudflared")
        let ngrok = RemoteCommands.executable("ngrok")
        ngrokPath = ngrok
        DispatchQueue.global(qos: .utility).async {
            let ngrokConfig = ngrok.map { OperationsCommand.run($0, ["config", "check"], timeout: 5) }
            let result = (probe ? tail : nil).map { OperationsCommand.run($0, ["status", "--json"], timeout: 5) }
            let status = result?.code == 0 ? try? JSONDecoder().decode(TailStatus.self, from: Data((result?.output ?? "").utf8)) : nil
            DispatchQueue.main.async {
                self.ngrokMessage = ngrok == nil ? "Not installed" : ngrokConfig?.code == 0 ? "Agent configuration available" : "Complete ngrok account setup"
                if probe {
                    self.tailscale = status
                    self.tailMessage = tail == nil ? "Not installed" : (status.map(\.displayState) ?? "Unavailable — connect Tailscale to continue")
                }
                self.refreshing = false
                if self.refreshQueued {
                    self.refreshQueued = false
                    self.refresh()
                }
            }
        }
    }
    func connectTailscale() {
        if tailscaleConnector.connecting {
            tailMessage = "Cancelling Tailscale sign-in…"
            tailscaleConnector.stop()
            return
        }
        if tailscale?.connected == true { refresh(); return }
        guard let path = tailscalePath else {
            NSWorkspace.shared.open(URL(string: "https://tailscale.com/download/mac")!)
            return
        }
        tailMessage = "Starting Tailscale sign-in…"
        tailscaleConnector.start(executable: path)
    }
    func share(_ provider: RemoteProvider, blockedPorts: Set<Int>) {
        guard !preparing, let port = RemoteCommands.port(localPort, blocked: blockedPorts) else {
            error = "Choose a local web service port (1–65535). Configured SOCKS and HTTP proxy ports cannot be shared."; return
        }
        let tunnel = provider == .cloudflare ? cloudTunnel : provider == .ngrok ? ngrokTunnel : tailTunnel
        guard !tunnel.running else { return }
        guard let path = provider == .cloudflare ? cloudflarePath : provider == .ngrok ? ngrokPath : tailscalePath else { error = "Install the provider's command-line tool first."; return }
        guard (provider == .cloudflare || provider == .ngrok) || tailscale?.connected == true else { error = "Connect Tailscale first."; return }
        let alert = NSAlert()
        alert.messageText = provider.isPublic ? "Share this service publicly?" : "Share this service with your tailnet?"
        alert.informativeText = "\(provider.rawValue) will expose http://127.0.0.1:\(port). " + (provider.isPublic ? "People on the Internet with the URL can reach it; your web service must provide its own authentication." : "Access follows your Tailscale policy.") + " Stop sharing here to close this tunnel."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Start Sharing")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        preparing = true
        let requestedGeneration = generation
        DispatchQueue.global(qos: .utility).async {
            var failure: String?
            if provider == .tailscale || provider == .funnel {
                let status = OperationsCommand.run(path, ["serve", "status", "--json"], timeout: 5)
                if status.code != 0 { failure = "Could not verify existing Tailscale Serve configuration." }
                else {
                    do { if try RemoteCommands.portInUse(status.output) { failure = "Tailscale HTTPS port 8443 is already in use. Existing shares have been preserved." } }
                    catch { failure = "Unrecognized Tailscale Serve configuration; no changes were made." }
                }
            } else if provider == .cloudflare {
                let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cloudflared")
                if ["config.yml", "config.yaml"].contains(where: { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) {
                    failure = "An existing Cloudflare tunnel configuration is present. Manage that tunnel in Cloudflare; Quick Tunnel setup will not modify it."
                }
            }
            if provider == .ngrok, OperationsCommand.run(path, ["config", "check"], timeout: 5).code != 0 { failure = "Complete ngrok agent setup in your account dashboard, then refresh. Existing configuration was not changed." }
            let errorMessage = failure
            DispatchQueue.main.async {
                guard self.generation == requestedGeneration else { return }
                self.preparing = false
                if let errorMessage { self.error = errorMessage; return }
                tunnel.start(executable: path, arguments: RemoteCommands.arguments(provider, port: port), provider: provider, localPort: port)
            }
        }
    }
    func shutdown() { generation += 1; preparing = false; timer?.invalidate(); tailscaleConnector.stop(); tailTunnel.stop(); cloudTunnel.stop(); ngrokTunnel.stop() }
}

struct TunnelControls: View {
    let title: String
    @ObservedObject var tunnel: SharedTunnel
    var body: some View {
        if tunnel.running {
            HStack {
                Text(tunnel.message).foregroundStyle(tunnel.ready ? .green : .secondary)
                Spacer()
                if let url = tunnel.url, tunnel.ready { Link("Open", destination: url); Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) } }
                Button("Stop", action: tunnel.stop)
            }.font(.caption)
        } else { Text("\(title) · \(tunnel.message)").font(.caption).foregroundStyle(.secondary) }
    }
}
struct RemoteAccessView: View {
    @ObservedObject var model: RemoteAccessModel
    @ObservedObject var manager: InfravibeManager
    @ObservedObject var browser: BrowserDashboard
    @State private var provider: RemoteProvider = .tailscale
    @State private var targetDashboard = true
    @State private var confirmRotation = false
    private var blockedPorts: Set<Int> { Set([Int(manager.configuration.teleport.localPort), Int(manager.configuration.httpProxy.port)].compactMap { $0 }) }
    var body: some View {
        VibePage("Remote") {
                SettingsSection("Authentication") {
                    LabeledContent("Authentication method", value: "SSH browser key or access key")
                    Text("Every browser connection authenticates, including localhost and provider tunnels. Browser sessions expire after 8 hours. Anyone with the key can open a shell as your Mac user.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Copy access key", action: browser.copyKey).disabled(!browser.running)
                        Button("Rotate key…") { confirmRotation = true }.disabled(!browser.running)
                        Spacer()
                        Button("Open local dashboard", action: browser.openBrowser).disabled(!browser.running)
                    }
                }
                SettingsSection("Trusted browser keys") { BrowserKeySettings(model: manager.browserKeys) }
                SettingsSection("Inbound destination") {
                    Picker("Forward incoming traffic to", selection: $targetDashboard) {
                        Text("infravibe dashboard & terminal").tag(true)
                        Text("Another local web service").tag(false)
                    }
                    if targetDashboard {
                        HStack { Text(browser.localURL?.absoluteString ?? "Browser server is stopped").font(.system(.caption, design: .monospaced)); Spacer(); if !browser.running { Button("Start browser server", action: browser.start).disabled(browser.starting) } }
                    } else { TextField("Local service port, e.g. 3000", text: $model.localPort).frame(width: 220) }
                    Text("Remote browser → provider tunnel → this Mac. Teleport SOCKS and HTTP forward proxies remain outbound connections in the Outbound tab.").font(.caption).foregroundStyle(.secondary)
                }
                SettingsSection("Tailscale integration") {
                    HStack {
                        Label(model.tailMessage, systemImage: "circle.fill").foregroundStyle(model.tailscale?.connected == true ? .green : (model.tailscale != nil ? .orange : .secondary))
                        Spacer()
                        if model.tailscaleConnector.connecting { ProgressView().controlSize(.small) }
                        Button(model.tailscaleActionTitle, action: model.connectTailscale)
                    }
                    if let hostname = model.tailscale?.hostname, !hostname.isEmpty { Text(hostname).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    Picker("Access", selection: $provider) { Text("Private · tailnet only").tag(RemoteProvider.tailscale); Text("Public · Funnel").tag(RemoteProvider.funnel) }.pickerStyle(.segmented)
                    HStack { Text("Incoming HTTPS on port 8443").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Start inbound access…") { share(provider) }.disabled(model.preparing || model.tailTunnel.running || model.tailscale?.connected != true || (targetDashboard && !browser.running)) }
                    TunnelControls(title: "Tailscale", tunnel: model.tailTunnel)
                    Text("Uses the installed Tailscale daemon directly and never launches the GUI app. Private Serve access follows your tailnet policy; the infravibe browser key is still required.").font(.caption).foregroundStyle(.secondary)
                }
                SettingsSection("ngrok integration") {
                    HStack { Text(model.ngrokMessage); Spacer(); Link("Account setup", destination: URL(string: "https://dashboard.ngrok.com/get-started/setup/macos")!) }
                    Text("Uses your installed ngrok agent and its existing account configuration. Public inbound HTTPS; request inspection is disabled.").font(.caption).foregroundStyle(.secondary)
                    HStack { TunnelControls(title: "ngrok", tunnel: model.ngrokTunnel); Spacer(); Button("Start ngrok…") { share(.ngrok) }.disabled(model.preparing || model.ngrokTunnel.running || (targetDashboard && !browser.running)) }
                }
                SettingsSection("Cloudflare integration") {
                    HStack { Text(model.cloudflarePath == nil ? "Install cloudflared to get started" : "Cloudflare Quick Tunnel available"); Spacer(); Link("Provider setup", destination: URL(string: "https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/")!) }
                    Text("Creates a temporary public inbound URL. Existing named tunnel configuration is preserved.").font(.caption).foregroundStyle(.secondary)
                    HStack { TunnelControls(title: "Cloudflare", tunnel: model.cloudTunnel); Spacer(); Button("Start Quick Tunnel…") { share(.cloudflare) }.disabled(model.preparing || model.cloudTunnel.running || (targetDashboard && !browser.running)) }
                }
                HStack { Text("Tailnet devices").font(.headline); Spacer(); Button("Refresh providers", action: model.refresh).disabled(model.refreshing) }
                ForEach(model.tailscale?.peers ?? []) { peer in
                    HStack { Circle().fill(peer.Online == true ? Color.green : Color.secondary).frame(width: 7, height: 7); Text(peer.name); Spacer(); Text(peer.address).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }.padding(.horizontal, 8)
                }
        }
        .alert("Inbound access", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert("Rotate browser access key?", isPresented: $confirmRotation) { Button("Cancel", role: .cancel) {}; Button("Rotate and disconnect", role: .destructive, action: browser.rotateKey) } message: { Text("All browser logins and terminals will be disconnected. Sign in again with the new key.") }
    }
    private func share(_ provider: RemoteProvider) {
        if targetDashboard { guard browser.running else { return }; model.localPort = String(browser.activePort) }
        model.share(provider, blockedPorts: blockedPorts)
    }
}
