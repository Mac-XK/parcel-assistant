import SwiftUI
import UIKit

// MARK: - 颜色工具

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "#", with: "")
        if s.hasPrefix("rgba(") { // rgba(32,32,34,0.42)
            let body = s.dropFirst(5).dropLast()
            let parts = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 4,
               let r = Double(parts[0]), let g = Double(parts[1]),
               let b = Double(parts[2]), let a = Double(parts[3]) {
                self.init(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
                return
            }
            self.init(white: 0.5, alpha: 1)
            return
        }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        switch s.count {
        case 8:
            self.init(red: CGFloat((v >> 24) & 0xFF) / 255,
                      green: CGFloat((v >> 16) & 0xFF) / 255,
                      blue: CGFloat((v >> 8) & 0xFF) / 255,
                      alpha: CGFloat(v & 0xFF) / 255)
        case 6:
            self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                      green: CGFloat((v >> 8) & 0xFF) / 255,
                      blue: CGFloat(v & 0xFF) / 255,
                      alpha: 1)
        default:
            self.init(white: 0.5, alpha: 1)
        }
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }

    /// 一套配色同时给出浅色与深色
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - 调色板（与 Scripting 版 theme.ts 对齐）

enum Palette {
    static let bg = Color(light: "#F2F2F7", dark: "#000000")
    static let card = Color(light: "#FFFFFF", dark: "#1C1C1E")
    static let card2 = Color(light: "#FFFFFF", dark: "#202022")
    static let elevated = Color(light: "#FFFFFF", dark: "#242426")
    static let text = Color(light: "#111114", dark: "#FFFFFF")
    static let secondary = Color(light: "#6C6C70", dark: "#9C9CA0")
    static let tertiary = Color(light: "#8E8E93", dark: "#68686C")
    static let separator = Color(light: "rgba(0,0,0,0.06)", dark: "rgba(255,255,255,0.08)")
    static let field = Color(light: "#E9E9EE", dark: "#2C2C2E")

    static let green = Color(light: "#34A853", dark: "#57C46B")
    static let red = Color(light: "#F0554F", dark: "#FF6B65")
    static let orange = Color(light: "#F08A2E", dark: "#E8A050")
    static let blue = Color(light: "#2F7BF6", dark: "#4C8DFF")
    static let purple = Color(light: "#6B5BD2", dark: "#8A7BF2")

    /// 主题色预设（对应「设置 → 主题色」）
    static let accents: [(name: String, hex: String)] = [
        ("星辉紫", "#7C4CB3"),
        ("天空蓝", "#2F7BF6"),
        ("青柠绿", "#7BB661"),
        ("品牌橙", "#F08A2E"),
    ]

    static func accent(_ name: String) -> Color {
        Color(hex: accents.first { $0.name == name }?.hex ?? "#7C4CB3")
    }
}

// MARK: - 卡片

struct CardBackground: ViewModifier {
    var radius: CGFloat = 20
    var fill: Color = Palette.card
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 0.6)
            )
    }
}

extension View {
    func cardStyle(radius: CGFloat = 20, fill: Color = Palette.card) -> some View {
        modifier(CardBackground(radius: radius, fill: fill))
    }
}

// MARK: - 触感

enum Haptic {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warn() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
