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

/// "Things 3 calm" design language, locked 2026-06-12; expanded to the full
/// 2026-redesign token set 2026-07-01 (BAK-98). Source of truth:
/// `docs/design/redesign-2026/README.md` ("Design tokens"). Views must read from
/// here rather than hardcoding handoff hex. Every value below is the exact hex from
/// the handoff so existing surfaces render identically.
public enum Theme {
    public enum Palette {
        // MARK: Surfaces
        public static let bg = Color(hex: "#FBFAF7")            // app / card
        public static let surface = Color(hex: "#EFEBE2")
        public static let titleBar = Color(hex: "#F4F1EA")     // title bar / panels
        public static let sidebar = Color(hex: "#F7F4ED")
        public static let chipActive = Color(hex: "#EAE5DB")
        public static let navActive = Color(hex: "#EDE9E0")
        public static let hairline = Color(hex: "#E7E3DA")     // borders are 0.5px
        public static let divider = Color(hex: "#E1DCD1")      // secondary divider

        // MARK: Text
        public static let textPrimary = Color(hex: "#2B2A26")
        public static let textSecondary = Color(hex: "#9A968B")
        public static let textTertiary = Color(hex: "#B0ACA1")
        public static let textMuted = Color(hex: "#A6A296")    // completed title
        public static let strikethrough = Color(hex: "#C8C3B7")
        public static let onSurface = Color(hex: "#46433B")
        public static let onSurfaceSoft = Color(hex: "#5C584E")

        // MARK: Accent (you) / agent (purple)
        public static let accent = Color(hex: "#2D7FF9")
        public static let agent = Color(hex: "#7F77DD")
        public static let agentText = Color(hex: "#6A61C9")
        public static let agentMid = Color(hex: "#8079C6")
        public static let agentTintLight = Color(hex: "#EEEBFA")
        public static let agentTintMid = Color(hex: "#CFC9F0")
        public static let agentTintStrong = Color(hex: "#BCB6EC")
        public static let agentTintFaint = Color(hex: "#F3F1FA")
        public static let ownerTabInactive = Color(hex: "#BBB6AA")

        // MARK: Done (green) / review
        public static let done = Color(hex: "#1D9E75")
        public static let reviewText = Color(hex: "#1B7A57")
        public static let reviewBg = Color(hex: "#E3F2EB")
        public static let doneAccent = Color(hex: "#9BD0BD")    // done column accent
        public static let doneHead = Color(hex: "#6A9C84")      // done column header

        // MARK: Warn (amber)
        public static let warning = Color(hex: "#D98A29")       // overdue / needs-attention
        public static let warnText = Color(hex: "#B07A29")
        public static let warnTintSoft = Color(hex: "#FBF1E2")  // amber pill bg (needs-action)
        public static let warningSoft = Color(hex: "#FAEEDA")   // amber pill background (needs-you badge)
        public static let warningDeep = Color(hex: "#633806")   // amber pill text (needs-you badge)

        // MARK: Error / destructive
        public static let error = Color(hex: "#D85A30")          // error text + destructive action

        // MARK: Muted status pill
        public static let statusMutedText = Color(hex: "#8A8579")
        public static let statusMutedBg = Color(hex: "#F1EDE4")

        // MARK: Confidence
        public static let confidenceHigh = done                 // ≥0.7
        public static let confidenceMedium = Color(hex: "#BA7517") // ≥0.5
        public static let confidenceLow = Color(hex: "#D85A30")    // else
        public static let confidenceUnfilled = Color(hex: "#E4DFD5")

        // MARK: Priority
        public static let priorityHighText = Color(hex: "#A8502E")
        public static let priorityHighBg = Color(hex: "#F7E4D8")
        public static let priorityUrgentText = Color.white
        public static let priorityUrgentBg = Color(hex: "#C2603F")

        // MARK: Area dots (handoff per-list intent)
        public static let areaBlue = Color(hex: "#2D7FF9")      // DLA SDK
        public static let areaGreen = Color(hex: "#3E8E7E")     // Admin
        public static let areaPurple = Color(hex: "#7F77DD")    // Errands
        public static let areaGrey = Color(hex: "#B0ACA1")      // Reading
    }

    // MARK: Confidence tiers — single source of truth (BAK-98)

    /// Canonical confidence tiers. ≥0.7 high, ≥0.5 medium, else low. Pure + testable;
    /// `confidenceColor(_:)` maps a tier to its palette colour. Unifies the previously
    /// divergent ≥0.4 cutoff in the console/rec-detail with the board card's ≥0.5.
    public enum ConfidenceTier { case high, medium, low }

    public static func confidenceTier(_ c: Double) -> ConfidenceTier {
        if c >= 0.7 { return .high }
        if c >= 0.5 { return .medium }
        return .low
    }

    public static func confidenceColor(_ c: Double) -> Color {
        switch confidenceTier(c) {
        case .high: return Palette.confidenceHigh
        case .medium: return Palette.confidenceMedium
        case .low: return Palette.confidenceLow
        }
    }

    // MARK: Source badges — centralised map (handoff "Source badges")

    public struct SourceBadge {
        public let label: String
        public let icon: String
        public let fg: Color
        public let bg: Color
    }

    /// Badge for a task/recommendation source, or nil for manual (no badge).
    /// `vault` and any unrecognised harvested source map to the KB grey badge.
    public static func sourceBadge(for source: String?) -> SourceBadge? {
        switch source {
        case "gmail":   return SourceBadge(label: "Gmail",  icon: "✉",  fg: Color(hex: "#A8442E"), bg: Color(hex: "#FBEAE4"))
        case "xero":    return SourceBadge(label: "Xero",   icon: "$",  fg: Color(hex: "#1B6FA8"), bg: Color(hex: "#E4F0FA"))
        case "meeting": return SourceBadge(label: "Notes",  icon: "◷",  fg: Palette.agentText,      bg: Palette.agentTintLight)
        case "slack":   return SourceBadge(label: "Slack",  icon: "#",  fg: Color(hex: "#6A4FA0"), bg: Color(hex: "#EFEAF7"))
        case "linear":  return SourceBadge(label: "Linear", icon: "◐",  fg: Color(hex: "#54599A"), bg: Color(hex: "#ECEDF7"))
        case "manual":  return nil
        default:        return SourceBadge(label: "KB",     icon: "📚", fg: Color(hex: "#7B776C"), bg: Color(hex: "#F1EDE4"))
        }
    }

    public enum Fonts {
        public static let body = Font.system(size: 15)
        public static let title = Font.system(size: 15, weight: .medium)
        public static let meta = Font.system(size: 13)
        public static let gutter = Font.system(size: 13)
        public static let header = Font.system(size: 22, weight: .medium)
    }
}
