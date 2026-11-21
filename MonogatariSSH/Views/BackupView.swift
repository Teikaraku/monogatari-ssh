import SwiftUI
import UniformTypeIdentifiers

/// 备份文件格式
struct BackupPayload: Codable {
    var version = 1
    var exportedAt = Date()
    var hosts: [Host]
    var snippets: [Snippet]
    var knownHosts: [KnownHost]
    var keys: [SSHKeyItem]
    /// 仅在用户选择「包含密钥与密码」时存在
    var passwords: [String: String]? // host id → password
    var privateKeys: [String: String]? // key id → private key
    var passphrases: [String: String]?
}

struct BackupView: View {
    @EnvironmentObject var store: AppStore
    @State private var includeSecrets = false
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("包含密码与私钥", isOn: $includeSecrets)
                Button("生成备份文件", systemImage: "doc.badge.arrow.up") { export() }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("分享 / 存到文件", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("导出")
            } footer: {
                if includeSecrets { Text("备份文件将包含明文密码和私钥") }
            }

            Section {
                Button("从文件导入", systemImage: "doc.badge.arrow.down") { importing = true }
            } header: {
                Text("导入")
            }

            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }

            Section("统计") {
                LabeledContent("主机", value: "\(store.hosts.count)")
                LabeledContent("密钥", value: "\(store.keys.count)")
                LabeledContent("指纹", value: "\(store.knownHosts.count)")
                LabeledContent("片段", value: "\(store.snippets.count)")
            }
        }
        .navigationTitle("备份与迁移")
        .onChange(of: includeSecrets) { _, _ in exportURL = nil }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data, .item]) { r in
            if case .success(let url) = r { importFrom(url) }
        }
    }

    private func export() {
        var p = BackupPayload(hosts: store.hosts, snippets: store.snippets, knownHosts: store.knownHosts, keys: store.keys)
        if includeSecrets {
            p.passwords = Dictionary(uniqueKeysWithValues: store.hosts.compactMap { h in store.password(for: h).map { (h.id.uuidString, $0) } })
            p.privateKeys = Dictionary(uniqueKeysWithValues: store.keys.compactMap { k in Keychain.get(Keychain.keyPrivate(k.id)).map { (k.id.uuidString, $0) } })
            p.passphrases = Dictionary(uniqueKeysWithValues: store.keys.compactMap { k in Keychain.get(Keychain.keyPassphrase(k.id)).map { (k.id.uuidString, $0) } })
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        do {
            let data = try enc.encode(p)
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("monogatari-ssh-\(f.string(from: Date())).json")
            try data.write(to: url, options: .completeFileProtection)
            exportURL = url
            message = "已生成：\(store.hosts.count) 台主机、\(store.snippets.count) 个片段\(includeSecrets ? "（含密钥）" : "")"
            Haptics.success()
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importFrom(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let p = try dec.decode(BackupPayload.self, from: Data(contentsOf: url))
            for h in p.hosts { store.upsert(h, password: p.passwords?[h.id.uuidString]) }
            for k in p.keys {
                if let i = store.keys.firstIndex(where: { $0.id == k.id }) { store.keys[i] = k } else { store.keys.append(k) }
                if let priv = p.privateKeys?[k.id.uuidString] { Keychain.set(priv, for: Keychain.keyPrivate(k.id)) }
                if let pass = p.passphrases?[k.id.uuidString] { Keychain.set(pass, for: Keychain.keyPassphrase(k.id)) }
            }
            for k in p.knownHosts { store.trust(k) }
            for s in p.snippets {
                if let i = store.snippets.firstIndex(where: { $0.id == s.id }) { store.snippets[i] = s } else { store.snippets.append(s) }
            }
            message = "已导入 \(p.hosts.count) 台主机、\(p.keys.count) 把密钥、\(p.snippets.count) 个片段"
            Haptics.success()
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }
}
