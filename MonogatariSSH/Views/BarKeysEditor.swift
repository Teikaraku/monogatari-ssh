import SwiftUI

/// 自定义辅助栏第二行：拖动排序、删除、从全部可用键里添加。
struct BarKeysEditor: View {
    @EnvironmentObject var settings: AppSettings
    @State private var ids: [String] = []

    private var available: [BarKey] { BarKey.catalog.filter { !ids.contains($0.id) } }

    var body: some View {
        List {
            Section {
                ForEach(ids, id: \.self) { id in
                    if let k = BarKey.byID[id] { row(k) }
                }
                .onMove { ids.move(fromOffsets: $0, toOffset: $1); save() }
                .onDelete { ids.remove(atOffsets: $0); save() }
            } header: {
                Text("已启用（\(ids.count)）")
            } footer: {
                Text("第一行固定为 esc / tab / ctrl / alt / 方向键 / 收起键盘。这里调整第二行（可横向滑动），拖动右侧把手排序。")
            }

            Section("可添加") {
                ForEach(available) { k in
                    Button {
                        withAnimation { ids.append(k.id) }
                        save()
                        Haptics.tap()
                    } label: {
                        HStack {
                            row(k)
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                ForEach(BarKey.presets, id: \.0) { name, symbol, keys in
                    Button {
                        withAnimation { ids = keys }
                        save()
                        Haptics.success()
                    } label: {
                        Label("使用「\(name)」方案", systemImage: symbol)
                    }
                }
            } header: {
                Text("预设方案")
            } footer: {
                Text("Agent：Claude Code 常用操作；Shell：控制键与管道符号；Vim：编辑器符号、F 键与按词移动。")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("键盘辅助栏")
        .onAppear { ids = settings.barKeyIDs }
    }

    private func row(_ k: BarKey) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                if let s = k.symbol { Image(systemName: s) }
                if !k.title.isEmpty { Text(k.title).font(.system(.subheadline, design: .monospaced).weight(.medium)) }
            }
            .foregroundStyle(k.tint.map { Color(uiColor: $0) } ?? .primary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            if !k.help.isEmpty {
                Text(k.help).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func save() { settings.barKeyIDs = ids }
}
