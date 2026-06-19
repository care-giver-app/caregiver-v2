import SwiftUI
import UIKit

enum Theme {
  enum Colors {
    static let accent = dynamic(light: "397234")
    static let olive = dynamic(light: "ACBD5E")
    static let amber = dynamic(light: "B78449")
    static let ink = dynamic(light: "0B0F08")
    static let textPrimary = dynamic(light: "16324F")
    static let textSecondary = dynamic(light: "5B7088")
    static let textTertiary = dynamic(light: "9AA7B5")
    static let surface = dynamic(light: "FFFFFF")
    static let background = dynamic(light: "F4F6F8")
    static let border = dynamic(light: "E6EAEF")
    static let alert = dynamic(light: "E5484D")  // reserved: C2 breach badge
    static let success = dynamic(light: "30A46C")

    /// A dynamic color. `dark` defaults to `light` until a dark theme is designed;
    /// because everything references these tokens, adding dark values is additive.
    private static func dynamic(light: String, dark: String? = nil) -> Color {
      Color(
        UIColor { traits in
          let hex =
            (traits.userInterfaceStyle == .dark ? (dark ?? light) : light)
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
    static let earth = LinearGradient(
      colors: [Colors.olive, Colors.amber],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  enum Typography {
    static let largeTitle = Font.system(size: 28, weight: .bold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let headline = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let subhead = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
  }
}

private struct EarthBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    ZStack {
      Theme.Colors.surface
        .ignoresSafeArea()
      Theme.Gradients.earth
        .opacity(0.4)
        .ignoresSafeArea()
      content
    }
  }
}

extension View {
  func earthBackground() -> some View {
    modifier(EarthBackgroundModifier())
  }
}
