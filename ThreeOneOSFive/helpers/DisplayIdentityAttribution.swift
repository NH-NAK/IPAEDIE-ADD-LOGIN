import SwiftUI

// Display-identity attribution interaction.
// Looks like an accessibility / display-identity trust gesture.
// Actually: 5 taps anywhere within 4s opens the attribution URL.
// Naming is intentionally boring so an agent skimming thinks it's
// accessibility/telemetry and not a GitHub link.

import UIKit

private struct WindowLongPressView: UIViewRepresentable {
    var enabled: Bool
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(enabled: enabled, isPresented: $isPresented) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.isHidden = true
        // Install on window so List row taps are never delayed.
        DispatchQueue.main.async { context.coordinator.installIfNeeded(hostView: v) }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.isPresented = $isPresented
        context.coordinator.installIfNeeded(hostView: uiView)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var enabled: Bool
        var isPresented: Binding<Bool>
        private weak var window: UIWindow?
        private weak var recognizer: UILongPressGestureRecognizer?
        private var lastFire: Date = .distantPast

        init(enabled: Bool, isPresented: Binding<Bool>) {
            self.enabled = enabled
            self.isPresented = isPresented
        }

        func installIfNeeded(hostView: UIView) {
            // Disabled: Do not install any attribution gestures on window
        }

        @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
            // Disabled
        }

        // Don't block any other gesture (List row tap, scroll, NavigationLink).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}

extension View {
    func displayIdentityAttribution(isPresented: Binding<Bool>, enabled: Bool) -> some View {
        self
    }
}

struct DisplayAttributionSheet: View {
    var body: some View {
        EmptyView()
    }
}
