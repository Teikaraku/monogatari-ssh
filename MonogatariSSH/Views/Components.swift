import SwiftUI

/// 渐变圆角图标块（参考图里的彩色方块）。
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 30
    var corner: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: corner ?? size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            )
    }
}

extension Color {
    static let tileBlue = [Color(red: 0.24, green: 0.56, blue: 0.98), Color(red: 0.17, green: 0.45, blue: 0.95)]
    static let tileIndigo = [Color(red: 0.43, green: 0.47, blue: 0.98), Color(red: 0.36, green: 0.33, blue: 0.90)]
    static let tileOrange = [Color(red: 0.97, green: 0.62, blue: 0.32), Color(red: 0.94, green: 0.53, blue: 0.27)]
    static let tilePink = [Color(red: 0.78, green: 0.30, blue: 0.85), Color(red: 0.93, green: 0.27, blue: 0.47)]
    static let tileGreen = [Color(red: 0.39, green: 0.78, blue: 0.42), Color(red: 0.35, green: 0.77, blue: 0.62)]
    static let tileTeal = [Color(red: 0.33, green: 0.76, blue: 0.82), Color(red: 0.30, green: 0.70, blue: 0.85)]
    static let tilePurple = [Color(red: 0.42, green: 0.36, blue: 0.93), Color(red: 0.36, green: 0.30, blue: 0.86)]
    static let tileMagenta = [Color(red: 0.74, green: 0.30, blue: 0.86), Color(red: 0.66, green: 0.24, blue: 0.82)]
    static let tileGray = [Color(white: 0.6), Color(white: 0.48)]
    static let tileRed = [Color(red: 0.98, green: 0.36, blue: 0.33), Color(red: 0.9, green: 0.22, blue: 0.25)]
}

/// 主机头像
struct HostAvatar: View {
    let host: Host
    var size: CGFloat = 44
    var body: some View {
        IconTile(symbol: host.icon.symbol, colors: host.icon.colors, size: size, corner: size * 0.24)
    }
}

/// 带眼睛的密码显示：默认 *** ，点眼睛显示，旁边一键复制。
struct SecretText: View {
    let value: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 10) {
            Text(revealed ? value : String(repeating: "•", count: min(max(value.count, 6), 16)))
                .font(.body.monospaced())
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .contentTransition(.opacity)
            Spacer(minLength: 4)
            Button {
                withAnimation(.snappy(duration: 0.2)) { revealed.toggle() }
                Haptics.tap()
            } label: {
                Image(systemName: revealed ? "eye" : "eye.slash")
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? "隐藏" : "显示")
            CopyButton(value: value)
        }
    }
}

struct CopyButton: View {
    let value: String
    @State private var done = false
    var body: some View {
        Button {
            Clipboard.copy(value)
            withAnimation(.snappy) { done = true }
            Task { try? await Task.sleep(nanoseconds: 1_200_000_000); withAnimation { done = false } }
        } label: {
            Image(systemName: done ? "checkmark" : "doc.on.doc")
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(value.isEmpty)
        .accessibilityLabel("复制")
    }
}

/// 可复制的一行信息
struct CopyRow: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let value: String
    var mono = true
    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, colors: colors)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value.isEmpty ? "—" : value)
                    .font(mono ? .body.monospaced() : .body)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            CopyButton(value: value)
        }
        .contextMenu { Button("复制", systemImage: "doc.on.doc") { Clipboard.copy(value) } }
    }
}

/// 表单里带图标的输入行
struct IconField: View {
    let symbol: String
    let colors: [Color]
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var mono = false

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, colors: colors)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(mono ? .body.monospaced() : .body)
        }
    }
}

/// 密码输入：SecureField / TextField 切换 + 复制
struct IconSecureField: View {
    let symbol: String
    let colors: [Color]
    let placeholder: String
    @Binding var text: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, colors: colors)
            Group {
                if revealed {
                    TextField(placeholder, text: $text).font(.body.monospaced())
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                revealed.toggle()
                Haptics.tap()
            } label: {
                Image(systemName: revealed ? "eye" : "eye.slash")
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !text.isEmpty { CopyButton(value: text) }
        }
    }
}

/// iOS 26 液态玻璃，旧系统退化为材质
extension View {
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// 全局 toast 覆盖层
struct ToastOverlay: View {
    @ObservedObject var toast = Toast.shared
    var body: some View {
        VStack {
            if let m = toast.message {
                Label(m, systemImage: m.hasPrefix("已") ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassCapsule()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.snappy, value: toast.message)
        .allowsHitTesting(false)
    }
}

extension Date {
    var relative: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
