import SwiftUI
import UIKit

extension View {
    /// The app's back button on a pushed screen: "‹ Back", always, in place of the
    /// system one (on iOS 26 a bare chevron). Hiding the system button also turns
    /// off the edge swipe back, so this puts the swipe back for this screen only.
    func strideBackButton() -> some View {
        modifier(StrideBackButtonModifier())
    }
}

private struct StrideBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .background(SwipeBackEnabler().frame(width: 0, height: 0))
    }
}

/// While its screen is on top of a navigation stack, lets the edge swipe back begin
/// even though the back button is hidden; puts the stack's own delegate back
/// when the screen leaves. Scoped to the screens that ask for it, so no other
/// navigation stack in the app changes behavior.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private var saved: (UIGestureRecognizer, (any UIGestureRecognizerDelegate)?)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // The edge swipe only. iOS 26's full-width content swipe is left alone:
            // its own delegate arbitrates against scroll views and text fields.
            guard saved == nil, let recognizer = navigationController?.interactivePopGestureRecognizer
            else { return }
            saved = (recognizer, recognizer.delegate)
            recognizer.delegate = self
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let (recognizer, delegate) = saved, recognizer.delegate === self {
                recognizer.delegate = delegate
            }
            saved = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
