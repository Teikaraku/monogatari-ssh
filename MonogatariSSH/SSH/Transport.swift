import Foundation
import Citadel
import NIOCore
import NIOPosix
import NIOSSH
import Crypto

/// 终端会话使用的传输层（SSH / Telnet）。
protocol TerminalTransport: AnyObject {
    /// 可能在后台线程回调
    var onData: ((Data) -> Void)? { get set }
    var onClose: ((Error?) -> Void)? { get set }
    func start(cols: Int, rows: Int) async throws
    func write(_ data: Data)
    func resize(cols: Int, rows: Int)
    func close()
}

enum ConnectError: LocalizedError {
    case hostKeyRejected
    case hostKeyChanged(String)
    case noPassword
    case jumpLoop
    case message(String)

    var errorDescription: String? {
        switch self {
        case .hostKeyRejected: return "已拒绝该主机指纹"
        case .hostKeyChanged(let fp): return "主机指纹已变化！可能存在中间人攻击。\n新指纹：\(fp)\n如确认服务器重装过，请到「指纹」里删除旧记录后重连。"
        case .noPassword: return "未保存密码"
        case .jumpLoop: return "跳板机配置形成了循环"
        case .message(let m): return m
        }
    }
}

/// 首次连接时询问用户是否信任指纹。由 UI 实现。
@MainActor
protocol HostKeyPrompter: AnyObject {
    func confirmNewHostKey(host: String, port: Int, keyType: String, fingerprint: String) async -> Bool
}

/// TOFU 主机指纹校验，结果写入「指纹」列表。
final class HostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    let host: String
    let port: Int
    weak var prompter: HostKeyPrompter?
    private(set) var rejectReason: ConnectError?

    init(host: String, port: Int, prompter: HostKeyPrompter?) {
        self.host = host
        self.port = port
        self.prompter = prompter
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let line = String(openSSHPublicKey: hostKey)
        let type = String(line.split(separator: " ").first ?? "")
        let fp = KeyParser.fingerprint(openSSHLine: line)
        let host = self.host, port = self.port
        Task { @MainActor in
            let store = AppStore.shared
            if let known = store.knownHost(host: host, port: port) {
                if known.fingerprint == fp {
                    validationCompletePromise.succeed(())
                } else {
                    self.rejectReason = .hostKeyChanged(fp)
                    validationCompletePromise.fail(ConnectError.hostKeyChanged(fp))
                }
                return
            }
            let ok = await self.prompter?.confirmNewHostKey(host: host, port: port, keyType: type, fingerprint: fp) ?? true
            if ok {
                store.trust(KnownHost(host: host, port: port, keyType: type, fingerprint: fp, openSSHKey: line))
                validationCompletePromise.succeed(())
            } else {
                self.rejectReason = .hostKeyRejected
                validationCompletePromise.fail(ConnectError.hostKeyRejected)
            }
        }
    }
}

/// 建立 SSH 连接（含跳板机链）。
enum SSHConnector {
    @MainActor
    static func authMethod(for host: Host) throws -> SSHAuthenticationMethod {
        switch host.auth {
        case .password:
            guard let pw = AppStore.shared.password(for: host) else { throw ConnectError.noPassword }
            return .passwordBased(username: host.username, password: pw)
        case .key:
            guard let keyID = host.keyID,
                  let text = Keychain.get(Keychain.keyPrivate(keyID)) else { throw KeyError.missing }
            let parsed = try KeyParser.parse(text, passphrase: Keychain.get(Keychain.keyPassphrase(keyID)))
            return parsed.auth(host.username)
        }
    }

    @MainActor
    static func connect(_ host: Host, prompter: HostKeyPrompter?) async throws -> (SSHClient, [SSHClient]) {
        // 解析跳板机链：最外层先连
        var chain: [Host] = []
        var cursor = host.jumpHostID.flatMap { AppStore.shared.host($0) }
        var seen: Set<UUID> = [host.id]
        while let j = cursor {
            guard !seen.contains(j.id) else { throw ConnectError.jumpLoop }
            seen.insert(j.id)
            chain.insert(j, at: 0)
            cursor = j.jumpHostID.flatMap { AppStore.shared.host($0) }
        }

        var jumps: [SSHClient] = []
        var current: SSHClient?
        for h in chain + [host] {
            let auth = try authMethod(for: h)
            let validator = HostKeyValidator(host: h.hostname, port: h.port, prompter: prompter)
            var settings = SSHClientSettings(
                host: h.hostname, port: h.port,
                authenticationMethod: { auth },
                hostKeyValidator: .custom(validator)
            )
            settings.algorithms = .all
            settings.connectTimeout = .seconds(15)
            do {
                let next: SSHClient
                if let current {
                    next = try await current.jump(to: settings)
                } else {
                    next = try await SSHClient.connect(to: settings)
                }
                if h.id != host.id { jumps.append(next) }
                current = next
            } catch {
                if let reason = validator.rejectReason { throw reason }
                throw friendly(error, host: h)
            }
        }
        return (current!, jumps)
    }

    static func friendly(_ error: Error, host: Host) -> Error {
        let text = String(describing: error)
        if text.contains("allAuthenticationOptionsFailed") || text.contains("authentication") {
            return ConnectError.message("认证失败：\(host.username)@\(host.hostname) 的密码或密钥不正确")
        }
        if text.contains("connectTimeout") || text.contains("timeout") {
            return ConnectError.message("连接超时：\(host.address)")
        }
        if text.contains("connection refused") || text.contains("Connection refused") {
            return ConnectError.message("连接被拒绝：\(host.address) 端口未开放")
        }
        if text.contains("NXDOMAIN") || text.contains("resolve") || text.contains("getaddrinfo") {
            return ConnectError.message("无法解析主机名：\(host.hostname)")
        }
        return ConnectError.message("连接失败：\(error.localizedDescription)")
    }
}

/// SSH PTY 传输。
final class SSHTransport: TerminalTransport {
    var onData: ((Data) -> Void)?
    var onClose: ((Error?) -> Void)?

    let host: Host
    weak var prompter: HostKeyPrompter?
    /// shell 就绪后要输入的命令（tmux / agent / 自定义）
    var bootstrap: String?

    private(set) var client: SSHClient?
    private var jumps: [SSHClient] = []
    private var writer: TTYStdinWriter?
    /// 所有写入按顺序进入同一条队列，由单个任务依次发送，保证按键不乱序
    private let outbox = AsyncStream<ByteBuffer>.makeStream()
    private var outboxTask: Task<Void, Never>?
    private var ptyTask: Task<Void, Never>?
    private var keepAlive: Task<Void, Never>?
    private var forwarders: [PortForwarder] = []
    private var pendingSize: (Int, Int)?
    private var closed = false

    init(host: Host, prompter: HostKeyPrompter?) {
        self.host = host
        self.prompter = prompter
    }

    @MainActor
    func start(cols: Int, rows: Int) async throws {
        let (client, jumps) = try await SSHConnector.connect(host, prompter: prompter)
        self.client = client
        self.jumps = jumps
        client.onDisconnect { [weak self] in
            Task { @MainActor in self?.finish(nil) }
        }

        for f in host.forwards where f.enabled {
            let fw = PortForwarder(client: client, rule: f)
            do { try await fw.start(); forwarders.append(fw) }
            catch { onData?(Data("\r\n\u{1b}[33m[端口转发 \(f.localPort) 启动失败：\(error.localizedDescription)]\u{1b}[0m\r\n".utf8)) }
        }

        let ready = AsyncStream<Void>.makeStream()
        // 读取循环放到后台，不继承 MainActor：主线程忙于渲染/手势时不会堵住数据接收
        ptyTask = Task.detached { [weak self] in
            guard let self else { return }
            let req = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true, term: "xterm-256color",
                terminalCharacterWidth: cols, terminalRowHeight: rows,
                terminalPixelWidth: 0, terminalPixelHeight: 0,
                terminalModes: SSHTerminalModes([:]))
            let env = [SSHChannelRequestEvent.EnvironmentRequest(wantReply: false, name: "LANG", value: "en_US.UTF-8"),
                       SSHChannelRequestEvent.EnvironmentRequest(wantReply: false, name: "COLORTERM", value: "truecolor")]
            do {
                try await client.withPTY(req, environment: env) { inbound, outbound in
                    self.writer = outbound
                    self.startOutbox(outbound)
                    ready.continuation.yield()
                    ready.continuation.finish()
                    for try await chunk in inbound {
                        switch chunk {
                        case .stdout(let buf), .stderr(let buf):
                            // 直接在网络线程交给终端解析（SwiftTerm 支持跨线程 feed），主线程只负责渲染与手势
                            self.onData?(Data(buf.readableBytesView))
                        }
                    }
                }
                await MainActor.run { self.finish(nil) }
            } catch {
                ready.continuation.finish()
                await MainActor.run { self.finish(error) }
            }
        }
        for await _ in ready.stream { break }
        guard writer != nil else { throw ConnectError.message("无法打开终端通道") }

        if let size = pendingSize { resize(cols: size.0, rows: size.1) }
        if let bootstrap, !bootstrap.isEmpty { write(Data((bootstrap + "\r").utf8)) }

        if host.keepAliveSeconds > 0 {
            let interval = UInt64(host.keepAliveSeconds) * 1_000_000_000
            keepAlive = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: interval)
                    guard let self, let client = self.client, client.isConnected else { return }
                    // 轻量探活：开一个 exec 通道执行 true
                    _ = try? await client.executeCommand("true")
                }
            }
        }

        // 后台识别系统以设置图标
        let hid = host.id
        Task { [weak client] in
            guard let client, let out = try? await client.executeCommand("cat /etc/os-release 2>/dev/null || uname -s") else { return }
            let text = String(buffer: out)
            await MainActor.run { if let icon = HostIcon.detect(osRelease: text) { AppStore.shared.setIcon(icon, for: hid) } }
        }
    }

    func write(_ data: Data) {
        guard writer != nil, !closed else { return }
        outbox.continuation.yield(ByteBuffer(bytes: data))
    }

    private func startOutbox(_ w: TTYStdinWriter) {
        let stream = outbox.stream
        outboxTask = Task.detached {
            for await buf in stream {
                do { try await w.write(buf) } catch { break }
            }
        }
    }

    func resize(cols: Int, rows: Int) {
        guard let writer else { pendingSize = (cols, rows); return }
        Task { try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0) }
    }

    func close() {
        closed = true
        keepAlive?.cancel()
        ptyTask?.cancel()
        outbox.continuation.finish()
        outboxTask?.cancel()
        forwarders.forEach { $0.stop() }
        forwarders.removeAll()
        let c = client, j = jumps
        client = nil
        writer = nil
        Task {
            try? await c?.close()
            for x in j.reversed() { try? await x.close() }
        }
    }

    @MainActor
    private func finish(_ error: Error?) {
        guard !closed else { return }
        closed = true
        keepAlive?.cancel()
        forwarders.forEach { $0.stop() }
        onClose?(error)
    }

    /// 为 SFTP 等复用当前连接
    func openSFTP() async throws -> SFTPClient {
        guard let client else { throw ConnectError.message("未连接") }
        return try await client.openSFTP()
    }
}
