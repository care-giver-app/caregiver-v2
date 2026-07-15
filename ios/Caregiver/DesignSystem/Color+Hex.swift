import SwiftUI
import UIKit

extension Color {
    /// Parses "#RRGGBB" or "RRGGBB". Falls back to system gray on bad input so a
    /// malformed tracker color never crashes the UI.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = Color(.systemGray)
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    /// The resolved sRGB as `"RRGGBB"` (lowercase, no `#`) — the inverse of
    /// `init(hex:)`, for persisting a user-picked color into `TrackerWrite.color`.
    /// Falls back to the accent cyan if components can't be read.
    var hexRGB: String {
        guard let c = rgbaComponents else { return "4dd6e6" }
        func byte(_ v: Double) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        return String(format: "%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b))
    }

    /// Test-only accessor for the resolved RGBA components.
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b), Double(a))
    }
}
