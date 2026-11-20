import Foundation
import Network

/// 极简 Telnet：处理 IAC 协商（同意 ECHO / SGA / NAWS，拒绝其他），支持窗口大小上报。
final class TelnetTransport: TerminalTransport {
    var onData: ((Data) -> Void)?
    var onClose: ((Error?) -> Void)?

    private let host: Host
    private var conn: NWConnection?
    private let queue = DispatchQueue(label: "telnet")
    private var size = (80, 24)
    private var naws = false

    private enum IAC {
        static let IAC: UInt8 = 255, DONT: UInt8 = 254, DO: UInt8 = 253, WONT: UInt8 = 252, WILL: UInt8 = 251
        static let SB: UInt8 = 250, SE: UInt8 = 240
        static let ECHO: UInt8 = 1, SGA: UInt8 = 3, TTYPE: UInt8 = 24, NAWS: UInt8 = 31
    }

    init(host: Host) { self.host = host }

    func start(cols: Int, rows: Int) async throws {
        size = (cols, rows)
        let c = NWConnection(host: .init(host.hostname), port: .init(integerLiteral: UInt16(host.port)), using: .tcp)
        conn = c
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            c.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; cont.resume() }
                case .failed(let e):
                    if !resumed { resumed = true; cont.resume(throwing: e) } else { self?.finish(e) }
                case .cancelled:
                    if !resumed { resumed = true; cont.resume(throwing: ConnectError.message("已取消")) } else { self?.finish(nil) }
                default: break
                }
            }
            c.start(queue: queue)
        }
        receive()
    }

    private func receive() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data, !data.isEmpty {
                let clean = self.process(data)
                if !clean.isEmpty { self.onData?(clean) }
            }
            if done || err != nil { self.finish(err); return }
            self.receive()
        }
    }

    private func process(_ data: Data) -> Data {
        var out = Data()
        let bytes = [UInt8](data)
        var idx = 0
        while idx < bytes.count {
            let b = bytes[idx]
            if b == IAC.IAC, idx + 1 < bytes.count {
                let cmd = bytes[idx + 1]
                if cmd == IAC.IAC { out.append(255); idx += 2; continue }
                if cmd == IAC.SB {
                    // 跳过子协商
                    var j = idx + 2
                    while j + 1 < bytes.count, !(bytes[j] == IAC.IAC && bytes[j + 1] == IAC.SE) { j += 1 }
                    idx = j + 2
                    continue
                }
                if idx + 2 < bytes.count {
                    let opt = bytes[idx + 2]
                    switch cmd {
                    case IAC.DO:
                        if opt == IAC.NAWS { send([IAC.IAC, IAC.WILL, opt]); naws = true; sendNAWS() }
                        else if opt == IAC.SGA { send([IAC.IAC, IAC.WILL, opt]) }
                        else { send([IAC.IAC, IAC.WONT, opt]) }
                    case IAC.WILL:
                        if opt == IAC.ECHO || opt == IAC.SGA { send([IAC.IAC, IAC.DO, opt]) }
                        else { send([IAC.IAC, IAC.DONT, opt]) }
                    default: break
                    }
                    idx += 3
                    continue
                }
                idx += 2
                continue
            }
            out.append(b)
            idx += 1
        }
        return out
    }

    private func send(_ bytes: [UInt8]) {
        conn?.send(content: Data(bytes), completion: .contentProcessed { _ in })
    }

    private func sendNAWS() {
        guard naws else { return }
        let w = UInt16(size.0), h = UInt16(size.1)
        send([IAC.IAC, IAC.SB, IAC.NAWS, UInt8(w >> 8), UInt8(w & 0xff), UInt8(h >> 8), UInt8(h & 0xff), IAC.IAC, IAC.SE])
    }

    func write(_ data: Data) {
        // 转义 0xFF
        var out = Data()
        for b in data { out.append(b); if b == 255 { out.append(255) } }
        conn?.send(content: out, completion: .contentProcessed { _ in })
    }

    func resize(cols: Int, rows: Int) {
        size = (cols, rows)
        queue.async { self.sendNAWS() }
    }

    func close() {
        onClose = nil
        conn?.cancel()
        conn = nil
    }

    private func finish(_ err: Error?) {
        let cb = onClose
        onClose = nil
        DispatchQueue.main.async { cb?(err) }
    }
}
