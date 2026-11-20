import Foundation
import Crypto
import Citadel
import NIOCore
import NIOSSH

enum KeyError: LocalizedError {
    case unsupported(String)
    case wrongPassphrase
    case missing

    var errorDescription: String? {
        switch self {
        case .unsupported(let s): return "不支持的私钥格式：\(s)"
        case .wrongPassphrase: return "私钥口令错误，或私钥已损坏"
        case .missing: return "找不到私钥，请在「密钥」里重新导入"
        }
    }
}

/// 私钥解析 / 生成 / 公钥导出。
enum KeyParser {
    struct Parsed {
        var kind: KeyKind
        var publicKey: String
        var auth: (String) -> SSHAuthenticationMethod  // username -> auth
    }

    static func parse(_ text: String, passphrase: String?) throws -> Parsed {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = passphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }

        if key.contains("BEGIN OPENSSH PRIVATE KEY") {
            let kind = detectOpenSSHKind(key)
            switch kind {
            case .ed25519:
                do {
                    let k = try Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: pass)
                    return Parsed(kind: .ed25519, publicKey: publicLine(ed25519: k.publicKey),
                                  auth: { .ed25519(username: $0, privateKey: k) })
                } catch { throw pass == nil ? KeyError.wrongPassphrase : KeyError.wrongPassphrase }
            case .rsa:
                do {
                    let k = try Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: pass)
                    return Parsed(kind: .rsa, publicKey: publicLine(rsa: k),
                                  auth: { .rsa(username: $0, privateKey: k) })
                } catch { throw KeyError.wrongPassphrase }
            default:
                throw KeyError.unsupported("OpenSSH 格式的 ECDSA 私钥请转成 PEM：ssh-keygen -p -m PEM -f 私钥文件")
            }
        }

        if key.contains("BEGIN EC PRIVATE KEY") || key.contains("BEGIN PRIVATE KEY") {
            if let k = try? P256.Signing.PrivateKey(pemRepresentation: key) {
                return Parsed(kind: .ecdsaP256, publicKey: publicLine(ecdsa: "nistp256", x963: k.publicKey.x963Representation),
                              auth: { .p256(username: $0, privateKey: k) })
            }
            if let k = try? P384.Signing.PrivateKey(pemRepresentation: key) {
                return Parsed(kind: .ecdsaP384, publicKey: publicLine(ecdsa: "nistp384", x963: k.publicKey.x963Representation),
                              auth: { .p384(username: $0, privateKey: k) })
            }
            if let k = try? P521.Signing.PrivateKey(pemRepresentation: key) {
                return Parsed(kind: .ecdsaP521, publicKey: publicLine(ecdsa: "nistp521", x963: k.publicKey.x963Representation),
                              auth: { .p521(username: $0, privateKey: k) })
            }
            if let k = try? Curve25519.Signing.PrivateKey(pemLike: key) {
                return Parsed(kind: .ed25519, publicKey: publicLine(ed25519: k.publicKey),
                              auth: { .ed25519(username: $0, privateKey: k) })
            }
        }
        if key.contains("BEGIN RSA PRIVATE KEY") {
            throw KeyError.unsupported("PEM 格式 RSA，请转换：ssh-keygen -p -f 私钥文件（会转成 OpenSSH 格式）")
        }
        throw KeyError.unsupported("无法识别")
    }

    /// 生成 ED25519 密钥，返回 (OpenSSH 私钥文本, 公钥行)
    static func generateEd25519(comment: String) -> (String, String) {
        let k = Curve25519.Signing.PrivateKey()
        let priv = k.makeSSHRepresentation(comment: comment)
        return (priv, publicLine(ed25519: k.publicKey) + " " + comment)
    }

    // MARK: - helpers

    private static func detectOpenSSHKind(_ pem: String) -> KeyKind {
        let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let data = Data(base64Encoded: body) else { return .unknown }
        // 头部明文含公钥类型字符串
        let head = String(decoding: data.prefix(200), as: UTF8.self)
        if head.contains("ssh-ed25519") { return .ed25519 }
        if head.contains("ssh-rsa") { return .rsa }
        if head.contains("nistp256") { return .ecdsaP256 }
        if head.contains("nistp384") { return .ecdsaP384 }
        if head.contains("nistp521") { return .ecdsaP521 }
        return .unknown
    }

    private static func sshString(_ d: Data) -> Data {
        var out = Data()
        var len = UInt32(d.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(d)
        return out
    }

    static func publicLine(ed25519 pub: Curve25519.Signing.PublicKey) -> String {
        let blob = sshString(Data("ssh-ed25519".utf8)) + sshString(pub.rawRepresentation)
        return "ssh-ed25519 " + blob.base64EncodedString()
    }

    static func publicLine(ecdsa curve: String, x963: Data) -> String {
        let type = "ecdsa-sha2-\(curve)"
        let blob = sshString(Data(type.utf8)) + sshString(Data(curve.utf8)) + sshString(x963)
        return type + " " + blob.base64EncodedString()
    }

    static func publicLine(rsa: Insecure.RSA.PrivateKey) -> String {
        var buf = ByteBuffer()
        _ = rsa.publicKey.write(to: &buf)
        let body = Data(buf.readableBytesView)
        let blob = sshString(Data("ssh-rsa".utf8)) + body
        return "ssh-rsa " + blob.base64EncodedString()
    }

    /// OpenSSH 公钥行 → "SHA256:xxxx"
    static func fingerprint(openSSHLine: String) -> String {
        let parts = openSSHLine.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return "?" }
        let digest = SHA256.hash(data: blob)
        let b64 = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:" + b64
    }
}

private extension Curve25519.Signing.PrivateKey {
    /// PKCS#8 PEM 的 ED25519（BEGIN PRIVATE KEY）：最后 32 字节是种子。
    init(pemLike pem: String) throws {
        let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: body), der.count >= 48,
              der.range(of: Data([0x06, 0x03, 0x2b, 0x65, 0x70])) != nil else {
            throw KeyError.unsupported("PEM")
        }
        try self.init(rawRepresentation: der.suffix(32))
    }
}
