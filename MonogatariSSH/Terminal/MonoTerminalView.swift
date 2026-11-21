import UIKit
import SwiftTerm

/// 在 SwiftTerm 的 TerminalView 上做的滑动优化：
///
/// 1. 普通屏（shell / 不开 tmux 的 Claude Code）：关闭鼠标上报劫持，单指滑动就是原生 UIScrollView，
///    带系统惯性、橡皮筋和"滚上去时不被新输出拽回底部"。
/// 2. 备用屏（tmux / vim / less / htop）：没有本地回滚历史可滚，原版只会逐格发滚轮、没有惯性，
///    手感是"一顿一顿"的。这里接管单指竖滑：按手指位移换算成滚轮事件，抬手后用 CADisplayLink
///    做指数衰减的惯性继续发，体验接近原生列表。没开鼠标的程序退化成上下方向键。
/// 3. 双指捏合实时调整字号。
final class MonoTerminalView: TerminalView {
    var onFontSizeChange: ((CGFloat) -> Void)?
    var onUserScroll: (() -> Void)?
    /// 为 true 时（tmux 会话），备用屏未开鼠标就不发方向键，避免误操作 shell 历史 / agent 选项
    var suppressArrowScroll = false
    /// 备用屏需要鼠标模式但未开启时回调（用于提示一键开启 tmux 鼠标）
    var onNeedsMouseMode: (() -> Void)?

    private var wheelPan: UIPanGestureRecognizer!
    private var pinch: UIPinchGestureRecognizer!
    private var pinchBaseSize: CGFloat = 13
    private lazy var gestureHelper = GestureHelper(owner: self)
    private var cursorTap: UITapGestureRecognizer?

    // 惯性
    private var displayLink: CADisplayLink?
    private var velocity: CGFloat = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var accumulator: CGFloat = 0

    var wheelStep: CGFloat { CGFloat(max(6, AppSettings.shared.wheelStep)) }

    override init(frame: CGRect, font: UIFont?) {
        super.init(frame: frame, font: font)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        allowMouseReporting = false          // 单指永远交给我们 / UIScrollView，不被逐格滚轮抢走
        optionAsMetaKey = true
        alwaysBounceVertical = false
        decelerationRate = .normal
        delaysContentTouches = false
        keyboardDismissMode = .none

        wheelPan = UIPanGestureRecognizer(target: self, action: #selector(handleWheelPan(_:)))
        wheelPan.maximumNumberOfTouches = 1
        wheelPan.delegate = gestureHelper
        addGestureRecognizer(wheelPan)

        let cursorTap = UITapGestureRecognizer(target: self, action: #selector(handleCursorTap(_:)))
        cursorTap.delegate = gestureHelper
        cursorTap.cancelsTouchesInView = false
        addGestureRecognizer(cursorTap)
        self.cursorTap = cursorTap

        pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = gestureHelper
        addGestureRecognizer(pinch)
    }

    // MARK: 状态

    /// 只有备用屏（tmux / vim / less / htop）才接管滑动；普通屏（shell、Claude Code）
    /// 一律交给原生 UIScrollView 滚动本地回滚历史，哪怕程序开了鼠标模式。
    var programOwnsScroll: Bool {
        terminalInputStateSnapshot()?.isAlternateBuffer ?? false
    }

    /// 是否停在底部（用于"回到底部"按钮）
    var isAtBottom: Bool {
        !canScroll || scrollPosition >= 0.999
    }

    func scrollToBottom() {
        scroll(toPosition: 1)
    }

    // MARK: 手势

    fileprivate func shouldBeginWheel() -> Bool {
        guard AppSettings.shared.inertiaWheel, programOwnsScroll else { return false }
        let v = wheelPan.velocity(in: self)
        return abs(v.y) > abs(v.x)
    }

    fileprivate func isPinch(_ g: UIGestureRecognizer) -> Bool { g === pinch }
    fileprivate func isCursorTap(_ g: UIGestureRecognizer) -> Bool { g === cursorTap }

    /// 点按光标所在行：发送左右方向键把光标移过去（编辑 agent 输入 / 命令行）。
    /// 仅在键盘已弹出、普通屏、停在底部时生效；按字符数而非格数计算（中文占两格只需一次方向键）。
    @objc private func handleCursorTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, AppSettings.shared.tapMovesCursor, isFirstResponder,
              !programOwnsScroll, isAtBottom, !hasActiveSelection else { return }
        let st = terminalStateSnapshot()
        let cols = st.dimensions.cols, rows = st.dimensions.rows
        guard cols > 0, rows > 0 else { return }
        let p = g.location(in: self)
        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)
        let tapCol = min(cols - 1, max(0, Int(p.x / cellW)))
        let tapRow = min(rows - 1, max(0, Int((p.y - contentOffset.y) / cellH)))
        let cur = st.cursor
        guard tapRow == cur.row, tapCol != cur.col else { return }
        // 按单元格宽度换算成字符数
        var presses = abs(tapCol - cur.col)
        if let snap = terminalContentSnapshot(region: .viewport), tapRow < snap.rows.count {
            let cells = snap.rows[tapRow].cells
            let lo = min(tapCol, cur.col), hi = min(max(tapCol, cur.col), cells.count)
            if lo < hi { presses = cells[lo..<hi].filter { $0.width > 0 }.count }
        }
        presses = min(presses, 300)
        guard presses > 0 else { return }
        for _ in 0..<presses { tapCol > cur.col ? sendKeyRight() : sendKeyLeft() }
        Haptics.soft()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        stopMomentum()
        super.touchesBegan(touches, with: event)
    }

    @objc private func handleWheelPan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            stopMomentum()
            accumulator = 0
            panGestureRecognizer.isEnabled = false
            panGestureRecognizer.isEnabled = true
        case .changed:
            let dy = g.translation(in: self).y
            g.setTranslation(.zero, in: self)
            emit(distance: dy)
        case .ended:
            let v = g.velocity(in: self).y
            startMomentum(velocity: max(-5000, min(5000, v)))
        case .cancelled, .failed:
            accumulator = 0
        default: break
        }
    }

    /// 手指向下 = 内容向上翻（看更早的输出）= 滚轮 up
    private func emit(distance: CGFloat) {
        accumulator += distance
        var ticks = 0
        while abs(accumulator) >= wheelStep, ticks < 12 {
            ticks += 1
            accumulator -= accumulator > 0 ? wheelStep : -wheelStep
        }
        guard ticks > 0 else { return }
        let up = distance > 0
        sendWheel(up: up, count: ticks)
        onUserScroll?()
    }

    private func sendWheel(up: Bool, count: Int) {
        guard let s = terminalInputStateSnapshot() else { return }
        let cols = s.dimensions.cols, rows = s.dimensions.rows
        if s.mouseMode != .off {
            for _ in 0..<count {
                sendMouseEvent(button: up ? 4 : 5, release: false, col: cols / 2, row: rows / 2)
            }
        } else if s.isAlternateBuffer {
            if suppressArrowScroll {
                stopMomentum()
                onNeedsMouseMode?()
            } else {
                for _ in 0..<count { up ? sendKeyUp() : sendKeyDown() }
            }
        }
    }

    private func startMomentum(velocity v: CGFloat) {
        guard abs(v) > 120 else { return }
        velocity = v
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(stepMomentum(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func stepMomentum(_ link: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = link.timestamp; return }
        let dt = CGFloat(link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp
        emit(distance: velocity * dt)
        // 与 UIScrollView .normal 接近的衰减（每毫秒 0.998）
        velocity *= pow(0.998, dt * 1000)
        if abs(velocity) < 60 { stopMomentum() }
    }

    func stopMomentum() {
        displayLink?.invalidate()
        displayLink = nil
        velocity = 0
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinchBaseSize = font.pointSize
        case .changed:
            let size = (pinchBaseSize * g.scale).rounded()
            let clamped = max(8, min(30, size))
            if clamped != font.pointSize {
                font = AppSettings.shared.uiFont(size: clamped)
                Haptics.soft()
            }
        case .ended:
            onFontSizeChange?(font.pointSize)
        default: break
        }
    }

    // MARK: 复制

    /// 复制整个缓冲区（含回滚历史）
    func allText() -> String {
        String(decoding: getBufferAsData(kind: .active), as: UTF8.self)
    }

    /// 当前屏幕可见文字
    func screenText() -> String {
        guard let snap = terminalContentSnapshot(region: .viewport) else { return "" }
        return snap.rows.map { $0.text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }
}

/// 独立的手势代理，避免干扰 SwiftTerm / UIScrollView 自带手势的代理逻辑。
private final class GestureHelper: NSObject, UIGestureRecognizerDelegate {
    weak var owner: MonoTerminalView?
    init(owner: MonoTerminalView) { self.owner = owner }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let owner else { return false }
        if owner.isPinch(g) || owner.isCursorTap(g) { return true }
        return owner.shouldBeginWheel()
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        guard let owner else { return false }
        return owner.isPinch(g) || owner.isCursorTap(g)
    }
}
