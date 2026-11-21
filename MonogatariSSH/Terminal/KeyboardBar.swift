import UIKit
import SwiftTerm

// MARK: - 按键定义

/// 辅助栏上的一个键。第二行的键可在「设置 → 键盘辅助栏」里增删排序。
struct BarKey: Identifiable, Hashable {
    enum Kind: Hashable {
        case bytes([UInt8])
        case text(String)
        case action(KeyboardBar.Action)
    }
    let id: String
    let title: String
    var symbol: String? = nil
    var tint: UIColor? = nil
    var repeats = false
    let kind: Kind
    /// 设置页里的说明
    var help: String = ""

    static func == (a: BarKey, b: BarKey) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    private static let esc = "\u{1b}"

    /// 所有可用的键
    static let catalog: [BarKey] = baseKeys + symbolKeys + functionKeys

    private static let symbolKeys: [BarKey] = ["|", "~", "-", "_", "/", "\\", "*", ".", "`", "$", "&", ";", ":", "'", "\"", "<", ">", "{", "}", "[", "]", "(", ")", "=", "+", "%", "^", "?"].map { (c: String) -> BarKey in
        BarKey(id: "sym" + c, title: c, kind: .text(c))
    }

    private static let functionKeys: [BarKey] = {
        let seqs = ["OP", "OQ", "OR", "OS", "[15~", "[17~", "[18~", "[19~", "[20~", "[21~", "[23~", "[24~"]
        var out: [BarKey] = []
        for (i, seq) in seqs.enumerated() {
            out.append(BarKey(id: "F\(i + 1)", title: "F\(i + 1)", kind: .bytes(Array((esc + seq).utf8))))
        }
        return out
    }()

    private static let baseKeys: [BarKey] = [
        // Agent
        BarKey(id: "mode", title: "模式", symbol: "arrow.triangle.2.circlepath", tint: .systemPurple, kind: .bytes(Array("\u{1b}[Z".utf8)), help: "Shift+Tab：Claude Code 切换 普通/自动接受/计划 模式"),
        BarKey(id: "newline", title: "换行", symbol: "return", tint: .systemBlue, kind: .text("\\\r"), help: "在 agent 输入框里换行而不发送"),
        BarKey(id: "interrupt", title: "中断", symbol: "stop.fill", tint: .systemRed, kind: .bytes([0x1b]), help: "Esc：打断 agent 当前操作"),
        BarKey(id: "rewind", title: "回退", symbol: "arrow.uturn.backward", tint: .systemOrange, kind: .bytes([0x1b, 0x1b]), help: "Esc Esc：Claude Code 回到上一条消息"),
        BarKey(id: "ok1", title: "1", tint: .systemGreen, kind: .text("1"), help: "选择第 1 项（通常是「是」）"),
        BarKey(id: "ok2", title: "2", tint: .systemGreen, kind: .text("2"), help: "选择第 2 项（通常是「是，且不再询问」）"),
        BarKey(id: "ok3", title: "3", tint: .systemGreen, kind: .text("3"), help: "选择第 3 项"),
        BarKey(id: "y", title: "y", kind: .text("y")),
        BarKey(id: "n", title: "n", kind: .text("n")),
        BarKey(id: "slashMenu", title: "/指令", tint: .systemOrange, kind: .action(.slashPalette), help: "弹出 Claude Code 斜杠指令面板"),
        BarKey(id: "slash", title: "/", tint: .systemOrange, kind: .text("/"), help: "输入斜杠"),
        BarKey(id: "at", title: "@", tint: .systemTeal, kind: .text("@"), help: "引用文件"),
        BarKey(id: "bang", title: "!", tint: .systemGreen, kind: .text("!"), help: "Claude Code 直接执行 shell"),
        BarKey(id: "hash", title: "#", tint: .systemIndigo, kind: .text("#"), help: "写入记忆"),
        BarKey(id: "verbose", title: "^O", tint: .systemGray, kind: .bytes([0x0f]), help: "Ctrl+O：展开/收起详细输出"),
        BarKey(id: "todo", title: "^T", tint: .systemGray, kind: .bytes([0x14]), help: "Ctrl+T：显示/隐藏待办列表"),
        BarKey(id: "background", title: "^B", tint: .systemGray, kind: .bytes([0x02]), help: "Ctrl+B：把运行中的命令转到后台（tmux 下为前缀键）"),
        // 工具
        BarKey(id: "paste", title: "粘贴", symbol: "doc.on.clipboard", kind: .action(.paste)),
        BarKey(id: "compose", title: "写作", symbol: "square.and.pencil", tint: .systemBlue, kind: .action(.compose), help: "用原生输入法写长内容再发送"),
        BarKey(id: "snippets", title: "片段", symbol: "text.badge.star", tint: .systemPink, kind: .action(.snippets)),
        BarKey(id: "copyScreen", title: "复制屏幕", symbol: "doc.on.doc", kind: .action(.copyScreen)),
        BarKey(id: "history", title: "历史", symbol: "clock.arrow.circlepath", kind: .action(.history), help: "服务器命令历史"),
        BarKey(id: "search", title: "搜索", symbol: "magnifyingglass", kind: .action(.search), help: "在输出中查找"),
        BarKey(id: "select", title: "选择", symbol: "selection.pin.in.out", kind: .action(.selectMode), help: "进入文本选择模式"),
        // 控制键
        BarKey(id: "^C", title: "^C", tint: .systemRed, kind: .bytes([0x03]), help: "中止"),
        BarKey(id: "^D", title: "^D", kind: .bytes([0x04]), help: "EOF / 退出"),
        BarKey(id: "^Z", title: "^Z", kind: .bytes([0x1a]), help: "挂起"),
        BarKey(id: "^L", title: "^L", kind: .bytes([0x0c]), help: "清屏"),
        BarKey(id: "^R", title: "^R", kind: .bytes([0x12]), help: "搜索历史"),
        BarKey(id: "^A", title: "^A", kind: .bytes([0x01]), help: "行首 / screen 前缀"),
        BarKey(id: "^E", title: "^E", kind: .bytes([0x05]), help: "行尾"),
        BarKey(id: "^U", title: "^U", kind: .bytes([0x15]), help: "删除到行首"),
        BarKey(id: "^K", title: "^K", kind: .bytes([0x0b]), help: "删除到行尾"),
        BarKey(id: "^W", title: "^W", kind: .bytes([0x17]), help: "删除前一个词"),
        BarKey(id: "tmuxPrefix", title: "^B", symbol: "square.split.2x1", tint: .systemPurple, kind: .bytes([0x02]), help: "tmux 前缀键"),
        BarKey(id: "tmuxCopy", title: "回滚", symbol: "scroll", tint: .systemPurple, kind: .bytes([0x02, 0x5b]), help: "tmux 进入回滚/复制模式（^B [）"),
        // 导航
        BarKey(id: "home", title: "Home", repeats: false, kind: .bytes(Array("\u{1b}[H".utf8))),
        BarKey(id: "end", title: "End", kind: .bytes(Array("\u{1b}[F".utf8))),
        BarKey(id: "pgup", title: "PgUp", repeats: true, kind: .bytes(Array("\u{1b}[5~".utf8))),
        BarKey(id: "pgdn", title: "PgDn", repeats: true, kind: .bytes(Array("\u{1b}[6~".utf8))),
        BarKey(id: "del", title: "Del", symbol: "delete.right", repeats: true, kind: .bytes(Array("\u{1b}[3~".utf8))),
        BarKey(id: "wordLeft", title: "⌥←", repeats: true, kind: .bytes(Array("\u{1b}b".utf8)), help: "按词左移"),
        BarKey(id: "wordRight", title: "⌥→", repeats: true, kind: .bytes(Array("\u{1b}f".utf8)), help: "按词右移"),
    ]

    static let byID: [String: BarKey] = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })

    static let defaultRow: [String] = [
        "mode", "newline", "ok1", "ok2", "ok3", "slashMenu", "at", "paste", "compose", "snippets",
        "^C", "sym|", "sym~", "sym-", "sym/", "sym_", "sym*", "sym.", "^R", "^L", "^D", "^Z",
        "home", "end", "pgup", "pgdn", "tmuxCopy", "verbose", "bang", "hash", "rewind", "search",
    ]
}

// MARK: - 辅助栏

/// 键盘上方的辅助栏：手动布局，避免 inputAccessoryView 里 AutoLayout 算错尺寸。
///
/// 第一行（固定、等宽）：esc tab ctrl alt ← ↑ ↓ → 收起键盘
/// 第二行（可横滑，可自定义）：agent 操作 / 控制键 / 符号 / 工具
final class KeyboardBar: UIInputView {
    enum Action: Hashable {
        case bytes([UInt8])
        case text(String)
        case toggleCtrl, toggleAlt
        case arrow(Arrow)
        case compose, snippets, paste, hideKeyboard, copyScreen, search, selectMode, slashPalette, history
    }
    enum Arrow: Hashable { case up, down, left, right }

    var onAction: ((Action) -> Void)?

    private let rowHeight: CGFloat = 40
    private let gap: CGFloat = 6
    private let pad: CGFloat = 6
    private var fixedKeys: [KeyCap] = []
    private let scroll = BarScrollView()
    private var scrollKeys: [KeyCap] = []
    private let showSecondRow: Bool
    private var ctrlCap: KeyCap!
    private var altCap: KeyCap!
    private var observers: [NSObjectProtocol] = []

    var barHeight: CGFloat { pad + rowHeight + (showSecondRow ? gap + rowHeight : 0) + pad }

    init(terminal: TerminalView, agentRow: Bool) {
        showSecondRow = agentRow
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 100), inputViewStyle: .keyboard)
        frame.size.height = barHeight
        autoresizingMask = [.flexibleWidth]
        allowsSelfSizing = true
        buildFixedRow()
        if agentRow { buildScrollRow() }
        observers.append(NotificationCenter.default.addObserver(forName: .terminalViewControlModifierReset, object: terminal, queue: .main) { [weak self] _ in
            self?.ctrlCap.isOn = false
        })
        observers.append(NotificationCenter.default.addObserver(forName: .terminalViewMetaModifierReset, object: terminal, queue: .main) { [weak self] _ in
            self?.altCap.isOn = false
        })
        observers.append(NotificationCenter.default.addObserver(forName: .monoBarKeysChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildScrollRow()
        })
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { for o in observers { NotificationCenter.default.removeObserver(o) } }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: barHeight) }

    private func buildFixedRow() {
        func cap(_ title: String, symbol: String? = nil, repeats: Bool = false, action: Action) -> KeyCap {
            let k = KeyCap(title: title, symbol: symbol)
            k.repeats = repeats
            k.onFire = { [weak self] in self?.onAction?(action) }
            addSubview(k)
            fixedKeys.append(k)
            return k
        }
        _ = cap("esc", action: .bytes([0x1b]))
        _ = cap("tab", action: .bytes([0x09]))
        ctrlCap = cap("ctrl", action: .toggleCtrl)
        ctrlCap.isToggle = true
        altCap = cap("alt", action: .toggleAlt)
        altCap.isToggle = true
        _ = cap("", symbol: "arrow.left", repeats: true, action: .arrow(.left))
        _ = cap("", symbol: "arrow.up", repeats: true, action: .arrow(.up))
        _ = cap("", symbol: "arrow.down", repeats: true, action: .arrow(.down))
        _ = cap("", symbol: "arrow.right", repeats: true, action: .arrow(.right))
        _ = cap("", symbol: "keyboard.chevron.compact.down", action: .hideKeyboard)
    }

    private func buildScrollRow() {
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true
        addSubview(scroll)
        rebuildScrollRow()
    }

    private func rebuildScrollRow() {
        guard showSecondRow else { return }
        scrollKeys.forEach { $0.removeFromSuperview() }
        scrollKeys = AppSettings.shared.barKeyIDs.compactMap { BarKey.byID[$0] }.map { key in
            let k = KeyCap(title: key.title, symbol: key.symbol, tint: key.tint)
            k.repeats = key.repeats
            k.help = key.help
            let action: Action
            switch key.kind {
            case .bytes(let b): action = .bytes(b)
            case .text(let t): action = .text(t)
            case .action(let a): action = a
            }
            k.onFire = { [weak self] in self?.onAction?(action) }
            scroll.addSubview(k)
            return k
        }
        setNeedsLayout()
    }

    func setCtrl(_ on: Bool) { ctrlCap.isOn = on }
    func setAlt(_ on: Bool) { altCap.isOn = on }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = safeAreaInsets
        let width = bounds.width - inset.left - inset.right - pad * 2
        // 第一行：等宽，收起键盘键略窄
        let n = CGFloat(fixedKeys.count)
        let w = floor((width - gap * (n - 1)) / n)
        var x = inset.left + pad
        for k in fixedKeys {
            k.frame = CGRect(x: x, y: pad, width: w, height: rowHeight)
            x += w + gap
        }
        guard showSecondRow else { return }
        scroll.frame = CGRect(x: inset.left, y: pad + rowHeight + gap, width: bounds.width - inset.left - inset.right, height: rowHeight)
        x = pad
        for k in scrollKeys {
            let kw = max(44, k.preferredWidth)
            k.frame = CGRect(x: x, y: 0, width: kw, height: rowHeight)
            x += kw + gap
        }
        scroll.contentSize = CGSize(width: x - gap + pad, height: rowHeight)
    }
}

extension Notification.Name {
    static let monoBarKeysChanged = Notification.Name("mono.barKeysChanged")
}

/// 从按键上开始横滑也能滚动（默认 UIScrollView 不取消 UIControl 的触摸）
final class BarScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

// MARK: - 键帽

/// 仿系统键盘键帽：按下高亮，抬手发送；可连发、可作为开关（ctrl/alt）。
final class KeyCap: UIControl {
    var onFire: (() -> Void)?
    var repeats = false
    var isToggle = false
    /// 长按显示的说明（不连发的键）
    var help = ""
    private var helpShown = false
    var isOn = false { didSet { updateColors() } }

    private let label = UILabel()
    private let icon = UIImageView()
    private let tint: UIColor?
    private var timer: Timer?
    private var firedByRepeat = false

    init(title: String, symbol: String?, tint: UIColor? = nil) {
        self.tint = tint
        super.init(frame: .zero)
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        isExclusiveTouch = true

        let ascii = title.allSatisfy { $0.isASCII }
        label.text = title
        label.font = ascii ? .monospacedSystemFont(ofSize: 15, weight: .medium) : .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        addSubview(label)
        if let symbol {
            icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
            icon.contentMode = .center
            addSubview(icon)
        }
        isAccessibilityElement = true
        accessibilityLabel = title.isEmpty ? symbol : title
        accessibilityTraits = .keyboardKey
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    var preferredWidth: CGFloat {
        let textW = label.text.map { ($0 as NSString).size(withAttributes: [.font: label.font!]).width } ?? 0
        let iconW: CGFloat = icon.image == nil ? 0 : 20
        let spacing: CGFloat = (textW > 0 && iconW > 0) ? 4 : 0
        return ceil(textW + iconW + spacing + 24)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let hasText = !(label.text ?? "").isEmpty
        if icon.image != nil && hasText {
            let textW = min(bounds.width - 32, (label.text! as NSString).size(withAttributes: [.font: label.font!]).width)
            let total = 20 + 4 + textW
            let x0 = (bounds.width - total) / 2
            icon.frame = CGRect(x: x0, y: 0, width: 20, height: bounds.height)
            label.frame = CGRect(x: x0 + 24, y: 0, width: textW, height: bounds.height)
        } else if icon.image != nil {
            icon.frame = bounds
        } else {
            label.frame = bounds.insetBy(dx: 4, dy: 0)
        }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 7).cgPath
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateColors()
    }

    private var normalBG: UIColor {
        traitCollection.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    }
    private var pressedBG: UIColor {
        traitCollection.userInterfaceStyle == .dark ? UIColor(white: 0.62, alpha: 1) : UIColor(white: 0.82, alpha: 1)
    }

    private func updateColors() {
        let on = isToggle && isOn
        backgroundColor = on ? .systemBlue : (isHighlighted ? pressedBG : normalBG)
        let fg: UIColor = on ? .white : (tint ?? .label)
        label.textColor = fg
        icon.tintColor = fg
    }

    override var isHighlighted: Bool { didSet { updateColors() } }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        firedByRepeat = false
        helpShown = false
        Haptics.soft()
        if !repeats && !help.isEmpty {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.helpShown = true
                Haptics.tap()
                Toast.shared.show(self.help)
            }
        }
        if repeats {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.firedByRepeat = true
                self.onFire?()
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) { [weak self] _ in self?.onFire?() }
            }
        }
        return super.beginTracking(touch, with: event)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        timer?.invalidate(); timer = nil
        guard let touch, bounds.insetBy(dx: -12, dy: -12).contains(touch.location(in: self)) else { return }
        if !firedByRepeat && !helpShown {
            Haptics.tap()
            onFire?()
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        timer?.invalidate(); timer = nil
    }
}
