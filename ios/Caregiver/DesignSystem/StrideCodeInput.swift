import SwiftUI

/// The segmented one-time-code entry (Figma `Stride/Code Input`, 6 `Stride/Code
/// Digit` cells). Interactive: one hidden text field drives the whole row, so the
/// system number pad and one-time-code autofill work while the cells stay purely
/// visual. The consumer owns the `code` string; input is sanitized to digits and
/// capped at `length`. The focus ring sits on the next empty cell.
struct StrideCodeInput: View {
    @Binding var code: String
    var length: Int = 6

    @FocusState private var isFocused: Bool

    private enum Metrics {
        static let cellSpacing: CGFloat = 9
    }

    var body: some View {
        HStack(spacing: Metrics.cellSpacing) {
            ForEach(0..<length, id: \.self) { index in
                StrideCodeDigit(
                    digit: digit(at: index),
                    isFocused: isFocused && index == min(code.count, length - 1)
                )
            }
        }
        .accessibilityHidden(true)
        .background { hiddenField }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onChange(of: code) { _, newValue in
            let clean = Self.sanitized(newValue, length: length)
            if clean != newValue { code = clean }
        }
    }

    /// Digits only, capped at `length` — applied to every edit (typing, paste, autofill).
    static func sanitized(_ raw: String, length: Int) -> String {
        String(raw.filter(\.isNumber).prefix(length))
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }

    private var hiddenField: some View {
        TextField("", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($isFocused)
            .opacity(0.001)
            .accessibilityLabel("Confirmation code")
    }
}

/// One cell of the code input: `surface` slab, frost hairline, 22pt digit; the
/// focused cell adds a glowing accent ring.
private struct StrideCodeDigit: View {
    let digit: String
    let isFocused: Bool

    private enum Metrics {
        static let width: CGFloat = 50
        static let height: CGFloat = 60
        static let radius: CGFloat = 14
    }

    var body: some View {
        Text(digit)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(width: Metrics.width, height: Metrics.height)
            .background {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(Theme.Colors.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .stroke(Theme.Colors.textSecondary.opacity(0.4), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 2.5, y: 3)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: Metrics.radius)
                        .stroke(Theme.Colors.accent, lineWidth: 1.5)
                        .padding(-1)
                        .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 3.5)
                }
            }
    }
}

#Preview("Partially entered") {
    @Previewable @State var code = "429"
    StrideCodeInput(code: $code)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Theme.Colors.background.ignoresSafeArea() }
}
