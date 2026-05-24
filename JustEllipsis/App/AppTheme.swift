import SwiftUI

enum AppTheme {

    // MARK: - Colours

    static let background   = Color(hex: "#0C0A08")
    static let text         = Color(hex: "#C8B898")
    static let textFaint    = Color(hex: "#C8B898").opacity(0.45)
    static let heading      = Color(hex: "#F5ECD7")
    static let accent       = Color(hex: "#FFFFFF")
    static let accentFaint  = Color(hex: "#FFFFFF").opacity(0.18)

    // Used inside the reader/reflect experience only
    static let readerAccent      = Color(hex: "#E8A83E")
    static let readerAccentFaint = Color(hex: "#E8A83E").opacity(0.18)
    static let surface      = Color(hex: "#161310")
    static let separator    = Color(hex: "#C8B898").opacity(0.12)
    static let danger       = Color(hex: "#D0553A")

    // MARK: - Typography

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Georgia", size: size).weight(weight)
    }

    static func sansSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: - Spacing

    static let pagePadding: CGFloat = 20
    static let cardRadius: CGFloat  = 14
    static let cardPadding: CGFloat = 16
}

// MARK: - Hex Colour Init

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
