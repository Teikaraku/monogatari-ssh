import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var sessions: SessionManager
    @EnvironmentObject var store: AppStore
    let openTab: (AppTab) -> Void

    var body: some View {
        List {
            ForEach(sessions.sessions) { s in
                SessionRow(session: s) {
                    openTab(.home)
                    DispatchQueue.main.async { sessions.show(s) }
                }
                .swipeActions {
                    Button(role: .destructive) { sessions.close(s) } label: { Label("断开", systemImage: "xmark") }
                    Button { s.reconnect() } label: { Label("重连", systemImage: "arrow.clockwise") }.tint(.blue)
                }
            }
        }
        .overlay {
            if sessions.sessions.isEmpty {
                ContentUnavailableView("没有活动会话", systemImage: "apple.terminal",
                                       description: Text("在主页打开一台主机后，会话会显示在这里，切换页面不会断开。"))
            }
        }
        .navigationTitle("会话")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(store.hosts) { h in
                        Button {
                            openTab(.home)
                            DispatchQueue.main.async { sessions.connect(h) }
                        } label: {
                            Label(h.displayName, systemImage: h.icon.symbol)
                        }
                    }
                } label: { Image(systemName: "plus") }
                .disabled(store.hosts.isEmpty)
                .accessibilityLabel("新建会话")
            }
            if !sessions.sessions.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("全部断开", systemImage: "xmark.circle", role: .destructive) { sessions.closeAll() }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
    }
}

struct SessionRow: View {
    @ObservedObject var session: TerminalSession
    let open: () -> Void

    var body: some View {
        HStack(spacing: 14) {
                HostAvatar(host: session.host, size: 46)
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(dotColor).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                            .offset(x: 3, y: 3)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.displayTitle).font(.title3.weight(.medium)).foregroundStyle(.primary)
                        if session.host.restore == .tmux {
                            Text(session.host.effectiveTmuxName)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                    if let label = session.agentStatus.label, session.state == .connected {
                        HStack(spacing: 4) {
                            Label(label, systemImage: session.agentStatus.symbol)
                            if let since = session.workingSince {
                                Text(since, style: .timer).monospacedDigit()
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(session.agentStatus.color)
                    }
                    Text(subtitle).font(.subheadline.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    if session.agentStatus == .needsInput && session.state == .connected {
                        HStack(spacing: 8) {
                            quick("1 允许", [0x31], .green)
                            quick("2 始终", [0x32], .blue)
                            quick("拒绝", [0x1b], .red)
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer()
                Text(session.startedAt, style: .relative)
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { open() }
            .accessibilityAddTraits(.isButton)
    }

    /// 不进终端直接回复 agent 的确认提示
    private func quick(_ title: String, _ bytes: [UInt8], _ color: Color) -> some View {
        Button {
            session.send(bytes)
            Haptics.success()
        } label: {
            Text(title).font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(color)
        .controlSize(.small)
    }

    var dotColor: Color {
        switch session.state {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        }
    }

    var subtitle: String {
        switch session.state {
        case .connecting: return "连接中…"
        case .connected:
            if !session.lastLine.isEmpty { return session.lastLine }
            return session.title.isEmpty ? "\(session.host.username)@\(session.host.address)" : session.title
        case .disconnected(let m): return m ?? "已断开"
        }
    }
}
