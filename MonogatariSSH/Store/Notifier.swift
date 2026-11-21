import UIKit
import UserNotifications

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

    static func didBecomeActive() {
        end()
        UNUserNotificationCenter.current().setBadgeCount(0)
        guard AppSettings.shared.autoReconnect else { return }
        for s in SessionManager.shared.sessions {
            if case .disconnected = s.state, s.wasConnectedOnce {
                s.reconnect()
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
