import Foundation
import SwiftUI

/// 全局数据：主机、密钥、指纹、片段、传输记录。JSON 落盘，敏感字段走钥匙串。
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var hosts: [Host] = [] { didSet { save() } }
    @Published var keys: [SSHKeyItem] = [] { didSet { save() } }
    @Published var knownHosts: [KnownHost] = [] { didSet { save() } }
    @Published var snippets: [Snippet] = [] { didSet { save() } }
    @Published var transfers: [TransferRecord] = [] { didSet { save() } }

    private var loading = true

    private struct Payload: Codable {
        var hosts: [Host]
        var keys: [SSHKeyItem]
        var knownHosts: [KnownHost]
        var snippets: [Snippet]
        var transfers: [TransferRecord]?
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("monogatari-ssh.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let p = try? JSONDecoder().decode(Payload.self, from: data) {
            hosts = p.hosts
            keys = p.keys
            knownHosts = p.knownHosts
            snippets = p.snippets
            transfers = p.transfers ?? []
        } else {
            snippets = Snippet.presets
        }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let p = Payload(hosts: hosts, keys: keys, knownHosts: knownHosts, snippets: snippets,
                        transfers: Array(transfers.prefix(200)))
        if let data = try? JSONEncoder().encode(p) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: Hosts

    func upsert(_ host: Host, password: String?) {
        if let i = hosts.firstIndex(where: { $0.id == host.id }) { hosts[i] = host } else { hosts.append(host) }
        if let password { Keychain.set(password, for: Keychain.hostPassword(host.id)) }
    }

    func delete(host: Host) {
        hosts.removeAll { $0.id == host.id }
        Keychain.set(nil, for: Keychain.hostPassword(host.id))
    }

    func duplicate(_ host: Host) {
        var copy = host
        copy.id = UUID()
        copy.alias = host.displayName + " 副本"
        copy.lastConnected = nil
        hosts.append(copy)
        Keychain.set(password(for: host), for: Keychain.hostPassword(copy.id))
    }

    func password(for host: Host) -> String? { Keychain.get(Keychain.hostPassword(host.id)) }

    func host(_ id: UUID?) -> Host? { id.flatMap { id in hosts.first { $0.id == id } } }

    func markConnected(_ id: UUID) {
        if let i = hosts.firstIndex(where: { $0.id == id }) { hosts[i].lastConnected = Date() }
    }

    func setIcon(_ icon: HostIcon, for id: UUID) {
        if let i = hosts.firstIndex(where: { $0.id == id }), hosts[i].icon == .server { hosts[i].icon = icon }
    }

    var recentHosts: [Host] {
        hosts.filter { $0.lastConnected != nil }
            .sorted { ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast) }
            .prefix(5).map { $0 }
    }

    // MARK: Keys

    func addKey(_ item: SSHKeyItem, privateKey: String, passphrase: String?) {
        Keychain.set(privateKey, for: Keychain.keyPrivate(item.id))
        Keychain.set(passphrase, for: Keychain.keyPassphrase(item.id))
        keys.append(item)
    }

    func delete(key: SSHKeyItem) {
        keys.removeAll { $0.id == key.id }
        Keychain.set(nil, for: Keychain.keyPrivate(key.id))
        Keychain.set(nil, for: Keychain.keyPassphrase(key.id))
    }

    func key(_ id: UUID?) -> SSHKeyItem? { id.flatMap { id in keys.first { $0.id == id } } }

    // MARK: Known hosts

    func knownHost(host: String, port: Int) -> KnownHost? {
        knownHosts.first { $0.host == host && $0.port == port }
    }

    func trust(_ k: KnownHost) {
        knownHosts.removeAll { $0.host == k.host && $0.port == k.port }
        knownHosts.append(k)
    }

    // MARK: Transfers

    func record(_ t: TransferRecord) {
        if let i = transfers.firstIndex(where: { $0.id == t.id }) { transfers[i] = t } else { transfers.insert(t, at: 0) }
    }
}

extension Snippet {
    /// 面向 AI agent 的常用预置。
    static let presets: [Snippet] = [
        Snippet(name: "启动 Claude Code", command: "claude", group: "Agent"),
        Snippet(name: "继续上次对话", command: "claude --continue", group: "Agent"),
        Snippet(name: "选择历史对话", command: "claude --resume", group: "Agent"),
        Snippet(name: "更新 Claude Code", command: "claude update", group: "Agent"),
        Snippet(name: "开启 Claude 响铃通知", command: "claude config set --global preferredNotifChannel terminal_bell", group: "Agent"),
        Snippet(name: "跳过权限确认启动", command: "claude --dangerously-skip-permissions", group: "Agent", autoReturn: false),
        Snippet(name: "Claude 诊断", command: "claude doctor", group: "Agent"),
        Snippet(name: "启动 Codex", command: "codex", group: "Agent"),
        Snippet(name: "/compact 压缩上下文", command: "/compact", group: "Agent 指令"),
        Snippet(name: "/clear 清空对话", command: "/clear", group: "Agent 指令"),
        Snippet(name: "/cost 查看用量", command: "/cost", group: "Agent 指令"),
        Snippet(name: "/model 切换模型", command: "/model", group: "Agent 指令"),
        Snippet(name: "/review 代码审查", command: "/review", group: "Agent 指令"),
        Snippet(name: "/init 生成 CLAUDE.md", command: "/init", group: "Agent 指令"),
        Snippet(name: "列出 tmux 会话", command: "tmux ls", group: "tmux"),
        Snippet(name: "开启 tmux 鼠标滚动", command: "tmux set -g mouse on", group: "tmux"),
        Snippet(name: "让 Claude 处理 Issue", command: "请阅读并解决 GitHub issue #{{编号}}，完成后跑测试并总结改动。", group: "Agent 指令", asPaste: true),
        Snippet(name: "进入项目并启动 Claude", command: "cd ~/{{项目目录}} && claude", group: "Agent"),
        Snippet(name: "Git 状态", command: "git status -sb", group: "常用"),
        Snippet(name: "提交", command: "git add -A && git commit -m \"{{说明}}\"", group: "常用"),
        Snippet(name: "最近提交", command: "git log --oneline -15", group: "常用"),
        Snippet(name: "系统负载", command: "uptime && free -h && df -h /", group: "常用"),
        Snippet(name: "实时进程", command: "htop || top", group: "常用"),
        Snippet(name: "监听端口", command: "ss -tlnp", group: "常用"),
    ]
}
