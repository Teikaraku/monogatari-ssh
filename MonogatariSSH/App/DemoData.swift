import SwiftUI

/// CI 截图用：启动参数 `-demo home|hosts|edit|terminal|settings|sessions|snippets`
/// 只在带参数启动时生效，正常使用不受影响。
enum DemoData {
    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demo"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    static var active: Bool { screen != nil }

    static var initialTab: AppTab {
        switch screen {
        case "settings": return .settings
        case "sessions": return .sessions
        default: return .home
        }
    }

    @MainActor
    static func installIfRequested() {
        guard active else { return }
        let store = AppStore.shared
        var box = Host(alias: "Box", hostname: "ssh.instabox.sh", port: 22, username: "root")
        box.icon = .linux
        box.lastConnected = Date().addingTimeInterval(-600)
        var us = Host(alias: "US", hostname: "216.167.70.23", port: 22, username: "root")
        us.icon = .debian
        us.restore = .tmux
        us.agent = .claude
        us.lastConnected = Date().addingTimeInterval(-60)
        var dev = Host(alias: "Dev Mac", hostname: "192.168.1.20", port: 22, username: "me")
        dev.icon = .apple
        dev.auth = .key
        store.hosts = [box, us, dev]
        store.upsert(us, password: "demo-password-123")
        store.knownHosts = [KnownHost(host: "216.167.70.23", port: 22, keyType: "ssh-ed25519",
                                      fingerprint: "SHA256:q3sN7k2yYb0x9Lw1uG4mZp8cVt6aDf5eHr2jKs1oXcE", openSSHKey: "")]
        if screen == "hosts" { SessionManager.shared.path.append(Route.hosts) }
        if screen == "snippets" { SessionManager.shared.path.append(Route.snippets) }
        if screen == "sessions" { _ = SessionManager.shared.open(box) }
        if screen == "terminal" || screen == "sessions" {
            let s = SessionManager.shared.open(us)
            if screen == "terminal" { SessionManager.shared.path.append(Route.terminal(s.id)) }
        }
    }

    /// 等待权限确认的演示输出
    static let permissionSample: String = {
        let esc = "\u{1b}"
        var s = "\(esc)[38;5;209m⏺\(esc)[0m \(esc)[1mBash\(esc)[0m(npm run build)\r\n\r\n"
        s += "╭────────────────────────────────────────╮\r\n"
        s += "│ Bash command                           │\r\n"
        s += "│   npm run build                        │\r\n"
        s += "│ Do you want to proceed?                │\r\n"
        s += "│ ❯ 1. Yes                               │\r\n"
        s += "│   2. Yes, and don't ask again          │\r\n"
        s += "│   3. No, and tell Claude what to do    │\r\n"
        s += "╰────────────────────────────────────────╯\r\n"
        return s
    }()

    /// 离线演示输出（模拟 Claude Code 在 tmux 里）
    static let terminalSample: String = {
        let esc = "\u{1b}"
        var s = "\(esc)[32mroot@RainYun-YL5JGMAG\(esc)[0m:\(esc)[34m~/monogatari\(esc)[0m# claude\r\n"
        s += "\(esc)[38;5;209m╭──────────────────────────────────────────╮\(esc)[0m\r\n"
        s += "\(esc)[38;5;209m│\(esc)[0m ✻ Welcome to \(esc)[1mClaude Code\(esc)[0m!                  \(esc)[38;5;209m│\(esc)[0m\r\n"
        s += "\(esc)[38;5;209m│\(esc)[0m   cwd: /root/monogatari                   \(esc)[38;5;209m│\(esc)[0m\r\n"
        s += "\(esc)[38;5;209m╰──────────────────────────────────────────╯\(esc)[0m\r\n\r\n"
        s += "\(esc)[2m> \(esc)[0m修复首页在 iPhone 上滑动卡顿的问题\r\n\r\n"
        s += "\(esc)[38;5;209m⏺\(esc)[0m 我先看一下列表组件的渲染逻辑。\r\n\r\n"
        s += "\(esc)[38;5;209m⏺\(esc)[0m \(esc)[1mRead\(esc)[0m(src/components/Feed.tsx)\r\n"
        s += "  ⎿  Read 214 lines\r\n\r\n"
        for i in 1...24 {
            s += "\(esc)[2m\(String(format: "%3d", 100 + i))\(esc)[0m  \(esc)[35mconst\(esc)[0m item\(i) = \(esc)[33museMemo\(esc)[0m(() => render(\(esc)[36mrows\(esc)[0m[\(i)]), [rows])\r\n"
        }
        s += "\r\n\(esc)[38;5;209m⏺\(esc)[0m \(esc)[1mUpdate\(esc)[0m(src/components/Feed.tsx)\r\n"
        s += "  ⎿  Updated with \(esc)[32m12 additions\(esc)[0m and \(esc)[31m4 removals\(esc)[0m\r\n\r\n"
        s += "\(esc)[38;5;209m⏺\(esc)[0m 已改为虚拟列表并缓存行高，滚动时不再触发整表重排。\r\n\r\n"
        s += "\(esc)[2m╭──────────────────────────────────────────╮\(esc)[0m\r\n"
        s += "\(esc)[2m│\(esc)[0m > \(esc)[7m \(esc)[0m                                       \(esc)[2m│\(esc)[0m\r\n"
        s += "\(esc)[2m╰──────────────────────────────────────────╯\(esc)[0m\r\n"
        s += "  \(esc)[2m⏵⏵ accept edits on (shift+tab to cycle)\(esc)[0m\r\n"
        return s
    }()
}
