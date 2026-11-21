import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sessions: SessionManager

    var body: some View {
        Form {
            Section {
                NavigationLink { GuideView() } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "book.fill", colors: Color.tileOrange)
                        Text("功能指南")
                    }
                }
            }
            Section {
                HStack(spacing: 12) {
                    IconTile(symbol: "plus.magnifyingglass", colors: Color.tileBlue)
                    Stepper("字号 \(Int(settings.fontSize))", value: $settings.fontSize, in: 8...30, step: 1)
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "paintbrush.pointed.fill", colors: Color.tileIndigo)
                    Picker("字体", selection: $settings.fontName) {
                        ForEach(AppSettings.fonts, id: \.self) { Text($0.replacingOccurrences(of: "-Regular", with: "").replacingOccurrences(of: "PSMT", with: "")).tag($0) }
                    }
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "cursorarrow", colors: Color.tileTeal)
                    Picker("光标", selection: $settings.cursorStyle) {
                        Text("方块").tag("block"); Text("竖线").tag("bar"); Text("下划线").tag("underline")
                    }
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "light.beacon.max", colors: Color.tileTeal)
                    Toggle("光标闪烁", isOn: $settings.cursorBlink)
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "hand.point.up.left.fill", colors: Color.tileTeal)
                    Toggle("点按移动光标", isOn: $settings.tapMovesCursor)
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "paintpalette.fill", colors: Color.tileMagenta)
                    Picker("新主机默认配色", selection: $settings.defaultTheme) {
                        ForEach(TerminalTheme.all) { Text($0.name).tag($0.id) }
                    }
                }
                FontPreview(size: settings.fontSize, name: settings.fontName)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("终端")
            } footer: {
                Text("在终端里双指捏合也能实时调整字号。点按移动光标：键盘弹出时点一下输入行的某个位置，光标就移过去，方便修改 agent 提示词或长命令。")
            }

            Section {
                HStack(spacing: 12) {
                    IconTile(symbol: "scroll.fill", colors: Color.tileGreen)
                    Picker("回滚行数", selection: $settings.scrollback) {
                        Text("5,000").tag(5000); Text("20,000").tag(20000); Text("50,000").tag(50000); Text("100,000").tag(100000)
                    }
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "hand.draw.fill", colors: Color.tileOrange)
                    Toggle("tmux / vim 惯性滑动", isOn: $settings.inertiaWheel)
                }
                if settings.inertiaWheel {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("滑动灵敏度")
                            Spacer()
                            Text(sensitivityLabel).foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.wheelStep, in: 8...40, step: 2) {
                            Text("灵敏度")
                        } minimumValueLabel: { Image(systemName: "hare") } maximumValueLabel: { Image(systemName: "tortoise") }
                    }
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "cpu", colors: Color.tileGray)
                    Toggle("Metal 渲染", isOn: $settings.useMetal)
                }
            } header: {
                Text("滑动与性能")
            } footer: {
                Text("普通输出使用系统原生滚动；在 tmux、vim、less 等全屏程序里，单指滑动会转换为带惯性的滚轮，长输出也能顺滑翻阅。Metal 渲染可显著降低大量输出时的掉帧，修改后对新会话生效。")
            }

            Section {
                HStack(spacing: 12) {
                    IconTile(symbol: "sparkles", colors: Color.tileOrange)
                    Toggle("第二行快捷键", isOn: $settings.agentBar)
                }
                NavigationLink { BarKeysEditor() } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "keyboard", colors: Color.tileBlue)
                        Text("自定义键盘辅助栏")
                        Spacer()
                        Text("\(settings.barKeyIDs.count) 个键").foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "square.stack.3d.up.fill", colors: Color.tileMagenta)
                    Toggle("tmux 手机优化", isOn: $settings.tmuxTuning)
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "arrow.clockwise", colors: Color.tilePurple)
                    Toggle("断线 / 回到前台自动重连", isOn: $settings.autoReconnect)
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "bell.badge.fill", colors: Color.tileRed)
                    Toggle("后台通知", isOn: $settings.notifyBell)
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "sun.max.fill", colors: Color.tileOrange)
                    Toggle("连接时保持亮屏", isOn: $settings.keepAwake)
                }
            } header: {
                Text("AI Agent")
            } footer: {
                Text("第二行快捷键默认提供 切换模式(⇧Tab)、换行、1/2/3 确认、/指令、@文件、粘贴、写作、片段 等 Claude Code 常用操作，可自定义增删排序。tmux 优化会开启鼠标滚动、5 万行历史、单行滚轮和零 Esc 延迟。后台通知：agent 从「工作中」变成「等待确认 / 完成」、响铃或发出 OSC 9/777 通知时提醒你（iOS 只给后台约 30 秒存活时间，长时间锁屏后回来会自动重连并接回 tmux）。")
            }

            Section {
                LabeledContent("Claude Code") {
                    TextField("claude", text: $settings.cmdClaude).multilineTextAlignment(.trailing)
                }
                LabeledContent("Codex") {
                    TextField("codex", text: $settings.cmdCodex).multilineTextAlignment(.trailing)
                }
                LabeledContent("Gemini CLI") {
                    TextField("gemini", text: $settings.cmdGemini).multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Agent 启动命令")
            } footer: {
                Text("「连接后启动」与「新建 agent 会话」使用的命令，可带参数，例如 claude --model opus 或 ~/.local/bin/claude。留空使用默认。")
            }
            .font(.body.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Section {
                NavigationLink { PhrasesEditor() } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "text.bubble.fill", colors: Color.tileBlue)
                        Text("写作框短语")
                    }
                }
            }

            Section("数据") {
                NavigationLink { BackupView() } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "externaldrive.fill", colors: Color.tileGray)
                        Text("备份与迁移")
                    }
                }
            }

            Section("通用") {
                HStack(spacing: 12) {
                    IconTile(symbol: "iphone.radiowaves.left.and.right", colors: Color.tilePink)
                    Toggle("触感反馈", isOn: $settings.haptics)
                }
            }

            Section {
                LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                LabeledContent("终端引擎", value: "SwiftTerm")
                LabeledContent("SSH", value: "Citadel / SwiftNIO SSH")
            } header: {
                Text("关于")
            } footer: {
                Text("物语SSH · 为在手机上驾驭 AI agent 而做").frame(maxWidth: .infinity).padding(.top, 12)
            }
        }
        .navigationTitle("设置")
        .onChange(of: settings.fontSize) { _, _ in sessions.sessions.forEach { $0.refreshFont() } }
        .onChange(of: settings.fontName) { _, _ in sessions.sessions.forEach { $0.refreshFont() } }
        .onChange(of: settings.agentBar) { _, _ in sessions.sessions.forEach { $0.rebuildBar() } }
        .onChange(of: settings.scrollback) { _, _ in sessions.sessions.forEach { $0.applyTerminalSettings() } }
        .onChange(of: settings.cursorStyle) { _, _ in sessions.sessions.forEach { $0.applyTerminalSettings() } }
        .onChange(of: settings.cursorBlink) { _, _ in sessions.sessions.forEach { $0.applyTerminalSettings() } }
    }

    var sensitivityLabel: String {
        switch settings.wheelStep {
        case ..<14: return "灵敏"
        case ..<24: return "标准"
        default: return "稳"
        }
    }
}

struct FontPreview: View {
    let size: Double
    let name: String
    var body: some View {
        let theme = TerminalTheme.find(AppSettings.shared.defaultTheme)
        VStack(alignment: .leading, spacing: 2) {
            Text("root@monogatari:~# ").foregroundColor(Color(uiColor: TerminalTheme.ui(theme.ansi[2])))
            + Text("claude").foregroundColor(theme.fgColor)
            Text("✻ Welcome to Claude Code").foregroundColor(Color(uiColor: TerminalTheme.ui(theme.ansi[3])))
        }
        .font(Font(AppSettings.shared.uiFont(size: CGFloat(size))))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.bgColor)
    }
}


/// 编辑写作框顶部的快捷短语
struct PhrasesEditor: View {
    @AppStorage("composePhrases") private var raw = ComposeSheet.defaultPhrases
    var body: some View {
        Form {
            Section {
                TextEditor(text: $raw)
                    .font(.callout.monospaced())
                    .frame(minHeight: 260)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } footer: {
                Text("每行一条，格式「按钮名=插入内容」。例如：\n审查=请审查这次改动，指出潜在 bug。")
            }
            Section {
                Button("恢复默认", role: .destructive) { raw = ComposeSheet.defaultPhrases }
            }
        }
        .navigationTitle("写作框短语")
    }
}
