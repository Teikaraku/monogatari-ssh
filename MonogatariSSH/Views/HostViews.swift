import SwiftUI

struct HostListView: View {
    @EnvironmentObject var store: AppStore
    @State private var adding = false
    @State private var importing = false
    @State private var quick = false
    @State private var query = ""
    @AppStorage("hostSort") private var sort = "created"

    var filtered: [Host] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = store.hosts.sorted { a, b in
            switch sort {
            case "name": return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            case "recent": return (a.lastConnected ?? .distantPast) > (b.lastConnected ?? .distantPast)
            default: return a.createdAt < b.createdAt
            }
        }
        guard !q.isEmpty else { return list }
        return list.filter { $0.displayName.lowercased().contains(q) || $0.hostname.lowercased().contains(q) || $0.username.lowercased().contains(q) }
    }

    var groups: [(String, [Host])] {
        let dict = Dictionary(grouping: filtered) { $0.group }
        return dict.keys.sorted { a, b in a.isEmpty ? true : (b.isEmpty ? false : a < b) }.map { ($0, dict[$0]!) }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.0) { name, hosts in
                Section(name.isEmpty ? "" : name) {
                    ForEach(hosts) { HostRow(host: $0) }
                }
            }
        }
        .overlay {
            if store.hosts.isEmpty {
                ContentUnavailableView {
                    Label("暂无主机", systemImage: "desktopcomputer")
                } actions: {
                    Button("添加主机") { adding = true }.buttonStyle(.borderedProminent)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "搜索主机")
        .navigationTitle("主机")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("排序", selection: $sort) {
                        Label("添加时间", systemImage: "calendar").tag("created")
                        Label("名称", systemImage: "textformat.abc").tag("name")
                        Label("最近连接", systemImage: "clock").tag("recent")
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新建主机", systemImage: "plus") { adding = true }
                    Button("快速连接", systemImage: "bolt") { quick = true }
                    Button("导入 ssh config", systemImage: "square.and.arrow.down") { importing = true }
                } label: { Image(systemName: "plus") } primaryAction: { adding = true }
                .accessibilityLabel("添加主机")
            }
        }
        .sheet(isPresented: $adding) { HostEditView(host: nil) }
        .sheet(isPresented: $importing) { SSHConfigImportView() }
        .sheet(isPresented: $quick) { QuickConnectSheet() }
    }
}

struct HostEditView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    @State private var host: Host
    @State private var password: String
    @State private var portText: String
    @State private var showAdvanced = false
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?
    private let isNew: Bool

    init(host: Host?) {
        var h = host ?? Host()
        if host == nil { h.themeID = AppSettings.shared.defaultTheme }
        _host = State(initialValue: h)
        _password = State(initialValue: host.flatMap { AppStore.shared.password(for: $0) } ?? "")
        _portText = State(initialValue: host.map { String($0.port) } ?? "")
        isNew = host == nil
    }

    var valid: Bool { !host.hostname.trimmingCharacters(in: .whitespaces).isEmpty && !host.username.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    IconField(symbol: "tag.fill", colors: Color.tileBlue, placeholder: "别名", text: $host.alias)
                }

                Section("连接") {
                    IconField(symbol: "globe", colors: Color.tileGreen, placeholder: "主机", text: $host.hostname, keyboard: .URL)
                    IconField(symbol: "number", colors: Color.tileTeal, placeholder: "端口（默认 \(host.proto.defaultPort)）", text: $portText, keyboard: .numberPad)
                    IconField(symbol: "person.fill", colors: Color.tileBlue, placeholder: "用户名", text: $host.username)
                    if host.proto == .ssh {
                        HStack(spacing: 12) {
                            IconTile(symbol: "lock.fill", colors: Color.tilePurple)
                            Text("身份验证")
                            Spacer()
                            Picker("身份验证", selection: $host.auth) {
                                ForEach(AuthMethod.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        if host.auth == .password {
                            IconSecureField(symbol: "key.fill", colors: Color.tileOrange, placeholder: "密码", text: $password)
                        } else {
                            HStack(spacing: 12) {
                                IconTile(symbol: "key.horizontal.fill", colors: Color.tileOrange)
                                Picker("密钥", selection: $host.keyID) {
                                    Text("未选择").tag(UUID?.none)
                                    ForEach(store.keys) { Text($0.name).tag(UUID?.some($0.id)) }
                                }
                            }
                            if store.keys.isEmpty {
                                NavigationLink { KeyListView() } label: {
                                    Label("先去导入或生成密钥", systemImage: "plus.circle")
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            IconTile(symbol: "arrow.clockwise", colors: Color.tileMagenta)
                            Picker("会话恢复", selection: $host.restore) {
                                ForEach(SessionRestore.allCases) { Text($0.title).tag($0) }
                            }
                        }
                    } else {
                        IconSecureField(symbol: "key.fill", colors: Color.tileOrange, placeholder: "密码（仅备忘，登录时手动输入）", text: $password)
                    }
                }

                if host.proto == .ssh {
                    Section {
                        HStack(spacing: 12) {
                            IconTile(symbol: "sparkles", colors: Color.tileOrange)
                            Picker("连接后启动", selection: $host.agent) {
                                ForEach(AgentPreset.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        if host.agent == .custom || !host.startupCommand.isEmpty {
                            IconField(symbol: "chevron.left.forwardslash.chevron.right", colors: Color.tileGray,
                                      placeholder: host.agent == .custom ? "启动命令，如 cd ~/app && claude" : "先执行（如 cd ~/project）",
                                      text: $host.startupCommand, mono: true)
                        } else {
                            Button("启动前先 cd 到项目目录…") { host.startupCommand = "cd ~/" }
                                .font(.footnote)
                        }
                        if host.restore == .tmux {
                            IconField(symbol: "square.stack.3d.up.fill", colors: Color.tileMagenta, placeholder: "tmux 会话名（默认 mono）", text: $host.tmuxSession, mono: true)
                        }
                    } header: {
                        Text("Agent")
                    }
                }

                if host.proto == .ssh {
                    Section {
                        Button {
                            Task { await runTest() }
                        } label: {
                            HStack {
                                Label("测试连接", systemImage: "antenna.radiowaves.left.and.right")
                                Spacer()
                                if testing { ProgressView() }
                            }
                        }
                        .disabled(!valid || testing)
                        if let r = testResult {
                            Label(r.text, systemImage: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(.footnote)
                                .foregroundStyle(r.ok ? .green : .red)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("外观") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            IconTile(symbol: "paintpalette.fill", colors: Color.tileMagenta)
                            Text("配色主题")
                        }
                        ThemePicker(selection: $host.themeID)
                    }
                    .padding(.vertical, 4)
                    HStack(spacing: 12) {
                        HostAvatar(host: host, size: 30)
                        Picker("图标", selection: $host.icon) {
                            ForEach(HostIcon.allCases) { i in
                                Label(i.title, systemImage: i.symbol).tag(i)
                            }
                        }
                    }
                    IconField(symbol: "folder.fill", colors: Color.tileBlue, placeholder: "分组（可选）", text: $host.group)
                }

                Section {
                    DisclosureGroup("高级", isExpanded: $showAdvanced) {
                        Picker("协议", selection: $host.proto) {
                            ForEach(ConnectionProtocol.allCases) { Text($0.title).tag($0) }
                        }
                        if host.proto == .ssh {
                            Picker("跳板机", selection: $host.jumpHostID) {
                                Text("无").tag(UUID?.none)
                                ForEach(store.hosts.filter { $0.id != host.id && $0.proto == .ssh }) {
                                    Text($0.displayName).tag(UUID?.some($0.id))
                                }
                            }
                            Stepper("保活间隔 \(host.keepAliveSeconds == 0 ? "关闭" : "\(host.keepAliveSeconds) 秒")",
                                    value: $host.keepAliveSeconds, in: 0...300, step: 15)
                            NavigationLink {
                                ForwardsEditor(forwards: $host.forwards)
                            } label: {
                                LabeledContent("端口转发", value: host.forwards.isEmpty ? "无" : "\(host.forwards.count) 条")
                            }
                        }
                        TextField("备注", text: $host.notes, axis: .vertical).lineLimit(1...4)
                    }
                }
            }
            .navigationTitle(isNew ? "新建主机" : "编辑主机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark") }
                        .disabled(!valid)
                }
            }
            .onChange(of: host.proto) { _, p in
                if portText.isEmpty || Int(portText) == 22 || Int(portText) == 23 { portText = "" }
                host.port = p.defaultPort
            }
        }
    }

    func runTest() async {
        testing = true
        defer { testing = false }
        var h = host
        h.hostname = h.hostname.trimmingCharacters(in: .whitespaces)
        h.port = Int(portText) ?? h.proto.defaultPort
        do {
            let (info, t) = try await SSHConnector.test(h, password: h.auth == .password ? password : nil)
            testResult = (true, "连接成功 · \(Int(t * 1000)) ms\n\(info)")
            Haptics.success()
        } catch {
            testResult = (false, error.localizedDescription)
        }
    }

    func save() {
        host.hostname = host.hostname.trimmingCharacters(in: .whitespaces)
        host.port = Int(portText) ?? host.proto.defaultPort
        store.upsert(host, password: password)
        Haptics.success()
        dismiss()
    }
}

/// 横向主题卡片（参考图「外观」区）
struct ThemePicker: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TerminalTheme.all) { t in
                    Button {
                        selection = t.id
                        Haptics.tap()
                    } label: {
                        ThemeCard(theme: t, selected: selection == t.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

struct ThemeCard: View {
    let theme: TerminalTheme
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(theme.name)
                .font(.system(size: 17, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.fgColor)
                .lineLimit(1)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) { ForEach(0..<8, id: \.self) { swatch(theme.swatches[$0]) } }
                HStack(spacing: 4) { ForEach(8..<16, id: \.self) { swatch(theme.swatches[$0]) } }
            }
        }
        .padding(10)
        .frame(width: 168, alignment: .leading)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                    .offset(x: 4, y: 4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
    func swatch(_ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 14, height: 14)
    }
}

struct ForwardsEditor: View {
    @Binding var forwards: [PortForward]
    var body: some View {
        Form {
            ForEach($forwards) { $f in
                Section {
                    Toggle("启用", isOn: $f.enabled)
                    LabeledContent("本地端口") {
                        TextField("8080", value: $f.localPort, format: .number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("远端主机") {
                        TextField("127.0.0.1", text: $f.remoteHost)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing)
                    }
                    LabeledContent("远端端口") {
                        TextField("80", value: $f.remotePort, format: .number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text(f.summary).font(.footnote.monospaced())
                }
            }
            .onDelete { forwards.remove(atOffsets: $0) }
            Section {
                Button("添加转发", systemImage: "plus") { forwards.append(PortForward()) }
            }
        }
        .navigationTitle("端口转发")
    }
}
