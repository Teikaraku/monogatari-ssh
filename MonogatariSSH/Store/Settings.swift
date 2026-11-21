import SwiftUI

/// 用户偏好，存在 UserDefaults。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("fontSize") var fontSize: Double = 13
    @AppStorage("fontName") var fontName: String = "SF Mono"
    @AppStorage("defaultTheme") var defaultTheme: String = TerminalTheme.defaultID
    @AppStorage("scrollback") var scrollback: Int = 20000
    @AppStorage("keepAwake") var keepAwake: Bool = true
    @AppStorage("haptics") var haptics: Bool = true
    @AppStorage("cursorBlink") var cursorBlink: Bool = true
    @AppStorage("cursorStyle") var cursorStyle: String = "block"
    /// 在备用屏（tmux/vim/less）里把单指滑动变成带惯性的滚轮
    @AppStorage("inertiaWheel") var inertiaWheel: Bool = true
    /// 每滑过多少点发一次滚轮，越小越灵敏
    @AppStorage("wheelStep") var wheelStep: Double = 18
    /// tmux 预设：鼠标滚动、5 万行历史、1 行/次滚轮（滑动更跟手）
    @AppStorage("tmuxTuning") var tmuxTuning: Bool = true
    @AppStorage("agentBar") var agentBar: Bool = true
    /// 辅助栏第二行的键（逗号分隔的 BarKey.id），空 = 默认
    @AppStorage("barKeys") var barKeysRaw: String = ""
    /// 连接成功 / 断开 / agent 响铃 时发本地通知（app 在后台时）
    @AppStorage("notifyBell") var notifyBell: Bool = true
    /// 点按光标所在行移动光标
    @AppStorage("tapMovesCursor") var tapMovesCursor: Bool = true
    @AppStorage("cmdClaude") var cmdClaude: String = ""
    @AppStorage("cmdCodex") var cmdCodex: String = ""
    @AppStorage("cmdGemini") var cmdGemini: String = ""

    var barKeyIDs: [String] {
        get {
            let ids = barKeysRaw.split(separator: ",").map(String.init).filter { BarKey.byID[$0] != nil }
            return ids.isEmpty ? BarKey.defaultRow : ids
        }
        set {
            barKeysRaw = newValue.joined(separator: ",")
            NotificationCenter.default.post(name: .monoBarKeysChanged, object: nil)
        }
    }
    @AppStorage("composeSendsReturn") var composeSendsReturn: Bool = true
    @AppStorage("autoReconnect") var autoReconnect: Bool = true
    @AppStorage("useMetal") var useMetal: Bool = true

    func uiFont(size: CGFloat? = nil) -> UIFont {
        let s = size ?? CGFloat(fontSize)
        if fontName != "SF Mono", let f = UIFont(name: fontName, size: s) { return f }
        return UIFont.monospacedSystemFont(ofSize: s, weight: .regular)
    }

    static let fonts = ["SF Mono", "Menlo-Regular", "Courier", "CourierNewPSMT"]
}

enum Haptics {
    @MainActor static func tap() {
        guard AppSettings.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    @MainActor static func soft() {
        guard AppSettings.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }
    @MainActor static func success() {
        guard AppSettings.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum Clipboard {
    @MainActor static func copy(_ s: String) {
        UIPasteboard.general.string = s
        Haptics.success()
        Toast.shared.show("已复制")
    }
}

/// 轻量 toast
@MainActor
final class Toast: ObservableObject {
    static let shared = Toast()
    @Published var message: String?
    private var task: Task<Void, Never>?
    func show(_ m: String) {
        message = m
        task?.cancel()
        task = Task { try? await Task.sleep(nanoseconds: 1_400_000_000); if !Task.isCancelled { message = nil } }
    }
}
