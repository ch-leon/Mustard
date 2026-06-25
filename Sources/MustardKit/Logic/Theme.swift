import SwiftUI

extension Color {
    init(hex: String) {
        let s = Scanner(string: hex.hasPrefix("#") ? String(hex.dropFirst()) : hex)
        var rgb: UInt64 = 0
        s.scanHexInt64(&rgb)
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// "Things 3 calm" design language, locked 2026-06-12:
/// warm off-white, hairline dividers, single blue accent, roomy type.
public enum Theme {
    public enum Palette {
        public static let bg = Color(hex: "#FBFAF7")
        public static let surface = Color(hex: "#EFEBE2")
        public static let hairline = Color(hex: "#E7E3DA")
        public static let textPrimary = Color(hex: "#2B2A26")
        public static let textSecondary = Color(hex: "#9A968B")
        public static let textTertiary = Color(hex: "#B0ACA1")
        public static let accent = Color(hex: "#2D7FF9")
        public static let agent = Color(hex: "#7F77DD")
        public static let done = Color(hex: "#1D9E75")
        public static let warning = Color(hex: "#D98A29") // overdue / needs-attention amber
        public static let warningSoft = Color(hex: "#FAEEDA") // amber pill background (needs-you badge)
        public static let warningDeep = Color(hex: "#633806") // amber pill text (needs-you badge)
    }

    public enum Fonts {
        public static let body = Font.system(size: 15)
        public static let title = Font.system(size: 15, weight: .medium)
        public static let meta = Font.system(size: 13)
        public static let gutter = Font.system(size: 13)
        public static let header = Font.system(size: 22, weight: .medium)
    }
}
