import SwiftUI
import UIKit
import SwiftTerm
import Citadel

/// 一个终端会话：持有传输层与终端视图，切到别的页面时继续在后台接收输出。
@MainActor
final class TerminalSession: ObservableObject, Identifiable, HostKeyPrompter {
    enum State: Equatable {
        case connecting, connected, disconnected(String?)
    }

    let id = UUID()
    @Published var host: Host
    @Published var state: State = .connecting
    /// 标题单独放：Claude Code 会高频刷新终端标题（转圈动画），不能让它重绘整个终端页
    let titleModel = TitleModel()
    var title: String { titleModel.title }
    @Published var atBottom = true
    @Published var pendingHostKey: PendingHostKey?
    let startedAt = Date()

    struct PendingHostKey: Identifiable {
        let id = UUID()
        let host: String
        let port: Int
        let keyType: String
        let fingerprint: String
        let reply: (Bool) -> Void
    }

    private(set) var transport: TerminalTransport?
    let terminalView: MonoTerminalView
    private(set) var bar: KeyboardBar!
    private var delegateProxy: Proxy!
    private var reconnecting = false

    var sshTransport: SSHTransport? { transport as? SSHTransport }
    var theme: TerminalTheme { TerminalTheme.find(host.themeID) }

    init(host: Host) {
        self.host = host
        let settings = AppSettings.shared
        terminalView = MonoTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), font: settings.uiFont())
        delegateProxy = Proxy(owner: self)
        terminalView.terminalDelegate = delegateProxy
        configureView()
        connect()
    }

    // MARK: 视图配置

    private func configureView() {
        let settings = AppSettings.shared
        let t = theme
        let v = terminalView
        v.nativeBackgroundColor = t.uiBackground
        v.nativeForegroundColor = t.uiForeground
        v.caretColor = t.uiCursor
        v.installColors(t.termColors)
        v.backgroundColor = t.uiBackground
        v.keyboardAppearance = t.isDark ? .dark : .light
        v.changeScrollback(max(1000, settings.scrollback))
        v.setCursorStyle(Self.cursorStyle(settings.cursorStyle, blink: settings.cursorBlink))
        if settings.useMetal { try? v.setUseMetal(true) }
        v.onFontSizeChange = { size in AppSettings.shared.fontSize = Double(size) }
        v.contentInsetAdjustmentBehavior = .never
        v.onUserScroll = { [weak self] in self?.setAtBottom(false) }

        bar = KeyboardBar(terminal: v, agentRow: settings.agentBar)
        bar.onAction = { [weak self] a in self?.handle(a) }
        v.inputAccessoryView = bar
    }

    static func cursorStyle(_ s: String, blink: Bool) -> CursorStyle {
        switch s {
        case "bar": return blink ? .blinkBar : .steadyBar
        case "underline": return blink ? .blinkUnderline : .steadyUnderline
        default: return blink ? .blinkBlock : .steadyBlock
        }
    }

    func setAtBottom(_ v: Bool) {
        if atBottom != v { atBottom = v }
    }

    func applyTheme(_ id: String) {
        host.themeID = id
        configureView()
    }

    func refreshFont() {
        terminalView.font = AppSettings.shared.uiFont()
    }

    // MARK: 连接

    func connect() {
        if DemoData.active {
            state = .connected
            titleModel.update("claude")
            terminalView.feed(text: DemoData.terminalSample)
            return
        }
        state = .connecting
        let dims = terminalView.terminalDimensions
        let cols = max(dims.cols, 20), rows = max(dims.rows, 5)

        let t: TerminalTransport
        switch host.proto {
        case .ssh:
            let ssh = SSHTransport(host: host, prompter: self)
            ssh.bootstrap = bootstrapCommand()
            t = ssh
        case .telnet:
            t = TelnetTransport(host: host)
        }
        let sender = terminalView.feedSender
        t.onData = { data in
            // 后台线程直接喂给解析器
            sender.feed(byteArray: ArraySlice([UInt8](data)))
        }
        t.onClose = { [weak self] err in
            Task { @MainActor in self?.transportClosed(err) }
        }
        transport = t
        if !reconnecting {
            terminalView.feed(text: "\u{1b}[2m正在连接 \(host.username)@\(host.address)…\u{1b}[0m\r\n")
        }
        Task {
            do {
                try await t.start(cols: cols, rows: rows)
                guard self.transport === t else { t.close(); return }
                self.state = .connected
                self.reconnecting = false
                AppStore.shared.markConnected(host.id)
                Haptics.success()
            } catch {
                guard self.transport === t else { return }
                self.state = .disconnected(error.localizedDescription)
                self.terminalView.feed(text: "\r\n\u{1b}[31m✕ \(error.localizedDescription)\u{1b}[0m\r\n")
            }
        }
    }

    /// shell 就绪后自动输入的命令：会话恢复（tmux/screen）+ agent 启动
    func bootstrapCommand() -> String? {
        var agentCmd = host.agent == .custom ? host.startupCommand : (host.agent.command ?? "")
        if host.agent != .custom, !host.startupCommand.isEmpty {
            agentCmd = agentCmd.isEmpty ? host.startupCommand : host.startupCommand + " && " + agentCmd
        }
        let name = host.effectiveTmuxName
        switch host.restore {
        case .none:
            return agentCmd.isEmpty ? nil : agentCmd
        case .tmux:
            var cmd = " exec tmux new-session -A -s \(shellQuote(name))"
            // -A：会话已存在时直接接回（忽略启动命令），不存在才新建并启动 agent
            if !agentCmd.isEmpty { cmd += " " + shellQuote(agentCmd + "; exec $SHELL") }
            if AppSettings.shared.tmuxTuning {
                // 鼠标滚轮进入回滚、5 万行历史、每次滚轮 1 行（配合惯性滑动更跟手）、Esc 无延迟（Claude Code 中断更灵敏）
                cmd += " \\; set -g mouse on \\; set -g history-limit 50000 \\; set -s escape-time 10"
                cmd += " \\; bind -T copy-mode WheelUpPane send -N1 -X scroll-up \\; bind -T copy-mode WheelDownPane send -N1 -X scroll-down"
                cmd += " \\; bind -T copy-mode-vi WheelUpPane send -N1 -X scroll-up \\; bind -T copy-mode-vi WheelDownPane send -N1 -X scroll-down"
            }
            return cmd
        case .screen:
            if agentCmd.isEmpty { return " exec screen -D -RR \(shellQuote(name))" }
            return " screen -ls \(shellQuote(name)) | grep -q \(shellQuote(name)) && exec screen -D -RR \(shellQuote(name)) || exec screen -S \(shellQuote(name)) sh -c \(shellQuote(agentCmd + "; exec $SHELL"))"
        }
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func transportClosed(_ err: Error?) {
        if case .disconnected = state { return }
        let msg = err?.localizedDescription
        state = .disconnected(msg)
        terminalView.feed(text: "\r\n\u{1b}[33m— 连接已断开\(msg.map { "：\($0)" } ?? "") —\u{1b}[0m\r\n")
        // tmux/screen 会话下自动重连一次，回到原来的 agent 现场
        if AppSettings.shared.autoReconnect, host.restore != .none, UIApplication.shared.applicationState == .active {
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if case .disconnected = self.state { self.reconnect() }
            }
        }
    }

    func reconnect() {
        transport?.onClose = nil
        transport?.close()
        reconnecting = true
        terminalView.feed(text: "\r\n\u{1b}[2m正在重新连接…\u{1b}[0m\r\n")
        connect()
    }

    func disconnect() {
        transport?.onClose = nil
        transport?.close()
        transport = nil
        state = .disconnected(nil)
    }

    // MARK: 输入

    func send(_ bytes: [UInt8]) {
        guard let transport else { return }
        if case .connected = state {} else if bytes == [0x0d] || bytes == [0x0a] {
            // 已断开时按回车 = 重连
            reconnect(); return
        }
        transport.write(Data(bytes))
        if !atBottom || !terminalView.isAtBottom { terminalView.scrollToBottom(); setAtBottom(true) }
    }

    func send(text: String) { send(Array(text.utf8)) }

    /// 以粘贴方式发送（agent 输入多行时不会被逐行执行）
    func paste(_ text: String, thenReturn: Bool) {
        terminalView.pasteText(text)
        if thenReturn {
            Task {
                try? await Task.sleep(nanoseconds: 60_000_000)
                self.send([0x0d])
            }
        }
    }

    func handle(_ a: KeyboardBar.Action) {
        switch a {
        case .bytes(let b): send(b)
        case .text(let t): send(text: t)
        case .toggleCtrl:
            terminalView.controlModifier.toggle()
            bar.setCtrl(terminalView.controlModifier)
        case .toggleAlt:
            terminalView.metaModifier.toggle()
            bar.setAlt(terminalView.metaModifier)
        case .arrow(let d):
            switch d {
            case .up: terminalView.sendKeyUp()
            case .down: terminalView.sendKeyDown()
            case .left: terminalView.sendKeyLeft()
            case .right: terminalView.sendKeyRight()
            }
        case .compose: NotificationCenter.default.post(name: .monoShowCompose, object: id)
        case .snippets: NotificationCenter.default.post(name: .monoShowSnippets, object: id)
        case .paste:
            if let s = UIPasteboard.general.string { terminalView.pasteText(s) }
        case .hideKeyboard: terminalView.resignFirstResponder()
        case .copyScreen: Clipboard.copy(terminalView.screenText())
        }
    }

    func run(_ snippet: Snippet) {
        if snippet.asPaste {
            paste(snippet.command, thenReturn: snippet.autoReturn)
        } else {
            send(text: snippet.command + (snippet.autoReturn ? "\r" : ""))
        }
    }

    // MARK: HostKeyPrompter

    func confirmNewHostKey(host: String, port: Int, keyType: String, fingerprint: String) async -> Bool {
        await withCheckedContinuation { cont in
            pendingHostKey = PendingHostKey(host: host, port: port, keyType: keyType, fingerprint: fingerprint) { [weak self] ok in
                self?.pendingHostKey = nil
                cont.resume(returning: ok)
            }
        }
    }

    // MARK: Delegate 代理

    final class Proxy: NSObject, TerminalViewDelegate {
        weak var owner: TerminalSession?
        init(owner: TerminalSession) { self.owner = owner }

        /// SwiftTerm 在主线程回调；同步处理，绝不经由 Task 转一手（会乱序）
        private func onMain(_ body: @escaping (TerminalSession) -> Void) {
            if Thread.isMainThread {
                MainActor.assumeIsolated { if let o = self.owner { body(o) } }
            } else {
                DispatchQueue.main.async { if let o = self.owner { body(o) } }
            }
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onMain { $0.transport?.resize(cols: newCols, rows: newRows) }
        }
        func setTerminalTitle(source: TerminalView, title: String) {
            onMain { o in o.titleModel.update(title) }
        }
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            onMain { $0.send(bytes) }
        }
        func scrolled(source: TerminalView, position: Double) {
            onMain { o in o.setAtBottom(o.terminalView.isAtBottom) }
        }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func bell(source: TerminalView) {
            Task { @MainActor in Haptics.soft() }
        }
        func clipboardCopy(source: TerminalView, content: Data) {
            if let s = String(data: content, encoding: .utf8) {
                Task { @MainActor in Clipboard.copy(s) }
            }
        }
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) { Task { @MainActor in UIApplication.shared.open(url) } }
        }
    }
}

/// 终端标题（节流，避免转圈动画导致频繁刷新）
@MainActor
final class TitleModel: ObservableObject {
    @Published private(set) var title = ""
    private var pending: String?
    private var scheduled = false

    func update(_ t: String) {
        let clean = t.trimmingCharacters(in: .whitespaces)
        pending = clean
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.scheduled = false
            if let p = self.pending, p != self.title { self.title = p }
            self.pending = nil
        }
    }

}

extension Notification.Name {
    static let monoShowCompose = Notification.Name("mono.showCompose")
    static let monoShowSnippets = Notification.Name("mono.showSnippets")
}

/// 管理所有活动会话（「会话」页）。
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()
    @Published var sessions: [TerminalSession] = []
    @Published var path = NavigationPath()

    func open(_ host: Host) -> TerminalSession {
        let s = TerminalSession(host: host)
        sessions.append(s)
        return s
    }

    func session(_ id: UUID) -> TerminalSession? { sessions.first { $0.id == id } }

    func close(_ s: TerminalSession) {
        s.disconnect()
        sessions.removeAll { $0.id == s.id }
    }

    func closeAll() {
        sessions.forEach { $0.disconnect() }
        sessions.removeAll()
    }
}
