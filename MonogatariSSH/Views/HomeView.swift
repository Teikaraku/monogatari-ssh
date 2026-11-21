import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var sessions: SessionManager
    @State private var quickConnect = false

    var body: some View {
        List {
            if !sessions.restorable.isEmpty && sessions.sessions.isEmpty {
                Section {
                    HStack(spacing: 14) {
                        IconTile(symbol: "arrow.counterclockwise", colors: Color.tilePurple, size: 50, corner: 13)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("继续上次的 \(sessions.restorable.count) 个会话").font(.headline)
                            Text(sessions.restorable.map { $0.restore == .tmux ? "\($0.displayName)·\($0.effectiveTmuxName)" : $0.displayName }.joined(separator: "、"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    HStack {
                        Button("全部恢复") { sessions.restoreAll() }
                            .buttonStyle(.borderedProminent)
                        Button("忽略") { withAnimation { sessions.dismissRestore() } }
                            .buttonStyle(.bordered)
                    }
                    .padding(.bottom, 4)
                }
            }
            Section { nav(.hosts, "主机", "desktopcomputer", Color.tileIndigo, count: store.hosts.count) }
            Section { nav(.keys, "密钥", "key.fill", Color.tileOrange, count: store.keys.count) }
            Section { nav(.knownHosts, "指纹", "person.text.rectangle.fill", Color.tilePink, count: store.knownHosts.count) }
            Section { nav(.snippets, "命令片段", "text.alignleft", Color.tileGreen, count: store.snippets.count) }
            Section { nav(.transfers, "传输", "arrow.up.arrow.down", Color.tileBlue, count: nil) }

            if !store.recentHosts.isEmpty {
                Section {
                    ForEach(store.recentHosts) { host in
                        HostRow(host: host, showChevron: true)
                    }
                } header: {
                    Text("最近")
                        .font(.title2.bold())
                        .foregroundStyle(Color(uiColor: .label))
                        .textCase(nil)
                        .padding(.leading, -16)
                        .padding(.top, 12)
                }
            }
        }
        .listSectionSpacing(14)
        .navigationTitle("主页")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { quickConnect = true } label: { Image(systemName: "bolt.fill") }
                    .accessibilityLabel("快速连接")
            }
        }
        .sheet(isPresented: $quickConnect) { QuickConnectSheet() }
    }

    private func nav(_ r: Route, _ title: String, _ symbol: String, _ colors: [Color], count: Int?) -> some View {
        NavigationLink(value: r) {
            HStack(spacing: 16) {
                IconTile(symbol: symbol, colors: colors, size: 50, corner: 13)
                Text(title).font(.title3.weight(.medium))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.vertical, 8)
        }
    }
}

/// 主机行：点击连接，长按菜单/左滑可复制 IP、用户名、密码、SSH 命令，编辑、复制、删除。
struct HostRow: View {
    let host: Host
    var showChevron = false
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var sessions: SessionManager
    @State private var editing = false
    @State private var info = false
    @State private var confirmDelete = false

    var body: some View {
        Button {
            Haptics.tap()
            if let live = sessions.sessions.first(where: { $0.host.id == host.id }) {
                sessions.show(live)
            } else {
                sessions.connect(host)
            }
        } label: {
            HStack(spacing: 14) {
                HostAvatar(host: host, size: 46)
                    .overlay(alignment: .bottomTrailing) {
                        if let live = sessions.sessions.first(where: { $0.host.id == host.id }) {
                            Circle().fill(live.state == .connected ? Color.green : Color.yellow)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                                .offset(x: 3, y: 3)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(host.displayName).font(.title3.weight(.medium)).foregroundStyle(.primary)
                    Text(host.address).font(.body).foregroundStyle(.secondary)
                }
                Spacer()
                if host.agent != .none {
                    Image(systemName: "sparkles").foregroundStyle(.orange).font(.footnote)
                }
                if host.restore != .none {
                    Image(systemName: "arrow.clockwise.circle").foregroundStyle(.purple).font(.footnote)
                }
                if showChevron {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("连接", systemImage: "play.fill") { sessions.connect(host) }
            if sessions.sessions.contains(where: { $0.host.id == host.id }) {
                Button("新开一个会话", systemImage: "plus.rectangle.on.rectangle") { sessions.connect(host) }
            }
            Button("主机信息", systemImage: "info.circle") { info = true }
            Divider()
            Button("复制地址", systemImage: "network") { Clipboard.copy(host.hostname) }
            Button("复制用户名", systemImage: "person") { Clipboard.copy(host.username) }
            if host.auth == .password, let pw = store.password(for: host) {
                Button("复制密码", systemImage: "key") { Clipboard.copy(pw) }
            }
            Button("复制 SSH 命令", systemImage: "terminal") { Clipboard.copy(host.sshCommand) }
            Divider()
            Button("编辑", systemImage: "pencil") { editing = true }
            Button("复制主机", systemImage: "plus.square.on.square") { store.duplicate(host) }
            Button("删除", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } preview: {
            HostInfoCard(host: host).frame(width: 340)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") }
            Button { editing = true } label: { Label("编辑", systemImage: "pencil") }.tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button { info = true } label: { Label("信息", systemImage: "info.circle") }.tint(.blue)
            Button { Clipboard.copy(host.hostname) } label: { Label("复制IP", systemImage: "doc.on.doc") }.tint(.teal)
        }
        .sheet(isPresented: $editing) { HostEditView(host: host) }
        .sheet(isPresented: $info) { HostInfoSheet(host: host) }
        .confirmationDialog("删除「\(host.displayName)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { store.delete(host: host) }
        }
    }
}

/// 长按预览卡片
struct HostInfoCard: View {
    let host: Host
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HostAvatar(host: host, size: 44)
                VStack(alignment: .leading) {
                    Text(host.displayName).font(.headline)
                    Text("\(host.proto.title) · \(host.auth.title)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("\(host.username)@\(host.address)").font(.callout.monospaced())
            if host.restore != .none || host.agent != .none {
                HStack {
                    if host.restore != .none { Label(host.restore.title, systemImage: "arrow.clockwise") }
                    if host.agent != .none { Label(host.agent.title, systemImage: "sparkles") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

/// 主机信息：地址/端口/用户/密码（隐藏+眼睛+复制）
struct HostInfoSheet: View {
    let host: Host
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var sessions: SessionManager
    @Environment(\.dismiss) var dismiss
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        HostAvatar(host: host, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(host.displayName).font(.title2.bold())
                            Text(host.lastConnected.map { "上次连接 " + $0.relative } ?? "从未连接")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section("连接") {
                    CopyRow(symbol: "globe", colors: Color.tileGreen, title: "主机", value: host.hostname)
                    CopyRow(symbol: "number", colors: Color.tileTeal, title: "端口", value: "\(host.port)")
                    CopyRow(symbol: "person.fill", colors: Color.tileBlue, title: "用户名", value: host.username)
                    if host.auth == .password {
                        HStack(spacing: 12) {
                            IconTile(symbol: "key.fill", colors: Color.tileOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("密码").font(.caption).foregroundStyle(.secondary)
                                SecretText(value: store.password(for: host) ?? "")
                            }
                        }
                    } else {
                        CopyRow(symbol: "key.horizontal.fill", colors: Color.tileOrange, title: "SSH 密钥",
                                value: store.key(host.keyID)?.name ?? "未选择", mono: false)
                    }
                    CopyRow(symbol: "terminal.fill", colors: Color.tileGray, title: "SSH 命令", value: host.sshCommand)
                }
                if !host.notes.isEmpty {
                    Section("备注") {
                        Text(host.notes).textSelection(.enabled)
                    }
                }
                if let fp = store.knownHost(host: host.hostname, port: host.port) {
                    Section("主机指纹") {
                        CopyRow(symbol: "touchid", colors: Color.tilePink, title: fp.keyType, value: fp.fingerprint)
                    }
                }
                Section {
                    Button {
                        dismiss()
                        sessions.connect(host)
                    } label: {
                        Label("连接", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("主机信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = true } label: { Image(systemName: "pencil") }
                }
            }
            .sheet(isPresented: $editing) { HostEditView(host: host) }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 快速连接：user@host:port 一行搞定，可选保存
struct QuickConnectSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var sessions: SessionManager
    @Environment(\.dismiss) var dismiss
    @State private var target = ""
    @State private var password = ""
    @State private var save = true

    var parsed: Host? {
        var s = target.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("ssh ") { s = String(s.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
        var h = Host()
        var port: Int?
        if let r = s.range(of: "-p ") {
            let rest = s[r.upperBound...].split(separator: " ")
            port = rest.first.flatMap { Int($0) }
            s = s.replacingCharacters(in: r.lowerBound..<s.endIndex, with: "") + rest.dropFirst().joined(separator: " ")
            s = s.trimmingCharacters(in: .whitespaces)
        }
        if let at = s.lastIndex(of: "@") { h.username = String(s[..<at]); s = String(s[s.index(after: at)...]) }
        if let colon = s.lastIndex(of: ":"), let p = Int(s[s.index(after: colon)...]) { port = p; s = String(s[..<colon]) }
        guard !s.isEmpty else { return nil }
        h.hostname = s
        h.port = port ?? 22
        return h
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    IconField(symbol: "bolt.fill", colors: Color.tileOrange, placeholder: "root@1.2.3.4:22", text: $target, keyboard: .URL, mono: true)
                    IconSecureField(symbol: "key.fill", colors: Color.tileOrange, placeholder: "密码", text: $password)
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) { target = s }
                    }
                    .labelStyle(.titleAndIcon)
                } footer: {
                    Text("支持 user@host、user@host:port，或直接粘贴 ssh -p 端口 user@host")
                }
                Section { Toggle("保存到主机列表", isOn: $save) }
            }
            .navigationTitle("快速连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { go() } label: { Image(systemName: "checkmark") }.disabled(parsed == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    func go() {
        guard var h = parsed else { return }
        h.alias = save ? h.hostname : ""
        store.upsert(h, password: password)
        if !save {
            // 不保存：连接后删除记录（密码仍在钥匙串里随记录一起删）
            sessions.connect(h)
            let id = h.id
            Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if let x = store.host(id) { store.delete(host: x) } }
        } else {
            sessions.connect(h)
        }
        dismiss()
    }
}
