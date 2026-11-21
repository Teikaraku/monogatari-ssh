import SwiftUI
import UniformTypeIdentifiers

// MARK: - 密钥

struct KeyListView: View {
    @EnvironmentObject var store: AppStore
    @State private var importing = false
    @State private var generating = false

    var body: some View {
        List {
            ForEach(store.keys) { k in
                NavigationLink { KeyDetailView(key: k) } label: {
                    HStack(spacing: 14) {
                        IconTile(symbol: "key.fill", colors: Color.tileOrange, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(k.name).font(.body.weight(.medium))
                            let used = store.hosts.filter { $0.auth == .key && $0.keyID == k.id }.count
                            Text("\(k.kind.title)\(k.hasPassphrase ? " · 有口令" : "")\(used > 0 ? " · \(used) 台主机使用中" : "")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu {
                    Button("复制公钥", systemImage: "doc.on.doc") { Clipboard.copy(k.publicKey) }
                    Button("删除", systemImage: "trash", role: .destructive) { store.delete(key: k) }
                }
            }
            .onDelete { idx in idx.map { store.keys[$0] }.forEach(store.delete(key:)) }
        }
        .overlay {
            if store.keys.isEmpty {
                ContentUnavailableView {
                    Label("没有密钥", systemImage: "key")
                } actions: {
                    Button("生成密钥") { generating = true }.buttonStyle(.borderedProminent)
                    Button("导入私钥") { importing = true }
                }
            }
        }
        .navigationTitle("密钥")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("生成 ED25519", systemImage: "wand.and.stars") { generating = true }
                    Button("导入私钥", systemImage: "square.and.arrow.down") { importing = true }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $importing) { KeyImportView() }
        .sheet(isPresented: $generating) { KeyGenerateView() }
    }
}

struct KeyDetailView: View {
    let key: SSHKeyItem
    @EnvironmentObject var store: AppStore
    @State private var showPrivate = false

    var body: some View {
        List {
            Section("公钥") {
                Text(key.publicKey).font(.caption.monospaced()).textSelection(.enabled)
                Button("复制公钥", systemImage: "doc.on.doc") { Clipboard.copy(key.publicKey) }
                Button("复制安装命令", systemImage: "terminal") {
                    Clipboard.copy("mkdir -p ~/.ssh && echo '\(key.publicKey)' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys")
                }
                ShareLink(item: key.publicKey) { Label("分享公钥", systemImage: "square.and.arrow.up") }
            }
            let users = store.hosts.filter { $0.auth == .key && $0.keyID == key.id }
            if !users.isEmpty {
                Section("使用此密钥的主机") {
                    ForEach(users) { h in
                        HStack(spacing: 12) {
                            HostAvatar(host: h, size: 30)
                            Text(h.displayName)
                            Spacer()
                            Text(h.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("信息") {
                LabeledContent("类型", value: key.kind.title)
                LabeledContent("指纹") { Text(KeyParser.fingerprint(openSSHLine: key.publicKey)).font(.caption.monospaced()).textSelection(.enabled) }
                LabeledContent("创建", value: key.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                if let priv = Keychain.get(Keychain.keyPrivate(key.id)) {
                    HStack(alignment: .top) {
                        Text(showPrivate ? priv : "已加密保存在钥匙串中")
                            .font(.caption2.monospaced())
                            .foregroundStyle(showPrivate ? .primary : .secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button { showPrivate.toggle() } label: { Image(systemName: showPrivate ? "eye" : "eye.slash") }
                            .buttonStyle(.plain).foregroundStyle(.tint)
                    }
                    Button("复制私钥", systemImage: "doc.on.doc") { Clipboard.copy(priv) }
                }
            } header: { Text("私钥") }
        }
        .navigationTitle(key.name)
    }
}

struct KeyImportView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var text = ""
    @State private var passphrase = ""
    @State private var error: String?
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Section { IconField(symbol: "tag.fill", colors: Color.tileBlue, placeholder: "名称", text: $name) }
                Section {
                    TextEditor(text: $text)
                        .font(.caption.monospaced())
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("从剪贴板粘贴", systemImage: "doc.on.clipboard") { text = UIPasteboard.general.string ?? "" }
                        Spacer()
                        Button("选择文件", systemImage: "folder") { picking = true }
                    }
                    .buttonStyle(.borderless)
                } header: { Text("私钥") }
                Section {
                    IconSecureField(symbol: "lock.fill", colors: Color.tilePurple, placeholder: "口令（没有则留空）", text: $passphrase)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("导入私钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark") }.disabled(text.isEmpty)
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.data, .text, .item]) { r in
                if case .success(let url) = r {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                }
            }
        }
    }

    func save() {
        do {
            let p = try KeyParser.parse(text, passphrase: passphrase)
            let item = SSHKeyItem(name: name.isEmpty ? p.kind.title : name, kind: p.kind, publicKey: p.publicKey, hasPassphrase: !passphrase.isEmpty)
            store.addKey(item, privateKey: text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n", passphrase: passphrase)
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct KeyGenerateView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = "iPhone"
    @State private var generated: SSHKeyItem?

    var body: some View {
        NavigationStack {
            Form {
                if let g = generated {
                    Section {
                        Label("已生成", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        Text(g.publicKey).font(.caption.monospaced()).textSelection(.enabled)
                        Button("复制公钥", systemImage: "doc.on.doc") { Clipboard.copy(g.publicKey) }
                        Button("复制安装命令", systemImage: "terminal") {
                            Clipboard.copy("mkdir -p ~/.ssh && echo '\(g.publicKey)' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys")
                        }
                    }
                } else {
                    Section { IconField(symbol: "tag.fill", colors: Color.tileBlue, placeholder: "名称", text: $name) }
                    Section {
                        Button("生成 ED25519 密钥", systemImage: "wand.and.stars") {
                            let (priv, pub) = KeyParser.generateEd25519(comment: "monogatari-\(name)")
                            let item = SSHKeyItem(name: name, kind: .ed25519, publicKey: pub, hasPassphrase: false)
                            store.addKey(item, privateKey: priv, passphrase: nil)
                            generated = item
                            Haptics.success()
                        }
                    }
                }
            }
            .navigationTitle("生成密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button { dismiss() } label: { Image(systemName: "checkmark") } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 指纹

struct KnownHostsView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        List {
            ForEach(store.knownHosts.sorted { $0.addedAt > $1.addedAt }) { k in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(k.endpoint).font(.body.weight(.medium))
                        Spacer()
                        Text(k.keyType).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(k.fingerprint).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("复制指纹", systemImage: "doc.on.doc") { Clipboard.copy(k.fingerprint) }
                    Button("复制公钥", systemImage: "key") { Clipboard.copy(k.openSSHKey) }
                    Button("删除", systemImage: "trash", role: .destructive) { store.knownHosts.removeAll { $0.id == k.id } }
                }
            }
            .onDelete { idx in
                let sorted = store.knownHosts.sorted { $0.addedAt > $1.addedAt }
                let ids = Set(idx.map { sorted[$0].id })
                store.knownHosts.removeAll { ids.contains($0.id) }
            }
        }
        .overlay {
            if store.knownHosts.isEmpty {
                ContentUnavailableView("暂无指纹", systemImage: "person.text.rectangle")
            }
        }
        .navigationTitle("指纹")
    }
}

// MARK: - 命令片段

struct SnippetsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var sessions: SessionManager
    @State private var editing: Snippet?
    @State private var query = ""

    private var visible: [Snippet] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? store.snippets : store.snippets.filter { $0.name.lowercased().contains(q) || $0.command.lowercased().contains(q) }
    }

    var groups: [String] {
        var order: [String] = []
        for s in visible where !order.contains(s.group) { order.append(s.group) }
        return order
    }

    var body: some View {
        List {
            ForEach(groups, id: \.self) { g in
                Section(g) {
                    ForEach(visible.filter { $0.group == g }) { s in
                        Button { editing = s } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.name).foregroundStyle(.primary)
                                Text(s.command).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .contextMenu {
                            Button("复制命令", systemImage: "doc.on.doc") { Clipboard.copy(s.command) }
                            if !sessions.sessions.isEmpty && s.variables.isEmpty {
                                Section("在会话中运行") {
                                    ForEach(sessions.sessions) { sess in
                                        Button(sess.displayTitle, systemImage: "play.fill") {
                                            sess.run(s)
                                            sessions.show(sess)
                                        }
                                    }
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { store.snippets.removeAll { $0.id == s.id } } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索片段")
        .navigationTitle("命令片段")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新建片段", systemImage: "plus") { editing = Snippet(name: "", command: "") }
                    Button("恢复 Agent 预置", systemImage: "sparkles") {
                        for p in Snippet.presets where !store.snippets.contains(where: { $0.command == p.command }) {
                            store.snippets.append(p)
                        }
                    }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { s in SnippetEditor(snippet: s) }
    }
}

struct SnippetEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var snippet: Snippet

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $snippet.name)
                    TextField("分组", text: $snippet.group)
                }
                Section("命令") {
                    TextEditor(text: $snippet.command)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Toggle("发送后自动回车", isOn: $snippet.autoReturn)
                    Toggle("作为粘贴发送", isOn: $snippet.asPaste)
                } footer: {
                    Text("命令中可使用 {{变量}}")
                }
            }
            .navigationTitle(snippet.name.isEmpty ? "新建片段" : "编辑片段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let i = store.snippets.firstIndex(where: { $0.id == snippet.id }) { store.snippets[i] = snippet }
                        else { store.snippets.append(snippet) }
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                    .disabled(snippet.name.isEmpty || snippet.command.isEmpty)
                }
            }
        }
    }
}

// MARK: - 传输

struct TransfersView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        List {
            ForEach(store.transfers) { t in
                HStack(spacing: 14) {
                    IconTile(symbol: t.direction == .upload ? "arrow.up" : "arrow.down",
                             colors: t.state == .failed ? Color.tileRed : (t.direction == .upload ? Color.tileGreen : Color.tileBlue), size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.localName).lineLimit(1)
                        Text("\(t.hostName) · \(t.remotePath)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        if t.state == .running {
                            ProgressView(value: Double(t.bytes), total: Double(max(t.total, 1)))
                        } else {
                            Text(t.state == .done ? ByteCountFormatter.string(fromByteCount: t.total, countStyle: .file) + " · " + t.date.relative : t.message)
                                .font(.caption2).foregroundStyle(t.state == .failed ? .red : .secondary)
                        }
                    }
                }
                .contextMenu { Button("复制远端路径", systemImage: "doc.on.doc") { Clipboard.copy(t.remotePath) } }
            }
        }
        .overlay {
            if store.transfers.isEmpty {
                ContentUnavailableView("暂无传输记录", systemImage: "arrow.up.arrow.down")
            }
        }
        .navigationTitle("传输")
        .toolbar {
            if !store.transfers.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("清空") { store.transfers.removeAll { $0.state != .running } }
                }
            }
        }
    }
}
