import SwiftUI
import UIKit
import GameCore

/// Flat two-tone look: a light background and one dark "ink" color for everything solid.
struct Theme: Equatable {
    let background: UIColor
    let ink: UIColor
    let accent: UIColor
    let doorGlow: UIColor

    var backgroundColor: Color { Color(uiColor: background) }
    var inkColor: Color { Color(uiColor: ink) }
    var accentColor: Color { Color(uiColor: accent) }
}

enum Palette {
    static let themes: [Theme] = [
        Theme(background: UIColor(hex: 0xF3E2C0), ink: UIColor(hex: 0x2A2522), accent: UIColor(hex: 0xE4572E), doorGlow: UIColor(hex: 0xFFF4D6)),
        Theme(background: UIColor(hex: 0xCFE8D5), ink: UIColor(hex: 0x1F2D2A), accent: UIColor(hex: 0xF25F5C), doorGlow: UIColor(hex: 0xF4FFF6)),
        Theme(background: UIColor(hex: 0xCDE3F2), ink: UIColor(hex: 0x1C2733), accent: UIColor(hex: 0xFF7F50), doorGlow: UIColor(hex: 0xF3FAFF)),
        Theme(background: UIColor(hex: 0xE4D8F0), ink: UIColor(hex: 0x2A2138), accent: UIColor(hex: 0xFF5E78), doorGlow: UIColor(hex: 0xFBF6FF)),
        Theme(background: UIColor(hex: 0xF7D4C1), ink: UIColor(hex: 0x33211C), accent: UIColor(hex: 0x3D9BE9), doorGlow: UIColor(hex: 0xFFF3EC)),
        Theme(background: UIColor(hex: 0xEDE6D3), ink: UIColor(hex: 0x262626), accent: UIColor(hex: 0xD7263D), doorGlow: UIColor(hex: 0xFFFBF0)),
    ]

    static let menu = themes[0]

    static func theme(for level: Level, index: Int) -> Theme {
        let i = level.theme ?? index
        return themes[((i % themes.count) + themes.count) % themes.count]
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
