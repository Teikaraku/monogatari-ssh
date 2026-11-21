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
    /// shell 通过 OSC 7 上报的当前目录
    var currentDirectory: String?

    /// 终端当前所在目录：tmux 用 pane_current_path，否则 OSC 7
    func resolveWorkingDirectory() async -> String? {
        if host.restore == .tmux, let t = sshTransport,
           let out = try? await t.exec("tmux display -p -t '\(host.effectiveTmuxName.replacingOccurrences(of: "'", with: ""))' '#{pane_current_path}' 2>/dev/null; true") {
            let p = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.hasPrefix("/") { return p }
        }
        return currentDirectory
    }

    /// 用户给会话起的名字（并行多个 agent 时区分用）
    @Published var label: String = "" { didSet { SessionManager.shared.persistSoon() } }
    var displayTitle: String { label.isEmpty ? host.displayName : label }
    @Published var state: State = .connecting
    /// 标题单独放：Claude Code 会高频刷新终端标题（转圈动画），不能让它重绘整个终端页
    let titleModel = TitleModel()
    var title: String { titleModel.title }
    @Published var atBottom = true
    /// 等待确认的多行粘贴
    @Published var pendingPaste: String?
    /// tmux 未开鼠标滚动时提示
    @Published var needsMouseHint = false
    @Published var pendingHostKey: PendingHostKey?
    let startedAt = Date()

    struct PendingHostKey: Identifiable {
        let id = UUID()
        let host: String
        let port: Int
        let keyType: String
        let fingerprint: String
        var oldFingerprint: String? = nil
        let reply: (Bool) -> Void
    }

    private(set) var transport: TerminalTransport?
    let terminalView: MonoTerminalView
    private(set) var bar: KeyboardBar!
    private var delegateProxy: Proxy!
    private var reconnecting = false
    private(set) var wasConnectedOnce = false
    @Published private(set) var agentStatus: AgentStatus = .unknown
    /// 本轮开始工作的时间（用于显示已工作时长）
    @Published private(set) var workingSince: Date?
    /// Claude Code 当前模式（计划 / 自动接受 / 跳过权限），nil = 普通
    @Published private(set) var agentMode: String?
    private var statusTimer: Timer?
    /// 最近一行有意义的输出（会话列表预览用）
    @Published private(set) var lastLine = ""
    private var oscObservation: TerminalOscObservation?

    var sshTransport: SSHTransport? { transport as? SSHTransport }
    var theme: TerminalTheme { TerminalTheme.find(host.themeID) }

    init(host: Host) {
        self.host = host
        let settings = AppSettings.shared
        terminalView = MonoTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), font: settings.uiFont())
        delegateProxy = Proxy(owner: self)
        terminalView.terminalDelegate = delegateProxy
        configureView()
        observeNotifications()
        connect()
    }

    /// agent 通过 OSC 9 / 777 / 99 发出的通知 → 系统通知（app 在后台时）
    private func observeNotifications() {
        let name = host.displayName
        let key = id.uuidString
        oscObservation = terminalView.observeOscEvents { ev in
            guard [9, 99, 777].contains(ev.code) else { return }
            Task { @MainActor in
                guard let parsed = Notifier.parse(code: ev.code, payload: ev.payload) else { return }
                Notifier.post(title: parsed.0 ?? name, body: parsed.1.isEmpty ? "有新消息" : parsed.1, key: key)
            }
        }
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
        v.suppressArrowScroll = host.restore == .tmux
        v.onNeedsMouseMode = { [weak self] in
            guard let self, !self.needsMouseHint else { return }
            self.needsMouseHint = true
        }
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

    // MARK: Agent 状态识别

    private func startStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollStatus() }
        }
        statusTimer?.tolerance = 0.5
    }

    private func pollStatus() {
        guard case .connected = state else { return }
        let rows = terminalView.screenText().split(separator: "\n").map(String.init)
        let tail = rows.suffix(14)
        let joined = tail.joined(separator: "\n").lowercased()
        let new = AgentStatus.detect(tail: joined)
        let mode: String? = joined.contains("plan mode on") ? "计划模式"
            : joined.contains("accept edits on") ? "自动接受"
            : joined.contains("bypass permissions on") ? "跳过权限" : nil
        if mode != agentMode { agentMode = mode }
        if let line = rows.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.contains("─") && !$0.contains("━") }) {
            let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: " │|╭╮╰╯>"))
            if clean != lastLine { lastLine = String(clean.prefix(120)) }
        }
        guard new != agentStatus else { return }
        let old = agentStatus
        agentStatus = new
        workingSince = new == .working ? (old == .working ? workingSince : Date()) : nil
        // 工作 → 等待确认 / 空闲：前台且没在看这个会话时弹应用内提示
        if old == .working, !Notifier.appInBackground, SessionManager.shared.visibleID != id,
           new == .needsInput || new == .idle {
            Toast.shared.show("\(host.displayName)：\(new == .needsInput ? "需要确认" : "任务完成")")
            Haptics.success()
        }
        // 工作 → 等待确认 / 空闲：提醒（app 在后台时）
        if old == .working {
            switch new {
            case .needsInput: Notifier.post(title: host.displayName, body: "需要你的确认：" + lastLine, key: id.uuidString + ".status")
            case .idle: Notifier.post(title: host.displayName, body: "任务已完成", key: id.uuidString + ".status")
            default: break
            }
        }
    }

    /// 提取 Claude Code 最后一条回复（以 ⏺ 开头的段落，直到输入框）
    func lastAgentReply() -> String? {
        let lines = terminalView.allText().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // 最后一个「⏺ 文本」（排除工具调用如 ⏺ Bash(…) / Read(…)）
        guard let start = lines.lastIndex(where: { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("⏺") else { return false }
            let body = t.dropFirst().trimmingCharacters(in: .whitespaces)
            return !(body.range(of: #"^[A-Za-z]+\("#, options: .regularExpression) != nil)
        }) else { return nil }
        var out: [String] = []
        for l in lines[start...] {
            let t = l.trimmingCharacters(in: .whitespaces)
            if !out.isEmpty && (t.hasPrefix("╭") || t.hasPrefix("⏺") || t.hasPrefix("> ") || t.hasPrefix("✻") || t.hasPrefix("·")) { break }
            var line = l
            if let r = line.range(of: "⏺") { line.removeSubrange(line.startIndex..<r.upperBound) }
            out.append(line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression))
        }
        // 去掉公共缩进与首尾空行
        while out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
        let indent = out.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
        let text = out.map { String($0.dropFirst(min(indent, $0.prefix(while: { $0 == " " }).count))) }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// 设置变化后同步到已打开的终端
    func applyTerminalSettings() {
        let st = AppSettings.shared
        terminalView.changeScrollback(max(1000, st.scrollback))
        terminalView.setCursorStyle(Self.cursorStyle(st.cursorStyle, blink: st.cursorBlink))
    }

    /// 设置变化后重建键盘辅助栏
    func rebuildBar() {
        bar = KeyboardBar(terminal: terminalView, agentRow: AppSettings.shared.agentBar)
        bar.onAction = { [weak self] a in self?.handle(a) }
        terminalView.inputAccessoryView = bar
        terminalView.reloadInputViews()
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
            terminalView.feed(text: host.alias == "Box" ? DemoData.permissionSample : DemoData.terminalSample)
            startStatusPolling()
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
                self.wasConnectedOnce = true
                self.startStatusPolling()
                Notifier.requestIfNeeded()
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
                cmd += " \\; set -g mouse on \\; set -g history-limit 50000 \\; set -s escape-time 10 \\; set -g set-clipboard on"
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
        statusTimer?.invalidate()
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
        case .bytes(let b): send(applyModifiers(b))
        case .text(let t): send(applyModifiers(Array(t.utf8)))
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
            guard let s = UIPasteboard.general.string, !s.isEmpty else { return }
            // 普通 shell（未开 bracketed paste）里粘贴多行会逐行立即执行：先确认
            if s.contains("\n") && !terminalView.terminalStateSnapshot().bracketedPasteMode {
                pendingPaste = s
            } else {
                terminalView.pasteText(s)
            }
        case .hideKeyboard: terminalView.resignFirstResponder()
        case .copyScreen: Clipboard.copy(terminalView.screenText())
        case .search: NotificationCenter.default.post(name: .monoShowSearch, object: id)
        case .selectMode: NotificationCenter.default.post(name: .monoShowOutput, object: id)
        case .slashPalette: NotificationCenter.default.post(name: .monoShowSlash, object: id)
        case .history: NotificationCenter.default.post(name: .monoShowHistory, object: id)
        case .copyReply:
            if let t = lastAgentReply() { Clipboard.copy(t) } else { Toast.shared.show("没有找到 agent 回复") }
        }
    }

    /// 辅助栏上的键也遵循粘滞的 ctrl / alt：ctrl+字符 → 控制码，alt → 前缀 ESC
    private func applyModifiers(_ bytes: [UInt8]) -> [UInt8] {
        var out = bytes
        if terminalView.controlModifier {
            if out.count == 1, let c = out.first {
                switch c {
                case 0x61...0x7a: out = [c - 0x60]          // a-z
                case 0x40...0x5f: out = [c - 0x40]          // @ A-Z [ \ ] ^ _
                case 0x20: out = [0x00]                      // ctrl+space
                case 0x3f: out = [0x7f]                      // ctrl+?
                default: break
                }
            }
            terminalView.controlModifier = false
            bar.setCtrl(false)
        }
        if terminalView.metaModifier {
            out = [0x1b] + out
            terminalView.metaModifier = false
            bar.setAlt(false)
        }
        return out
    }

    /// 通过 exec 通道给 tmux 开启鼠标滚动（不往终端里打字）
    func enableTmuxMouse() {
        needsMouseHint = false
        guard let t = sshTransport else { return }
        Task {
            _ = try? await t.exec("tmux set -g mouse on; tmux bind -T copy-mode WheelUpPane send -N1 -X scroll-up; tmux bind -T copy-mode WheelDownPane send -N1 -X scroll-down; tmux bind -T copy-mode-vi WheelUpPane send -N1 -X scroll-up; tmux bind -T copy-mode-vi WheelDownPane send -N1 -X scroll-down; true")
            Toast.shared.show("已开启 tmux 鼠标滚动")
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

    func confirmChangedHostKey(host: String, port: Int, keyType: String, old: String, new: String) async -> Bool {
        await withCheckedContinuation { cont in
            pendingHostKey = PendingHostKey(host: host, port: port, keyType: keyType, fingerprint: new, oldFingerprint: old) { [weak self] ok in
                self?.pendingHostKey = nil
                cont.resume(returning: ok)
            }
        }
    }

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
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // OSC 7 形如 file://host/path
            guard let d = directory else { return }
            let path = URL(string: d)?.path ?? d
            onMain { $0.currentDirectory = path.isEmpty ? nil : path }
        }
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            onMain { $0.send(bytes) }
        }
        func scrolled(source: TerminalView, position: Double) {
            onMain { o in o.setAtBottom(o.terminalView.isAtBottom) }
        }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func bell(source: TerminalView) {
            onMain { o in
                Haptics.soft()
                Notifier.post(title: o.host.displayName, body: o.host.agent == .none ? "终端响铃" : "\(o.host.agent.title) 需要你的确认或已完成任务", key: o.id.uuidString)
            }
        }
        func clipboardCopy(source: TerminalView, content: Data) {
            if let s = String(data: content, encoding: .utf8) {
                Task { @MainActor in Clipboard.copy(s) }
            }
        }
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            onMain { o in
                // http(s) 在应用内浏览器打开，保持连接不进后台
                if url.scheme == "http" || url.scheme == "https" {
                    NotificationCenter.default.post(name: .monoOpenURL, object: o.id, userInfo: ["url": url])
                } else {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}

/// 从屏幕内容推断 agent 状态（以 Claude Code 为主，兼容 Codex / Gemini 的常见提示）
enum AgentStatus: Equatable {
    case unknown, working, needsInput, idle

    static func detect(tail: String) -> AgentStatus {
        if tail.contains("esc to interrupt") || tail.contains("esc to cancel") || tail.contains("ctrl+c to interrupt") {
            return .working
        }
        if tail.contains("do you want to") || tail.contains("❯ 1.") || tail.contains("› 1.") || tail.contains("(y/n)")
            || tail.contains("[y/n]") || tail.contains("allow this") || tail.contains("approve")
            || tail.contains("allow command") || tail.contains("apply this change") || tail.contains("waiting for your") {
            return .needsInput
        }
        if tail.contains("? for shortcuts") || tail.contains("shift+tab to cycle") || tail.contains("> try") || tail.contains("│ >") {
            return .idle
        }
        return .unknown
    }

    var label: String? {
        switch self {
        case .working: return "工作中"
        case .needsInput: return "等待确认"
        case .idle: return "空闲"
        case .unknown: return nil
        }
    }

    var color: SwiftUI.Color {
        switch self {
        case .working: return .blue
        case .needsInput: return .orange
        case .idle: return .green
        case .unknown: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .working: return "ellipsis.circle.fill"
        case .needsInput: return "exclamationmark.bubble.fill"
        case .idle: return "checkmark.circle.fill"
        case .unknown: return "circle"
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
    static let monoShowSearch = Notification.Name("mono.showSearch")
    static let monoShowOutput = Notification.Name("mono.showOutput")
    static let monoShowSlash = Notification.Name("mono.showSlash")
    static let monoOpenURL = Notification.Name("mono.openURL")
    static let monoShowHistory = Notification.Name("mono.showHistory")
}

/// 管理所有活动会话（「会话」页）。
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()
    @Published var sessions: [TerminalSession] = [] { didSet { persist() } }
    @Published var path = NavigationPath()
    /// 当前正在查看的终端会话
    var visibleID: UUID?
    /// 自增即让根视图切回主页标签（终端页在主页导航栈里）
    @Published var focusHome = 0
    /// 上次 app 退出前开着的会话（主机快照，含 tmux 会话名），用于一键恢复
    @Published private(set) var restorable: [Host] = []

    private let restoreKey = "lastSessions"

    init() {
        if !DemoData.active, let data = UserDefaults.standard.data(forKey: restoreKey),
           let hosts = try? JSONDecoder().decode([Host].self, from: data) {
            // 只恢复仍存在的主机（用最新配置，但保留会话自己的 tmux 名）
            restorable = hosts.compactMap { snap in
                guard var h = AppStore.shared.host(snap.id) else { return nil }
                h.tmuxSession = snap.tmuxSession
                h.restore = snap.restore
                h.agent = .none // 恢复时不重复启动 agent，tmux 会直接接回现场
                return h
            }
            let labels = UserDefaults.standard.stringArray(forKey: restoreKey + ".labels") ?? []
            restorableLabels = labels.count == hosts.count ? hosts.indices.compactMap { i in
                AppStore.shared.host(hosts[i].id) == nil ? nil : labels[i]
            } : []
        }
    }

    private var restorableLabels: [String] = []

    func persistSoon() { persist() }

    private func persist() {
        guard !DemoData.active else { return }
        let hosts = sessions.map(\.host)
        if let data = try? JSONEncoder().encode(hosts) { UserDefaults.standard.set(data, forKey: restoreKey) }
        UserDefaults.standard.set(sessions.map(\.label), forKey: restoreKey + ".labels")
    }

    func restoreAll() {
        let list = restorable
        let labels = restorableLabels
        restorable = []
        for (i, h) in list.enumerated() {
            let s = open(h)
            if i < labels.count { s.label = labels[i] }
        }
        if let first = sessions.first { path.append(Route.terminal(first.id)) }
    }

    func dismissRestore() {
        restorable = []
    }

    func open(_ host: Host) -> TerminalSession {
        let s = TerminalSession(host: host)
        sessions.append(s)
        restorable = []
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
