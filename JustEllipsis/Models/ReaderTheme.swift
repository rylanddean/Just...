import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case ember = "ember"
    case slate = "slate"
    case dusk  = "dusk"
    case sage  = "sage"
    case sepia = "sepia"
    case paper = "paper"
    case night = "night"   // applied automatically; not shown in the theme picker

    var id: String { rawValue }

    // The subset of themes the user can manually choose. Night is excluded because
    // it is applied by NightModeService, not selected directly.
    static let pickerCases: [ReaderTheme] = [.ember, .slate, .dusk, .sage, .sepia, .paper]

    var displayName: String {
        switch self {
        case .ember: "Ember"
        case .slate: "Slate"
        case .dusk:  "Dusk"
        case .sage:  "Sage"
        case .sepia: "Sepia"
        case .paper: "Paper"
        case .night: "Night"
        }
    }

    var bgHex: String {
        switch self {
        case .ember: "#0C0A08"
        case .slate: "#0D1117"
        case .dusk:  "#1A1020"
        case .sage:  "#0F1612"
        case .sepia: "#F4ECD8"
        case .paper: "#FAFAF8"
        case .night: "#130D07"
        }
    }

    var surfaceHex: String {
        switch self {
        case .ember: "#161310"
        case .slate: "#161B22"
        case .dusk:  "#231628"
        case .sage:  "#171E19"
        case .sepia: "#EAE0CA"
        case .paper: "#F0F0EE"
        case .night: "#1D1409"
        }
    }

    var textHex: String {
        switch self {
        case .ember: "#C8B898"
        case .slate: "#C9D1D9"
        case .dusk:  "#D4C8E0"
        case .sage:  "#C8D8C0"
        case .sepia: "#3D2B1F"
        case .paper: "#1A1A1A"
        case .night: "#A88560"
        }
    }

    var accentHex: String {
        switch self {
        case .ember: "#E8A83E"
        case .slate: "#58A6FF"
        case .dusk:  "#C084FC"
        case .sage:  "#6FBF73"
        case .sepia: "#8B4513"
        case .paper: "#E05C2A"
        case .night: "#C07820"
        }
    }

    var headingHex: String {
        switch self {
        case .ember: "#F5ECD7"
        case .slate: "#E6EDF3"
        case .dusk:  "#EDE8F5"
        case .sage:  "#E0EDD8"
        case .sepia: "#1A0804"
        case .paper: "#111111"
        case .night: "#C4A068"
        }
    }

    var isLight: Bool { self == .sepia || self == .paper }

    var bg: Color      { Color(hex: bgHex) }
    var surface: Color { Color(hex: surfaceHex) }
    var text: Color    { Color(hex: textHex) }
    var accent: Color  { Color(hex: accentHex) }
    var heading: Color { Color(hex: headingHex) }
    var colorScheme: ColorScheme { isLight ? .light : .dark }

    static let defaultsKey = "selectedReaderTheme"
}
