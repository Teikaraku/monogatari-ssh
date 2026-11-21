import SwiftUI
import Citadel
import NIOCore
import UniformTypeIdentifiers
import QuickLook

struct EditableFile: Identifiable {
    var id: String { entry.path }
    let entry: RemoteEntry
    var text: String
}

struct RemoteEntry: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isDir: Bool
    let isLink: Bool
    let size: UInt64
    let modified: Date?
    let permissions: UInt32?

    var isTextLike: Bool {
        guard !isDir else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        let textExt: Set<String> = ["md", "txt", "log", "json", "yml", "yaml", "toml", "ini", "conf", "cfg", "env", "sh", "bash", "zsh",
                                    "py", "js", "ts", "tsx", "jsx", "mjs", "cjs", "swift", "go", "rs", "c", "h", "cpp", "hpp", "java", "kt",
                                    "rb", "php", "css", "scss", "html", "xml", "sql", "csv", "service", "gitignore", "dockerfile", "lock", "prisma", "vue", "svelte"]
        if textExt.contains(ext) { return true }
        let n = name.lowercased()
        return ext.isEmpty && (n.hasPrefix(".") || ["dockerfile", "makefile", "readme", "license", "authorized_keys", "config", "hosts", "crontab"].contains(n))
    }

    var symbol: String {
        if isDir { return "folder.fill" }
        if isLink { return "link" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "md", "txt", "log": return "doc.text"
        case "swift", "js", "ts", "tsx", "py", "go", "rs", "c", "h", "java", "kt", "rb", "sh", "json", "yml", "yaml", "toml": return "chevron.left.forwardslash.chevron.right"
        case "zip", "gz", "tar", "xz", "7z": return "doc.zipper"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}

@MainActor
final class SFTPModel: ObservableObject {
    @Published var path = ""
    @Published var entries: [RemoteEntry] = []
    @Published var loading = false
    @Published var error: String?
    @Published var showHidden = false
    @Published var query = ""
    @Published var sort: SortKey = .name

    enum SortKey: String, CaseIterable { case name = "名称", size = "大小", date = "修改时间" }
    @Published var preview: URL?
    @Published var editing: EditableFile?

    let session: TerminalSession
    private var client: SFTPClient?

    init(session: TerminalSession) { self.session = session }

    var visible: [RemoteEntry] {
        var list = showHidden ? entries : entries.filter { !$0.name.hasPrefix(".") }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { list = list.filter { $0.name.lowercased().contains(q) } }
        list.sort { a, b in
            if a.isDir != b.isDir { return a.isDir }
            switch sort {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: return a.size > b.size
            case .date: return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
            }
        }
        return list
    }

    func sftp() async throws -> SFTPClient {
        if let client, client.isActive { return client }
        guard let t = session.sshTransport else { throw ConnectError.message("当前会话不支持 SFTP") }
        let c = try await t.openSFTP()
        client = c
        return c
    }

    func load(_ target: String? = nil) async {
        loading = true
        defer { loading = false }
        do {
            let c = try await sftp()
            let p = try await c.getRealPath(atPath: target ?? (path.isEmpty ? "." : path))
            let names = try await c.listDirectory(atPath: p)
            var list: [RemoteEntry] = []
            for n in names {
                for comp in n.components where comp.filename != "." && comp.filename != ".." {
                    let perms = comp.attributes.permissions
                    let type = (perms ?? 0) & 0o170000
                    let isDir = type == 0o040000 || comp.longname.hasPrefix("d")
                    let isLink = type == 0o120000 || comp.longname.hasPrefix("l")
                    list.append(RemoteEntry(name: comp.filename,
                                            path: (p == "/" ? "" : p) + "/" + comp.filename,
                                            isDir: isDir, isLink: isLink,
                                            size: comp.attributes.size ?? 0,
                                            modified: comp.attributes.accessModificationTime?.modificationTime,
                                            permissions: perms))
                }
            }
            list.sort { a, b in a.isDir != b.isDir ? a.isDir : a.name.localizedStandardCompare(b.name) == .orderedAscending }
            if p != path { query = "" }
            path = p
            entries = list
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func open(_ e: RemoteEntry) async {
        if e.isDir { await load(e.path); return }
        if e.isLink {
            // 符号链接：尝试当目录进入，失败则当文件下载
            let before = path
            await load(e.path)
            if error == nil && path != before { return }
            error = nil
        }
        if e.isTextLike && e.size < 2_000_000 {
            if let text = await readText(e) { editing = EditableFile(entry: e, text: text); return }
        }
        if let url = await download(e) { preview = url }
    }

    func readText(_ e: RemoteEntry) async -> String? {
        do {
            let c = try await sftp()
            let file = try await c.openFile(filePath: e.path, flags: .read)
            let buf = try await file.readAll()
            try await file.close()
            let data = Data(buf.readableBytesView)
            if data.prefix(4096).contains(0) { return nil } // 二进制
            return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        } catch {
            self.error = "读取失败：\(error.localizedDescription)"
            return nil
        }
    }

    func writeText(_ path: String, _ text: String) async throws {
        let c = try await sftp()
        let file = try await c.openFile(filePath: path, flags: [.write, .create, .truncate])
        let data = Data(text.utf8)
        var offset: UInt64 = 0
        var rest = data[...]
        while !rest.isEmpty {
            let chunk = rest.prefix(64 * 1024)
            try await file.write(ByteBuffer(bytes: chunk), at: offset)
            offset += UInt64(chunk.count)
            rest = rest.dropFirst(chunk.count)
        }
        try await file.close()
    }

    func download(_ e: RemoteEntry) async -> URL? {
        var record = TransferRecord(hostName: session.host.displayName, remotePath: e.path, localName: e.name,
                                    direction: .download, bytes: 0, total: Int64(e.size), state: .running)
        AppStore.shared.record(record)
        do {
            let c = try await sftp()
            let file = try await c.openFile(filePath: e.path, flags: .read)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(e.name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            var offset: UInt64 = 0
            let chunk: UInt32 = 256 * 1024
            while true {
                let buf = try await file.read(from: offset, length: chunk)
                if buf.readableBytes == 0 { break }
                try handle.write(contentsOf: Data(buf.readableBytesView))
                offset += UInt64(buf.readableBytes)
                record.bytes = Int64(offset)
                AppStore.shared.record(record)
                if buf.readableBytes < Int(chunk) && offset >= e.size { break }
            }
            try handle.close()
            try await file.close()
            record.state = .done
            record.total = Int64(offset)
            AppStore.shared.record(record)
            return url
        } catch {
            record.state = .failed
            record.message = error.localizedDescription
            AppStore.shared.record(record)
            self.error = "下载失败：\(error.localizedDescription)"
            return nil
        }
    }

    func upload(_ local: URL) async {
        let ok = local.startAccessingSecurityScopedResource()
        defer { if ok { local.stopAccessingSecurityScopedResource() } }
        let remote = (path == "/" ? "" : path) + "/" + local.lastPathComponent
        let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? 0
        var record = TransferRecord(hostName: session.host.displayName, remotePath: remote, localName: local.lastPathComponent,
                                    direction: .upload, bytes: 0, total: size, state: .running)
        AppStore.shared.record(record)
        do {
            let c = try await sftp()
            let file = try await c.openFile(filePath: remote, flags: [.write, .create, .truncate])
            let handle = try FileHandle(forReadingFrom: local)
            var offset: UInt64 = 0
            while let data = try handle.read(upToCount: 256 * 1024), !data.isEmpty {
                try await file.write(ByteBuffer(bytes: data), at: offset)
                offset += UInt64(data.count)
                record.bytes = Int64(offset)
                AppStore.shared.record(record)
            }
            try handle.close()
            try await file.close()
            record.state = .done
            record.total = Int64(offset)
            AppStore.shared.record(record)
            Toast.shared.show("已上传 \(local.lastPathComponent)")
            await load(path)
        } catch {
            record.state = .failed
            record.message = error.localizedDescription
            AppStore.shared.record(record)
            self.error = "上传失败：\(error.localizedDescription)"
        }
    }

    func mkdir(_ name: String) async {
        do { try await sftp().createDirectory(atPath: (path == "/" ? "" : path) + "/" + name); await load(path) }
        catch { self.error = error.localizedDescription }
    }

    func delete(_ e: RemoteEntry) async {
        do {
            let c = try await sftp()
            if e.isDir { try await c.rmdir(at: e.path) } else { try await c.remove(at: e.path) }
            await load(path)
        } catch { self.error = "删除失败（目录需为空）：\(error.localizedDescription)" }
    }

    func rename(_ e: RemoteEntry, to name: String) async {
        let parent = (e.path as NSString).deletingLastPathComponent
        do { try await sftp().rename(at: e.path, to: (parent == "/" ? "" : parent) + "/" + name); await load(path) }
        catch { self.error = error.localizedDescription }
    }

    func close() {
        let c = client
        client = nil
        Task { try? await c?.close() }
    }
}

struct SFTPBrowser: View {
    @StateObject private var model: SFTPModel
    @Environment(\.dismiss) var dismiss
    @State private var importing = false
    @State private var newFolder = false
    @State private var newFile = false
    @State private var fileName = ""
    @State private var folderName = ""
    @State private var renaming: RemoteEntry?
    @State private var renameText = ""
    @State private var pathInput = false
    @State private var pathText = ""

    init(session: TerminalSession) {
        _model = StateObject(wrappedValue: SFTPModel(session: session))
    }

    var body: some View {
        List {
            if model.path != "/" && !model.path.isEmpty && model.query.isEmpty {
                Button {
                    Task { await model.load((model.path as NSString).deletingLastPathComponent) }
                } label: {
                    Label("上一级", systemImage: "arrow.turn.left.up")
                }
            }
            ForEach(model.visible) { e in
                Button { Task { await model.open(e) } } label: { row(e) }
                    .buttonStyle(.plain)
                    .contextMenu { menu(e) }
                    .swipeActions {
                        Button(role: .destructive) { Task { await model.delete(e) } } label: { Label("删除", systemImage: "trash") }
                        Button { renameText = e.name; renaming = e } label: { Label("重命名", systemImage: "pencil") }.tint(.orange)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $model.query, prompt: "在当前目录中筛选")
        .refreshable { await model.load(model.path) }
        .overlay {
            if model.loading && model.entries.isEmpty { ProgressView() }
            else if let err = model.error, model.entries.isEmpty {
                ContentUnavailableView("无法打开", systemImage: "exclamationmark.triangle", description: Text(err))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let err = model.error, !model.entries.isEmpty {
                Text(err).font(.footnote).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    .onTapGesture { model.error = nil }
            }
        }
        .navigationTitle((model.path as NSString).lastPathComponent.isEmpty ? "/" : (model.path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { pathText = model.path; pathInput = true } label: {
                    VStack(spacing: 0) {
                        Text((model.path as NSString).lastPathComponent.isEmpty ? "/" : (model.path as NSString).lastPathComponent).font(.headline)
                        Text(model.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("上传文件", systemImage: "square.and.arrow.up") { importing = true }
                    Button("新建文件夹", systemImage: "folder.badge.plus") { folderName = ""; newFolder = true }
                    Button("新建文件", systemImage: "doc.badge.plus") { fileName = "CLAUDE.md"; newFile = true }
                    Button("前往路径…", systemImage: "arrow.right.circle") { pathText = model.path; pathInput = true }
                    Divider()
                    Button("在终端 cd 到这里", systemImage: "terminal") {
                        model.session.send(text: "cd \(quote(model.path))\r"); dismiss()
                    }
                    Button("复制当前路径", systemImage: "doc.on.doc") { Clipboard.copy(model.path) }
                    Toggle("显示隐藏文件", systemImage: "eye", isOn: $model.showHidden)
                    Picker("排序", systemImage: "arrow.up.arrow.down", selection: $model.sort) {
                        ForEach(SFTPModel.SortKey.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .task { await model.load() }
        .onDisappear { model.close() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r {
                Task { for u in urls { await model.upload(u) } }
            }
        }
        .quickLookPreview($model.preview)
        .sheet(item: $model.editing) { f in RemoteTextEditor(model: model, file: f) }
        .alert("新建文件", isPresented: $newFile) {
            TextField("文件名", text: $fileName).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("创建并编辑") {
                let name = fileName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let path = (model.path == "/" ? "" : model.path) + "/" + name
                Task {
                    do {
                        if !model.entries.contains(where: { $0.name == name }) { try await model.writeText(path, "") }
                        await model.load(model.path)
                        let entry = model.entries.first { $0.name == name }
                            ?? RemoteEntry(name: name, path: path, isDir: false, isLink: false, size: 0, modified: nil, permissions: nil)
                        let text = await model.readText(entry) ?? ""
                        model.editing = EditableFile(entry: entry, text: text)
                    } catch {
                        model.error = "创建失败：\(error.localizedDescription)"
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("新建文件夹", isPresented: $newFolder) {
            TextField("名称", text: $folderName)
            Button("创建") { Task { await model.mkdir(folderName) } }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("新名称", text: $renameText)
            Button("确定") { if let e = renaming { Task { await model.rename(e, to: renameText) } } }
            Button("取消", role: .cancel) {}
        }
        .alert("前往路径", isPresented: $pathInput) {
            TextField("/var/www", text: $pathText).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("前往") { Task { await model.load(pathText) } }
            Button("取消", role: .cancel) {}
        }
    }

    private func row(_ e: RemoteEntry) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: e.symbol, colors: e.isDir ? Color.tileBlue : Color.tileGray, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).lineLimit(1).foregroundStyle(.primary)
                Text(detail(e)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if e.isDir { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private func menu(_ e: RemoteEntry) -> some View {
        Button("复制路径", systemImage: "doc.on.doc") { Clipboard.copy(e.path) }
        Button("作为 @文件 发给 agent", systemImage: "at") {
            model.session.send(text: "@\(e.path) "); dismiss()
        }
        Button("插入路径到终端", systemImage: "character.cursor.ibeam") {
            model.session.send(text: quote(e.path) + " "); dismiss()
        }
        if e.isDir {
            Button("在终端 cd 到这里", systemImage: "terminal") { model.session.send(text: "cd \(quote(e.path))\r"); dismiss() }
        } else {
            Button("下载并分享", systemImage: "square.and.arrow.down") { Task { await model.open(e) } }
        }
        Button("重命名", systemImage: "pencil") { renameText = e.name; renaming = e }
        Button("删除", systemImage: "trash", role: .destructive) { Task { await model.delete(e) } }
    }

    private func detail(_ e: RemoteEntry) -> String {
        var parts: [String] = []
        if !e.isDir { parts.append(ByteCountFormatter.string(fromByteCount: Int64(e.size), countStyle: .file)) }
        if let m = e.modified { parts.append(m.formatted(date: .abbreviated, time: .shortened)) }
        if let p = e.permissions { parts.append(String(p & 0o777, radix: 8)) }
        return parts.joined(separator: " · ")
    }

    private func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}


/// 远程文本编辑器：改完直接经 SFTP 写回（适合改 CLAUDE.md、.env、配置文件）
struct RemoteTextEditor: View {
    @ObservedObject var model: SFTPModel
    let file: EditableFile
    @Environment(\.dismiss) var dismiss
    @State private var text: String = ""
    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var errorText: String?

    var dirty: Bool { text != file.text }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 8)
                .navigationTitle(file.entry.name)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red).padding(8)
                            .frame(maxWidth: .infinity).background(.regularMaterial)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { if dirty { confirmDiscard = true } else { dismiss() } } label: { Image(systemName: "xmark") }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(file.entry.name).font(.headline)
                            Text(dirty ? "未保存" : "\(text.count) 字符").font(.caption2).foregroundStyle(dirty ? .orange : .secondary)
                        }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            Button("复制全部", systemImage: "doc.on.doc") { Clipboard.copy(text) }
                            Button("复制路径", systemImage: "link") { Clipboard.copy(file.entry.path) }
                            Button("作为 @文件 发给 agent", systemImage: "at") {
                                model.session.send(text: "@\(file.entry.path) ")
                                dismiss()
                            }
                        } label: { Image(systemName: "ellipsis") }
                        Button { Task { await save() } } label: {
                            if saving { ProgressView() } else { Image(systemName: "checkmark") }
                        }
                        .disabled(!dirty || saving)
                    }
                }
        }
        .interactiveDismissDisabled(dirty)
        .onAppear { text = file.text }
        .confirmationDialog("放弃未保存的修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { dismiss() }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await model.writeText(file.entry.path, text)
            Haptics.success()
            Toast.shared.show("已保存")
            dismiss()
            await model.load(model.path)
        } catch {
            errorText = "保存失败：\(error.localizedDescription)"
        }
    }
}
