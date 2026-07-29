import SwiftUI
import UIKit

enum Theme {
  enum Colors {
    // Stride palette (see ios/specs/design-system.md)
    static let accent        = dynamic(light: "1c8fe0")
    static let highlight     = dynamic(light: "8fc6ee")
    static let tertiary      = dynamic(light: "c9dbea")
    static let ink           = dynamic(light: "0B0F08")  // shadow-only; not for text
    static let textPrimary   = dynamic(light: "14273f")
    static let textSecondary = dynamic(light: "4a6480")
    static let textTertiary  = dynamic(light: "7f97b0")
    static let textOnAccent  = dynamic(light: "f2fcfd")  // ink on accent fills (FAB glyph, primary buttons)
    static let surface       = dynamic(light: "ffffff")
    static let surfaceHi     = dynamic(light: "e7f1f9")  // raised surface (toggle off-track)
    static let background    = dynamic(light: "eef5fb")
    static let border        = dynamic(light: "cfe0ee")
    static let muted         = dynamic(light: "7c93ac")
    static let alert         = dynamic(light: "d6304f")  // reserved: C2 breach badge
    static let success       = dynamic(light: "1f9d6c")
    static let warning       = dynamic(light: "c2790a")
    static let informational = dynamic(light: "5b76b3")

    // Tracker hues (per-entity recognition; amber/red is the status layer, never a base hue).
    // info-blue trackers reuse `informational`. Hue map per receiver: ios/specs/sample-data.md.
    static let trackerCyan   = dynamic(light: "1c8fe0")
    static let trackerTeal   = dynamic(light: "0d8c86")
    static let trackerViolet = dynamic(light: "6f5fe0")

    /// A dynamic color. `dark` defaults to `light` until a dark palette variant is designed;
    /// because everything references these tokens, adding dark values is purely additive.
    private static func dynamic(light: String, dark: String? = nil) -> Color {
      Color(
        UIColor { traits in
          let hex = traits.userInterfaceStyle == .dark ? (dark ?? light) : light
          return UIColor(Color(hex: hex))
        }
      )
    }
  }

  enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
  }

  enum Radius {
    static let card: CGFloat = 12
  }

  enum Typography {
    static let largeTitle = Font.system(size: 28, weight: .bold)
    static let title      = Font.system(size: 20, weight: .semibold)
    static let headline   = Font.system(size: 16, weight: .semibold)
    static let body       = Font.system(size: 15, weight: .regular)
    static let subhead    = Font.system(size: 13, weight: .regular)
    static let caption    = Font.system(size: 12, weight: .regular)
  }
}

/// The post-login Aurora substrate: the same night gradient as
/// `.strideAuroraBackground()` but without the auth glow ellipses —
/// the glows are an auth-screen signature (see ios/specs/design-system.md).
private struct StrideBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    ZStack {
      LinearGradient(
        colors: [Theme.Colors.background, Color(hex: "e4edf9")],
        startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea()
      content
    }
  }
}

extension View {
  func strideBackground() -> some View {
    modifier(StrideBackgroundModifier())
  }
}
