import SwiftUI
import UIKit

/// 承载会话持有的 TerminalView（会话在后台时视图仍被保留，回来不丢内容）
struct TerminalContainer: UIViewRepresentable {
    let session: TerminalSession

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = session.theme.uiBackground
        attach(to: host)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if session.terminalView.superview !== uiView { attach(to: uiView) }
    }

    private func attach(to host: UIView) {
        let tv = session.terminalView
        tv.removeFromSuperview()
        tv.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            tv.topAnchor.constraint(equalTo: host.topAnchor),
            tv.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }
}

struct TerminalScreen: View {
    @ObservedObject var session: TerminalSession
    @EnvironmentObject var sessions: SessionManager
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showCompose = false
    @State private var showSnippets = false
    @State private var showInfo = false
    @State private var showThemes = false
    @State private var confirmClose = false

    private var theme: TerminalTheme { session.theme }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottomTrailing) {
                TerminalContainer(session: session)
                    .ignoresSafeArea(.container, edges: .bottom)
                overlays
            }
        }
        .background(theme.bgColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .statusBarHidden(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                _ = session.terminalView.becomeFirstResponder()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monoShowCompose)) { n in
            if n.object as? UUID == session.id { showCompose = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monoShowSnippets)) { n in
            if n.object as? UUID == session.id { showSnippets = true }
        }
        .sheet(isPresented: $showCompose) { ComposeSheet(session: session) }
        .sheet(isPresented: $showSnippets) { SnippetPicker(session: session) }
        .sheet(isPresented: $showInfo) { HostInfoSheet(host: session.host) }
        .sheet(isPresented: $showThemes) {
            NavigationStack {
                ScrollView { ThemeGrid(selection: Binding(get: { session.host.themeID }, set: { id in
                    session.applyTheme(id)
                    var h = session.host; h.themeID = id
                    store.upsert(h, password: nil)
                })) }
                .navigationTitle("配色主题").navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .alert("新的主机指纹", isPresented: Binding(get: { session.pendingHostKey != nil }, set: { if !$0 { session.pendingHostKey?.reply(false) } }),
               presenting: session.pendingHostKey) { p in
            Button("信任并连接") { p.reply(true) }
            Button("拒绝", role: .cancel) { p.reply(false) }
        } message: { p in
            Text("首次连接 \(p.host):\(p.port)\n\(p.keyType)\n\(p.fingerprint)\n\n确认这是你的服务器后再继续。")
        }
        .confirmationDialog("断开并关闭会话？", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("断开", role: .destructive) { closeSession() }
        } message: {
            Text(session.host.restore == .tmux ? "tmux 会话会继续在服务器上运行，下次连接自动接回。" : "未开启会话恢复，正在运行的程序（如 agent）会被终止。")
        }
    }

    // MARK: 顶栏（参考图：左侧返回/关闭胶囊，中间标题，右侧文件/写作胶囊）

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                barButton("chevron.left", label: "返回") { dismiss() }
                barButton("xmark", label: "断开") {
                    if case .connected = session.state { confirmClose = true } else { closeSession() }
                }
            }
            .glassCapsule()

            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(session.host.displayName)
                    .font(.headline)
                    .lineLimit(1)
                statusLine
            }
            .foregroundStyle(theme.isDark ? .white : .black)
            Spacer(minLength: 4)

            HStack(spacing: 0) {
                if session.host.proto == .ssh {
                    barButton("folder", label: "文件") {
                        sessions.path.append(Route.sftp(session.id))
                    }
                    .disabled(session.state != .connected)
                }
                barButton("square.and.pencil", label: "写作") { showCompose = true }
                Menu {
                    Button("命令片段", systemImage: "text.badge.star") { showSnippets = true }
                    Button("复制屏幕内容", systemImage: "doc.on.doc") { Clipboard.copy(session.terminalView.screenText()) }
                    Button("复制全部输出", systemImage: "doc.on.clipboard") { Clipboard.copy(session.terminalView.allText()) }
                    Divider()
                    Button("放大字号", systemImage: "plus.magnifyingglass") { bumpFont(1) }
                    Button("缩小字号", systemImage: "minus.magnifyingglass") { bumpFont(-1) }
                    Button("配色主题", systemImage: "paintpalette") { showThemes = true }
                    Divider()
                    Button("主机信息", systemImage: "info.circle") { showInfo = true }
                    Button("重新连接", systemImage: "arrow.clockwise") { session.reconnect() }
                    Button("清屏", systemImage: "eraser") { session.terminalView.feed(text: "\u{1b}[H\u{1b}[2J") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多")
            }
            .glassCapsule()
        }
        .foregroundStyle(theme.isDark ? .white : .black)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var statusLine: some View {
        switch session.state {
        case .connecting:
            HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("连接中") }
                .font(.caption2).foregroundStyle(.secondary)
        case .connected:
            if !session.title.isEmpty, session.title != session.host.displayName {
                Text(session.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        case .disconnected:
            Text("已断开").font(.caption2).foregroundStyle(.orange)
        }
    }

    private func barButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: 浮层

    @ViewBuilder private var overlays: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if !session.atBottom {
                Button {
                    session.terminalView.stopMomentum()
                    session.terminalView.scrollToBottom()
                    session.atBottom = true
                    Haptics.tap()
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(theme.isDark ? .white : .black)
                }
                .glassCircle()
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("回到底部")
            }
            if case .disconnected(let msg) = session.state {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.horizontal.circle").font(.title3).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("连接已断开").font(.subheadline.weight(.semibold))
                        if let msg { Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer(minLength: 8)
                    Button("重新连接") { session.reconnect() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: 460)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(16)
        .animation(.snappy, value: session.atBottom)
        .animation(.snappy, value: session.state)
    }

    private func bumpFont(_ d: Double) {
        settings.fontSize = max(8, min(30, settings.fontSize + d))
        session.refreshFont()
    }

    private func closeSession() {
        sessions.close(session)
        dismiss()
    }
}

struct ThemeGrid: View {
    @Binding var selection: String
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(TerminalTheme.all) { t in
                Button { selection = t.id; Haptics.tap() } label: { ThemeCard(theme: t, selected: selection == t.id) }
                    .buttonStyle(.plain)
            }
        }
        .padding()
    }
}
