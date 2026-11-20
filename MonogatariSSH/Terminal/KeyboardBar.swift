import UIKit
import SwiftTerm

/// 键盘上方的辅助栏。第一行通用终端按键，第二行为 AI agent（Claude Code 等）优化的快捷键。
final class KeyboardBar: UIInputView {
    enum Action {
        case bytes([UInt8])
        case text(String)
        case toggleCtrl, toggleAlt
        case arrow(Arrow)
        case compose, snippets, paste, hideKeyboard, copyScreen
    }
    enum Arrow { case up, down, left, right }

    var onAction: ((Action) -> Void)?
    private weak var terminal: TerminalView?
    private var ctrlButton: UIButton?
    private var altButton: UIButton?
    private var observers: [NSObjectProtocol] = []
    private let showAgentRow: Bool

    static func height(agent: Bool) -> CGFloat { agent ? 92 : 48 }

    init(terminal: TerminalView, agentRow: Bool) {
        self.terminal = terminal
        self.showAgentRow = agentRow
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: Self.height(agent: agentRow)), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        build()
        observers.append(NotificationCenter.default.addObserver(forName: .terminalViewControlModifierReset, object: terminal, queue: .main) { [weak self] _ in
            self?.setToggle(self?.ctrlButton, on: false)
        })
        observers.append(NotificationCenter.default.addObserver(forName: .terminalViewMetaModifierReset, object: terminal, queue: .main) { [weak self] _ in
            self?.setToggle(self?.altButton, on: false)
        })
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height(agent: showAgentRow))
    }

    // MARK: 构建

    private func build() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
        ])

        // 第一行：通用按键 + 固定在右侧的收起键盘
        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.spacing = 6
        let scroll1 = makeScrollRow(keys: [
            key("esc", bytes: [0x1b]),
            key("tab", symbol: "arrow.right.to.line", bytes: [0x09]),
            toggle("ctrl", isCtrl: true),
            toggle("alt", isCtrl: false),
            ArrowPad(onArrow: { [weak self] a in self?.fire(.arrow(a)) }),
            key("/", text: "/"), key("-", text: "-"), key("|", text: "|"), key("~", text: "~"),
            key("`", text: "`"), key("*", text: "*"), key("$", text: "$"), key("&", text: "&"),
            key("home", bytes: Array("\u{1b}[H".utf8)), key("end", bytes: Array("\u{1b}[F".utf8)),
            key("pgup", bytes: Array("\u{1b}[5~".utf8), repeats: true), key("pgdn", bytes: Array("\u{1b}[6~".utf8), repeats: true),
            key("^C", bytes: [0x03]), key("^D", bytes: [0x04]), key("^Z", bytes: [0x1a]),
            key("^L", bytes: [0x0c]), key("^R", bytes: [0x12]), key("^A", bytes: [0x01]), key("^E", bytes: [0x05]),
            key("^U", bytes: [0x15]), key("^W", bytes: [0x17]),
        ])
        row1.addArrangedSubview(scroll1)
        let hide = key("", symbol: "keyboard.chevron.compact.down", action: .hideKeyboard)
        hide.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row1.addArrangedSubview(hide)
        row1.isLayoutMarginsRelativeArrangement = true
        row1.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        stack.addArrangedSubview(row1)

        if showAgentRow {
            let row2 = makeScrollRow(keys: [
                key("中断", symbol: "stop.circle", bytes: [0x1b], tint: .systemRed),
                key("模式", symbol: "arrow.triangle.2.circlepath", bytes: Array("\u{1b}[Z".utf8), tint: .systemPurple),
                key("换行", symbol: "return", text: "\\\r", tint: .systemBlue),
                key("1", text: "1"), key("2", text: "2"), key("3", text: "3"),
                key("y", text: "y"), key("n", text: "n"),
                key("/指令", text: "/", tint: .systemOrange),
                key("@文件", text: "@", tint: .systemTeal),
                key("!命令", text: "!", tint: .systemGreen),
                key("#记忆", text: "#", tint: .systemIndigo),
                key("粘贴", symbol: "doc.on.clipboard", action: .paste),
                key("复制屏幕", symbol: "doc.on.doc", action: .copyScreen),
                key("写作", symbol: "square.and.pencil", action: .compose, tint: .systemBlue),
                key("片段", symbol: "text.badge.star", action: .snippets, tint: .systemPink),
            ])
            stack.addArrangedSubview(row2)
        }
    }

    private func makeScrollRow(keys: [UIView]) -> UIScrollView {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.alwaysBounceHorizontal = true
        sv.delaysContentTouches = false
        sv.canCancelContentTouches = true
        let inner = UIStackView(arrangedSubviews: keys)
        inner.axis = .horizontal
        inner.spacing = 6
        inner.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor, constant: 6),
            inner.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor, constant: -6),
            inner.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor),
            inner.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor),
            inner.heightAnchor.constraint(equalTo: sv.frameLayoutGuide.heightAnchor),
            sv.heightAnchor.constraint(equalToConstant: 38),
        ])
        return sv
    }

    private func baseConfig(title: String, symbol: String?, tint: UIColor?) -> UIButton.Configuration {
        var c = UIButton.Configuration.filled()
        c.baseBackgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : .white }
        c.baseForegroundColor = tint ?? .label
        c.cornerStyle = .medium
        c.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        if let symbol {
            c.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            c.imagePadding = title.isEmpty ? 0 : 4
        }
        if !title.isEmpty {
            var attr = AttributedString(title)
            attr.font = title.count <= 4 && title.allSatisfy({ $0.isASCII })
                ? UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
                : UIFont.systemFont(ofSize: 14, weight: .medium)
            c.attributedTitle = attr
        }
        return c
    }

    private func key(_ title: String, symbol: String? = nil, bytes: [UInt8]? = nil, text: String? = nil,
                     action: Action? = nil, tint: UIColor? = nil, repeats: Bool = false) -> UIButton {
        let b = RepeatButton(configuration: baseConfig(title: title, symbol: symbol, tint: tint))
        let act: Action = action ?? (bytes.map { .bytes($0) } ?? .text(text ?? title))
        b.repeats = repeats
        b.handler = { [weak self] in self?.fire(act) }
        b.layer.shadowColor = UIColor.black.cgColor
        b.layer.shadowOpacity = 0.12
        b.layer.shadowRadius = 0
        b.layer.shadowOffset = CGSize(width: 0, height: 1)
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return b
    }

    private func toggle(_ title: String, isCtrl: Bool) -> UIButton {
        let b = UIButton(configuration: baseConfig(title: title, symbol: nil, tint: nil))
        b.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.fire(isCtrl ? .toggleCtrl : .toggleAlt)
        }, for: .touchUpInside)
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        if isCtrl { ctrlButton = b } else { altButton = b }
        return b
    }

    func setCtrl(_ on: Bool) { setToggle(ctrlButton, on: on) }
    func setAlt(_ on: Bool) { setToggle(altButton, on: on) }

    private func setToggle(_ b: UIButton?, on: Bool) {
        guard let b, var c = b.configuration else { return }
        c.baseBackgroundColor = on ? .systemBlue : UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : .white }
        c.baseForegroundColor = on ? .white : .label
        b.configuration = c
    }

    private func fire(_ a: Action) {
        onAction?(a)
    }
}

/// 支持按住连发的按键。
private final class RepeatButton: UIButton {
    var handler: (() -> Void)?
    var repeats = false
    private var timer: Timer?

    override init(frame: CGRect) { super.init(frame: frame); wire() }
    convenience init(configuration: UIButton.Configuration) {
        self.init(frame: .zero)
        self.configuration = configuration
    }
    required init?(coder: NSCoder) { fatalError() }

    private func wire() {
        addTarget(self, action: #selector(down), for: .touchDown)
        addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    @objc private func down() {
        Haptics.tap()
        handler?()
        guard repeats else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in self?.handler?() }
        }
    }
    @objc private func up() { timer?.invalidate(); timer = nil }
}

/// 方向键摇杆：点击上下左右区域发送一次；按住拖动按距离连续发送（适合在长命令里移动光标、在 agent 的选项列表里上下选）。
private final class ArrowPad: UIView {
    let onArrow: (KeyboardBar.Arrow) -> Void
    private var origin: CGPoint = .zero
    private var acc: CGPoint = .zero
    private var repeatTimer: Timer?
    private var lastDir: KeyboardBar.Arrow?
    private let step: CGFloat = 14

    init(onArrow: @escaping (KeyboardBar.Arrow) -> Void) {
        self.onArrow = onArrow
        super.init(frame: .zero)
        backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : .white }
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        let img = UIImageView(image: UIImage(systemName: "dpad", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)))
        img.tintColor = .label
        img.translatesAutoresizingMaskIntoConstraints = false
        addSubview(img)
        NSLayoutConstraint.activate([
            img.centerXAnchor.constraint(equalTo: centerXAnchor),
            img.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 64),
        ])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(onHold(_:)))
        hold.minimumPressDuration = 0.35
        addGestureRecognizer(hold)
        accessibilityLabel = "方向键"
    }
    required init?(coder: NSCoder) { fatalError() }

    private func direction(at p: CGPoint) -> KeyboardBar.Arrow {
        let dx = p.x - bounds.midX, dy = (p.y - bounds.midY) * (bounds.width / max(bounds.height, 1))
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        Haptics.tap()
        onArrow(direction(at: g.location(in: self)))
    }

    @objc private func onHold(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            let d = direction(at: g.location(in: self))
            Haptics.tap()
            onArrow(d)
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in self?.onArrow(d) }
        case .ended, .cancelled, .failed:
            repeatTimer?.invalidate(); repeatTimer = nil
        default: break
        }
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        repeatTimer?.invalidate(); repeatTimer = nil
        switch g.state {
        case .began: acc = .zero
        case .changed:
            let t = g.translation(in: self)
            g.setTranslation(.zero, in: self)
            acc.x += t.x; acc.y += t.y
            while abs(acc.x) >= step { let r = acc.x > 0; acc.x -= r ? step : -step; onArrow(r ? .right : .left); Haptics.soft() }
            while abs(acc.y) >= step { let d = acc.y > 0; acc.y -= d ? step : -step; onArrow(d ? .down : .up); Haptics.soft() }
        default: break
        }
    }
}
