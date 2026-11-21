import SwiftUI
import PhotosUI
import NIOCore

/// 写作框：用系统原生输入（中文输入法、听写、粘贴都顺手）写好再一次性发给 agent。
/// 用 bracketed paste 发送，多行内容不会被逐行执行；可选发送后自动回车。
struct ComposeSheet: View {
    @ObservedObject var session: TerminalSession
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    @AppStorage("composeHistory") private var historyData: Data = Data()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var uploading = 0
    @State private var uploadError: String?
    @State private var pickingFile = false

    private var history: [String] {
        (try? JSONDecoder().decode([String].self, from: historyData)) ?? []
    }

    /// 常用短语：「设置 → 写作框短语」可编辑，每行「按钮名=内容」
    static let defaultPhrases = """
    继续=继续
    深度思考=ultrathink 
    中文回答=请用中文回答。
    先给计划=先不要改代码，给出实现计划，等我确认。
    跑测试=运行测试并修复失败的用例。
    提交=提交当前改动，写清晰的 commit message。
    解释报错=解释上面的报错原因并修复。
    """
    @AppStorage("composePhrases") private var phrasesRaw = ComposeSheet.defaultPhrases

    private var quick: [(String, String)] {
        phrasesRaw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard let name = parts.first?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return (name, parts.count > 1 ? parts[1] : name)
        }
    }

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
                        Label("回车", systemImage: "return")
                    }
                    .toggleStyle(.button)
                    .buttonBorderShape(.capsule)
                    if session.sshTransport != nil {
                        Button { pickingFile = true } label: { Label("文件", systemImage: "at") }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                            if uploading > 0 {
                                HStack(spacing: 4) { ProgressView().controlSize(.small); Text("上传 \(uploading)") }
                            } else {
                                Label("图片", systemImage: "photo.badge.plus")
                            }
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .disabled(uploading > 0)
                    }
                    Spacer()
                    if let uploadError { Text(uploadError).font(.caption).foregroundStyle(.red).lineLimit(1) }
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
            .sheet(isPresented: $pickingFile) {
                RemoteFilePicker(session: session) { path in
                    text += (text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " ") + "@" + path + " "
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await upload(items) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 图片经 SFTP 传到服务器 /tmp，再把路径插入提示词（Claude Code 可直接读取图片路径）
    private func upload(_ items: [PhotosPickerItem]) async {
        guard let t = session.sshTransport else { return }
        uploadError = nil
        uploading = items.count
        defer { uploading = 0 }
        do {
            let sftp = try await t.openSFTP()
            defer { Task { try? await sftp.close() } }
            for item in items {
                guard let raw = try await item.loadTransferable(type: Data.self) else { continue }
                // HEIC 等转成 JPEG，agent 才能读
                let data: Data
                if let img = UIImage(data: raw), let jpg = img.jpegData(compressionQuality: 0.85) { data = jpg } else { data = raw }
                let path = "/tmp/mono-\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 1000...9999)).jpg"
                let file = try await sftp.openFile(filePath: path, flags: [.write, .create, .truncate])
                var offset: UInt64 = 0
                var rest = data[...]
                while !rest.isEmpty {
                    let chunk = rest.prefix(128 * 1024)
                    try await file.write(ByteBuffer(bytes: chunk), at: offset)
                    offset += UInt64(chunk.count)
                    rest = rest.dropFirst(chunk.count)
                }
                try await file.close()
                text += (text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " ") + path + " "
                uploading -= 1
                Haptics.success()
            }
        } catch {
            uploadError = "上传失败：\(error.localizedDescription)"
        }
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
    @State private var filling: Snippet?

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
                                if s.variables.isEmpty {
                                    session.run(s)
                                    Haptics.tap()
                                    dismiss()
                                } else {
                                    filling = s
                                }
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
            .sheet(item: $filling) { sn in
                SnippetFillSheet(snippet: sn) { filled in
                    session.run(filled)
                    filling = nil
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}


extension Snippet {
    /// 片段里的 {{变量}}，按出现顺序去重
    var variables: [String] {
        var out: [String] = []
        var rest = command[...]
        while let a = rest.range(of: "{{"), let b = rest[a.upperBound...].range(of: "}}") {
            let name = String(rest[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !out.contains(name) { out.append(name) }
            rest = rest[b.upperBound...]
        }
        return out
    }

    func filled(_ values: [String: String]) -> Snippet {
        var copy = self
        for (k, v) in values {
            copy.command = copy.command.replacingOccurrences(of: "{{\(k)}}", with: v)
                .replacingOccurrences(of: "{{ \(k) }}", with: v)
        }
        return copy
    }
}

/// 填写片段变量
struct SnippetFillSheet: View {
    let snippet: Snippet
    let onRun: (Snippet) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var values: [String: String] = [:]
    @FocusState private var focus: String?

    var preview: String { snippet.filled(values).command }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(snippet.variables, id: \.self) { v in
                        TextField(v, text: Binding(get: { values[v] ?? "" }, set: { values[v] = $0 }))
                            .focused($focus, equals: v)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(v == snippet.variables.last ? .send : .next)
                            .onSubmit {
                                if let i = snippet.variables.firstIndex(of: v), i + 1 < snippet.variables.count {
                                    focus = snippet.variables[i + 1]
                                } else { run() }
                            }
                    }
                } header: { Text(snippet.name) }
                Section("将发送") {
                    Text(preview).font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            .navigationTitle("填写变量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
                ToolbarItem(placement: .confirmationAction) { Button { run() } label: { Image(systemName: "paperplane.fill") } }
            }
            .onAppear { focus = snippet.variables.first }
        }
        .presentationDetents([.medium])
    }

    private func run() {
        onRun(snippet.filled(values))
        Haptics.tap()
    }
}
