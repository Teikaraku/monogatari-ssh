import UIKit
import UserNotifications
import Network

/// app 在后台时，把 agent 的响铃 / OSC 9 / OSC 777 通知转成系统通知。
/// Claude Code 里执行：claude config set --global preferredNotifChannel terminal_bell
/// 之后它在需要确认、任务完成时会响铃，就能在锁屏上收到提醒。
@MainActor
enum Notifier {
    private static var asked = false
    private static var lastFire: [String: Date] = [:]

    static func requestIfNeeded() {
        guard AppSettings.shared.notifyBell, !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static var appInBackground: Bool {
        UIApplication.shared.applicationState != .active
    }

    /// - Parameter key: 同一来源 4 秒内只提醒一次，避免连环响铃刷屏
    static func post(title: String, body: String, key: String, force: Bool = false) {
        guard AppSettings.shared.notifyBell, force || appInBackground else { return }
        let now = Date()
        if let last = lastFire[key], now.timeIntervalSince(last) < 4 { return }
        lastFire[key] = now
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.threadIdentifier = key
        // key 以会话 UUID 开头，点通知时据此跳转
        c.userInfo = ["session": String(key.prefix(36))]
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// 解析 OSC 通知负载
    static func parse(code: Int, payload: [UInt8]) -> (String?, String)? {
        let text = String(decoding: payload, as: UTF8.self)
        switch code {
        case 9:
            // OSC 9;4;… 是进度条，不是通知
            if text.hasPrefix("4;") { return nil }
            return (nil, text)
        case 777:
            // notify;title;body
            let parts = text.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.first == "notify" else { return nil }
            return (parts.count > 1 ? parts[1] : nil, parts.count > 2 ? parts[2] : "")
        case 99:
            // kitty: 只取负载里 ';' 之后的文字
            if let i = text.firstIndex(of: ";") { return (nil, String(text[text.index(after: i)...])) }
            return (nil, text)
        default:
            return nil
        }
    }
}

/// 前后台切换：进后台时申请一点额外存活时间；回到前台时重连断开的会话。
@MainActor
enum Lifecycle {
    private static var bgTask: UIBackgroundTaskIdentifier = .invalid

    static func didEnterBackground() {
        guard !SessionManager.shared.sessions.isEmpty else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "keep-ssh") {
            end()
        }
    }

    private static var monitor: NWPathMonitor?
    private static var lastPathKey = ""

    /// 网络切换（Wi-Fi ⇄ 蜂窝、恢复联网）时探活重连
    static func startNetworkMonitor() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { path in
            let key = "\(path.status)-\(path.availableInterfaces.map(\.name).joined(separator: ","))"
            Task { @MainActor in
                defer { lastPathKey = key }
                guard !lastPathKey.isEmpty, key != lastPathKey, path.status == .satisfied,
                      UIApplication.shared.applicationState == .active else { return }
                checkConnections()
            }
        }
        m.start(queue: DispatchQueue(label: "net-monitor"))
        monitor = m
    }

    static func didBecomeActive() {
        end()
        UNUserNotificationCenter.current().setBadgeCount(0)
        startNetworkMonitor()
        checkConnections()
    }

    static func checkConnections() {
        guard AppSettings.shared.autoReconnect else { return }
        for s in SessionManager.shared.sessions {
            if case .disconnected = s.state, s.wasConnectedOnce {
                s.reconnect()
            } else if s.state == .connected, let t = s.sshTransport {
                // iOS 常在后台静默掐断 TCP：探活失败就立即重连，不用等用户打字才发现
                Task { @MainActor in
                    if !(await t.probe()), s.state == .connected, s.sshTransport === t { s.reconnect() }
                }
            }
        }
    }

    private static func end() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}
