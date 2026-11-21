import SwiftUI
import UIKit
import SafariServices

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
    @State private var showSearch = false
    @State private var showOutput = false
    @State private var showTmux = false
    @State private var showSlash = false
    @State private var showHistory = false
    @State private var keyboardVisible = false
    @State private var editingHost = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var webURL: WebURL?
    @AppStorage("terminalTipsSeen") private var tipsSeen = false
    @State private var showStatus = false

    private var theme: TerminalTheme { session.theme }

    var body: some View {
        dialogs(sheets(receivers(core)))
    }

    private var core: some View {
        VStack(spacing: 0) {
            topBar
            if showSearch {
                TerminalSearchBar(session: session) { showSearch = false; refocus() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack(alignment: .bottomTrailing) {
                TerminalContainer(session: session)
                    .ignoresSafeArea(.container, edges: .bottom)
                overlays
                if !keyboardVisible && session.state == .connected && session.agentStatus == .needsInput {
                    HStack(spacing: 8) {
                        quickReply("1 允许", [0x31], .green)
                        quickReply("2 始终", [0x32], .blue)
                        quickReply("拒绝", [0x1b], .red)
                    }
                    .padding(8)
                    .glassCapsule()
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if !keyboardVisible && session.state == .connected {
                    Button {
                        _ = session.terminalView.becomeFirstResponder()
                        Haptics.tap()
                    } label: {
                        Image(systemName: "keyboard")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .foregroundStyle(theme.isDark ? .white : .black)
                    }
                    .glassCircle()
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("显示键盘")
                }
            }
            .animation(.snappy, value: keyboardVisible)
            .animation(.snappy, value: session.agentStatus)
        }
        .background(theme.bgColor.ignoresSafeArea())
        .background(shortcuts)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .statusBarHidden(false)
        .onDisappear {
            if sessions.visibleID == session.id { sessions.visibleID = nil }
        }
        .onAppear {
            sessions.visibleID = session.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                _ = session.terminalView.becomeFirstResponder()
            }
        }
    }

    private func receivers<V: View>(_ v: V) -> some View {
        v
        .onReceive(NotificationCenter.default.publisher(for: .monoShowCompose)) { n in
            if n.object as? UUID == session.id { showCompose = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monoShowSnippets)) { n in
            if n.object as? UUID == session.id { showSnippets = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monoShowSearch)) { n in
            if n.object as? UUID == session.id { withAnimation(.snappy) { showSearch = true } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .monoShowHistory)) { n in
            if n.object as? UUID == session.id { showHistory = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monoOpenURL)) { n in
            if n.object as? UUID == session.id, let url = n.userInfo?["url"] as? URL { webURL = WebURL(url: url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monoShowSlash)) { n in
            if n.object as? UUID == session.id { showSlash = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monoShowOutput)) { n in
            if n.object as? UUID == session.id { showOutput = true }
        }
    }

    private func sheets<V: View>(_ v: V) -> some View {
        v
        .sheet(isPresented: $showSlash, onDismiss: refocus) { SlashPalette(session: session) }
        .sheet(isPresented: $showOutput, onDismiss: refocus) { OutputBrowser(session: session) }
        .sheet(item: $webURL, onDismiss: refocus) { w in SafariView(url: w.url).ignoresSafeArea() }
        .sheet(isPresented: $showTmux, onDismiss: refocus) { TmuxManagerSheet(session: session) }
        .sheet(isPresented: $showStatus, onDismiss: refocus) { ServerStatusSheet(session: session) }
        .sheet(isPresented: $showHistory, onDismiss: refocus) { HistorySheet(session: session) }
        .sheet(isPresented: $showCompose, onDismiss: refocus) { ComposeSheet(session: session) }
        .sheet(isPresented: $showSnippets, onDismiss: refocus) { SnippetPicker(session: session) }
        .sheet(isPresented: $editingHost) { HostEditView(host: store.host(session.host.id)) }
        .sheet(isPresented: $showInfo, onDismiss: refocus) { HostInfoSheet(host: session.host) }
        .sheet(isPresented: $showThemes, onDismiss: refocus) {
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
    }

    private func dialogs<V: View>(_ v: V) -> some View {
        v
        .alert(session.pendingHostKey?.oldFingerprint == nil ? "新的主机指纹" : "⚠️ 主机指纹已变化", isPresented: Binding(get: { session.pendingHostKey != nil }, set: { if !$0 { session.pendingHostKey?.reply(false) } }),
               presenting: session.pendingHostKey) { p in
            if p.oldFingerprint == nil {
                Button("信任并连接") { p.reply(true) }
                Button("拒绝", role: .cancel) { p.reply(false) }
            } else {
                Button("更新指纹并连接", role: .destructive) { p.reply(true) }
                Button("断开", role: .cancel) { p.reply(false) }
            }
        } message: { p in
            if let old = p.oldFingerprint {
                Text("\(p.host):\(p.port) 的指纹与上次不同，可能是服务器重装，也可能是中间人攻击。\n\n旧：\(old)\n新：\(p.fingerprint)\n\n确认是你重装了服务器再继续。")
            } else {
                Text("首次连接 \(p.host):\(p.port)\n\(p.keyType)\n\(p.fingerprint)\n\n确认这是你的服务器后再继续。")
            }
        }
        .alert("重命名会话", isPresented: $renaming) {
            TextField(session.host.displayName, text: $renameText)
            Button("确定") { session.label = renameText.trimmingCharacters(in: .whitespaces) }
            Button("取消", role: .cancel) {}
        } message: { Text("例如「前端重构」「写测试」，方便区分并行的 agent") }
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
            Menu {
                Section("切换会话") {
                    ForEach(sessions.sessions) { s in
                        Button {
                            guard s.id != session.id else { return }
                            switchTo(s)
                        } label: {
                            Label("\(s.displayTitle)\(s.host.restore == .tmux ? " · " + s.host.effectiveTmuxName : "")\(s.agentStatus.label.map { " · " + $0 } ?? "")",
                                  systemImage: s.id == session.id ? "checkmark" : s.agentStatus.symbol)
                        }
                    }
                }
                Button("重命名会话", systemImage: "pencil") {
                    renameText = session.label
                    renaming = true
                }
                if session.host.proto == .ssh {
                    Button("新开同一主机的会话", systemImage: "plus.rectangle.on.rectangle") {
                        var h = session.host
                        if h.restore == .tmux { h.tmuxSession = h.effectiveTmuxName + "-\(Int.random(in: 2...99))" }
                        let s = sessions.open(h)
                        switchTo(s)
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Text(session.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                        if sessions.sessions.count > 1 {
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).opacity(0.6)
                        }
                    }
                    statusLine
                }
                .foregroundStyle(theme.isDark ? .white : .black)
            }
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
                    Button("搜索输出", systemImage: "magnifyingglass") { withAnimation(.snappy) { showSearch = true } }
                    Button("选择 / 浏览输出", systemImage: "text.viewfinder") { showOutput = true }
                    if session.host.proto == .ssh {
                        Divider()
                        Button("tmux 会话 / 并行 agent", systemImage: "square.stack.3d.up") { showTmux = true }
                        Button("服务器状态", systemImage: "gauge.with.dots.needle.33percent") { showStatus = true }
                        Button("命令历史", systemImage: "clock.arrow.circlepath") { showHistory = true }
                    }
                    let fwd = session.host.forwards.filter(\.enabled)
                    if !fwd.isEmpty {
                        Section("端口转发 · 在浏览器打开") {
                            ForEach(fwd) { f in
                                Button("localhost:\(f.localPort) → \(f.remotePort)", systemImage: "safari") {
                                    if let url = URL(string: "http://localhost:\(f.localPort)") { webURL = WebURL(url: url) }
                                }
                            }
                        }
                    }
                    Button("复制 agent 最后回复", systemImage: "bubble.left.and.text.bubble.right") {
                        if let t = session.lastAgentReply() { Clipboard.copy(t) } else { Toast.shared.show("没有找到 agent 回复") }
                    }
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
            if let label = session.agentStatus.label {
                HStack(spacing: 4) {
                    Circle().fill(session.agentStatus.color).frame(width: 6, height: 6)
                    Text(label)
                    if let since = session.workingSince {
                        Text(since, style: .timer).monospacedDigit()
                    }
                    if let mode = session.agentMode {
                        Text("· " + mode).foregroundStyle(mode == "跳过权限" ? .red : .purple)
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            } else {
                TitleLine(model: session.titleModel, hostName: session.host.displayName)
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
            if !tipsSeen && session.state == .connected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("终端小贴士").font(.subheadline.weight(.semibold))
                    Group {
                        Label("双指捏合调整字号", systemImage: "arrow.up.left.and.arrow.down.right")
                        Label("长按选择文字；「⋯ → 选择/浏览输出」更方便复制", systemImage: "hand.tap")
                        Label("点顶部主机名切换 / 新开会话", systemImage: "chevron.down.circle")
                        Label("ctrl / alt 点一下锁定一次，再按字母即组合键", systemImage: "control")
                        Label("tmux / vim 中单指滑动即可带惯性滚动", systemImage: "hand.draw")
                    }
                    .font(.caption)
                    Button("知道了") { withAnimation { tipsSeen = true } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(14)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
            if session.needsMouseHint {
                HStack(spacing: 10) {
                    Image(systemName: "computermouse").foregroundStyle(.purple)
                    Text("tmux 未开启鼠标滚动").font(.subheadline)
                    Button("开启") { session.enableTmuxMouse() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button { session.needsMouseHint = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !session.atBottom {
                Button {
                    session.terminalView.stopMomentum()
                    session.terminalView.scrollToBottom()
                    session.setAtBottom(true)
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
                    if session.host.proto == .ssh, store.host(session.host.id) != nil {
                        Button("编辑") { editingHost = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button("重新连接") {
                        if let latest = store.host(session.host.id) {
                            // 用最新配置重连，但保留本会话的 tmux 名
                            var h = latest
                            h.tmuxSession = session.host.tmuxSession
                            h.restore = session.host.restore
                            session.host = h
                        }
                        session.reconnect()
                    }
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

    private func quickReply(_ title: String, _ bytes: [UInt8], _ color: Color) -> some View {
        Button {
            session.send(bytes)
            Haptics.success()
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(color)
    }

    /// 硬件键盘快捷键（iPad / 蓝牙键盘），按住 ⌘ 时系统会列出
    private var shortcuts: some View {
        Group {
            Button("搜索") { withAnimation(.snappy) { showSearch = true } }.keyboardShortcut("f", modifiers: .command)
            Button("清屏") { session.terminalView.feed(text: "\u{1b}[H\u{1b}[2J"); session.send([0x0c]) }.keyboardShortcut("k", modifiers: .command)
            Button("放大字号") { bumpFont(1) }.keyboardShortcut("+", modifiers: .command)
            Button("缩小字号") { bumpFont(-1) }.keyboardShortcut("-", modifiers: .command)
            Button("写作") { showCompose = true }.keyboardShortcut("e", modifiers: [.command, .shift])
            Button("片段") { showSnippets = true }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("断开") { confirmClose = true }.keyboardShortcut("w", modifiers: .command)
            Button("上一个会话") { cycle(-1) }.keyboardShortcut("[", modifiers: .command)
            Button("下一个会话") { cycle(1) }.keyboardShortcut("]", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cycle(_ d: Int) {
        let all = sessions.sessions
        guard all.count > 1, let i = all.firstIndex(where: { $0.id == session.id }) else { return }
        switchTo(all[(i + d + all.count) % all.count])
    }

    /// 替换导航栈顶部的终端页，不堆叠
    private func switchTo(_ s: TerminalSession) {
        Haptics.tap()
        if !sessions.path.isEmpty { sessions.path.removeLast() }
        DispatchQueue.main.async { sessions.path.append(Route.terminal(s.id)) }
    }

    private func refocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if session.state == .connected { _ = session.terminalView.becomeFirstResponder() }
        }
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

/// 只有这一小块观察终端标题，标题刷新不会重绘终端页
private struct TitleLine: View {
    @ObservedObject var model: TitleModel
    let hostName: String
    var body: some View {
        if !model.title.isEmpty, model.title != hostName {
            Text(model.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}


struct WebURL: Identifiable { let url: URL; var id: String { url.absoluteString } }

/// 应用内浏览器：保持 app 在前台，端口转发不会因进入后台而断开
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController.Configuration()
        c.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: c)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
