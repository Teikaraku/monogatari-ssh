import Foundation
import SwiftUI

// MARK: - Host

enum ConnectionProtocol: String, Codable, CaseIterable, Identifiable {
    case ssh, telnet
    var id: String { rawValue }
    var title: String { self == .ssh ? "SSH" : "Telnet" }
    var defaultPort: Int { self == .ssh ? 22 : 23 }
}

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password, key
    var id: String { rawValue }
    var title: String { self == .password ? "密码" : "SSH 密钥" }
}

/// 断线或重新打开时恢复远端会话。对跑 Claude Code 这类长任务很关键。
enum SessionRestore: String, Codable, CaseIterable, Identifiable {
    case none, tmux, screen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "无"
        case .tmux: return "tmux"
        case .screen: return "screen"
        }
    }
}

/// 连接后自动启动的 agent。
enum AgentPreset: String, Codable, CaseIterable, Identifiable {
    case none, claude, claudeContinue, codex, gemini, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "不启动"
        case .claude: return "Claude Code"
        case .claudeContinue: return "Claude Code（继续上次）"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .custom: return "自定义命令"
        }
    }
    /// 启动命令（可在「设置 → AI Agent」自定义，如 claude --model opus）
    var command: String? {
        let d = UserDefaults.standard
        func get(_ key: String, _ fallback: String) -> String {
            let v = (d.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? fallback : v
        }
        switch self {
        case .none, .custom: return nil
        case .claude: return get("cmdClaude", "claude")
        case .claudeContinue: return get("cmdClaude", "claude") + " --continue"
        case .codex: return get("cmdCodex", "codex")
        case .gemini: return get("cmdGemini", "gemini")
        }
    }
}

struct PortForward: Codable, Hashable, Identifiable {
    var id = UUID()
    var localPort: Int = 8080
    var remoteHost: String = "127.0.0.1"
    var remotePort: Int = 80
    var enabled: Bool = true

    var summary: String { "localhost:\(localPort) → \(remoteHost):\(remotePort)" }
}

enum HostIcon: String, Codable, CaseIterable, Identifiable {
    case server, linux, debian, ubuntu, apple, cloud, cpu, pi, windows
    var id: String { rawValue }
    var title: String {
        switch self {
        case .server: return "服务器"
        case .linux: return "Linux"
        case .debian: return "Debian"
        case .ubuntu: return "Ubuntu"
        case .apple: return "Mac"
        case .cloud: return "云主机"
        case .cpu: return "开发机"
        case .pi: return "树莓派"
        case .windows: return "Windows"
        }
    }
    var symbol: String {
        switch self {
        case .server: return "server.rack"
        case .linux: return "terminal.fill"
        case .debian: return "hurricane"
        case .ubuntu: return "circle.hexagongrid.fill"
        case .apple: return "apple.logo"
        case .cloud: return "cloud.fill"
        case .cpu: return "cpu.fill"
        case .pi: return "memorychip.fill"
        case .windows: return "squareshape.split.2x2"
        }
    }
    var colors: [Color] {
        switch self {
        case .server: return [Color(red: 0.36, green: 0.55, blue: 0.98), Color(red: 0.36, green: 0.35, blue: 0.90)]
        case .linux: return [Color(red: 0.33, green: 0.76, blue: 0.85), Color(red: 0.30, green: 0.68, blue: 0.86)]
        case .debian: return [Color(red: 0.36, green: 0.80, blue: 0.86), Color(red: 0.25, green: 0.70, blue: 0.85)]
        case .ubuntu: return [Color(red: 0.98, green: 0.52, blue: 0.24), Color(red: 0.89, green: 0.32, blue: 0.16)]
        case .apple: return [Color(white: 0.45), Color(white: 0.25)]
        case .cloud: return [Color(red: 0.45, green: 0.72, blue: 1.0), Color(red: 0.2, green: 0.5, blue: 0.95)]
        case .cpu: return [Color(red: 0.42, green: 0.80, blue: 0.45), Color(red: 0.25, green: 0.66, blue: 0.47)]
        case .pi: return [Color(red: 0.93, green: 0.30, blue: 0.45), Color(red: 0.78, green: 0.17, blue: 0.35)]
        case .windows: return [Color(red: 0.2, green: 0.6, blue: 0.95), Color(red: 0.1, green: 0.45, blue: 0.85)]
        }
    }

    /// 根据 /etc/os-release 的 ID 自动选择图标。
    static func detect(osRelease: String) -> HostIcon? {
        let lower = osRelease.lowercased()
        let id = lower.split(separator: "\n").first { $0.hasPrefix("id=") }?
            .dropFirst(3).trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) ?? ""
        switch id {
        case "debian": return .debian
        case "ubuntu": return .ubuntu
        case "raspbian": return .pi
        case "": return lower.contains("darwin") ? .apple : nil
        default: return .linux
        }
    }
}

struct Host: Codable, Hashable, Identifiable {
    var id = UUID()
    var alias: String = ""
    var hostname: String = ""
    var port: Int = 22
    var username: String = "root"
    var proto: ConnectionProtocol = .ssh
    var auth: AuthMethod = .password
    var keyID: UUID?
    var jumpHostID: UUID?
    var restore: SessionRestore = .none
    var tmuxSession: String = ""
    var agent: AgentPreset = .none
    var startupCommand: String = ""
    var themeID: String = TerminalTheme.defaultID
    var icon: HostIcon = .server
    var forwards: [PortForward] = []
    var keepAliveSeconds: Int = 30
    var group: String = ""
    var notes: String = ""
    var lastConnected: Date?
    var createdAt: Date = Date()

    var displayName: String { alias.isEmpty ? hostname : alias }
    var address: String { port == proto.defaultPort ? hostname : "\(hostname):\(port)" }
    var sshCommand: String {
        port == 22 ? "ssh \(username)@\(hostname)" : "ssh -p \(port) \(username)@\(hostname)"
    }
    var effectiveTmuxName: String {
        let base = tmuxSession.isEmpty ? "mono" : tmuxSession
        return base.replacingOccurrences(of: " ", with: "-")
    }
}

// MARK: - Keys

enum KeyKind: String, Codable {
    case ed25519, rsa, ecdsaP256, ecdsaP384, ecdsaP521, unknown
    var title: String {
        switch self {
        case .ed25519: return "ED25519"
        case .rsa: return "RSA"
        case .ecdsaP256: return "ECDSA P-256"
        case .ecdsaP384: return "ECDSA P-384"
        case .ecdsaP521: return "ECDSA P-521"
        case .unknown: return "未知"
        }
    }
}

struct SSHKeyItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var kind: KeyKind
    var publicKey: String
    var hasPassphrase: Bool
    var createdAt: Date = Date()
}

// MARK: - Known hosts (指纹)

struct KnownHost: Codable, Hashable, Identifiable {
    var id = UUID()
    var host: String
    var port: Int
    var keyType: String
    var fingerprint: String   // SHA256:base64
    var openSSHKey: String
    var addedAt: Date = Date()

    var endpoint: String { port == 22 ? host : "[\(host)]:\(port)" }
}

// MARK: - Snippets

struct Snippet: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var command: String
    var group: String = "常用"
    /// 发送后自动回车
    var autoReturn: Bool = true
    /// 以 bracketed paste 方式发送（多行内容给 agent 时不会被逐行执行）
    var asPaste: Bool = false
}

// MARK: - Transfers

struct TransferRecord: Codable, Hashable, Identifiable {
    enum Direction: String, Codable { case upload, download }
    enum State: String, Codable { case running, done, failed }
    var id = UUID()
    var hostName: String
    var remotePath: String
    var localName: String
    var direction: Direction
    var bytes: Int64
    var total: Int64
    var state: State
    var message: String = ""
    var date: Date = Date()
}

// MARK: - 容错解码：新版本加字段时，旧数据缺少的键用默认值，不会整体解码失败丢数据

private extension KeyedDecodingContainer {
    func v<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

extension Host {
    enum CodingKeys: String, CodingKey {
        case id, alias, hostname, port, username, proto, auth, keyID, jumpHostID, restore, tmuxSession, agent,
             startupCommand, themeID, icon, forwards, keepAliveSeconds, group, notes, lastConnected, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Host()
        id = c.v(.id, d.id)
        alias = c.v(.alias, d.alias)
        hostname = c.v(.hostname, d.hostname)
        port = c.v(.port, d.port)
        username = c.v(.username, d.username)
        proto = c.v(.proto, d.proto)
        auth = c.v(.auth, d.auth)
        keyID = c.v(.keyID, d.keyID)
        jumpHostID = c.v(.jumpHostID, d.jumpHostID)
        restore = c.v(.restore, d.restore)
        tmuxSession = c.v(.tmuxSession, d.tmuxSession)
        agent = c.v(.agent, d.agent)
        startupCommand = c.v(.startupCommand, d.startupCommand)
        themeID = c.v(.themeID, d.themeID)
        icon = c.v(.icon, d.icon)
        forwards = c.v(.forwards, d.forwards)
        keepAliveSeconds = c.v(.keepAliveSeconds, d.keepAliveSeconds)
        group = c.v(.group, d.group)
        notes = c.v(.notes, d.notes)
        lastConnected = c.v(.lastConnected, d.lastConnected)
        createdAt = c.v(.createdAt, d.createdAt)
    }
}

extension Snippet {
    enum CodingKeys: String, CodingKey { case id, name, command, group, autoReturn, asPaste }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: c.v(.id, UUID()), name: c.v(.name, ""), command: c.v(.command, ""),
                  group: c.v(.group, "常用"), autoReturn: c.v(.autoReturn, true), asPaste: c.v(.asPaste, false))
    }
}
