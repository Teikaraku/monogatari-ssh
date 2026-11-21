import UIKit
import SwiftUI
import UserNotifications

/// 主屏幕长按图标的快捷菜单：最近连接的主机，一键直连
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 点通知：跳到对应会话
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let sid = response.notification.request.content.userInfo["session"] as? String
        Task { @MainActor in
            if let sid, let id = UUID(uuidString: sid), let s = SessionManager.shared.session(id) {
                SessionManager.shared.show(s)
            }
            completionHandler()
        }
    }

    /// 前台时不弹系统横幅（应用内已有提示）
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { QuickActions.pending = item.type }
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            QuickActions.handle(shortcutItem.type)
            completionHandler(true)
        }
    }
}

@MainActor
enum QuickActions {
    /// 冷启动时由快捷菜单带进来的动作，等界面就绪后执行
    static var pending: String?

    static func refresh() {
        UIApplication.shared.shortcutItems = AppStore.shared.recentHosts.prefix(3).map { h in
            UIApplicationShortcutItem(type: "host:\(h.id.uuidString)", localizedTitle: h.displayName,
                                      localizedSubtitle: "\(h.username)@\(h.address)",
                                      icon: UIApplicationShortcutIcon(systemImageName: "terminal"))
        }
    }

    static func runPending() {
        guard let p = pending else { return }
        pending = nil
        handle(p)
    }

    static func handle(_ type: String) {
        guard type.hasPrefix("host:"), let id = UUID(uuidString: String(type.dropFirst(5))),
              let host = AppStore.shared.host(id) else { return }
        let sm = SessionManager.shared
        if let live = sm.sessions.first(where: { $0.host.id == id }) { sm.show(live) } else { sm.connect(host) }
    }
}
