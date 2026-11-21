import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sessions: SessionManager

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    IconTile(symbol: "textformat.size", colors: Color.tileBlue)
                    Stepper("字号 \(Int(settings.fontSize))", value: $settings.fontSize, in: 8...30, step: 1)
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "textformat", colors: Color.tileIndigo)
                    Picker("字体", selection: $settings.fontName) {
                        ForEach(AppSettings.fonts, id: \.self) { Text($0.replacingOccurrences(of: "-Regular", with: "").replacingOccurrences(of: "PSMT", with: "")).tag($0) }
                    }
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "character.cursor.ibeam", colors: Color.tileTeal)
                    Picker("光标", selection: $settings.cursorStyle) {
                        Text("方块").tag("block"); Text("竖线").tag("bar"); Text("下划线").tag("underline")
                    }
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "light.beacon.max", colors: Color.tileTeal)
                    Toggle("光标闪烁", isOn: $settings.cursorBlink)
                }
                FontPreview(size: settings.fontSize, name: settings.fontName)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("终端")
            } footer: {
                Text("在终端里双指捏合也能实时调整字号。")
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
                    Toggle("断线自动重连", isOn: $settings.autoReconnect)
                }
                HStack(spacing: 12) {
                    IconTile(symbol: "sun.max.fill", colors: Color.tileOrange)
                    Toggle("连接时保持亮屏", isOn: $settings.keepAwake)
                }
            } header: {
                Text("AI Agent")
            } footer: {
                Text("第二行快捷键默认提供 切换模式(⇧Tab)、换行、1/2/3 确认、/指令、@文件、粘贴、写作、片段 等 Claude Code 常用操作，可自定义增删排序。tmux 优化会开启鼠标滚动、5 万行历史、单行滚轮和零 Esc 延迟。自动重连仅对开启了会话恢复的主机生效。")
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
