import SwiftUI
import UIKit
import SwiftTerm

/// 终端配色。16 色 + 前景/背景/光标，十六进制。
struct TerminalTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let background: String
    let foreground: String
    let cursor: String
    let ansi: [String] // 16

    static let defaultID = "default"

    var isDark: Bool {
        let c = Self.rgb(background)
        return (0.299 * c.0 + 0.587 * c.1 + 0.114 * c.2) < 0.5
    }

    var bgColor: SwiftUI.Color { SwiftUI.Color(uiColor: uiBackground) }
    var fgColor: SwiftUI.Color { SwiftUI.Color(uiColor: uiForeground) }
    var uiBackground: UIColor { Self.ui(background) }
    var uiForeground: UIColor { Self.ui(foreground) }
    var uiCursor: UIColor { Self.ui(cursor) }
    var swatches: [SwiftUI.Color] { ansi.map { SwiftUI.Color(uiColor: Self.ui($0)) } }

    var termColors: [SwiftTerm.Color] {
        ansi.map { hex in
            let c = Self.rgb(hex)
            return SwiftTerm.Color(red: UInt16(c.0 * 65535), green: UInt16(c.1 * 65535), blue: UInt16(c.2 * 65535))
        }
    }

    static func rgb(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0
        return (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }
    static func ui(_ hex: String) -> UIColor {
        let c = rgb(hex)
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
    }

    static func find(_ id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? all[0]
    }

    static let all: [TerminalTheme] = [
        TerminalTheme(id: "default", name: "Default", background: "#000000", foreground: "#e6e6e6", cursor: "#e6e6e6",
                      ansi: ["#000000", "#c23621", "#25bc24", "#adad27", "#492ee1", "#d338d3", "#33bbc8", "#cbcccd",
                             "#818383", "#fc391f", "#31e722", "#eaec23", "#5833ff", "#f935f8", "#14f0f0", "#e9ebeb"]),
        TerminalTheme(id: "midnight", name: "Midnight", background: "#1f1d45", foreground: "#f8dcc0", cursor: "#efbf38",
                      ansi: ["#050404", "#bd0013", "#4ab118", "#e7741e", "#0f4ac6", "#665993", "#70a598", "#f8dcc0",
                             "#4e7cbf", "#fc5f5a", "#9eff6e", "#efc11a", "#1997c6", "#9b5953", "#c8faf4", "#f6f5fb"]),
        TerminalTheme(id: "tokyonight", name: "Tokyo Night", background: "#1a1b26", foreground: "#c0caf5", cursor: "#c0caf5",
                      ansi: ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
                             "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"]),
        TerminalTheme(id: "dracula", name: "Dracula", background: "#282a36", foreground: "#f8f8f2", cursor: "#f8f8f2",
                      ansi: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                             "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"]),
        TerminalTheme(id: "catppuccin", name: "Catppuccin Mocha", background: "#1e1e2e", foreground: "#cdd6f4", cursor: "#f5e0dc",
                      ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
                             "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"]),
        TerminalTheme(id: "onedark", name: "One Dark", background: "#282c34", foreground: "#abb2bf", cursor: "#528bff",
                      ansi: ["#282c34", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
                             "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff"]),
        TerminalTheme(id: "nord", name: "Nord", background: "#2e3440", foreground: "#d8dee9", cursor: "#d8dee9",
                      ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                             "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"]),
        TerminalTheme(id: "gruvbox", name: "Gruvbox Dark", background: "#282828", foreground: "#ebdbb2", cursor: "#ebdbb2",
                      ansi: ["#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
                             "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"]),
        TerminalTheme(id: "solarized", name: "Solarized Dark", background: "#002b36", foreground: "#839496", cursor: "#93a1a1",
                      ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                             "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]),
        TerminalTheme(id: "paper", name: "Paper Light", background: "#fbfbfd", foreground: "#1d1d1f", cursor: "#007aff",
                      ansi: ["#1d1d1f", "#c41a16", "#007400", "#826b28", "#0e3fbe", "#a90d91", "#3e8087", "#86868b",
                             "#6e6e73", "#e0362f", "#1a8f1a", "#a8851c", "#2f6fe0", "#c032b0", "#3a9fa8", "#1d1d1f"]),
    ]
}
