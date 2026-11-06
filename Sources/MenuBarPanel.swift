import Cocoa
import SwiftUI

enum InterfaceTheme: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
}
enum DashboardTab: String, CaseIterable {
    case devops, connections, browser, remote, cloud, advanced, agents, notifications, about
    var title: String {
        switch self {
        case .devops: return "DevOps"
        case .connections: return "Outbound"
        case .browser: return "Server"
        case .remote: return "Remote"
        case .cloud: return "Cloud"
        case .advanced: return "Settings"
        case .agents: return "Agents"
        case .notifications: return "Notifications"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .devops: return "hammer"
        case .connections: return "network"
        case .browser: return "server.rack"
        case .remote: return "point.3.connected.trianglepath.dotted"
        case .cloud: return "cloud"
        case .advanced: return "gearshape.2"
        case .agents: return "person.badge.key"
        case .notifications: return "bell"
        case .about: return "info.circle"
        }
    }
}

private enum MenuStyle {
    static let width: CGFloat = 384
    static let animation: Double = 0.15
}

private struct PanelAction: View {
    let title: String
    let icon: String
    var secondary = false
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hovered ? Color(NSColor.controlBackgroundColor).opacity(0.7) : Color.clear)
                        .scaleEffect(hovered ? 1.04 : 1.0))
        }
        .buttonStyle(.plain)
        .foregroundStyle(secondary ? .secondary : .primary)
        .onHover { value in withAnimation(.easeInOut(duration: MenuStyle.animation)) { hovered = value } }
    }
}

private struct StatusBadge: View {
    let running: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(running ? Color.green : Color.secondary).frame(width: 6, height: 6)
            Text(running ? "Running" : "Stopped").font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(running ? .green : .secondary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill((running ? Color.green : Color.secondary).opacity(0.1)))
        .overlay(Capsule().stroke((running ? Color.green : Color.secondary).opacity(0.3), lineWidth: 0.5))
    }
}

private struct EndpointRow: View {
    let icon: String
    let label: String
    let value: String
    let url: URL?
    @State private var hovered = false
    @State private var copied = false
    @FocusState private var copyFocused: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.green).frame(width: 14)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            if let url {
                Button { NSWorkspace.shared.open(url) } label: {
                    Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.green).underline(hovered)
                }.buttonStyle(.plain)
            } else {
                Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.green)
            }
            Spacer(minLength: 2)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url?.absoluteString ?? value, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc").font(.system(size: 10)).foregroundStyle(.green)
            }
            .buttonStyle(.plain).help(copied ? "Copied" : "Copy address")
            .focused($copyFocused)
            .accessibilityLabel("Copy address")
            .opacity(hovered || copyFocused || copied ? 1 : 0)
        }
        .lineLimit(1)
        .onHover { value in withAnimation(.easeInOut(duration: MenuStyle.animation)) { hovered = value } }
    }
}

private struct MenuSectionHeader: View {
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if let count { Text("(\(count))").font(.system(size: 11)).foregroundStyle(.tertiary) }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}

private struct MenuNavigationRow: View {
    let title: String
    let icon: String
    let status: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? Color.accentColor.opacity(0.1) : Color.clear).padding(.horizontal, 4))
        .onHover { value in withAnimation(.easeInOut(duration: MenuStyle.animation)) { hovered = value } }
    }
}

struct MenuBarPanel: View {
    @ObservedObject var manager: InfravibeManager
    @ObservedObject var operations: OperationsModel
    @ObservedObject var remote: RemoteAccessModel
    @AppStorage("interfaceTheme") private var theme: InterfaceTheme = .system
    @Environment(\.colorScheme) private var colorScheme
    private var online: Int { operations.connections.filter(\.listening).count }
    private var sessions: Int { operations.connections.reduce(0) { $0 + $1.sessions.count } }
    private func open(_ tab: DashboardTab) { manager.closePanel(); manager.openDashboard(tab) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 24, height: 24).cornerRadius(4)
                    Text("infravibe").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    StatusBadge(running: manager.browserDashboard.running)
                }
                if let url = manager.browserDashboard.localURL {
                    EndpointRow(icon: "server.rack", label: "Local:", value: url.absoluteString, url: url)
                }
                if remote.tailscale?.connected == true, let hostname = remote.tailscale?.hostname, !hostname.isEmpty {
                    EndpointRow(icon: "shield", label: "Tailscale:", value: hostname, url: remote.tailTunnel.ready ? remote.tailTunnel.url : nil)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(LinearGradient(colors: [Color(NSColor.controlBackgroundColor).opacity(colorScheme == .dark ? 0.6 : 1), Color(NSColor.controlBackgroundColor).opacity(colorScheme == .dark ? 0.3 : 0.8)], startPoint: .top, endPoint: .bottom))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    MenuSectionHeader(title: "Infrastructure")
                    MenuNavigationRow(title: "Outbound proxies", icon: "network", status: "\(online) listeners · \(sessions) sessions") { open(.connections) }
                    HStack {
                        Text("Teleport").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(teleportStatus).font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 12).padding(.bottom, 6)
                    Divider().padding(.vertical, 4)
                    RemoteOverview(browser: manager.browserDashboard, remote: remote) { manager.closePanel(); manager.browserDashboard.openDashboard() }
                    Divider().padding(.vertical, 4)
                    MenuSectionHeader(title: "Monitoring")
                    DevOpsMenuSummary(model: operations.devops) { open(.devops) }
                }
            }.frame(maxHeight: 420)
            Divider()
            HStack(spacing: 8) {
                PanelAction(title: "Dashboard", icon: "square.grid.2x2") { manager.closePanel(); manager.browserDashboard.openDashboard() }
                PanelAction(title: "Settings", icon: "gearshape", secondary: true) { manager.closePanel(); manager.showSettings() }
                Spacer()
                PanelAction(title: "Quit", icon: "power", secondary: true, action: manager.quitApp)
            }.padding(.horizontal).padding(.vertical, 12)
        }
        .frame(width: MenuStyle.width)
        .background(.regularMaterial)
        .environment(\.colorScheme, theme.colorScheme ?? colorScheme)
    }

    private var teleportStatus: String {
        if operations.expiry == nil { return "Sign in to view expiry" }
        if operations.expiry! <= operations.now { return "Expired · Log in" }
        return TeleportExpiry.label(operations.expiry, now: operations.now) + " remaining"
    }
}

private struct RemoteOverview: View {
    @ObservedObject var browser: BrowserDashboard
    @ObservedObject var remote: RemoteAccessModel
    var open: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MenuSectionHeader(title: "Terminal sessions", count: browser.sessions.count)
            if browser.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("No active sessions").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Open Dashboard", action: open).buttonStyle(.link).font(.system(size: 11))
                }.frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                ForEach(browser.sessions.prefix(6), id: \.self) { id in
                    MenuNavigationRow(title: String(id.prefix(8)), icon: "terminal", status: "Running", action: open)
                }
            }
            CompactTunnel(tunnel: remote.tailTunnel)
            CompactTunnel(tunnel: remote.cloudTunnel)
            CompactTunnel(tunnel: remote.ngrokTunnel)
        }
    }
}

private struct CompactTunnel: View {
    @ObservedObject var tunnel: SharedTunnel
    var body: some View {
        if tunnel.running {
            HStack(spacing: 6) {
                Circle().fill(tunnel.ready ? Color.green : Color.orange).frame(width: 5, height: 5)
                Text(tunnel.provider?.rawValue ?? "Tunnel").font(.system(size: 10, weight: .medium))
                if let url = tunnel.url, tunnel.ready {
                    Link(url.host ?? url.absoluteString, destination: url).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy remote URL")
                } else {
                    Text(tunnel.message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.padding(.horizontal, 12).padding(.vertical, 4)
        }
    }
}
