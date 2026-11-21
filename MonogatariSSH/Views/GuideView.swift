import SwiftUI

/// 功能指南：功能多，集中说明入口在哪
struct GuideView: View {
    private struct Item: Identifiable { let id = UUID(); let symbol: String; let title: String; let detail: String }
    private struct Group_: Identifiable { let id = UUID(); let title: String; let items: [Item] }

    private let groups: [Group_] = [
        Group_(title: "驾驭 AI agent", items: [
            Item(symbol: "sparkles", title: "连接后自动启动", detail: "编辑主机 → Agent：选 Claude Code / Codex / Gemini，配合 tmux 会话恢复，断网锁屏任务不停。"),
            Item(symbol: "circle.dashed", title: "状态与计时", detail: "顶栏与「会话」页显示 工作中 / 等待确认 / 空闲、当前模式与已工作时长。"),
            Item(symbol: "bell.badge", title: "提醒", detail: "agent 需要确认或完成时：后台推送通知（点开直达会话），前台看别的会话时顶部提示。"),
            Item(symbol: "hand.thumbsup", title: "快速回复", detail: "「会话」页里等待确认的会话直接点 1 允许 / 2 始终 / 拒绝，不用进终端。"),
            Item(symbol: "square.stack.3d.up", title: "并行 agent", detail: "终端 ⋯ → tmux 会话：新建会话并启动 agent；点顶栏标题或双指左右滑在会话间切换；可重命名。"),
            Item(symbol: "slash.circle", title: "斜杠指令", detail: "辅助栏「/指令」：/compact /clear /model /resume /context …"),
            Item(symbol: "square.and.pencil", title: "写作框", detail: "原生输入法写长提示词，整段粘贴发送；「文件」按钮从服务器选文件插入 @路径；可插入相册图片（自动上传到 /tmp）；短语可在设置中自定义。"),
            Item(symbol: "text.badge.star", title: "片段", detail: "预置常用 agent 命令；命令里写 {{变量}} 运行时填写。"),
        ]),
        Group_(title: "终端操作", items: [
            Item(symbol: "keyboard", title: "辅助栏", detail: "第一行 esc tab ctrl alt 方向键（按住连发）；第二行可横滑、可在设置中增删排序；长按按键看说明。"),
            Item(symbol: "hand.draw", title: "滑动", detail: "普通输出原生惯性滚动；tmux / vim 中单指滑动即带惯性滚轮；右下角按钮回到底部。"),
            Item(symbol: "hand.point.up.left", title: "点按移动光标", detail: "键盘弹出时点输入行某处，光标移过去。"),
            Item(symbol: "text.viewfinder", title: "选择复制", detail: "⋯ → 选择 / 浏览输出：系统原生选择、查找、分享，可把选中的报错引用到写作框发给 agent；也可长按终端选择。"),
            Item(symbol: "magnifyingglass", title: "搜索", detail: "⋯ → 搜索输出，或 ⌘F。"),
            Item(symbol: "arrow.up.left.and.arrow.down.right", title: "字号", detail: "双指捏合，或 ⋯ → 放大 / 缩小。"),
            Item(symbol: "exclamationmark.shield", title: "粘贴保护", detail: "往普通 shell 粘贴多行时先确认（可合并为一行或转到写作框），防止误执行。"),
            Item(symbol: "command", title: "硬件键盘", detail: "⌘F 搜索 · ⌘K 清屏 · ⌘± 字号 · ⌘⇧E 写作 · ⌘⇧P 片段 · ⌘[ ⌘] 切换会话 · ⌘W 断开。"),
        ]),
        Group_(title: "服务器", items: [
            Item(symbol: "folder", title: "文件", detail: "终端右上角文件夹：浏览、上传下载、编辑文本文件、作为 @文件 发给 agent。"),
            Item(symbol: "gauge.with.dots.needle.33percent", title: "服务器状态", detail: "⋯ → 服务器状态：CPU / 内存 / 磁盘 / 运行中的 agent。"),
            Item(symbol: "clock.arrow.circlepath", title: "命令历史", detail: "⋯ → 命令历史：读取服务器 shell 历史，点按填入。"),
            Item(symbol: "safari", title: "端口转发", detail: "编辑主机 → 高级 → 端口转发；⋯ 菜单里在应用内浏览器打开。"),
        ]),
        Group_(title: "主机与数据", items: [
            Item(symbol: "eye.slash", title: "密码", detail: "默认隐藏，眼睛切换，一键复制；主机长按 / 左滑复制 IP、用户名、密码、SSH 命令。"),
            Item(symbol: "antenna.radiowaves.left.and.right", title: "测试连接", detail: "编辑主机时不保存即可验证。"),
            Item(symbol: "square.and.arrow.down", title: "导入", detail: "主机页 ＋ → 导入 ssh config；设置 → 备份与迁移。"),
            Item(symbol: "arrow.counterclockwise", title: "恢复会话", detail: "app 被系统关掉后，主页「继续上次的会话」一键接回 tmux 现场；长按 app 图标直连最近主机。"),
        ]),
    ]

    var body: some View {
        List {
            ForEach(groups) { g in
                Section(g.title) {
                    ForEach(g.items) { i in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: i.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(i.title).font(.subheadline.weight(.semibold))
                                Text(i.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("功能指南")
    }
}
