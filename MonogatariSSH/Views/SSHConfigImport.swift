import SwiftUI

/// 解析 OpenSSH 配置（~/.ssh/config）
enum SSHConfigParser {
    struct Entry: Identifiable, Hashable {
        var id: String { alias }
        var alias: String
        var hostname: String = ""
        var port: Int = 22
        var user: String = ""
        var proxyJump: String = ""
        var selected = true
    }

    static func parse(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        var current: [Entry] = []
        func flush() { entries += current; current = [] }
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" }).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"="))
            switch key {
            case "host":
                flush()
                // 跳过通配符
                current = value.split(separator: " ").map(String.init)
                    .filter { !$0.contains("*") && !$0.contains("?") && !$0.hasPrefix("!") }
                    .map { Entry(alias: $0, hostname: $0) }
            case "match":
                flush()
            case "hostname": for i in current.indices { current[i].hostname = value }
            case "port": for i in current.indices { current[i].port = Int(value) ?? 22 }
            case "user": for i in current.indices { current[i].user = value }
            case "proxyjump": for i in current.indices { current[i].proxyJump = value.split(separator: ",").first.map(String.init) ?? "" }
            default: break
            }
        }
        flush()
        return entries
    }
}

struct SSHConfigImportView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var entries: [SSHConfigParser.Entry] = []
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.caption.monospaced())
                        .frame(minHeight: 140)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("粘贴", systemImage: "doc.on.clipboard") { text = UIPasteboard.general.string ?? "" }
                        Spacer()
                        Button("选择文件", systemImage: "folder") { picking = true }
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("ssh config")
                } footer: {
                    Text("密码和私钥需导入后单独设置")
                }
                if !entries.isEmpty {
                    Section("将导入 \(entries.filter(\.selected).count) 台主机") {
                        ForEach($entries) { $e in
                            Toggle(isOn: $e.selected) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.alias).font(.body.weight(.medium))
                                    Text("\(e.user.isEmpty ? "root" : e.user)@\(e.hostname)\(e.port == 22 ? "" : ":\(e.port)")\(e.proxyJump.isEmpty ? "" : " 经 \(e.proxyJump)")")
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(store.hosts.contains { $0.alias == e.alias })
                        }
                    }
                }
            }
            .navigationTitle("导入 ssh config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { importAll() } label: { Image(systemName: "checkmark") }
                        .disabled(!entries.contains { $0.selected })
                }
            }
            .onChange(of: text) { _, t in
                entries = SSHConfigParser.parse(t).map { e in
                    var e = e
                    if store.hosts.contains(where: { $0.alias == e.alias }) { e.selected = false }
                    return e
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { r in
                if case .success(let url) = r {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                }
            }
        }
    }

    private func importAll() {
        let chosen = entries.filter(\.selected)
        var created: [String: UUID] = [:]
        for e in chosen {
            var h = Host()
            h.alias = e.alias
            h.hostname = e.hostname
            h.port = e.port
            h.username = e.user.isEmpty ? "root" : e.user
            store.upsert(h, password: nil)
            created[e.alias] = h.id
        }
        // 第二遍：解析 ProxyJump（可能指向刚导入的或已有的主机）
        for e in chosen where !e.proxyJump.isEmpty {
            let target = e.proxyJump.split(separator: "@").last.map(String.init) ?? e.proxyJump
            let jumpID = created[target] ?? store.hosts.first { $0.alias == target || $0.hostname == target }?.id
            if let id = created[e.alias], let jumpID, var h = store.host(id) {
                h.jumpHostID = jumpID
                store.upsert(h, password: nil)
            }
        }
        Toast.shared.show("已导入 \(chosen.count) 台主机")
        Haptics.success()
        dismiss()
    }
}
