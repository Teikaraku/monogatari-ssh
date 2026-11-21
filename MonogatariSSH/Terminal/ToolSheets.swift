import SwiftUI

// MARK: - tmux 会话管理

struct TmuxSessionInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let windows: Int
    let attached: Int
    let activity: Date?
    let command: String
}

/// 列出服务器上的 tmux 会话：一键接入、新开 agent 会话（多个 Claude 并行）、结束会话。
struct TmuxManagerSheet: View {
    @ObservedObject var session: TerminalSession
    @EnvironmentObject var sessions: SessionManager
    @Environment(\.dismiss) var dismiss
    @State private var items: [TmuxSessionInfo] = []
    @State private var loading = true
    @State private var error: String?
    @State private var newName = ""
    @State private var newAgent: AgentPreset = .claude
    @State private var newDir = ""
    @State private var creating = false
    @State private var killing: TmuxSessionInfo?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { t in
                        Button { open(t.name, agent: .none) } label: { row(t) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { killing = t } label: { Label("结束", systemImage: "xmark") }
                            }
                            .contextMenu {
                                Button("在新会话中打开", systemImage: "rectangle.stack.badge.plus") { open(t.name, agent: .none) }
                                Button("复制接入命令", systemImage: "doc.on.doc") { Clipboard.copy("tmux attach -t \(t.name)") }
                                Button("结束会话", systemImage: "xmark.circle", role: .destructive) { killing = t }
                            }
                    }
                } header: {
                    Text("服务器上的会话")
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else if !loading && items.isEmpty { Text("还没有 tmux 会话。") }
                    else { Text("点按在新的终端里接入；左滑可结束会话。会话在服务器上持续运行，断网也不影响。") }
                }

                Section {
                    TextField("会话名，如 agent-2", text: $newName)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.body.monospaced())
                    Picker("启动", selection: $newAgent) {
                        ForEach(AgentPreset.allCases.filter { $0 != .custom }) { Text($0.title).tag($0) }
                    }
                    TextField("工作目录（可选），如 ~/project", text: $newDir)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button {
                        let name = newName.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedName : newName
                        open(name, agent: newAgent, dir: newDir)
                    } label: {
                        Label("新建并打开", systemImage: "plus.rectangle.on.rectangle")
                    }
                } header: {
                    Text("新建 agent 会话")
                } footer: {
                    Text("在同一台服务器上并行跑多个 agent：每个会话独立的 tmux，互不干扰，在「会话」页之间切换。")
                }
            }
            .overlay { if loading && items.isEmpty { ProgressView() } }
            .refreshable { await load() }
            .navigationTitle("tmux 会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
                ToolbarItem(placement: .primaryAction) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } }
            }
            .task { await load() }
            .confirmationDialog("结束 tmux 会话「\(killing?.name ?? "")」？", isPresented: Binding(get: { killing != nil }, set: { if !$0 { killing = nil } }), titleVisibility: .visible) {
                Button("结束", role: .destructive) {
                    if let k = killing { Task { await kill(k.name) } }
                }
            } message: { Text("会话里运行的程序（包括 agent）会被终止。") }
        }
        .presentationDetents([.medium, .large])
    }

    private var suggestedName: String {
        var i = 2
        while items.contains(where: { $0.name == "agent-\(i)" }) { i += 1 }
        return "agent-\(i)"
    }

    private func row(_ t: TmuxSessionInfo) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: t.name == session.host.effectiveTmuxName ? "star.fill" : "square.stack.3d.up.fill",
                     colors: t.attached > 0 ? Color.tileGreen : Color.tileMagenta, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.name).font(.body.monospaced().weight(.medium))
                Text([
                    "\(t.windows) 个窗口",
                    t.attached > 0 ? "\(t.attached) 个客户端在线" : "未接入",
                    t.command.isEmpty ? nil : t.command,
                    t.activity.map { "活跃于 " + $0.relative },
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func load() async {
        guard let t = session.sshTransport else { error = "当前会话不支持"; loading = false; return }
        loading = true
        defer { loading = false }
        do {
            let out = try await t.exec("tmux ls -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_activity}|#{pane_current_command}' 2>/dev/null; true")
            items = out.split(separator: "\n").compactMap { line in
                let p = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard p.count >= 4 else { return nil }
                return TmuxSessionInfo(name: p[0], windows: Int(p[1]) ?? 1, attached: Int(p[2]) ?? 0,
                                       activity: TimeInterval(p[3]).map { Date(timeIntervalSince1970: $0) },
                                       command: p.count > 4 ? p[4] : "")
            }
            .sorted { ($0.activity ?? .distantPast) > ($1.activity ?? .distantPast) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func kill(_ name: String) async {
        guard let t = session.sshTransport else { return }
        _ = try? await t.exec("tmux kill-session -t '\(name.replacingOccurrences(of: "'", with: ""))'; true")
        Haptics.success()
        await load()
    }

    private func open(_ name: String, agent: AgentPreset, dir: String = "") {
        var h = session.host
        h.restore = .tmux
        h.tmuxSession = name
        h.agent = agent
        let d = dir.trimmingCharacters(in: .whitespaces)
        h.startupCommand = d.isEmpty ? "" : "cd \(d)"
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let s = sessions.open(h)
            sessions.path.append(Route.terminal(s.id))
        }
    }
}

// MARK: - 服务器状态

struct ServerStats {
    var hostname = ""
    var os = ""
    var uptime: TimeInterval = 0
    var load: [Double] = []
    var cpus = 1
    var cpuUsage: Double = 0
    var memTotal: Double = 0
    var memUsed: Double = 0
    var diskTotal: Double = 0
    var diskUsed: Double = 0
    var agents: [String] = []
}

/// 服务器状态：CPU / 内存 / 磁盘 / 负载 / 运行中的 agent 进程，每 3 秒刷新
struct ServerStatusSheet: View {
    @ObservedObject var session: TerminalSession
    @Environment(\.dismiss) var dismiss
    @State private var stats: ServerStats?
    @State private var error: String?

    private static let script = """
    echo "host=$(hostname)"; \
    echo "os=$( (. /etc/os-release 2>/dev/null && echo $PRETTY_NAME) || uname -sr)"; \
    echo "up=$(cut -d. -f1 /proc/uptime 2>/dev/null)"; \
    echo "load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"; \
    echo "cpus=$(nproc 2>/dev/null || echo 1)"; \
    a=$(head -1 /proc/stat); sleep 0.4; b=$(head -1 /proc/stat); echo "cpu1=$a"; echo "cpu2=$b"; \
    free -b 2>/dev/null | awk '/^Mem:/{print "mem="$2" "$3}'; \
    df -B1 / 2>/dev/null | awk 'NR==2{print "disk="$2" "$3}'; \
    ps -eo pid,etime,comm,args 2>/dev/null | grep -E '[c]laude|[c]odex|[g]emini' | awk '{print "agent="$1" "$2" "$3}' | head -8; true
    """

    var body: some View {
        NavigationStack {
            List {
                if let s = stats {
                    Section {
                        LabeledContent("主机名", value: s.hostname)
                        LabeledContent("系统", value: s.os)
                        LabeledContent("运行时间", value: format(uptime: s.uptime))
                        LabeledContent("负载", value: s.load.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                    }
                    Section {
                        gauge("CPU", value: s.cpuUsage, detail: "\(s.cpus) 核", colors: Color.tileBlue)
                        gauge("内存", value: s.memTotal > 0 ? s.memUsed / s.memTotal : 0,
                              detail: "\(bytes(s.memUsed)) / \(bytes(s.memTotal))", colors: Color.tileGreen)
                        gauge("磁盘 /", value: s.diskTotal > 0 ? s.diskUsed / s.diskTotal : 0,
                              detail: "\(bytes(s.diskUsed)) / \(bytes(s.diskTotal))", colors: Color.tileOrange)
                    }
                    Section("运行中的 agent") {
                        if s.agents.isEmpty {
                            Text("没有检测到 claude / codex / gemini 进程").foregroundStyle(.secondary)
                        } else {
                            ForEach(s.agents, id: \.self) { a in
                                Label(a, systemImage: "sparkles").font(.callout.monospaced())
                            }
                        }
                    }
                } else if let error {
                    ContentUnavailableView("无法获取", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .navigationTitle("服务器状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
            }
            .task {
                while !Task.isCancelled {
                    await refresh()
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func gauge(_ title: String, value: Double, detail: String, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.0f%%", value * 100)).font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(value > 0.85 ? .red : .primary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(LinearGradient(colors: value > 0.85 ? Color.tileRed : colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, g.size.width * min(1, value)))
                }
            }
            .frame(height: 8)
            .animation(.snappy, value: value)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func refresh() async {
        guard let t = session.sshTransport else { error = "当前会话不支持"; return }
        do {
            let out = try await t.exec(Self.script)
            stats = parse(out)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func parse(_ out: String) -> ServerStats {
        var s = ServerStats()
        var cpu1: [Double] = [], cpu2: [Double] = []
        for line in out.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<eq]), v = String(line[line.index(after: eq)...])
            let nums = v.split(separator: " ").compactMap { Double($0) }
            switch k {
            case "host": s.hostname = v
            case "os": s.os = v
            case "up": s.uptime = Double(v) ?? 0
            case "load": s.load = nums
            case "cpus": s.cpus = Int(v) ?? 1
            case "cpu1": cpu1 = nums
            case "cpu2": cpu2 = nums
            case "mem": if nums.count >= 2 { s.memTotal = nums[0]; s.memUsed = nums[1] }
            case "disk": if nums.count >= 2 { s.diskTotal = nums[0]; s.diskUsed = nums[1] }
            case "agent":
                let p = v.split(separator: " ")
                if p.count >= 3 { s.agents.append("\(p[2])  pid \(p[0])  运行 \(p[1])") }
            default: break
            }
        }
        // /proc/stat：user nice system idle iowait irq softirq ...
        if cpu1.count >= 4, cpu2.count >= 4 {
            let t1 = cpu1.reduce(0, +), t2 = cpu2.reduce(0, +)
            let idle1 = cpu1[3] + (cpu1.count > 4 ? cpu1[4] : 0), idle2 = cpu2[3] + (cpu2.count > 4 ? cpu2[4] : 0)
            let dt = t2 - t1
            s.cpuUsage = dt > 0 ? max(0, min(1, 1 - (idle2 - idle1) / dt)) : 0
        }
        return s
    }

    private func bytes(_ v: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .memory) }

    private func format(uptime: TimeInterval) -> String {
        let d = Int(uptime) / 86400, h = Int(uptime) % 86400 / 3600, m = Int(uptime) % 3600 / 60
        return d > 0 ? "\(d) 天 \(h) 小时" : (h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟")
    }
}

// MARK: - 斜杠指令面板

struct SlashCommand: Identifiable, Hashable {
    var id: String { cmd }
    let cmd: String
    let desc: String
    var needsArg = false
}

/// Claude Code 常用斜杠指令，点按即发送
struct SlashPalette: View {
    @ObservedObject var session: TerminalSession
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @AppStorage("slashRecent") private var recentRaw = ""

    static let commands: [SlashCommand] = [
        SlashCommand(cmd: "/compact", desc: "压缩上下文（可附加要保留的重点）", needsArg: true),
        SlashCommand(cmd: "/clear", desc: "清空对话，开始新任务"),
        SlashCommand(cmd: "/model", desc: "切换模型"),
        SlashCommand(cmd: "/resume", desc: "恢复历史对话"),
        SlashCommand(cmd: "/context", desc: "查看上下文占用"),
        SlashCommand(cmd: "/cost", desc: "查看本次花费 / 用量"),
        SlashCommand(cmd: "/status", desc: "账号与版本状态"),
        SlashCommand(cmd: "/init", desc: "为项目生成 CLAUDE.md"),
        SlashCommand(cmd: "/memory", desc: "编辑记忆文件"),
        SlashCommand(cmd: "/review", desc: "代码审查"),
        SlashCommand(cmd: "/permissions", desc: "管理工具权限"),
        SlashCommand(cmd: "/agents", desc: "管理子 agent"),
        SlashCommand(cmd: "/mcp", desc: "MCP 服务器"),
        SlashCommand(cmd: "/config", desc: "设置"),
        SlashCommand(cmd: "/add-dir", desc: "添加工作目录", needsArg: true),
        SlashCommand(cmd: "/export", desc: "导出对话"),
        SlashCommand(cmd: "/doctor", desc: "诊断安装问题"),
        SlashCommand(cmd: "/bug", desc: "反馈问题"),
        SlashCommand(cmd: "/help", desc: "帮助"),
        SlashCommand(cmd: "/exit", desc: "退出 Claude Code"),
    ]

    private var recent: [String] { recentRaw.split(separator: ",").map(String.init) }

    private var filtered: [SlashCommand] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? Self.commands : Self.commands.filter { $0.cmd.contains(q) || $0.desc.contains(q) }
        // 最近使用的排在前面
        return list.sorted { a, b in
            let ia = recent.firstIndex(of: a.cmd) ?? Int.max, ib = recent.firstIndex(of: b.cmd) ?? Int.max
            return ia < ib
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { c in
                Button { run(c) } label: {
                    HStack {
                        Text(c.cmd).font(.body.monospaced().weight(.medium)).foregroundStyle(.orange)
                        Text(c.desc).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if c.needsArg { Image(systemName: "character.cursor.ibeam").foregroundStyle(.tertiary) }
                    }
                }
                .swipeActions {
                    Button { insert(c) } label: { Label("只输入", systemImage: "character.cursor.ibeam") }.tint(.orange)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索指令")
            .navigationTitle("斜杠指令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func remember(_ c: SlashCommand) {
        var r = recent.filter { $0 != c.cmd }
        r.insert(c.cmd, at: 0)
        recentRaw = r.prefix(6).joined(separator: ",")
    }

    /// 需要参数的只输入不回车，其余直接发送
    private func run(_ c: SlashCommand) {
        if c.needsArg { insert(c); return }
        remember(c)
        session.send(text: c.cmd + "\r")
        Haptics.tap()
        dismiss()
    }

    private func insert(_ c: SlashCommand) {
        remember(c)
        session.send(text: c.cmd + " ")
        Haptics.tap()
        dismiss()
    }
}
