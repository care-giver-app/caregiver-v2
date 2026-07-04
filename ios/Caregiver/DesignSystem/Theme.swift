import SwiftUI
import UIKit

enum Theme {
  enum Colors {
    // Aurora palette (Figma `aurora/*` + `color/auth/*` variables — see ios/specs/design-system.md)
    static let accent        = dynamic(light: "4dd6e6")
    static let highlight     = dynamic(light: "98d4ff")
    static let tertiary      = dynamic(light: "bac3e0")
    static let ink           = dynamic(light: "0B0F08")  // shadow-only; not for text
    static let textPrimary   = dynamic(light: "e8f0ff")
    static let textSecondary = dynamic(light: "9db0d6")
    static let textTertiary  = dynamic(light: "5e709c")
    static let textOnAccent  = dynamic(light: "04121a")  // ink on cyan fills (FAB glyph, primary buttons)
    static let surface       = dynamic(light: "0e1c4a")
    static let background    = dynamic(light: "050b2e")
    static let border        = dynamic(light: "294272")
    static let muted         = dynamic(light: "5A6E9E")
    static let alert         = dynamic(light: "ff4d6a")  // reserved: C2 breach badge
    static let success       = dynamic(light: "3dd68c")
    static let warning       = dynamic(light: "FCD34D")
    static let informational = dynamic(light: "93C5FD")

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
    static let control: CGFloat = 11
  }

  enum Gradients {
    static let stride = LinearGradient(
      colors: [
        Colors.highlight.opacity(0.55),
        Colors.accent.opacity(0.55),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
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

private struct StrideBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    ZStack {
      Theme.Colors.background
        .ignoresSafeArea()
      Theme.Gradients.stride
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
