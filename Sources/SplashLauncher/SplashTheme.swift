import AppKit
import SwiftUI

enum SplashTheme {
    static let accent = adaptive(light: 0x1F6F78, dark: 0x5FC2C9)
    /// Fill behind white text (the Start button): deeper than `accent` so the text stays readable.
    static let accentFill = adaptive(light: 0x1F6F78, dark: 0x237F8A)
    static let canvas = adaptive(light: 0xF7F6F2, dark: 0x20211F)
    static let sidebar = adaptive(light: 0xEEEDE7, dark: 0x272824)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x2A2B28)
    static let inset = adaptive(light: 0xF0EFEA, dark: 0x333430)
    static let border = adaptive(light: 0xE6E4DC, dark: 0x3B3C37)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

enum LauncherPage: String, CaseIterable {
    case overview = "Overview"
    case settings = "Settings"
    case logs = "Logs"
    case app = "App"

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .settings: return "slider.horizontal.3"
        case .logs: return "terminal"
        case .app: return "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Your model, running on your Mac."
        case .settings: return "Make Splash work the way you want."
        case .logs: return "A closer look at what your server is doing."
        case .app: return "A few things to make yourself at home."
        }
    }
}
