import SwiftUI

@main
struct MonogatariSSHApp: App {
    @StateObject private var store = AppStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var sessions = SessionManager.shared

    init() {
        DemoData.installIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(sessions)
                .overlay(ToastOverlay())
        }
    }
}

enum AppTab: Hashable { case home, sessions, settings }

struct RootView: View {
    @EnvironmentObject var sessions: SessionManager
    @EnvironmentObject var settings: AppSettings
    @State private var tab: AppTab = DemoData.initialTab

    var body: some View {
        if DemoData.screen == "edit" {
            HostEditView(host: AppStore.shared.hosts.dropFirst().first)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $sessions.path) {
                HomeView()
                    .navigationDestination(for: Route.self) { $0.destination }
            }
            .tabItem { Label("主页", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                SessionsView(openTab: { tab = $0 })
            }
            .tabItem { Label("会话", systemImage: "apple.terminal.fill") }
            .badge(sessions.sessions.count)
            .tag(AppTab.sessions)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
        }
        .onChange(of: sessions.sessions.contains { $0.state == .connected }) { _, connected in
            UIApplication.shared.isIdleTimerDisabled = connected && settings.keepAwake
        }
    }
}

/// 主页导航栈的路由
enum Route: Hashable {
    case hosts, keys, knownHosts, snippets, transfers
    case terminal(UUID)
    case sftp(UUID)

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .hosts: HostListView()
        case .keys: KeyListView()
        case .knownHosts: KnownHostsView()
        case .snippets: SnippetsView()
        case .transfers: TransfersView()
        case .terminal(let id):
            if let s = SessionManager.shared.session(id) { TerminalScreen(session: s) }
            else { ContentUnavailableView("会话已关闭", systemImage: "xmark.circle") }
        case .sftp(let id):
            if let s = SessionManager.shared.session(id) { SFTPBrowser(session: s) }
            else { ContentUnavailableView("会话已关闭", systemImage: "xmark.circle") }
        }
    }
}

extension SessionManager {
    /// 打开主机：新建会话并推入终端页
    func connect(_ host: Host) {
        let s = open(host)
        path.append(Route.terminal(s.id))
    }

    func show(_ s: TerminalSession) {
        path.append(Route.terminal(s.id))
    }
}
