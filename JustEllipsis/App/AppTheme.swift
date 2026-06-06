import SwiftUI

// MARK: - AppTheme

struct AppTheme {

    // MARK: Theme-derived colours (vary with the selected palette)

    let background:  Color
    let surface:     Color
    let text:        Color
    let textFaint:   Color
    let heading:     Color
    let accent:      Color
    let accentFaint: Color
    let separator:   Color
    let colorScheme: ColorScheme
    let isLight:     Bool

    init(theme: ReaderTheme = .ember) {
        background  = theme.bg
        surface     = theme.surface
        text        = theme.text
        textFaint   = theme.text.opacity(0.45)
        heading     = theme.heading
        accent      = theme.accent
        accentFaint = theme.accent.opacity(0.18)
        separator   = theme.text.opacity(0.12)
        colorScheme = theme.colorScheme
        isLight     = theme.isLight
    }

    // MARK: Fixed colours (not theme-dependent)

    static let danger = Color(hex: "#D0553A")

    // MARK: Typography

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Georgia", size: size).weight(weight)
    }

    static func sansSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat) -> Font {
        .custom("DMMono-Regular", size: size)
    }

    static func playfair(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold: return .custom("PlayfairDisplay-SemiBold", size: size)
        case .bold:     return .custom("PlayfairDisplay-Bold", size: size)
        default:        return .custom("PlayfairDisplay-Regular", size: size)
        }
    }

    // MARK: Spacing

    static let pagePadding: CGFloat = 20
    static let cardRadius:  CGFloat = 14
    static let cardPadding: CGFloat = 16
}

// MARK: - Environment

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme()
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Hex colour init

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >>  8) & 0xFF) / 255
        let b = Double( rgb        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
