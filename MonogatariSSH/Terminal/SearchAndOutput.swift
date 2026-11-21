import SwiftUI
import UIKit
import SwiftTerm

/// 终端内搜索：高亮并滚动到匹配，显示「第 n / 共 m 处」
struct TerminalSearchBar: View {
    @ObservedObject var session: TerminalSession
    let close: () -> Void
    @State private var term = ""
    @State private var caseSensitive = false
    @State private var summary: (index: Int, total: Int) = (0, 0)
    @FocusState private var focused: Bool

    private var options: SearchOptions { SearchOptions(caseSensitive: caseSensitive) }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索输出", text: $term)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { next() }
                if !term.isEmpty {
                    Text(summary.total == 0 ? "无结果" : "\(summary.index)/\(summary.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassCapsule()

            Button { caseSensitive.toggle(); refresh() } label: {
                Text("Aa").font(.subheadline.weight(caseSensitive ? .bold : .regular))
                    .foregroundStyle(caseSensitive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 36, height: 36)
            }
            .glassCircle()
            HStack(spacing: 0) {
                Button { prev() } label: { Image(systemName: "chevron.up").frame(width: 38, height: 36) }
                Button { next() } label: { Image(systemName: "chevron.down").frame(width: 38, height: 36) }
            }
            .glassCapsule()
            .disabled(term.isEmpty)
            Button {
                session.terminalView.clearSearch()
                close()
            } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
            .glassCircle()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .onAppear { focused = true }
        .onChange(of: term) { _, _ in
            session.terminalView.clearSearch()
            if !term.isEmpty { next() } else { summary = (0, 0) }
        }
    }

    private func next() {
        guard !term.isEmpty else { return }
        session.terminalView.stopMomentum()
        let found = session.terminalView.findNext(term, options: options)
        if found { session.setAtBottom(session.terminalView.isAtBottom) }
        refresh()
        Haptics.tap()
    }

    private func prev() {
        guard !term.isEmpty else { return }
        session.terminalView.findPrevious(term, options: options)
        session.setAtBottom(session.terminalView.isAtBottom)
        refresh()
        Haptics.tap()
    }

    private func refresh() {
        summary = term.isEmpty ? (0, 0) : session.terminalView.searchMatchSummary(term, options: options)
    }
}

/// 输出浏览：把整个缓冲区放进原生文本视图，系统级的选择、复制、查找、分享都可用。
/// 手机上在终端里拖选文字很难，这里一次解决。
struct OutputBrowser: View {
    @ObservedObject var session: TerminalSession
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var lastOnly = true
    @State private var findTrigger = 0

    var body: some View {
        NavigationStack {
            NativeTextView(text: text, font: AppSettings.shared.uiFont(size: CGFloat(max(11, AppSettings.shared.fontSize - 1))),
                           findTrigger: findTrigger, scrollToEnd: true)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("输出")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                    }
                    ToolbarItem(placement: .principal) {
                        Picker("范围", selection: $lastOnly) {
                            Text("最近 500 行").tag(true)
                            Text("全部").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { findTrigger += 1 } label: { Image(systemName: "magnifyingglass") }
                        Menu {
                            Button("复制全部", systemImage: "doc.on.doc") { Clipboard.copy(text) }
                            ShareLink(item: text) { Label("分享", systemImage: "square.and.arrow.up") }
                            Button("作为附件发给写作框", systemImage: "square.and.pencil") {
                                UIPasteboard.general.string = text
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    NotificationCenter.default.post(name: .monoShowCompose, object: session.id)
                                }
                            }
                        } label: { Image(systemName: "ellipsis") }
                    }
                }
        }
        .onAppear(perform: load)
        .onChange(of: lastOnly) { _, _ in load() }
    }

    private func load() {
        let all = session.terminalView.allText()
        let lines = all.split(separator: "\n", omittingEmptySubsequences: false)
        // 去掉尾部空行
        var trimmed = Array(lines)
        while let l = trimmed.last, l.trimmingCharacters(in: .whitespaces).isEmpty { trimmed.removeLast() }
        let slice = lastOnly ? trimmed.suffix(500) : trimmed[...]
        text = slice.map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }.joined(separator: "\n")
    }
}

/// 只读、可选择、带系统查找的 UITextView
struct NativeTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    var findTrigger: Int = 0
    var scrollToEnd = false

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 40, right: 10)
        tv.dataDetectorTypes = [.link]
        if #available(iOS 16.0, *) { tv.isFindInteractionEnabled = true }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
            tv.font = font
            if scrollToEnd {
                DispatchQueue.main.async {
                    let bottom = max(0, tv.contentSize.height - tv.bounds.height + tv.contentInset.bottom)
                    tv.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                }
            }
        }
        if context.coordinator.lastFind != findTrigger {
            context.coordinator.lastFind = findTrigger
            if #available(iOS 16.0, *) { tv.findInteraction?.presentFindNavigator(showingReplace: false) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastFind = 0 }
}
