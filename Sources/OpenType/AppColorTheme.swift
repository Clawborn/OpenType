import AppKit
import SwiftUI

enum AppColorTheme: String, CaseIterable, Identifiable {
    case ocean
    case violet
    case mint
    case sunset
    case sakura
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean: return OpenTypeL10n.text("深海蓝", english: "Ocean Blue")
        case .violet: return OpenTypeL10n.text("灵感紫", english: "Creative Violet")
        case .mint: return OpenTypeL10n.text("薄荷青", english: "Mint")
        case .sunset: return OpenTypeL10n.text("日落橙", english: "Sunset")
        case .sakura: return OpenTypeL10n.text("樱花粉", english: "Sakura")
        case .graphite: return OpenTypeL10n.text("石墨灰", english: "Graphite")
        }
    }

    var subtitle: String {
        switch self {
        case .ocean: return OpenTypeL10n.text("清晰 · 默认", english: "Clear · Default")
        case .violet: return OpenTypeL10n.text("专注 · 创造", english: "Focus · Create")
        case .mint: return OpenTypeL10n.text("轻盈 · 平静", english: "Light · Calm")
        case .sunset: return OpenTypeL10n.text("温暖 · 鲜活", english: "Warm · Vivid")
        case .sakura: return OpenTypeL10n.text("柔和 · 亲近", english: "Soft · Personal")
        case .graphite: return OpenTypeL10n.text("中性 · 克制", english: "Neutral · Quiet")
        }
    }

    var accent: Color {
        switch self {
        case .ocean:
            return Color(red: 0.05, green: 0.45, blue: 0.98)
        case .violet:
            return Color(red: 0.47, green: 0.30, blue: 0.96)
        case .mint:
            return Color(red: 0.00, green: 0.62, blue: 0.56)
        case .sunset:
            return Color(red: 0.96, green: 0.34, blue: 0.20)
        case .sakura:
            return Color(red: 0.91, green: 0.28, blue: 0.51)
        case .graphite:
            return Color(red: 0.36, green: 0.40, blue: 0.47)
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .ocean:
            return Color(red: 0.34, green: 0.32, blue: 0.98)
        case .violet:
            return Color(red: 0.78, green: 0.25, blue: 0.90)
        case .mint:
            return Color(red: 0.04, green: 0.75, blue: 0.72)
        case .sunset:
            return Color(red: 1.00, green: 0.55, blue: 0.18)
        case .sakura:
            return Color(red: 0.98, green: 0.49, blue: 0.65)
        case .graphite:
            return Color(red: 0.52, green: 0.56, blue: 0.64)
        }
    }

    var nsAccent: NSColor {
        switch self {
        case .ocean:
            return NSColor(red: 0.05, green: 0.45, blue: 0.98, alpha: 1)
        case .violet:
            return NSColor(red: 0.47, green: 0.30, blue: 0.96, alpha: 1)
        case .mint:
            return NSColor(red: 0.00, green: 0.62, blue: 0.56, alpha: 1)
        case .sunset:
            return NSColor(red: 0.96, green: 0.34, blue: 0.20, alpha: 1)
        case .sakura:
            return NSColor(red: 0.91, green: 0.28, blue: 0.51, alpha: 1)
        case .graphite:
            return NSColor(red: 0.36, green: 0.40, blue: 0.47, alpha: 1)
        }
    }
}
