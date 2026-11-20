import SwiftUI

/// 写作框：用系统原生输入（中文输入法、听写、粘贴都顺手）写好再一次性发给 agent。
/// 用 bracketed paste 发送，多行内容不会被逐行执行；可选发送后自动回车。
struct ComposeSheet: View {
    @ObservedObject var session: TerminalSession
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    @AppStorage("composeHistory") private var historyData: Data = Data()

    private var history: [String] {
        (try? JSONDecoder().decode([String].self, from: historyData)) ?? []
    }

    private let quick: [(String, String)] = [
        ("继续", "继续"),
        ("深度思考", "ultrathink "),
        ("中文回答", "请用中文回答。"),
        ("先给计划", "先不要改代码，给出实现计划，等我确认。"),
        ("跑测试", "运行测试并修复失败的用例。"),
        ("提交", "提交当前改动，写清晰的 commit message。"),
        ("解释报错", "解释上面的报错原因并修复。"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quick, id: \.0) { item in
                            Button(item.0) {
                                text += (text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " ") + item.1
                                Haptics.tap()
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                TextEditor(text: $text)
                    .focused($focused)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("写给 \(session.host.agent == .none ? "终端" : session.host.agent.title) 的内容…\n支持多行、中文输入法、粘贴图片路径等")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 17).padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }

                if !history.isEmpty && text.isEmpty {
                    List {
                        Section("最近发送") {
                            ForEach(history.prefix(8), id: \.self) { h in
                                Button { text = h } label: {
                                    Text(h).lineLimit(2).foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 220)
                }

                HStack {
                    Toggle(isOn: $settings.composeSendsReturn) {
                        Label("发送后回车", systemImage: "return")
                    }
                    .toggleStyle(.button)
                    .buttonBorderShape(.capsule)
                    Spacer()
                    Text("\(text.count) 字").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("写作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { send() } label: { Image(systemName: "paperplane.fill") }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func send() {
        let content = text
        var h = history.filter { $0 != content }
        h.insert(content, at: 0)
        historyData = (try? JSONEncoder().encode(Array(h.prefix(30)))) ?? Data()
        session.paste(content, thenReturn: settings.composeSendsReturn)
        Haptics.success()
        dismiss()
    }
}

/// 终端内的片段选择面板
struct SnippetPicker: View {
    @ObservedObject var session: TerminalSession
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var query = ""

    var groups: [(String, [Snippet])] {
        let q = query.lowercased()
        let list = q.isEmpty ? store.snippets : store.snippets.filter { $0.name.lowercased().contains(q) || $0.command.lowercased().contains(q) }
        var order: [String] = []
        for s in list where !order.contains(s.group) { order.append(s.group) }
        return order.map { g in (g, list.filter { $0.group == g }) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { g, items in
                    Section(g) {
                        ForEach(items) { s in
                            Button {
                                session.run(s)
                                Haptics.tap()
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.name).foregroundStyle(.primary)
                                    Text(s.command).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .swipeActions {
                                Button { session.send(text: s.command) ; dismiss() } label: { Label("只输入", systemImage: "character.cursor.ibeam") }
                                    .tint(.orange)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索片段")
            .navigationTitle("命令片段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
